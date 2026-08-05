module Env
  class File
    class ParseError < StandardError
    end

    # A double-quoted value. A backslash escapes an arbitrary character, so a
    # `\"` does not end the value — both the parser and the inline-comment
    # scanner have to skip it the same way.
    DOUBLE_QUOTED = /\A"((?:\\.|[^"\\])*)"/m

    # `NAME=value`. The value part crosses newlines because a quoted value may
    # span lines and arrives here as one folded entry.
    ASSIGNMENT = /\A([A-Za-z_][A-Za-z0-9_]*)=(.*)/m

    # What has to be neutralized inside double quotes so Compose hands the
    # container back the value HELIOS stored — the mirror image of the escapes
    # and references Env::Interpolation resolves on read. The control-character
    # half is inverted from the reader's own table rather than spelled out
    # again: two hand-kept lists would let the save/load round-trip break the
    # moment one side learns a sequence the other doesn't (#377). What stays
    # here is what quoting alone demands, which the reader has no table for.
    DOUBLE_QUOTE_ESCAPES = {
      '\\' => '\\\\',
      '"' => '\\"',
      '$' => '$$',
    }.merge(Interpolation::ESCAPE_SEQUENCES.invert.transform_values { |escape| "\\#{escape}" }).freeze

    ESCAPABLE = Regexp.union(DOUBLE_QUOTE_ESCAPES.keys).freeze

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

      # Hand-edited files are regularly not UTF-8, or carry a byte order mark
      # (see TextEncoding); parsed raw they would raise on the first umlaut in
      # a comment and silently swallow the first variable.
      @lines = fold_quoted_values(TextEncoding.utf8(::File.read(path)).lines(chomp: true))
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
      @lines << "# +#{'-' * width}+"
      @lines << "# |#{content.ljust(width)}|"
      @lines << "# +#{'-' * width}+"
      @lines << '#'
      @lines << ''
    end

    def to_s
      result = @lines.join("\n")
      result = "#{@header_comment}\n#{result}" if @header_comment
      "#{result}\n"
    end

    private

    # A quoted value may span lines, and a donor .env carrying a certificate or
    # a private key regularly does. Read line by line such a value would end at
    # the first newline and its remainder would parse as further variables, so
    # continuation lines are folded back into the entry that opened the quote.
    # They rejoin with "\n", which leaves `to_s` byte-identical to the file.
    def fold_quoted_values(lines)
      lines.each_with_object([]) do |line, folded|
        if folded.last && unterminated_quote?(folded.last)
          folded[-1] = "#{folded.last}\n#{line}"
        else
          folded << line
        end
      end
    end

    def unterminated_quote?(entry)
      value = entry.match(ASSIGNMENT)&.[](2)

      case value&.[](0)
      when '"' then !value.match?(DOUBLE_QUOTED)
      when "'" then !value.index("'", 1)
      else false
      end
    end

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
      match = line.match(ASSIGNMENT)
      return nil unless match

      [match[1], extract_value(match[2])]
    end

    # Follows Docker Compose's quoting rules: single quotes are literal, double
    # quotes process backslash escapes, and everything except the single-quoted
    # form expands `$VAR` references afterwards.
    def extract_value(raw_value)
      case raw_value[0]
      when "'" then single_quoted_value(raw_value)
      when '"' then double_quoted_value(raw_value)
      else unquoted_value(raw_value)
      end
    end

    # An unterminated quote is not a quoted value at all — treat the whole
    # remainder as unquoted, as before.
    def single_quoted_value(raw_value)
      end_quote = raw_value.index("'", 1)
      end_quote ? raw_value[1...end_quote] : unquoted_value(raw_value)
    end

    def double_quoted_value(raw_value)
      match = raw_value.match(DOUBLE_QUOTED)
      return unquoted_value(raw_value) unless match

      Interpolation.resolve_escaped(match[1], @variables)
    end

    # References resolve against the variables parsed so far, mirroring
    # Compose's top-to-bottom read of the file.
    def unquoted_value(raw_value)
      Interpolation.resolve(strip_inline_comment(raw_value), @variables)
    end

    def strip_inline_comment(value)
      comment_pos = value.index(' #')
      value = value[0...comment_pos] if comment_pos
      value.strip
    end

    def find_line_index(key)
      prefix = "#{key}="
      @lines.find_index { |line| line.start_with?(prefix) }
    end

    def quote_value(value)
      val = value.to_s
      return val unless needs_quoting?(val)
      return "'#{val}'" unless val.match?(/['\n\r]/)

      # Single quotes are the literal form and need no escaping, but a value
      # that contains one — or a line break, which the line-oriented parser
      # could never recover from the literal form — has to fall back to double
      # quotes, where Docker Compose still expands `$…` and reads backslashes
      # as escapes.
      %("#{val.gsub(ESCAPABLE, DOUBLE_QUOTE_ESCAPES)}")
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
      match = after_value(line[(line.index('=') + 1)..]).match(/( #.*)/)
      match ? match[1] : ''
    end

    # Text following the value, where an inline comment may live. Quoted values
    # are skipped with the grammar the parser uses, so an escaped quote inside a
    # double-quoted value does not end it early — otherwise the rest of the
    # value would be mistaken for a comment and grafted onto the next write.
    def after_value(text)
      case text[0]
      when "'" then (end_quote = text.index("'", 1)) ? text[(end_quote + 1)..] : text
      when '"' then text.match(DOUBLE_QUOTED)&.post_match || text
      else text
      end
    end
  end
end
