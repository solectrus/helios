module SupportBundle
  # Captures the last N lines of logs for every container in the HELIOS
  # compose project. Uses `docker logs` (via Open3) to get plain text —
  # bypasses the Docker multiplex stream protocol and works for stopped
  # containers too.
  module ContainerLogs
    # Docker keeps 30 MB per service on disk (10 MB over three files, set in
    # the generated compose.yaml), so the limit here is what the bundle stays
    # small enough to attach, not what Docker can deliver. At 2000 lines the
    # nine services of a full stack come to roughly 1.4 MB of text, which the
    # zip takes down to a few hundred KB.
    TAIL_LINES = 2000

    # A line count alone does not bound the bytes. The estimate above assumes
    # about 78 bytes per line, which holds for a service that logs one short
    # sentence per event. A service that logs a stack trace or a JSON document
    # per line writes lines an order of magnitude longer, and that is the state
    # a user builds a bundle in. So the bytes are capped as well, per service,
    # and the newest lines win.
    MAX_BYTES = 1.megabyte

    module_function

    # Yields one log per container, so the caller can write it away and let go
    # of it. Collecting them first would hold every service's log at once, for
    # no gain: the zip takes them one at a time either way.
    def each_log
      containers = Orchestration::Container.all
      containers.each { |container| yield filename_for(container), fetch_log(container.id) }
    rescue Orchestration::ConnectionError => e
      yield 'logs/_error.txt', "Docker unavailable: #{e.message}\n"
    end

    def filename_for(container)
      name = container.service_name.presence || container.name.presence || container.id[0, 12]
      "logs/#{name.gsub(/[^A-Za-z0-9._-]/, '_')}.log"
    end

    def fetch_log(container_id)
      output, status = capture_tail(
        'docker', 'logs', '--tail', TAIL_LINES.to_s, '--timestamps', container_id
      )
      return output if status.success?

      "failed (exit #{status.exitstatus}):\n#{output}"
    rescue StandardError => e
      "unavailable: #{e.class}: #{e.message}\n"
    end

    # Runs the command and returns the last MAX_BYTES of its output, plus the
    # exit status. `docker logs` prints the oldest line first, so the end of
    # the output is the part worth keeping.
    #
    # Read line by line and dropped while it reads, so the bytes Docker
    # delivers never all sit in memory at once. A service that logs a JSON
    # document per line can deliver tens of megabytes within TAIL_LINES, and a
    # user builds a bundle while exactly that happens.
    #
    # Counted in whole lines, and the newest line is always kept: a cut by byte
    # can land inside a character and leave the file invalid, and a single line
    # can be larger than the whole budget. The cap can therefore be exceeded by
    # one line.
    #
    # The bytes are decoded once, at the end: a service logs in whatever
    # encoding it pleases, and anonymizing invalid UTF-8 would raise and take
    # the whole bundle down.
    def capture_tail(*command)
      text = nil
      dropped = 0

      status =
        Open3.popen2e(*command) do |stdin, out, wait_thread|
          stdin.close
          text, dropped = read_tail(out)
          wait_thread.value
        end

      [with_drop_note(TextEncoding.utf8(text), dropped), status]
    end

    # Keeps the last MAX_BYTES of the stream, in whole lines, and counts the
    # lines it dropped on the way.
    def read_tail(stream)
      stream.binmode
      lines = []
      bytes = 0
      dropped = 0

      stream.each_line do |line|
        lines << line
        bytes += line.bytesize

        while lines.size > 1 && bytes > MAX_BYTES
          bytes -= lines.shift.bytesize
          dropped += 1
        end
      end

      [lines.join, dropped]
    end

    def with_drop_note(text, dropped)
      return text if dropped.zero?

      "[#{dropped} older #{'line'.pluralize(dropped)} removed to keep the bundle small]\n#{text}"
    end
  end
end
