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

    it 'refuses to alias when multiple services share the prefix' do
      # Two shelly-collector services — ambiguous, so no alias is added.
      File.write(compose_path, <<~YAML)
        services:
          shelly-fridge:
            image: ghcr.io/solectrus/shelly-collector:latest
          shelly-washer:
            image: ghcr.io/solectrus/shelly-collector:latest
      YAML

      expect(reader.services).not_to have_key('shelly-collector')
    end
  end
end
