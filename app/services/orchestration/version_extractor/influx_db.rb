module Orchestration
  module VersionExtractor
    class InfluxDb < Base
      def match?
        image.include?('influxdb')
      end

      def extract
        env_value('INFLUXDB_VERSION')
      end
    end
  end
end
