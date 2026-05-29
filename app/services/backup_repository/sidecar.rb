require 'open3'

class BackupRepository
  # Sidecar IO helpers shared by the External and S3 adapters. Both reach
  # their destination only through a short-lived docker sidecar; this
  # module holds the run/capture/stream wrappers that are otherwise
  # identical.
  #
  # Including adapters must provide: `sidecar_command(*cmd)`.
  module Sidecar
    include Loggable

    def sidecar_run(*cmd)
      Open3.capture2e(*sidecar_command(*cmd))
    end

    # Like sidecar_run, but raises BackupRepository::Error on a non-zero
    # exit — mutating operations must not update the DB after the actual
    # rm/cp silently failed.
    def sidecar_run!(*cmd)
      output, status = sidecar_run(*cmd)
      return output if status.success?

      message = output.to_s.strip.presence || "exited with status #{status.exitstatus}"
      logger.error("sidecar failed: #{cmd.inspect} — #{message}")
      raise BackupRepository::Error, message
    end

    def sidecar_capture(*cmd)
      Open3.capture2(*sidecar_command(*cmd))
    end

    # Runs a sidecar whose stdout is a tar stream and parses it into an
    # ArchiveContents. Uses `popen2`, not `popen2e`, on purpose: the stdout
    # is a binary tar — merging stderr into it would corrupt the archive.
    # With `popen2` the sidecar's stderr passes straight through to HELIOS's
    # own stderr/log instead.
    #
    # Every failure mode is logged and yields an empty archive: a non-zero
    # exit, an unreadable tar, a sidecar that could not launch, and — the
    # subtle one — a clean exit that nonetheless produced no entries (an S3
    # object not yet readable in the moments right after upload).
    def stream_sidecar_archive(*cmd)
      Open3.popen2(*sidecar_command(*cmd)) do |_in, out, wait|
        out.binmode
        archive = BackupRepository.parse_tar_stream(BackupRepository::PipeIo.new(out))
        # Drain anything left over so the wait status reflects a clean exit
        # — TarReader stops as soon as it sees the zero-block sentinel.
        out.read
        verified_archive(archive, wait.value, cmd)
      end
    rescue Gem::Package::TarInvalidError => e
      warn_archive("produced an unreadable tar (#{e.message})", cmd)
    rescue Errno::ENOENT => e
      warn_archive("could not be launched (#{e.message})", cmd)
    end

    # Runs a sidecar whose stdout is a tar stream and yields it to the block
    # in 64 KB chunks (HTTP download). `popen2` keeps stderr off the stdout
    # pipe so a docker warning can never end up inside the download;
    # a non-zero exit raises BackupRepository::Error.
    def stream_sidecar_download(*cmd)
      Open3.popen2(*sidecar_command(*cmd)) do |_in, out, wait|
        out.binmode
        while (chunk = out.read(64 * 1024))
          yield chunk
        end
        status = wait.value
        next if status.success?

        raise BackupRepository::Error, "sidecar exited with status #{status.exitstatus}"
      end
    end

    private

    def verified_archive(archive, status, cmd)
      return warn_archive("exited #{status.exitstatus}", cmd) unless status.success?

      warn_archive('produced no tar entries', cmd) if archive.entries.empty?
      archive
    end

    def warn_archive(reason, cmd)
      logger.warn("archive sidecar #{reason} — #{cmd.inspect}")
      BackupRepository::EMPTY_ARCHIVE
    end
  end
end
