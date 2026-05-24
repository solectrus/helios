RSpec.describe BackupRepository::S3::Uploader do
  let(:filename) { 'solectrus-backup-20260508-100000.tar' }
  let(:staging_dir) { BackupRepository::S3.directory }
  let(:staged_tar) { File.join(staging_dir, filename) }
  let(:error_file) { File.join(staging_dir, 'error.txt') }

  before do
    with_config_yaml('backup' => {
                       'destination' => 's3', 'aws_bucket' => 'my-bucket',
                       'aws_access_key_id' => 'AKIA', 'aws_secret_access_key' => 'secret',
                       'aws_region' => 'eu-central-1'
                     })
    FileUtils.mkdir_p(staging_dir)

    # Detached BackupRunner is "done" by default — the upload thread's
    # first wait_for_container_exit poll observes a non-running container.
    allow(BackupRunner).to receive(:running?).and_return(false)

    # Force a clean slate between examples — the class holds @thread and
    # @filename across tests when the previous example left them around.
    reset_class_state
  end

  describe '.start_async / .current' do
    it 'is idempotent while a thread is alive' do
      gate = Queue.new
      allow(described_class).to receive(:run) do |_filename|
        # Hold the worker open so the second start_async sees it alive.
        gate.pop
      end

      expect(described_class.start_async(filename)).to be(true)
      expect(described_class.start_async(filename)).to be(false)

      gate << :go
      described_class.send(:instance_variable_get, :@thread).join
    end

    it 'exposes an InProgress snapshot while running, then nil after' do
      gate = Queue.new
      allow(described_class).to receive(:run) { gate.pop }

      described_class.start_async(filename)

      snapshot = described_class.current
      aggregate_failures do
        expect(snapshot).to be_a(BackupRepository::InProgress)
        expect(snapshot.filename).to eq(filename)
        expect(snapshot.phase).to eq(:uploading)
        expect(snapshot.progress).to eq(0.0)
      end

      gate << :go
      described_class.send(:instance_variable_get, :@thread).join
      expect(described_class.current).to be_nil
    end
  end

  describe 'progress reporting' do
    it 'reflects the latest TransferManager callback in #current' do
      gate = Queue.new
      captured = nil
      allow(BackupRepository::S3).to receive(:upload_from_staging!) do |_filename, progress_callback:|
        captured = progress_callback
        gate.pop
      end
      allow(BackupRepository::S3).to receive(:record_from_staging!)
      FileUtils.touch(staged_tar)

      described_class.start_async(filename)
      # Wait for the upload thread to enter upload_from_staging!.
      Timeout.timeout(1) { sleep 0.01 until captured }

      captured.call(750, 1000)

      expect(described_class.current.progress).to be_within(0.001).of(0.75)

      gate << :go
      described_class.send(:instance_variable_get, :@thread).join
    end
  end

  describe '.run (synchronous worker)' do
    before do
      allow(BackupRepository::S3).to receive(:upload_from_staging!)
      allow(BackupRepository::S3).to receive(:record_from_staging!)
    end

    it 'uploads, records and deletes the local tar on success' do
      FileUtils.touch(staged_tar)

      described_class.send(:run, filename)

      expect(BackupRepository::S3)
        .to have_received(:upload_from_staging!).with(filename, progress_callback: kind_of(Proc))
      expect(BackupRepository::S3).to have_received(:record_from_staging!).with(filename)
      expect(File).not_to exist(staged_tar)
      expect(File).not_to exist(error_file)
    end

    it 'skips the upload when the script left an error.txt behind' do
      FileUtils.touch(staged_tar)
      File.write(error_file, 'Disk full')

      described_class.send(:run, filename)

      expect(BackupRepository::S3).not_to have_received(:upload_from_staging!)
      expect(BackupRepository::S3).not_to have_received(:record_from_staging!)
      # The script's error.txt stays for detect_completion! to pick up.
      expect(File.read(error_file)).to eq('Disk full')
    end

    it 'skips the upload when the tar is missing (no record run started)' do
      described_class.send(:run, filename)

      expect(BackupRepository::S3).not_to have_received(:upload_from_staging!)
    end

    it 'writes an error.txt and removes the tar when upload fails' do
      FileUtils.touch(staged_tar)
      allow(BackupRepository::S3).to receive(:upload_from_staging!).and_raise(
        BackupRepository::Error, 'AccessDenied: no write'
      )

      described_class.send(:run, filename)

      expect(File).not_to exist(staged_tar)
      expect(File.read(error_file)).to include('S3 upload failed').and include('AccessDenied')
    end
  end

  describe '.wait_for_container_exit' do
    it 'returns once BackupRunner stops reporting a running container' do
      stub_const("#{described_class}::POLL_INTERVAL", 0.01)
      states = [true, true, false]
      allow(BackupRunner).to receive(:running?) { states.shift }

      expect { described_class.send(:wait_for_container_exit) }.not_to raise_error
      expect(BackupRunner).to have_received(:running?).at_least(3).times
    end

    it 'raises after CONTAINER_WAIT_TIMEOUT when the container never exits' do
      stub_const("#{described_class}::POLL_INTERVAL", 0.01)
      stub_const("#{described_class}::CONTAINER_WAIT_TIMEOUT", 0.02.seconds)
      allow(BackupRunner).to receive(:running?).and_return(true)

      expect { described_class.send(:wait_for_container_exit) }
        .to raise_error(/did not exit/)
    end
  end

  def reset_class_state
    described_class.instance_variables.each do |ivar|
      described_class.remove_instance_variable(ivar) if described_class.instance_variable_defined?(ivar)
    end
  end
end
