module SupportBundle
  module SystemInfo
    # InfluxDB diagnostics: schema-level counts (measurements / fields / tags)
    # plus on-disk size of the bucket data directory. Three index-only Flux
    # queries per call — no range scans, no per-measurement N+1 — so the
    # report stays fast even on multi-GB, multi-year buckets.
    module InfluxReport
      module_function

      BUCKET_DATA_DIR = 'influxdb'.freeze

      # Schema queries default to `start: -30d`. For diagnostics we want the
      # entire history of the bucket, so every query is anchored at epoch.
      START = 'time(v: 1)'.freeze

      def overview
        return 'InfluxDB not configured.' if bucket.blank?

        client = InfluxDb::Client.from_configuration(Configuration.current)
        base = target_info(client)
        measurements = client.query(measurements_flux)
        return base.merge('Status' => 'unreachable') if measurements.nil?

        base.merge(schema_counts(client, measurements)).merge('Bucket data size' => bucket_data_size)
      rescue StandardError => e
        "unavailable: #{e.class}: #{e.message}"
      end

      # Bucket + org names can hint at the user's location ("berlin-pv");
      # the endpoint host can be a public domain. Both get anonymized so
      # the report is safe to share in a public support forum. Mask keeps
      # the first 3 chars visible so support can still spot non-default
      # naming at a glance.
      def target_info(client)
        config = Configuration.current.influxdb
        {
          'Target' => anonymized_endpoint(client),
          'Org' => Anonymizer.mask(config.org),
          'Bucket' => Anonymizer.mask(config.bucket),
        }
      end

      def anonymized_endpoint(client)
        uri = URI.parse(client.endpoint)
        return client.endpoint unless Anonymizer.public_hostname?(uri.host)

        "#{uri.scheme}://#{Anonymizer.mask(uri.host)}:#{uri.port}"
      rescue URI::InvalidURIError
        client.endpoint
      end

      def schema_counts(client, measurements)
        {
          'Measurements' => list_size(measurements).to_s,
          'Field keys (total)' => list_size(client.query(field_keys_flux)).to_s,
          'Tag keys (total)' => list_size(client.query(tag_keys_flux)).to_s,
        }
      end

      def bucket
        Configuration.current.influxdb.bucket
      end

      # Centralised so the `start:` arg can't silently go missing on a single
      # call — InfluxDB's default of `-30d` would understate field/tag totals
      # for any series that hasn't been written in the last month.
      def schema_flux(function)
        <<~FLUX
          import "influxdata/influxdb/schema"
          schema.#{function}(bucket: "#{bucket}", start: #{START})
        FLUX
      end

      def measurements_flux = schema_flux('measurements')
      def field_keys_flux = schema_flux('fieldKeys')
      def tag_keys_flux = schema_flux('tagKeys')

      def list_values(rows)
        Array(rows).filter_map { |r| r['_value'].presence }
      end

      def list_size(rows)
        return 0 if rows.nil?

        list_values(rows).size
      end

      # In full/dashboard_only mode InfluxDB is a local container whose data
      # directory is bind-mounted under data_path. In collectors_only mode the
      # bucket lives on a remote host and the directory is absent — surface
      # that explicitly rather than reporting 0 B.
      def bucket_data_size
        path = Rails.configuration.data_path.to_s
        dir = File.join(path, BUCKET_DATA_DIR)
        return 'not on this host' unless File.directory?(dir)

        output = OutputFormatter.capture('du', '-sk', dir)
        return output if output.start_with?('failed', 'unavailable')

        blocks = output.split.first
        return 'unknown' unless blocks&.match?(/\A\d+\z/)

        OutputFormatter.human_bytes(blocks.to_i * 1024)
      end
    end
  end
end
