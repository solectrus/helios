require 'rails_helper'

RSpec.describe Compose::File do
  let(:fixture_path) { Rails.root.join('spec/fixtures/compose.yaml') }
  let(:tmp_path) { Rails.root.join('tmp/test-compose.yaml') }

  after { FileUtils.rm_f(tmp_path) }

  describe '.load' do
    it 'loads an existing file' do
      compose = described_class.load(fixture_path)
      expect(compose.services).to be_a(Compose::ServiceCollection)
      expect(compose.services.names).to include('helios', 'postgresql', 'redis')
    end

    it 'handles non-existent file' do
      compose = described_class.load('/nonexistent/compose.yaml')
      expect(compose.services).to be_empty
    end

    it 'raises ParseError for invalid YAML' do
      File.write(tmp_path, 'invalid: yaml: content:')
      expect { described_class.load(tmp_path) }.to raise_error(
        Compose::File::ParseError,
      )
    end
  end

  describe '#services' do
    let(:compose) { described_class.load(fixture_path) }

    it 'returns all services' do
      expect(compose.services.names).to eq(%w[helios postgresql redis])
    end

    it 'returns service configuration via find' do
      helios = compose.services.find('helios')
      expect(helios.image).to eq('ghcr.io/solectrus/helios:latest')
      expect(helios.ports).to include('3999:3000')
    end

    it 'allows bracket access' do
      helios = compose.services['helios']
      expect(helios.image).to eq('ghcr.io/solectrus/helios:latest')
    end
  end

  describe '#name' do
    it 'returns the project name' do
      compose = described_class.load(fixture_path)
      expect(compose.name).to eq('solectrus')
    end

    it 'returns nil when not set' do
      compose = described_class.new(tmp_path)
      expect(compose.name).to be_nil
    end
  end

  describe '#name=' do
    it 'sets the project name' do
      compose = described_class.new(tmp_path)
      compose.name = 'myproject'
      expect(compose.name).to eq('myproject')
    end
  end

  describe '#add_service' do
    let(:compose) { described_class.load(fixture_path) }

    it 'adds a new service with hash config' do
      compose.add_service(
        'watchtower',
        image: 'nickfedor/watchtower:latest',
        restart: 'unless-stopped',
      )

      expect(compose.services.exists?('watchtower')).to be true
      expect(compose.services.find('watchtower').image).to eq(
        'nickfedor/watchtower:latest',
      )
    end

    it 'adds a service with nested configuration' do
      compose.add_service(
        'influxdb',
        {
          image: 'influxdb:2-alpine',
          environment: {
            'DOCKER_INFLUXDB_INIT_MODE' => 'setup',
          },
          volumes: ['./influxdb:/var/lib/influxdb2'],
        },
      )

      service = compose.services.find('influxdb')
      expect(service.environment['DOCKER_INFLUXDB_INIT_MODE']).to eq('setup')
      expect(service.volumes).to include('./influxdb:/var/lib/influxdb2')
    end

    it 'accepts symbol keys and converts them to strings' do
      compose.add_service(:newservice, image: 'alpine')
      expect(compose.services.exists?('newservice')).to be true
    end
  end

  describe '#remove_service' do
    let(:compose) { described_class.load(fixture_path) }

    it 'removes an existing service' do
      compose.remove_service('redis')
      expect(compose.services.exists?('redis')).to be false
    end

    it 'handles removing non-existent service' do
      expect { compose.remove_service('nonexistent') }.not_to raise_error
    end
  end

  describe '#save' do
    it 'writes to file' do
      compose = described_class.new(tmp_path)
      compose.name = 'testproject'
      compose.add_service('test', image: 'alpine')
      compose.save

      content = File.read(tmp_path)
      expect(content).to include('name: testproject')
      expect(content).to include('test:')
      expect(content).to include('image: alpine')
    end

    it 'preserves existing services when modifying' do
      FileUtils.cp(fixture_path, tmp_path)
      compose = described_class.load(tmp_path)
      compose.add_service('watchtower', image: 'watchtower:latest')
      compose.save

      reloaded = described_class.load(tmp_path)
      expect(reloaded.services.names).to include(
        'helios',
        'postgresql',
        'redis',
        'watchtower',
      )
    end
  end

  describe '#to_yaml' do
    it 'returns YAML string' do
      compose = described_class.load(fixture_path)
      yaml = compose.to_yaml

      expect(yaml).to include('name: solectrus')
      expect(yaml).to include('services:')
    end
  end

  describe '#to_h' do
    it 'returns the data as a hash' do
      compose = described_class.load(fixture_path)
      hash = compose.to_h

      expect(hash).to be_a(Hash)
      expect(hash['name']).to eq('solectrus')
      expect(hash['services']).to be_a(Hash)
    end
  end
end
