module DockerHost
  class Image
    class Postgres < Image
      def self.identifier
        'postgres'
      end

      def version
        env_value('PG_VERSION')
      end
    end
  end
end
