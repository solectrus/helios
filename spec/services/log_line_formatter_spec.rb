RSpec.describe LogLineFormatter do
  describe '.call' do
    it 'formats a standard Docker Compose log line' do
      line = 'shelly-collector-1  | 2026-03-23T15:28:36.372876006Z Got 5 records'
      html = described_class.call(line)

      expect(html).to include('data-ts="2026-03-23T15:28:36.372876006Z"')
      expect(html).to include('Got 5 records')
      expect(html).not_to include('shelly-collector-1')
    end

    it 'formats the timestamp as local date and time' do
      line = 'app-1  | 2026-03-23T15:28:36.123Z hello'
      html = described_class.call(line)

      expect(html).to include('23.03. ')
      expect(html).to match(/\d{2}:\d{2}:\d{2}/)
    end

    it 'wraps timestamp in a <time> tag with datetime attribute' do
      line = 'app-1  | 2026-03-23T15:28:36.123Z hello'
      html = described_class.call(line)

      expect(html).to include('<time')
      expect(html).to include('datetime="2026-03-23T15:28:36.123Z"')
    end

    it 'renders ANSI colors in the message' do
      line = "app-1  | 2026-03-23T15:28:36.123Z \e[32mgreen\e[0m"
      html = described_class.call(line)

      expect(html).to include('color:green')
      expect(html).to include('green')
    end

    it 'renders lines without timestamp as plain spans' do
      line = 'some output without timestamp format'
      html = described_class.call(line)

      expect(html).to include('block whitespace-pre')
      expect(html).to include('some output without timestamp format')
      expect(html).not_to include('data-ts')
    end

    it 'preserves leading whitespace in the message' do
      line = 'app-1  | 2026-03-23T15:28:36.123Z   => heatpump:status = Warten'
      html = described_class.call(line)

      expect(html).to include('  =&gt; heatpump:status = Warten')
    end

    it 'returns html_safe output' do
      line = 'app-1  | 2026-03-23T15:28:36.123Z hello'
      expect(described_class.call(line)).to be_html_safe
    end

    it 'escapes HTML in the message' do
      line = 'app-1  | 2026-03-23T15:28:36.123Z <b>bold</b>'
      html = described_class.call(line)

      expect(html).to include('&lt;b&gt;bold&lt;/b&gt;')
      expect(html).not_to include('<b>bold</b>')
    end
  end
end
