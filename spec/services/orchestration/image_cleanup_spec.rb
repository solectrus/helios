RSpec.describe Orchestration::ImageCleanup do
  let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }

  before do
    stub_const(
      'DockerImages::POSTGRESQL',
      { current: 'postgres:18-alpine', legacy: %w[postgres:17-alpine].freeze }.freeze,
    )
    stub_const(
      'DockerImages::REDIS',
      { current: 'redis:8-alpine', legacy: %w[redis:7-alpine].freeze }.freeze,
    )
    stub_const(
      'DockerImages::WATCHTOWER',
      { current: 'nickfedor/watchtower:latest', legacy: %w[containrrr/watchtower].freeze }.freeze,
    )
    stub_const(
      'DockerImages::REGISTRY_BY_SERVICE',
      { 'postgresql' => :POSTGRESQL, 'redis' => :REDIS, 'watchtower' => :WATCHTOWER }.freeze,
    )
    allow(Orchestration::Container).to receive(:invalidate_cache)
    allow(Open3).to receive(:capture2e).and_return(['', status])
  end

  def container(service_name:, image:, running: true)
    instance_double(Orchestration::Container, service_name:, image:, running?: running)
  end

  describe '.run' do
    it 'batches legacy tags of running services, sparing the in-use image' do
      allow(Orchestration::Container).to receive(:all).and_return(
        [container(service_name: 'postgresql', image: 'postgres:18-alpine')],
      )

      described_class.run

      expect(Open3).to have_received(:capture2e).with('docker', 'image', 'rm', 'postgres:17-alpine')
      expect(Open3).not_to have_received(:capture2e).with(
        'docker', 'image', 'rm', a_string_including('postgres:18')
      )
      expect(Open3).not_to have_received(:capture2e).with(
        'docker', 'image', 'rm', a_string_including('redis')
      )
    end

    it 'skips stopped containers' do
      allow(Orchestration::Container).to receive(:all).and_return(
        [container(service_name: 'postgresql', image: 'postgres:18-alpine', running: false)],
      )

      described_class.run

      expect(Open3).not_to have_received(:capture2e).with(
        'docker', 'image', 'rm', a_string_including('postgres')
      )
    end

    it 'expands bare-repo legacy entries against host tags, skipping <none>' do
      allow(Orchestration::Container).to receive(:all).and_return(
        [container(service_name: 'watchtower', image: 'nickfedor/watchtower:latest')],
      )
      allow(Open3).to receive(:capture2e).with(
        'docker', 'images', 'containrrr/watchtower', '--format', '{{.Repository}}:{{.Tag}}'
      ).and_return(["containrrr/watchtower:1.7.1\ncontainrrr/watchtower:<none>\n", status])

      described_class.run

      expect(Open3).to have_received(:capture2e).with(
        'docker', 'image', 'rm', 'containrrr/watchtower:1.7.1'
      )
      expect(Open3).not_to have_received(:capture2e).with(
        'docker', 'image', 'rm', a_string_including('<none>')
      )
    end

    it 'removes the explicit previous_image even with no running services' do
      allow(Orchestration::Container).to receive(:all).and_return([])

      described_class.run(previous_image: 'alpine:3.18')

      expect(Open3).to have_received(:capture2e).with('docker', 'image', 'rm', 'alpine:3.18')
    end
  end
end
