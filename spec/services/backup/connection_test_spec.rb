RSpec.describe Backup::ConnectionTest do
  subject(:tester) { described_class.new }

  describe 'external_path check' do
    def probe(path)
      tester.call(check: 'external_path', values: { 'external_path' => path })
    end

    it 'reports incomplete when path is blank' do
      expect(probe('')).to have_attributes(ok: false, reason: :incomplete)
    end

    it 'rejects relative paths up front (no docker call)' do
      allow(Open3).to receive(:capture2e)
      expect(probe('relative/path')).to have_attributes(ok: false, reason: :backup_path_not_absolute)
      expect(Open3).not_to have_received(:capture2e)
    end

    it 'rejects paths with shell-significant characters up front' do
      allow(Open3).to receive(:capture2e)
      expect(probe('/mnt/with spaces')).to have_attributes(ok: false, reason: :backup_path_invalid_chars)
      expect(Open3).not_to have_received(:capture2e)
    end

    it 'reports writable on sidecar exit 0' do
      stub_probe(exitstatus: 0, output: '')
      expect(probe('/mnt/backups')).to have_attributes(ok: true, reason: :backup_path_writable)
    end

    it 'maps sidecar exit 10 to backup_path_not_directory' do
      stub_probe(exitstatus: 10, output: '')
      expect(probe('/mnt/backups')).to have_attributes(ok: false, reason: :backup_path_not_directory)
    end

    it 'maps sidecar exit 11 to backup_path_not_writable' do
      stub_probe(exitstatus: 11, output: '')
      expect(probe('/mnt/backups')).to have_attributes(ok: false, reason: :backup_path_not_writable)
    end

    it 'maps a docker "no such file" error to backup_path_missing' do
      stub_probe(exitstatus: 125, output: 'docker: Error: stat /mnt/backups: no such file or directory.')
      expect(probe('/mnt/backups')).to have_attributes(ok: false, reason: :backup_path_missing)
    end

    it 'falls back to backup_path_error for unrecognized failures' do
      stub_probe(exitstatus: 2, output: 'unexpected gibberish')
      expect(probe('/mnt/backups')).to have_attributes(ok: false, reason: :backup_path_error)
    end

    it 'reports error when the docker call raises' do
      allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT, 'docker missing')
      expect(probe('/mnt/backups')).to have_attributes(ok: false, reason: :backup_path_error)
    end
  end

  def stub_probe(exitstatus:, output:)
    status = instance_double(Process::Status, exitstatus: exitstatus, success?: exitstatus.zero?)
    allow(Open3).to receive(:capture2e).and_return([output, status])
  end
end
