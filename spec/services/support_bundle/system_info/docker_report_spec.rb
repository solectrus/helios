RSpec.describe SupportBundle::SystemInfo::DockerReport do
  describe '.fetch_snapshot' do
    it 'collects daemon info, version and containers in one snapshot' do
      containers = [instance_double(Docker::Container)]
      allow(Orchestration::Connection).to receive(:configure!)
      allow(Docker).to receive_messages(info: { 'ID' => 'abc' }, version: { 'Version' => '27.0' })
      allow(Docker::Container).to receive(:all).with(all: true).and_return(containers)

      expect(described_class.fetch_snapshot).to eq(
        info: { 'ID' => 'abc' },
        version: { 'Version' => '27.0' },
        containers:,
      )
    end

    # A bundle collected while the daemon is down must still be produced; the
    # Docker sections then carry the error instead of failing the whole run.
    it 'reports an unreachable daemon as an error entry' do
      allow(Orchestration::Connection).to receive(:configure!)
      allow(Docker).to receive(:info).and_raise(Excon::Error::Socket.new(StandardError.new('no socket')))

      expect(described_class.fetch_snapshot[:error]).to start_with('unavailable: Excon::Error::Socket')
    end
  end

  describe '.network_membership' do
    it 'groups containers by attached network' do
      containers = [
        fake_container('helios', { 'default' => {} }),
        fake_container('influxdb', { 'solectrus_default' => {} }),
        fake_container('dashboard', { 'solectrus_default' => {} }),
      ]

      expect(described_class.network_membership(containers)).to eq(
        'default' => ['helios'],
        'solectrus_default' => %w[influxdb dashboard],
      )
    end

    it 'lists a container under each network it is attached to' do
      containers = [fake_container('proxy', { 'frontend' => {}, 'backend' => {} })]

      expect(described_class.network_membership(containers)).to eq(
        'frontend' => ['proxy'],
        'backend' => ['proxy'],
      )
    end

    it 'ignores containers without network settings' do
      bare = instance_double(Docker::Container, info: { 'Names' => ['/orphan'] })

      expect(described_class.network_membership([bare])).to eq({})
    end

    def fake_container(name, networks)
      instance_double(
        Docker::Container,
        info: { 'Names' => ["/#{name}"], 'NetworkSettings' => { 'Networks' => networks } },
      )
    end
  end
end
