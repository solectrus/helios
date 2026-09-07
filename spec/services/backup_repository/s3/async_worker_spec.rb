RSpec.describe BackupRepository::S3::AsyncWorker do
  it 'demands a phase from every worker, and reports none while idle' do
    expect { described_class.default_phase }.to raise_error(NotImplementedError)
    expect(BackupRepository::S3::Uploader.default_phase).to eq(:uploading)
    expect(BackupRepository::S3::Downloader.default_phase).to eq(:downloading)
    expect(described_class.current).to be_nil
    expect(described_class).not_to be_running
  end
end
