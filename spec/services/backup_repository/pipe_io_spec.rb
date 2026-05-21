require 'rubygems/package'

RSpec.describe BackupRepository::PipeIo do
  let(:tar_bytes) do
    StringIO.new.tap do |io|
      Gem::Package::TarWriter.new(io) do |tar|
        tar.add_file_simple('solectrus-postgresql-backup-2026-05-08.sql.gz', 0o644, 1024) { |f| f.write('p' * 1024) }
        tar.add_file_simple('solectrus-influxdb-backup-2026-05-08.tar.gz', 0o644, 2048) { |f| f.write('i' * 2048) }
        config = 'system: {}'
        tar.add_file_simple('helios/config.yaml', 0o644, config.bytesize) { |f| f.write(config) }
      end
    end.string
  end

  it 'lets TarReader iterate a non-seekable IO without raising ESPIPE' do
    IO.pipe.then do |reader, writer|
      writer.binmode
      writer.write(tar_bytes)
      writer.close

      archive = BackupRepository.parse_tar_stream(described_class.new(reader))
      reader.close

      expect(archive.entries.map(&:name)).to contain_exactly(
        'solectrus-postgresql-backup-2026-05-08.sql.gz',
        'solectrus-influxdb-backup-2026-05-08.tar.gz',
        'helios/config.yaml',
      )
      expect(archive.config).to eq('system' => {})
    end
  end

  it 'raises Errno::EINVAL on seek so TarReader falls back to read' do
    pipe = described_class.new(StringIO.new('payload'))
    expect { pipe.seek(0, IO::SEEK_SET) }.to raise_error(Errno::EINVAL)
    expect { pipe.rewind }.to raise_error(Errno::EINVAL)
  end

  it 'tracks position across reads' do
    pipe = described_class.new(StringIO.new('hello world'))
    expect(pipe.pos).to eq(0)
    pipe.read(5)
    expect(pipe.pos).to eq(5)
    pipe.read(6)
    expect(pipe.pos).to eq(11)
  end
end
