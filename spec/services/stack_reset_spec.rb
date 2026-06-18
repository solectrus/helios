RSpec.describe StackReset do
  let(:dir) { with_config_yaml }
  let(:compose_path) { File.join(dir, 'compose.yaml') }
  let(:env_path) { File.join(dir, '.env') }
  let(:original_compose) { "services:\n  dashboard:\n    image: original:latest\n" }
  let(:original_env) { "TZ=Europe/Berlin\n" }

  # Helper methods (not `let`) so the memoized-helper count stays in budget.
  def regenerated_compose = "services:\n  dashboard:\n    image: regenerated:latest\n"
  def regenerated_env = "TZ=Europe/Berlin\nREGENERATED=true\n"

  # The real export regenerates compose.yaml / .env from the imported config,
  # overwriting the just-restored originals. Mirror that here so the specs can
  # tell the original (in the backup) apart from the regenerated output (in the
  # live files).
  def stub_regenerating_export
    builder = instance_double(Export::Builder)
    allow(builder).to receive(:write!) do
      File.write(compose_path, regenerated_compose)
      File.write(env_path, regenerated_env)
    end
    allow(Export::Builder).to receive(:new).and_return(builder)
  end

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

      stub_regenerating_export
    end

    it 'restores the original backup before re-importing' do
      reader = instance_double(Import::StackReader)
      allow(Import::StackReader).to receive(:new).and_return(reader)
      importer = instance_double(Import::ConfigurationImporter)
      allow(Import::ConfigurationImporter).to receive(:new).with(reader).and_return(importer)
      allow(importer).to receive(:import!) do
        # At import time the original config must be in place, not the edited one.
        expect(File.read(compose_path)).to eq(original_compose)
        expect(File.read(env_path)).to eq(original_env)
      end

      described_class.perform!
      expect(importer).to have_received(:import!)
    end

    it 'leaves the regenerated compose.yaml / .env in place after re-import' do
      described_class.perform!
      expect(File.read(compose_path)).to eq(regenerated_compose)
      expect(File.read(env_path)).to eq(regenerated_env)
    end

    it 'preserves the original backup (does not clobber it with regenerated output)' do
      described_class.perform!
      expect(File.read(StackBackup.backup_path(compose_path))).to eq(original_compose)
      expect(File.read(StackBackup.backup_path(env_path))).to eq(original_env)
    end

    it 'keeps the backup available for a repeated reset' do
      described_class.perform!
      expect(StackBackup.exist?).to be true
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
