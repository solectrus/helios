module Env
  class File
    class ParseError < StandardError
    end

    def self.load(path)
      new(path).tap(&:load)
    end

    attr_reader :path
    attr_writer :header_comment

    def initialize(path)
      @path = path
      @lines = []
      @variables = {}
    end

    def load
      return unless ::File.exist?(path)

      @lines = ::File.readlines(path, chomp: true)
      parse_lines
      self
    end

    def [](key)
      @variables[key.to_s]
    end

    def []=(key, value)
      key = key.to_s
      @variables[key] = value

      existing_index = find_line_index(key)
      if existing_index
        update_line(existing_index, key, value)
      else
        @lines << "#{key}=#{quote_value(value)}"
      end
    end

    def key?(key)
      @variables.key?(key.to_s)
    end

    delegate :keys, :to_h, to: :@variables

    def delete(key)
      key = key.to_s
      @variables.delete(key)

      index = find_line_index(key)
      @lines.delete_at(index) if index
    end

    def add_comment(text)
      @lines << "# #{text}"
    end

    def add_blank_line
      @lines << ''
    end

    def save
      ::File.write(path, to_s)
    end

    def add_section(title)
      content = "  #{title}  "
      width = [58, content.length].max
      @lines << '#'
      @lines << "# ┌#{'─' * width}┐"
      @lines << "# │#{content.ljust(width)}│"
      @lines << "# └#{'─' * width}┘"
      @lines << '#'
      @lines << ''
    end

    def to_s
      result = @lines.join("\n")
      result = "#{@header_comment}\n#{result}" if @header_comment
      "#{result}\n"
    end

    private

    def parse_lines
      @lines.each do |line|
        next if comment_or_empty?(line)

        key, value = parse_variable(line)
        @variables[key] = value if key
      end
    end

    def comment_or_empty?(line)
      stripped = line.strip
      stripped.empty? || stripped.start_with?('#')
    end

    def parse_variable(line)
      match = line.match(/\A([A-Za-z_][A-Za-z0-9_]*)=(.*)/)
      return nil unless match

      key = match[1]
      value = extract_value(match[2])
      [key, value]
    end

    def extract_value(raw_value)
      value = raw_value

      if value.start_with?('"')
        end_quote = value.index('"', 1)
        return value[1...end_quote] if end_quote
      elsif value.start_with?("'")
        end_quote = value.index("'", 1)
        return value[1...end_quote] if end_quote
      end

      comment_pos = value.index(' #')
      value = value[0...comment_pos] if comment_pos
      value.strip
    end

    def find_line_index(key)
      @lines.find_index { |line| line.match?(/\A#{Regexp.escape(key)}=/) }
    end

    def quote_value(value)
      val = value.to_s
      return val unless needs_quoting?(val)
      return "\"#{val}\"" if val.include?("'")

      "'#{val}'"
    end

    def needs_quoting?(value)
      value.match?(/[\s#'"$]/)
    end

    def update_line(index, key, value)
      old_line = @lines[index]
      inline_comment = extract_inline_comment(old_line)
      @lines[index] = "#{key}=#{quote_value(value)}#{inline_comment}"
    end

    def extract_inline_comment(line)
      after_eq = line[(line.index('=') + 1)..]

      # Skip past quoted value to find inline comment
      remainder = if after_eq.start_with?("'", '"')
                    quote = after_eq[0]
                    end_pos = after_eq.index(quote, 1)
                    end_pos ? after_eq[(end_pos + 1)..] : ''
                  else
                    after_eq
                  end

      match = remainder.match(/( #.*)/)
      match ? match[1] : ''
    end
  end
end
