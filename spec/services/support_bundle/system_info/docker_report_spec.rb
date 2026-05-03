RSpec.describe SupportBundle::SystemInfo::DockerReport do
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
