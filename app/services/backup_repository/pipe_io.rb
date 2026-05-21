class BackupRepository
  # Wrapper around a non-rewindable IO (e.g. an Open3.popen stdout pipe) that
  # satisfies the contract Gem::Package::TarReader expects from its source —
  # `pos`, `read`, `eof?`, `getc`, `readpartial`. Without it, TarReader's
  # constructor calls `io.pos` (which raises Errno::ESPIPE on a pipe) and the
  # Entry#close routines call `io.seek` to skip over file bodies the consumer
  # did not read.
  #
  # The wrapper exposes a virtual byte counter that advances on every read,
  # and answers every `seek` with Errno::EINVAL — the documented escape
  # hatch that triggers TarReader's read-and-discard fallback (see
  # rubygems/package/tar_reader/entry.rb).
  class PipeIo
    def initialize(io)
      @io = io
      @pos = 0
    end

    attr_reader :pos

    delegate :eof?, to: :@io

    def read(length = nil, outbuf = nil)
      data = outbuf ? @io.read(length, outbuf) : @io.read(length)
      @pos += data.bytesize if data
      data
    end

    def readpartial(maxlen, outbuf = +'')
      @io.readpartial(maxlen, outbuf)
      @pos += outbuf.bytesize
      outbuf
    end

    def getc
      char = @io.getc
      @pos += char.bytesize if char
      char
    end

    # Documented contract with TarReader: raising Errno::EINVAL signals
    # "stream is not seekable" and triggers its read-fallback.
    def seek(*)
      raise Errno::EINVAL
    end

    def rewind
      raise Errno::EINVAL
    end
  end
end
