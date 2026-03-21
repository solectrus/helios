module Orchestration
  module VersionExtractor
    class Postgresql < Base
      def match?
        image.include?('postgres')
      end

      def extract
        env_value('PG_VERSION')
      end
    end
  end
end
