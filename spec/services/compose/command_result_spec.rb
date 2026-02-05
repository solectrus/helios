RSpec.describe Compose::CommandResult do
  let(:result) do
    described_class.new(output: 'Container started', exit_status: 0)
  end

  describe '#success?' do
    it 'returns true when exit status is 0' do
      expect(result.success?).to be true
    end

    it 'returns false when exit status is non-zero' do
      failed_result = described_class.new(output: 'error', exit_status: 1)
      expect(failed_result.success?).to be false
    end
  end

  describe '#output' do
    it 'returns the command output' do
      expect(result.output).to eq('Container started')
    end
  end

  describe '#to_s' do
    it 'returns the output' do
      expect(result.to_s).to eq('Container started')
    end
  end
end
