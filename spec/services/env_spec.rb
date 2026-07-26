RSpec.describe Env do
  let(:data_path) { Rails.root.join("tmp/env#{ENV.fetch('TEST_ENV_NUMBER', nil)}").to_s }

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(data_path)
  end

  after { FileUtils.rm_rf(data_path) }

  describe '.spawn_overrides' do
    it 'maps every key of the file to nil so the child process loses it' do
      File.write(described_class.path, <<~ENV_FILE)
        # comment
        ADMIN_PASSWORD=secret
        TZ=Europe/Berlin
      ENV_FILE

      expect(described_class.spawn_overrides).to eq(
        'ADMIN_PASSWORD' => nil,
        'TZ' => nil,
      )
    end

    it 'reads the given path when one is passed' do
      other = File.join(data_path, 'other.env')
      File.write(other, "SECRET_KEY_BASE=abc\n")

      expect(described_class.spawn_overrides(other)).to eq('SECRET_KEY_BASE' => nil)
    end

    it 'returns an empty hash when the file is missing' do
      expect(described_class.spawn_overrides).to eq({})
    end
  end
end
