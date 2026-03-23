# Parses Docker Compose log lines and formats them as HTML.
# Input:  "container-1  | 2024-03-23T14:30:05.123456789Z some message"
# Output: '<span data-ts="..." class="block whitespace-pre">
#           <time ...>14:30:05</time> message</span>'
class LogLineFormatter
  # Matches: anything | ISO-timestamp rest-of-line
  LINE_RE = /\A.*?\|\s*(\d{4}-\d{2}-\d{2}T[\d:.]+Z) (.*)/m

  def self.call(raw_line)
    new(raw_line).to_html
  end

  def initialize(raw_line)
    @raw_line = raw_line
  end

  def to_html
    html = if (match = @raw_line.match(LINE_RE))
             formatted_line(match[1], match[2])
           else
             plain_line
           end

    ActiveSupport::SafeBuffer.new(html)
  end

  private

  def formatted_line(timestamp, message)
    time = format_time(timestamp)
    content = AnsiToHtml.convert(message)
    time_tag = "<time class=\"text-base-content/40 select-none\" datetime=\"#{timestamp}\">#{time}</time>"

    "<span data-ts=\"#{timestamp}\" class=\"block whitespace-pre\">#{time_tag} #{content}</span>"
  end

  def plain_line
    "<span class=\"block whitespace-pre\">#{AnsiToHtml.convert(@raw_line)}</span>"
  end

  def format_time(iso_string)
    Time.zone.parse(iso_string).strftime('%d.%m. %H:%M:%S')
  rescue ArgumentError, NoMethodError
    ''
  end
end
