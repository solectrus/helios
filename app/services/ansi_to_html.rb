# Converts ANSI SGR escape sequences to HTML <span> tags.
# Handles standard colors (30-37, 40-47), bright colors (90-97, 100-107),
# bold (1), and reset (0). Unknown codes are silently ignored.
class AnsiToHtml
  COLORS = %w[black red green yellow blue magenta cyan white].freeze

  BRIGHT = {
    'black' => '#555', 'red' => '#f55', 'green' => '#5f5', 'yellow' => '#ff5',
    'blue' => '#55f', 'magenta' => '#f5f', 'cyan' => '#5ff', 'white' => '#fff'
  }.freeze

  ESC_RE = /\e\[([0-9;]*)m/

  def self.convert(text)
    new.convert(text)
  end

  def convert(text)
    return '' if text.nil?

    open_spans = 0
    result = ERB::Util.html_escape(text).gsub(ESC_RE) do
      codes = Regexp.last_match(1).split(';').map(&:to_i)
      html, open_spans = process_codes(codes, open_spans)
      html
    end

    result + ('</span>' * open_spans)
  end

  private

  def process_codes(codes, open_spans)
    html = +''

    if codes.empty? || codes.include?(0)
      html << ('</span>' * open_spans)
      open_spans = 0
      codes = codes.reject(&:zero?)
    end

    styles = codes.filter_map { |c| code_to_style(c) }
    if styles.any?
      html << "<span style=\"#{styles.join(';')}\">"
      open_spans += 1
    end

    [html, open_spans]
  end

  def code_to_style(code)
    case code
    when 1 then 'font-weight:bold'
    when 2 then 'opacity:0.7'
    when 3 then 'font-style:italic'
    when 4 then 'text-decoration:underline'
    when 30..37 then "color:#{COLORS[code - 30]}"
    when 40..47 then "background-color:#{COLORS[code - 40]}"
    when 90..97 then "color:#{BRIGHT[COLORS[code - 90]]}"
    when 100..107 then "background-color:#{BRIGHT[COLORS[code - 100]]}"
    end
  end
end
