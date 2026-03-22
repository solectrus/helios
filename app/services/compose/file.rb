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

    def load
      return self unless ::File.exist?(path)

      content = ::File.read(path)
      @data = YAML.safe_load(content, permitted_classes: [Symbol]) || {}
      self
    rescue Psych::SyntaxError => e
      raise ParseError, "Invalid YAML: #{e.message}"
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

    def save
      ::File.write(path, to_yaml)
    end

    def to_yaml
      base = YAML.dump(@data)
      base = insert_blank_lines_between_services(base)
      @header_comment ? "#{@header_comment}\n#{base}" : base
    end

    def to_h
      @data.dup
    end

    private

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

      lines.drop(1).each do |line|
        if line.match?(/\A {2}\w/)
          result << "\n"
          # Add service comment if this is a service definition
          match = line.match(/\A {2}([\w-]+):/)
          comment = match && @service_comments[match[1]]
          result << "  # #{comment}\n" if comment
        end
        result << line
      end

      result.join
    end
  end
end
