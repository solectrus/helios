RSpec.describe StackBackup do
  let(:dir) { with_config_yaml }
  let(:compose_path) { File.join(dir, 'compose.yaml') }
  let(:env_path) { File.join(dir, '.env') }

  before do
    File.write(compose_path, "services: {}\n")
    File.write(env_path, "TZ=Europe/Berlin\n")
  end

  describe '.create!' do
    it 'copies the current stack files next to the originals' do
      described_class.create!

      expect(File.read("#{compose_path}.bak")).to eq("services: {}\n")
      expect(File.read("#{env_path}.bak")).to eq("TZ=Europe/Berlin\n")
      expect(described_class).to exist
    end

    it 'skips a file that is not there' do
      File.delete(env_path)

      described_class.create!

      expect(File.exist?("#{env_path}.bak")).to be(false)
      expect(described_class).not_to exist
    end

    # The file can vanish between the existence check and the copy (an import
    # running in parallel). Losing the backup is acceptable, raising is not.
    it 'ignores a file that vanishes while it is copied' do
      allow(FileUtils).to receive(:cp).and_raise(Errno::ENOENT, compose_path)

      expect { described_class.create! }.not_to raise_error
      expect(described_class).not_to exist
    end
  end

  describe '.restore' do
    # A copy, not a move: the backup is the user's pre-HELIOS original and a
    # later reset must be able to revert to it again.
    it 'copies the backup back and keeps it in place' do
      described_class.create!
      File.write(compose_path, "services:\n  edited: {}\n")

      described_class.restore(compose_path)

      expect(File.read(compose_path)).to eq("services: {}\n")
      expect(File.exist?("#{compose_path}.bak")).to be(true)
    end
  end

  describe '.discard!' do
    it 'removes both backups' do
      described_class.create!

      described_class.discard!

      expect(described_class).not_to exist
      expect(File.exist?("#{compose_path}.bak")).to be(false)
      expect(File.exist?("#{env_path}.bak")).to be(false)
    end

    it 'does nothing when there is no backup' do
      expect { described_class.discard! }.not_to raise_error
    end
  end
end
