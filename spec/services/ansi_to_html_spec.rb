RSpec.describe AnsiToHtml do
  describe '.convert' do
    it 'returns plain text unchanged' do
      expect(described_class.convert('hello world')).to eq('hello world')
    end

    it 'returns empty string for nil' do
      expect(described_class.convert(nil)).to eq('')
    end

    it 'escapes HTML entities' do
      expect(described_class.convert('<script>alert("xss")</script>')).to eq(
        '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;',
      )
    end

    it 'converts foreground colors' do
      input = "\e[31mred text\e[0m"
      expect(described_class.convert(input)).to eq(
        '<span style="color:red">red text</span>',
      )
    end

    it 'converts background colors' do
      input = "\e[42mgreen bg\e[0m"
      expect(described_class.convert(input)).to eq(
        '<span style="background-color:green">green bg</span>',
      )
    end

    it 'converts bright foreground colors' do
      input = "\e[91mbright red\e[0m"
      expect(described_class.convert(input)).to eq(
        '<span style="color:#f55">bright red</span>',
      )
    end

    it 'converts bold text' do
      input = "\e[1mbold\e[0m"
      expect(described_class.convert(input)).to eq(
        '<span style="font-weight:bold">bold</span>',
      )
    end

    it 'converts dim text' do
      input = "\e[2mdim\e[0m"
      expect(described_class.convert(input)).to eq(
        '<span style="opacity:0.7">dim</span>',
      )
    end

    it 'converts italic text' do
      input = "\e[3mitalic\e[0m"
      expect(described_class.convert(input)).to eq(
        '<span style="font-style:italic">italic</span>',
      )
    end

    it 'converts underlined text' do
      input = "\e[4munderline\e[0m"
      expect(described_class.convert(input)).to eq(
        '<span style="text-decoration:underline">underline</span>',
      )
    end

    it 'converts bright background colors' do
      input = "\e[102mbright green bg\e[0m"
      expect(described_class.convert(input)).to eq(
        '<span style="background-color:#5f5">bright green bg</span>',
      )
    end

    it 'handles combined codes' do
      input = "\e[1;31mbold red\e[0m"
      expect(described_class.convert(input)).to eq(
        '<span style="font-weight:bold;color:red">bold red</span>',
      )
    end

    it 'closes unclosed spans at end' do
      input = "\e[32mno reset"
      expect(described_class.convert(input)).to eq(
        '<span style="color:green">no reset</span>',
      )
    end

    it 'handles reset in the middle' do
      input = "\e[31mred\e[0m normal \e[32mgreen\e[0m"
      expect(described_class.convert(input)).to eq(
        '<span style="color:red">red</span> normal <span style="color:green">green</span>',
      )
    end

    it 'strips unknown codes gracefully' do
      input = "\e[99munknown\e[0m"
      expect(described_class.convert(input)).to eq('unknown')
    end

    it 'handles empty escape sequence' do
      input = "\e[mtext"
      expect(described_class.convert(input)).to eq('text')
    end
  end
end
