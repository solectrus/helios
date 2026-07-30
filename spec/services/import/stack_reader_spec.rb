RSpec.describe Import::StackReader do
  describe '.image_matches?' do
    it 'accepts an exact-match image' do
      expect(described_class.image_matches?('postgres', 'postgres')).to be true
    end

    it 'accepts a tagged image' do
      expect(described_class.image_matches?('postgres:16-alpine', 'postgres')).to be true
    end

    it 'accepts a digest-pinned image' do
      expect(described_class.image_matches?('postgres@sha256:abc', 'postgres')).to be true
    end

    it 'rejects a different image with the same leading name' do
      # postgresql-backup is a distinct product — must not be claimed as plain postgres.
      expect(described_class.image_matches?('ghcr.io/solectrus/postgres-s3-backup', 'postgres')).to be false
    end

    it 'accepts a match against any entry in a prefix array' do
      expect(
        described_class.image_matches?('nickfedor/watchtower:latest',
                                       %w[containrrr/watchtower nickfedor/watchtower]),
      ).to be true
    end
  end

  describe '.managed_image?' do
    it 'recognizes all registered image prefixes' do
      expect(described_class.managed_image?('ghcr.io/solectrus/solectrus:latest')).to be true
      expect(described_class.managed_image?('postgres:18-alpine')).to be true
      expect(described_class.managed_image?('nickfedor/watchtower:latest')).to be true
    end

    it 'rejects unknown images' do
      expect(described_class.managed_image?('amir20/dozzle:latest')).to be false
      expect(described_class.managed_image?('custom/app:v1')).to be false
    end

    it 'returns false for nil' do
      expect(described_class.managed_image?(nil)).to be false
    end
  end

  describe 'invalid compose project' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:compose_path) { File.join(tmpdir, 'compose.yaml') }
    let(:env_path) { File.join(tmpdir, '.env') }
    let(:reader) { described_class.new(compose_path: compose_path, env_path: env_path) }

    after { FileUtils.remove_entry(tmpdir) }

    it 'raises Error carrying the docker message without warning noise' do
      # ${UNDEFINED_VAR} triggers a warning; the undefined depends_on fails.
      File.write(compose_path, <<~YAML)
        services:
          app:
            image: ghcr.io/solectrus/solectrus:latest
            environment:
              FOO: ${UNDEFINED_VAR}
            depends_on:
              - missing
      YAML
      File.write(env_path, '')

      expect { reader.services }.to raise_error(described_class::Error) do |error|
        expect(error.detail).to include('missing')
        expect(error.detail).not_to include('level=warning')
      end
    end
  end

  # Hand-edited .env files are regularly Latin-1. docker reads them, but
  # replaces the invalid bytes with U+FFFD — so without normalization the
  # resolved value and raw_env disagree, and the extractors read both.
  describe 'a .env that is not UTF-8' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:compose_path) { File.join(tmpdir, 'compose.yaml') }
    let(:env_path) { File.join(tmpdir, '.env') }
    let(:reader) { described_class.new(compose_path: compose_path, env_path: env_path) }

    before do
      File.write(compose_path, <<~YAML)
        services:
          dashboard:
            image: ghcr.io/solectrus/solectrus:latest
            environment:
              ADMIN_PASSWORD: ${ADMIN_PASSWORD}
      YAML
      File.binwrite(env_path, "ADMIN_PASSWORD=gehe\xFCm\n")
    end

    after { FileUtils.remove_entry(tmpdir) }

    it 'resolves values the way raw_env reads them' do
      expect(reader.service('dashboard')['environment']['ADMIN_PASSWORD']).to eq('geheüm')
      expect(reader.raw_env['ADMIN_PASSWORD']).to eq('geheüm')
    end
  end

  describe 'image-based aliasing' do
    # Legacy SOLECTRUS installations often use historical service names:
    # 'app' instead of 'dashboard', 'db' instead of 'postgresql'. Callers should
    # be able to look these up under the canonical name without caring about
    # what the user chose to name the service.
    let(:tmpdir) { Dir.mktmpdir }
    let(:compose_path) { File.join(tmpdir, 'compose.yaml') }
    let(:env_path) { File.join(tmpdir, '.env') }
    let(:reader) { described_class.new(compose_path: compose_path, env_path: env_path) }

    before do
      File.write(compose_path, <<~YAML)
        services:
          app:
            image: ghcr.io/solectrus/solectrus:latest
          db:
            image: postgres:16-alpine
      YAML
      File.write(env_path, '')
    end

    after { FileUtils.remove_entry(tmpdir) }

    it 'resolves canonical names via image prefix' do
      expect(reader.service('dashboard')).to include('image' => 'ghcr.io/solectrus/solectrus:latest')
      expect(reader.service('postgresql')).to include('image' => 'postgres:16-alpine')
    end

    it 'preserves the original service names too' do
      expect(reader.services.keys).to include('app', 'db', 'dashboard', 'postgresql')
    end

    it 'skips aliasing when the canonical name already exists' do
      File.write(compose_path, <<~YAML)
        services:
          dashboard:
            image: ghcr.io/solectrus/solectrus:develop
          app:
            image: ghcr.io/solectrus/solectrus:latest
      YAML

      # The actual 'dashboard' service wins over the aliased 'app'
      expect(reader.service('dashboard')).to include('image' => 'ghcr.io/solectrus/solectrus:develop')
    end

    it 'aliases the first service when multiple share the prefix' do
      # Two services share the mqtt-collector image. The first one in source
      # order wins the canonical alias; the second keeps its own name and is
      # treated as unmanaged downstream.
      File.write(compose_path, <<~YAML)
        services:
          mqtt-primary:
            image: ghcr.io/solectrus/mqtt-collector:0.7.4
          mqtt-secondary:
            image: ghcr.io/solectrus/mqtt-collector:0.7.4
      YAML

      expect(reader.service('mqtt-collector'))
        .to include('image' => 'ghcr.io/solectrus/mqtt-collector:0.7.4')
      expect(reader.service('mqtt-collector').object_id)
        .to eq(reader.service('mqtt-primary').object_id)
    end

    it 'picks source order, not alphabetical order, when multiple share the prefix' do
      # `docker compose config` alphabetizes services in its JSON output, so the
      # canonical pick must come from raw_compose (original YAML) — otherwise
      # `forecast-collector-forecast-solar` would beat `forecast-collector-pvnode`
      # even though the user listed pvnode first (real-world: user5).
      File.write(compose_path, <<~YAML)
        services:
          forecast-collector-pvnode:
            image: ghcr.io/solectrus/forecast-collector:latest
            environment:
              - FORECAST_PROVIDER=pvnode
          forecast-collector-forecast-solar:
            image: ghcr.io/solectrus/forecast-collector:latest
            environment:
              - FORECAST_PROVIDER=forecast.solar
      YAML

      expect(reader.service('forecast-collector')['environment'])
        .to include('FORECAST_PROVIDER' => 'pvnode')
    end
  end
end
