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

    def add_service(name, config)
      @services = nil # Reset memoized collection
      (@data['services'] ||= {})[name.to_s] = stringify_keys(config)
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
      @header_comment ? "#{@header_comment}\n#{base}" : base
    end

    def to_h
      @data.dup
    end

    private

    def stringify_keys(hash)
      hash.deep_stringify_keys
    end
  end
end
