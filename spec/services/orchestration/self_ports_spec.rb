RSpec.describe Orchestration::SelfPorts do
  subject(:drifted) { described_class.drifted? }

  # A real compose.yaml on disk, so the ports are parsed the way they are for
  # the generated file. Only the container is a double: reading it needs Docker.
  # Unique per parallel worker so concurrent specs don't clobber each other.
  let(:data_path) { Rails.root.join("tmp/selfports#{ENV.fetch('TEST_ENV_NUMBER', nil)}").to_s }
  let(:compose_ports) { ['3999:3000'] }
  let(:helios_service) { { 'image' => 'ghcr.io/solectrus/helios:develop', 'ports' => compose_ports } }
  let(:services) { { 'helios' => helios_service } }
  let(:container_ports) { [3999] }

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(data_path)
    File.write(File.join(data_path, 'compose.yaml'), YAML.dump('services' => services))

    container =
      container_ports &&
      instance_double(Orchestration::Container, published_host_ports: container_ports)
    allow(Orchestration::Container).to receive(:find).with('helios').and_return(container)
  end

  after { FileUtils.rm_rf(data_path) }

  it 'is false while HELIOS keeps the port it holds' do
    expect(drifted).to be false
  end

  context 'with several ports in another order' do
    let(:compose_ports) { ['3000:3000', '3999:3000'] }
    let(:container_ports) { [3999, 3000] }

    it { is_expected.to be false }
  end

  # Choosing the built-in Traefik moves :3999 to Traefik. The container left
  # out of the run keeps holding it, and Traefik cannot bind it.
  context 'when HELIOS gives its port to Traefik' do
    let(:helios_service) { { 'image' => 'ghcr.io/solectrus/helios:develop' } }

    it { is_expected.to be true }
  end

  # The way back: Traefik goes and HELIOS takes the port again, which a run
  # without HELIOS never binds.
  context 'when HELIOS takes a port it does not hold yet' do
    let(:container_ports) { [] }

    it { is_expected.to be true }
  end

  # Development runs HELIOS natively, so the compose file names no such
  # service and there is nothing to hand over.
  context 'without a helios service in the compose file' do
    let(:services) { { 'dashboard' => { 'image' => 'ghcr.io/solectrus/dashboard:latest' } } }

    it { is_expected.to be false }
  end

  context 'without a running helios container' do
    let(:container_ports) { nil }

    it { is_expected.to be false }
  end

  # Nothing can be read while Docker is unreachable, and the start that asks
  # is about to fail on its own terms.
  context 'when Docker is unreachable' do
    before do
      allow(Orchestration::Container).to receive(:find).and_raise(Orchestration::ConnectionError)
    end

    it { is_expected.to be false }
  end
end
