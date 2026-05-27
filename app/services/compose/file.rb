require 'yaml'

module Compose
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
      @data = {}
      @service_comments = {}
    end

    # The parsed @data is cached process-wide, keyed by file mtime — every
    # render of /services hits 1 + 8 (rows) requests, each of which used to
    # re-parse the YAML. Each call returns a deep_dup so per-instance mutations
    # (add_service, remove_service, save) stay local; the disk write then
    # changes mtime and the next loader sees the updated content.
    def load
      return self unless ::File.exist?(path)

      mtime = ::File.mtime(path).to_f
      @data = Rails.cache.fetch([:compose_file_data, path, mtime]) { parse_yaml }.deep_dup
      self
    end

    def services
      @services ||= ServiceCollection.new(@data['services'] ||= {})
    end

    def networks
      @data['networks'] ||= {}
    end

    def volumes
      @data['volumes'] ||= {}
    end

    def name
      @data['name']
    end

    def name=(value)
      @data['name'] = value
    end

    KEY_ORDER = %w[
      image
      user
      command
      environment
      volumes
      ports
      labels
      depends_on
      healthcheck
      restart
      logging
    ].freeze

    def add_service(name, config, comment: nil)
      @services = nil # Reset memoized collection
      (@data['services'] ||= {})[name.to_s] = sort_keys(stringify_keys(config))
      @service_comments[name.to_s] = comment if comment
    end

    def remove_service(name)
      @services = nil # Reset memoized collection
      @data['services']&.delete(name.to_s)
    end

    # Atomic write: a concurrent reader observing a partial truncated file
    # would cache empty/partial YAML under the file's mtime via #load.
    def save
      tmp_path = "#{path}.tmp"
      ::File.write(tmp_path, to_yaml)
      ::File.rename(tmp_path, path)
    end

    def to_yaml
      base = YAML.dump(@data).delete_prefix("---\n")
      base = insert_blank_lines_between_services(base)
      @header_comment ? "#{@header_comment}\n\n#{base}" : base
    end

    def to_h
      @data.dup
    end

    private

    def parse_yaml
      YAML.safe_load_file(path, permitted_classes: [Symbol]) || {}
    rescue Psych::SyntaxError => e
      raise ParseError, "Invalid YAML: #{e.message}"
    end

    def stringify_keys(hash)
      hash.deep_stringify_keys
    end

    def sort_keys(hash)
      hash.sort_by { |key, _| KEY_ORDER.index(key) || KEY_ORDER.size }.to_h
    end

    # Insert blank lines between top-level sections and comments before services
    def insert_blank_lines_between_services(yaml)
      lines = yaml.lines
      result = [lines.first]
      in_services = lines.first.start_with?('services:')

      lines.drop(1).each do |line|
        if line.match?(/\A\w/)
          in_services = line.start_with?('services:')
          result << "\n"
        elsif in_services && (match = line.match(/\A {2}([\w-]+):/))
          result << "\n"
          comment = @service_comments[match[1]]
          result.concat(service_comment_box(comment)) if comment
        end
        result << line
      end

      result.join
    end

    def service_comment_box(comment)
      content = "  #{comment}  "
      width = [58, content.length].max
      [
        "  # +#{'-' * width}+\n",
        "  # |#{content.ljust(width)}|\n",
        "  # +#{'-' * width}+\n",
        "  #\n",
      ]
    end
  end
end
