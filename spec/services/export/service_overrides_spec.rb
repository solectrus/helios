RSpec.describe Export::ServiceOverrides do
  before { with_config_yaml }

  let(:configuration) { Configuration.current }

  describe '.apply' do
    subject(:apply) { described_class.apply(configuration, service_name, service_hash) }

    let(:service_name) { 'mqtt-collector' }
    let(:service_hash) { { image: 'foo:1', labels: %w[a=1 watchtower.scope=solectrus] } }

    context 'without overrides configured' do
      it 'returns the service hash unchanged' do
        expect(apply).to eq(service_hash)
      end
    end

    context 'with override for an unrelated service' do
      before do
        configuration.update('service_overrides', { 'dashboard' => { 'labels' => ['x=1'] } })
      end

      it 'leaves this service alone' do
        expect(apply[:labels]).to eq(%w[a=1 watchtower.scope=solectrus])
      end
    end

    context 'with labels override' do
      before do
        configuration.update('service_overrides', {
                               service_name => { 'labels' => ['traefik.foo=1', 'traefik.bar=2'] },
                             })
      end

      it 'appends override labels after the generated ones' do
        expect(apply[:labels]).to eq(%w[a=1 watchtower.scope=solectrus traefik.foo=1 traefik.bar=2])
      end
    end

    context 'with ports override on a service that has no ports' do
      let(:service_hash) { { image: 'foo:1' } }

      before do
        configuration.update('service_overrides', { service_name => { 'ports' => ['8086:8086'] } })
      end

      it 'sets the ports field' do
        expect(apply[:ports]).to eq(['8086:8086'])
      end
    end

    context 'with volumes override on a service with existing volumes' do
      let(:service_hash) { { image: 'foo:1', volumes: ['./data:/data'] } }

      before do
        configuration.update('service_overrides', { service_name => { 'volumes' => ['./ca.pem:/etc/ssl/ca.pem:ro'] } })
      end

      it 'appends the new mount' do
        expect(apply[:volumes]).to eq(['./data:/data', './ca.pem:/etc/ssl/ca.pem:ro'])
      end
    end

    context 'with environment override (list form)' do
      let(:service_hash) { { image: 'foo:1', environment: ['TZ', 'POWER_SPLITTER_INTERVAL=300'] } }

      before do
        configuration.update('service_overrides', {
                               service_name => { 'environment' => ['CUSTOM_FLAG=on', 'TZ=UTC'] },
                             })
      end

      it 'merges with override-wins per name' do
        expect(apply[:environment]).to eq(['POWER_SPLITTER_INTERVAL=300', 'CUSTOM_FLAG=on', 'TZ=UTC'])
      end
    end

    context 'with environment override (hash form)' do
      let(:service_hash) { { image: 'foo:1', environment: ['TZ'] } }

      before do
        configuration.update('service_overrides', {
                               service_name => { 'environment' => { 'CUSTOM_FLAG' => 'on' } },
                             })
      end

      it 'normalizes the hash and merges' do
        expect(apply[:environment]).to eq(['TZ', 'CUSTOM_FLAG=on'])
      end
    end

    context 'with disallowed override key persisted in config.yaml' do
      before do
        FileUtils.mkdir_p(File.dirname(Configuration.path))
        File.write(Configuration.path, YAML.dump(
                                         'service_overrides' => {
                                           service_name => {
                                             'labels' => ['x=1'],
                                             'privileged' => true,
                                           },
                                         },
                                       ))
        Current.configuration = nil
      end

      it 'ignores the unallowed key (only allowlist is applied)' do
        expect(apply[:labels]).to eq(%w[a=1 watchtower.scope=solectrus x=1])
        expect(apply.key?(:privileged)).to be false
      end
    end
  end
end
