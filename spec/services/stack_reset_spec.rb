RSpec.describe StackReset do
  let(:dir) { with_config_yaml }
  let(:compose_path) { File.join(dir, 'compose.yaml') }
  let(:env_path) { File.join(dir, '.env') }
  let(:original_compose) { "services:\n  dashboard:\n    image: original:latest\n" }
  let(:original_env) { "TZ=Europe/Berlin\n" }

  before do
    File.write(compose_path, "services:\n  dashboard:\n    image: edited:latest\n")
    File.write(env_path, "TZ=UTC\n")
    File.write(StackBackup.backup_path(compose_path), original_compose)
    File.write(StackBackup.backup_path(env_path), original_env)
  end

  describe '.perform!' do
    before do
      FileUtils.mkdir_p(File.dirname(Configuration.path))
      File.write(Configuration.path, YAML.dump('system' => { 'timezone' => 'UTC' }))

      allow(Orchestration::Runner).to receive(:down)
      allow(Orchestration::StackStatus).to receive(:refresh!)
      allow(Import::StackReader).to receive(:new).and_return(instance_double(Import::StackReader))
      allow(Import::ConfigurationImporter).to receive(:new)
        .and_return(instance_double(Import::ConfigurationImporter, import!: nil))
      allow(Export::Builder).to receive(:new).and_return(instance_double(Export::Builder, write!: nil))
    end

    it 'restores compose.yaml from the backup' do
      described_class.perform!
      expect(File.read(compose_path)).to eq(original_compose)
    end

    it 'restores .env from the backup' do
      described_class.perform!
      expect(File.read(env_path)).to eq(original_env)
    end

    it 'creates fresh backups from the restored files' do
      described_class.perform!
      expect(File.read(StackBackup.backup_path(compose_path))).to eq(original_compose)
      expect(File.read(StackBackup.backup_path(env_path))).to eq(original_env)
    end

    it 'deletes the existing config.yaml' do
      described_class.perform!
      expect(File.exist?(Configuration.path)).to be false
    end

    it 'raises when backup files are missing' do
      File.delete(StackBackup.backup_path(compose_path))
      expect { described_class.perform! }.to raise_error(/Backup files missing/)
    end
  end

  describe '.postgresql_downgrade?' do
    before do
      FileUtils.mkdir_p(File.dirname(Configuration.path))
      File.write(Configuration.path, YAML.dump('postgresql' => { 'image' => 'postgres:18-alpine' }))
    end

    def write_backup_compose(services)
      File.write(StackBackup.backup_path(compose_path), "services:\n#{services}")
    end

    it 'is true when the backup pins an older PostgreSQL major' do
      write_backup_compose("  postgresql:\n    image: postgres:17-alpine\n")
      expect(described_class.postgresql_downgrade?).to be true
    end

    it 'is false when the backup pins the same PostgreSQL major' do
      write_backup_compose("  postgresql:\n    image: postgres:18-alpine\n")
      expect(described_class.postgresql_downgrade?).to be false
    end

    it 'is false when the backup has no PostgreSQL service' do
      write_backup_compose("  dashboard:\n    image: dashboard:latest\n")
      expect(described_class.postgresql_downgrade?).to be false
    end
  end
end
