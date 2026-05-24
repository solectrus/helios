RSpec.describe BackupRepository::S3::Downloader do
  let(:filename) { 'solectrus-backup-20260508-100000.tar' }
  let(:staging_dir) { BackupRepository::S3.directory }
  let(:staged_tar) { File.join(staging_dir, filename) }
  let(:error_file) { File.join(staging_dir, RestoreRunner::ERROR_FILENAME) }

  before do
    with_config_yaml('backup' => {
                       'destination' => 's3', 'aws_bucket' => 'my-bucket',
                       'aws_access_key_id' => 'AKIA', 'aws_secret_access_key' => 'secret',
                       'aws_region' => 'eu-central-1'
                     })
    FileUtils.mkdir_p(staging_dir)
    reset_class_state
  end

  describe '.start_async / .current' do
    it 'is idempotent while a thread is alive' do
      gate = Queue.new
      allow(described_class).to receive(:run) do |_filename|
        gate.pop
      end

      expect(described_class.start_async(filename)).to be(true)
      expect(described_class.start_async(filename)).to be(false)

      gate << :go
      described_class.send(:instance_variable_get, :@thread).join
    end

    it 'exposes an :downloading InProgress snapshot while running, then nil after' do
      gate = Queue.new
      allow(described_class).to receive(:run) { gate.pop }

      described_class.start_async(filename)

      snapshot = described_class.current
      aggregate_failures do
        expect(snapshot).to be_a(BackupRepository::InProgress)
        expect(snapshot.filename).to eq(filename)
        expect(snapshot.phase).to eq(:downloading)
        expect(snapshot.progress).to eq(0.0)
      end

      gate << :go
      described_class.send(:instance_variable_get, :@thread).join
      expect(described_class.current).to be_nil
    end
  end

  describe '.run (synchronous worker)' do
    before { allow(BackupRepository::S3).to receive(:download_to_staging!) }

    it 'downloads then invokes the on_complete block' do
      sentinel = Object.new
      called_with = nil
      callback = ->(*) { called_with = sentinel }

      described_class.send(:run, filename, &callback)

      expect(BackupRepository::S3)
        .to have_received(:download_to_staging!)
        .with(filename, progress_callback: kind_of(Proc))
      expect(called_with).to eq(sentinel)
    end

    it 'writes a restore-error and clears the staged tar on download failure' do
      FileUtils.touch(staged_tar)
      allow(BackupRepository::S3)
        .to receive(:download_to_staging!)
        .and_raise(BackupRepository::Error, 'AccessDenied: bucket missing')

      described_class.send(:run, filename) { raise 'on_complete must not be called on failure' }

      expect(File).not_to exist(staged_tar)
      expect(File.read(error_file)).to include('S3 download failed').and include('AccessDenied')
    end

    it 'writes the raw error from on_complete (no S3-download prefix) when post-download work fails' do
      described_class.send(:run, filename) { raise RestoreRunner::Error, 'INFLUX_ADMIN_TOKEN missing' }

      expect(File.read(error_file)).to eq('INFLUX_ADMIN_TOKEN missing')
    end
  end

  describe 'progress reporting' do
    it 'reflects the latest TransferManager callback in #current' do
      gate = Queue.new
      captured = nil
      allow(BackupRepository::S3).to receive(:download_to_staging!) do |_filename, progress_callback:|
        captured = progress_callback
        gate.pop
      end

      described_class.start_async(filename)
      Timeout.timeout(1) { sleep 0.01 until captured }

      captured.call(125, 500)

      expect(described_class.current.progress).to be_within(0.001).of(0.25)

      gate << :go
      described_class.send(:instance_variable_get, :@thread).join
    end
  end

  def reset_class_state
    described_class.instance_variables.each do |ivar|
      described_class.remove_instance_variable(ivar) if described_class.instance_variable_defined?(ivar)
    end
  end
end
