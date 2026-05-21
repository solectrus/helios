require 'json'

class BackupRepository
  # JSON-backed cache of the backup listing — shared across the local and
  # external storage adapters. Without it every /backups visit would have
  # to scan tar headers from disk (local) or round-trip through one
  # docker:cli sidecar per backup (external) just to render the table.
  #
  # The index stores everything the UI needs — filename, size, mtime, tar
  # entries, image versions, last backup/restore error — plus a
  # `destination` field that lets the adapter detect a settings change and
  # rebuild from scratch.
  #
  # Lives next to helios/config.yaml because it is HELIOS-internal runtime
  # state, not part of the user's compose stack (mirrors
  # Orchestration::AffectedServices.deployed_hashes_path).
  class Index
    FILENAME = 'backups_index.json'.freeze

    class << self
      def read
        parsed = JSON.parse(::File.read(path))
        parsed.is_a?(::Hash) ? parsed : nil
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      def write(data)
        FileUtils.mkdir_p(::File.dirname(path))
        tmp = "#{path}.tmp"
        ::File.write(tmp, JSON.pretty_generate(data))
        ::File.rename(tmp, path)
      end

      def delete!
        FileUtils.rm_f(path)
      end

      def path
        ::File.join(Rails.configuration.data_path, 'helios', FILENAME)
      end
    end
  end
end
