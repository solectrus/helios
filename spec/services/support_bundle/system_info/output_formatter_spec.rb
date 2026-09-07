RSpec.describe SupportBundle::SystemInfo::OutputFormatter do
  describe '.format_body' do
    it 'aligns the keys of a hash body' do
      expect(described_class.format_body({ 'a' => 1, 'long key' => 2 })).to eq(
        ['a         1', 'long key  2'],
      )
    end

    # Multi-line values (a captured command output) start on their own line and
    # stay indented, so they do not break the key column.
    it 'indents a multi-line value below its key' do
      expect(described_class.format_body({ 'out' => "one\ntwo\n" })).to eq(
        ["out  \n  one\n  two"],
      )
    end
  end

  describe '.capture' do
    it 'returns the stripped output of a successful command' do
      expect(described_class.capture('echo', 'hello')).to eq('hello')
    end

    it 'reports the exit code of a failing command' do
      expect(described_class.capture('sh', '-c', 'echo boom; exit 3')).to eq('failed (exit 3): boom')
    end

    it 'reports a command that cannot be executed at all' do
      expect(described_class.capture('definitely-no-such-binary')).to start_with('unavailable: Errno::ENOENT')
    end
  end

  describe '.value_after' do
    it 'returns the stripped remainder, and nil when there is none to take' do
      expect(described_class.value_after('model name : Intel', ':')).to eq('Intel')
      # A separator inside the value belongs to the value.
      expect(described_class.value_after('ID=my=host', '=')).to eq('my=host')
      expect(described_class.value_after(nil, ':')).to be_nil
      expect(described_class.value_after('no separator here', ':')).to be_nil
    end
  end

  describe '.human_bytes' do
    it 'formats a byte count, and reports non-numeric input as unknown' do
      expect(described_class.human_bytes(2048)).to eq('2 KB')
      expect(described_class.human_bytes(nil)).to eq('unknown')
    end
  end

  describe '.int_or_nil' do
    it 'parses an integer, and answers nil for anything else' do
      expect(described_class.int_or_nil('-5')).to eq(-5)
      expect(described_class.int_or_nil('max')).to be_nil
    end
  end
end
