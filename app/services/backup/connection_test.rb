require 'open3'

module Backup
  # Probes the configured external backup path from inside a docker:cli
  # sidecar — the exact same mount the External storage adapter uses
  # at runtime, so a successful probe guarantees that listing and writing
  # will work too. Uses `--mount type=bind` (not `-v`) on purpose: that
  # form fails if the host source does not exist, instead of silently
  # creating an empty directory.
  class ConnectionTest
    include ConnectionTesting::ResultBuilder

    PROBE_IMAGE = 'docker:cli'.freeze
    WRITE_PROBE_NAME = '.helios-write-test'.freeze

    SAFE_PATH = %r{\A/[A-Za-z0-9_/.-]+\z}

    EXIT_NOT_DIRECTORY = 10
    EXIT_NOT_WRITABLE = 11

    def call(check:, values:)
      case check
      when 'external_path' then external_path(values)
      else result(false, :error)
      end
    end

    private

    def external_path(values)
      path = values['external_path'].to_s.strip
      return result(false, :incomplete) if path.blank?
      return result(false, :backup_path_not_absolute) unless path.start_with?('/')
      return result(false, :backup_path_invalid_chars) unless path.match?(SAFE_PATH)

      probe(path)
    rescue StandardError => e
      Rails.logger.warn("External backup path probe failed (#{e.class}): #{e.message}")
      result(false, :backup_path_error)
    end

    def probe(path)
      output, status = Open3.capture2e(*probe_command(path))
      classify(status, output)
    end

    def probe_command(path)
      [
        'docker', 'run', '--rm',
        '--mount', "type=bind,source=#{path},target=/probe",
        PROBE_IMAGE,
        'sh', '-c',
        "test -d /probe || exit #{EXIT_NOT_DIRECTORY}; " \
        "touch /probe/#{WRITE_PROBE_NAME} 2>/dev/null || exit #{EXIT_NOT_WRITABLE}; " \
        "rm -f /probe/#{WRITE_PROBE_NAME}"
      ]
    end

    def classify(status, output)
      case status.exitstatus
      when 0 then result(true, :backup_path_writable)
      when EXIT_NOT_DIRECTORY then result(false, :backup_path_not_directory)
      when EXIT_NOT_WRITABLE then result(false, :backup_path_not_writable)
      else missing_or_error(output)
      end
    end

    # Docker rejects a `--mount type=bind` with a missing source by exiting
    # before the inner `sh -c` runs — the failure shows up as a non-zero
    # status and a "no such file" message on stderr.
    def missing_or_error(output)
      if output.include?('no such file') || output.include?('does not exist')
        result(false, :backup_path_missing)
      else
        Rails.logger.warn("External backup path probe failed: #{output.strip}")
        result(false, :backup_path_error)
      end
    end
  end
end
