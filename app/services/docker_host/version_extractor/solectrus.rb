module DockerHost
  module VersionExtractor
    class Solectrus < Base
      def match?
        image.include?('solectrus/solectrus')
      end

      def extract
        env_value('COMMIT_VERSION')
      end
    end
  end
end
