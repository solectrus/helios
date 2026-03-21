module Orchestration
  module VersionExtractor
    class Base
      attr_reader :container

      def initialize(container)
        @container = container
      end

      def extract
        raise NotImplementedError, "#{self.class} must implement #extract"
      end

      def match?
        raise NotImplementedError, "#{self.class} must implement #match?"
      end

      private

      def image
        container.info['Image'] || ''
      end

      def image_name
        # Extract image name without registry and tag
        # e.g., "ghcr.io/solectrus/app:latest" -> "solectrus/app"
        image.split('/').last(2).join('/').split(':').first
      end

      def labels
        @labels ||= container.json.dig('Config', 'Labels') || {}
      end

      def env
        @env ||= container.json.dig('Config', 'Env') || []
      end

      def env_value(key)
        env.find { |var| var.start_with?("#{key}=") }&.split('=', 2)&.last
      end
    end
  end
end
