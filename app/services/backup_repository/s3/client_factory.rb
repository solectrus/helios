require 'aws-sdk-s3'

class BackupRepository
  module S3
    # Builds Aws::S3::Client instances from raw credential fields. Shared
    # between the live S3 adapter (which reads from Configuration.current)
    # and Backups::ConnectionTest (which validates user input before save).
    module ClientFactory
      module_function

      # `endpoint` is optional — when present, path-style addressing is
      # forced because MinIO and most self-hosted S3-compatible servers
      # don't resolve virtual-hosted-style URLs (bucket.host).
      def build(access_key_id:, secret_access_key:, region:, endpoint: nil)
        opts = {
          region: region,
          credentials: Aws::Credentials.new(access_key_id, secret_access_key),
          retry_mode: 'standard',
          max_attempts: 3,
        }
        if (endpoint = endpoint.to_s.strip.presence)
          opts[:endpoint] = endpoint
          opts[:force_path_style] = true
        end
        Aws::S3::Client.new(**opts)
      end
    end
  end
end
