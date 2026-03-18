class StackBuilder
  module Services
    class ShellyCollector < Base
      attr_reader :chapter

      def initialize(configuration, chapter:)
        super(configuration)
        @chapter = chapter
      end

      def service_name
        "shelly-#{identifier}"
      end

      def comment
        "Shelly collector for #{chapter.name}"
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/shelly-collector:latest',
          environment: shelly_environment,
          depends_on: healthy_depends_on(%i[influxdb]),
          restart: 'unless-stopped',
        }
      end

      # Find all chapters that use Shelly as data source
      def self.chapters_for(configuration)
        configuration.chapters.select(&:shelly?)
      end

      private

      def shelly_environment
        env = {
          'SHELLY_HOST' => chapter.data['shelly_host'],
          'SHELLY_INTERVAL' => chapter.data['shelly_interval'] || '5',
          'INFLUX_HOST' => 'influxdb',
          'INFLUX_TOKEN' => '${INFLUX_TOKEN}',
          'INFLUX_ORG' => '${INFLUX_ORG}',
          'INFLUX_BUCKET' => '${INFLUX_BUCKET}',
          'INFLUX_MEASUREMENT' => measurement_name,
        }

        password = chapter.data['shelly_password']
        env['SHELLY_PASSWORD'] = password if password.present?

        env
      end

      def identifier
        chapter.data['identifier']
      end

      alias measurement_name identifier
    end
  end
end
