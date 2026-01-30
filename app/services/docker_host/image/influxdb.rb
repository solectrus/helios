module DockerHost
  class Image
    class Influxdb < Image
      def self.identifier
        'influxdb'
      end

      def version
        env_value('INFLUXDB_VERSION')
      end
    end
  end
end
