module Orchestration
  module VersionExtractor
    # SOLECTRUS-built images (solectrus, helios, the collectors, ingest, ...)
    # embed the git-describe version as COMMIT_VERSION. Prefer it over the OCI
    # `org.opencontainers.image.version` label, which on branch/PR builds is
    # just the branch name (e.g. "develop") instead of a real version.
    class Commit < Base
      def match?
        env_value('COMMIT_VERSION').present?
      end

      def extract
        env_value('COMMIT_VERSION')
      end
    end
  end
end
