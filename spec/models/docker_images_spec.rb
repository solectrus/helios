RSpec.describe DockerImages do
  describe '.current' do
    it 'returns the :current string for single-version services' do
      expect(described_class.current(:INFLUXDB)).to eq('influxdb:2.9-alpine')
    end

    it 'unwraps the first `{image:, label:}` hash for multi-version services' do
      expect(described_class.current(:DASHBOARD))
        .to eq(DockerImages::DASHBOARD[:current].first[:image])
    end
  end

  describe '.recommended_for' do
    it 'returns the current image for a known service' do
      expect(described_class.recommended_for('influxdb')).to eq('influxdb:2.9-alpine')
    end

    it 'derives the registry name from a hyphenated compose name' do
      expect(described_class.recommended_for('senec-collector'))
        .to eq(described_class.current(:SENEC_COLLECTOR))
    end

    it 'returns nil for unknown services' do
      expect(described_class.recommended_for('foobar')).to be_nil
    end
  end

  describe '.legacy?' do
    before do
      stub_const(
        'DockerImages::INFLUXDB',
        { current: 'influxdb:9-alpine', legacy: %w[influxdb:7-alpine influxdb:8-alpine].freeze }.freeze,
      )
      stub_const(
        'DockerImages::WATCHTOWER',
        { current: 'nickfedor/watchtower:latest', legacy: %w[containrrr/watchtower].freeze }.freeze,
      )
    end

    it 'is true for a tagged legacy image' do
      expect(described_class.legacy?('influxdb', 'influxdb:7-alpine')).to be true
    end

    it 'is false for the recommended image' do
      expect(described_class.legacy?('influxdb', 'influxdb:9-alpine')).to be false
    end

    it 'is false for a user-pinned image not on the legacy list' do
      expect(described_class.legacy?('influxdb', 'influxdb:8.5-alpine')).to be false
    end

    it 'is false when the image is nil' do
      expect(described_class.legacy?('influxdb', nil)).to be false
    end

    it 'matches a bare-repo legacy entry against any tag from that repo' do
      expect(described_class.legacy?('watchtower', 'containrrr/watchtower:1.7.1')).to be true
      expect(described_class.legacy?('watchtower', 'containrrr/watchtower:latest')).to be true
    end

    it 'does not flag the recommended image even when its repo prefix appears in legacy' do
      expect(described_class.legacy?('watchtower', 'nickfedor/watchtower:latest')).to be false
    end

    it 'returns false for an unknown service' do
      expect(described_class.legacy?('foobar', 'foobar:1.0')).to be false
    end

    it 'returns false when the registry entry has no legacy list' do
      stub_const('DockerImages::INGEST', { current: 'ghcr.io/solectrus/ingest:latest' }.freeze)
      expect(described_class.legacy?('ingest', 'ghcr.io/solectrus/ingest:1.0.0')).to be false
    end

    context 'with a multi-version registry entry (DASHBOARD)' do
      it 'is false for the recommended image' do
        expect(described_class.legacy?('dashboard', described_class.current(:DASHBOARD))).to be false
      end

      it 'is false for a non-default selectable variant' do
        variant = DockerImages::DASHBOARD[:current].last[:image]
        expect(described_class.legacy?('dashboard', variant)).to be false
      end

      it 'is true for an explicit legacy entry' do
        legacy = DockerImages::DASHBOARD[:legacy].first
        expect(described_class.legacy?('dashboard', legacy)).to be true
      end

      it 'is true for an unknown custom tag (e.g. PR build)' do
        expect(described_class.legacy?('dashboard', 'ghcr.io/solectrus/solectrus:pr-9999')).to be true
      end
    end
  end

  describe '.choices' do
    it 'returns nil for single-version services' do
      expect(described_class.choices(:INFLUXDB)).to be_nil
    end

    it 'returns the :current array verbatim for multi-version services' do
      expect(described_class.choices(:DASHBOARD)).to eq(DockerImages::DASHBOARD[:current])
    end
  end

  describe '.selectable' do
    it 'wraps the :current string in an array for single-version services' do
      expect(described_class.selectable(:INFLUXDB)).to eq(['influxdb:2.9-alpine'])
    end

    it 'unwraps every `{image:, label:}` hash for multi-version services' do
      expect(described_class.selectable(:DASHBOARD))
        .to eq(DockerImages::DASHBOARD[:current].pluck(:image))
    end
  end

  describe '.known_for' do
    it 'returns current + tagged legacy for a single-version service' do
      expect(described_class.known_for('redis')).to include('redis:8-alpine', 'redis:7-alpine')
    end

    it 'returns every variant for a multi-version service' do
      expect(described_class.known_for('dashboard')).to include(
        'ghcr.io/solectrus/solectrus:latest',
        'ghcr.io/solectrus/solectrus:develop',
      )
    end

    it 'preserves bare-repo legacy entries verbatim' do
      expect(described_class.known_for('watchtower')).to include('containrrr/watchtower')
    end

    it 'derives the registry name from a hyphenated compose name' do
      expect(described_class.known_for('senec-collector'))
        .to include(described_class.current(:SENEC_COLLECTOR))
    end

    it 'returns an empty array for unknown services' do
      expect(described_class.known_for('foobar')).to eq([])
    end
  end
end
