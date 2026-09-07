RSpec.describe BackupRepository::Sidecar do
  # The real adapters build a `docker run …` command line; the module itself
  # only cares that it gets one, so a plain shell command keeps this spec free
  # of Docker while exercising the real pipes.
  let(:adapter) do
    Class.new do
      include BackupRepository::Sidecar

      attr_writer :command

      def sidecar_command(*_cmd) = @command
    end.new
  end

  describe '#stream_sidecar_archive' do
    it 'parses the tar the sidecar writes to stdout' do
      tar_path = File.join(Dir.mktmpdir, 'backup.tar')
      File.binwrite(tar_path, config_only_tar)
      adapter.command = ['cat', tar_path]

      archive = adapter.stream_sidecar_archive('cat', '/data/backup.tar')

      expect(archive.entries.map(&:name)).to eq(['helios/config.yaml'])
      expect(archive.config).to eq('system' => {})
    end

    # Every failure ends the same way: an empty archive and a log line, never
    # an exception that would take the backup list down.
    {
      'exits non-zero' => ['sh', '-c', 'exit 2'],
      # What an S3 object that is not readable yet looks like.
      'writes nothing at all' => ['true'],
      # A proxy error page, or a partial object.
      'writes something that is not a tar' => ['sh', '-c', 'yes y | head -c 1024'],
      'cannot be launched' => ['definitely-no-such-binary'],
    }.each do |reason, command|
      it "returns an empty archive when the sidecar #{reason}" do
        adapter.command = command

        expect(adapter.stream_sidecar_archive('cat', '/data/backup.tar')).to eq(BackupRepository::EMPTY_ARCHIVE)
      end
    end
  end
end
