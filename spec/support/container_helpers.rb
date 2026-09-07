# Doubles for the two container objects the specs deal with: the raw
# `Docker::Container` the API returns, and the `Orchestration::Container`
# HELIOS wraps around it. Both shapes are needed in components, requests and
# service specs, so they live here instead of being rebuilt per file.
module ContainerHelpers
  def docker_container_double(service:, state: 'running', health: nil, image: 'alpine:latest')
    instance_double(
      Docker::Container,
      id: "id-#{service}",
      json: { 'Config' => { 'Image' => image } },
      info: {
        'Names' => ["/solectrus-#{service}-1"],
        'State' => state,
        'Status' => health ? "Up 2 hours (#{health})" : 'Up 2 hours',
        'Image' => image,
        'Labels' => { 'com.docker.compose.service' => service },
      },
    )
  end

  def orchestration_container(**)
    Orchestration::Container.new(docker_container_double(**))
  end

  # Stubs the lookup of a single service. `running: nil` stands for "no
  # container at all".
  def stub_container_find(service_name, running: true)
    container = running.nil? ? nil : instance_double(Orchestration::Container, running?: running)
    allow(Orchestration::Container).to receive(:find).with(service_name).and_return(container)
    container
  end
end

RSpec.configure { |config| config.include ContainerHelpers }
