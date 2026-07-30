class LogsChannel < ApplicationCable::Channel
  MAX_SUBSCRIPTIONS = 5

  # Upper bound for a single batch, so a service dumping its startup output
  # neither grows the buffer nor delays the first lines without end.
  MAX_BATCH = 500

  def subscribed
    @service_name = params[:service]
    return reject unless valid_service?
    return reject if subscription_limit_reached?

    @stream_id = "logs:#{@service_name}:#{SecureRandom.hex(8)}"
    stream_from @stream_id

    start_streaming
  end

  def unsubscribed
    stop_streaming
  end

  private

  def valid_service?
    return false if @service_name.blank?

    Compose.load.services.any? { |s| s.name == @service_name }
  rescue StandardError
    false
  end

  def subscription_limit_reached?
    count = connection.subscriptions.identifiers.count do |id|
      JSON.parse(id)['channel'] == self.class.name
    end
    count >= MAX_SUBSCRIPTIONS
  rescue JSON::ParserError
    false
  end

  def start_streaming
    @io, @pid = Orchestration::Runner.stream_logs(service: @service_name, tail: 0)
    io = @io
    stream_id = @stream_id
    pid = @pid

    @reader_future = Concurrent::Promises.future do
      read_log_stream(io, stream_id, pid)
    end
  end

  # While a service keeps writing, collect its lines and send them as one
  # message. Solid Cable polls at 0.1s and hands out everything from a cycle at
  # once, so one broadcast per line buys no speed and costs a row plus a trim
  # job (~0.8ms) each, while the browser restarts its smooth scroll per line.
  # Batching only when the pipe is not empty keeps latency untouched: as soon as
  # the service goes quiet, the batch goes out.
  def read_log_stream(io, stream_id, pid)
    batch = []

    io.each_line do |line|
      # Services log in whatever encoding they please. An invalid byte would
      # raise in the formatter (and again in the broadcast's JSON encoding),
      # and this future swallows that: the live log would freeze without a
      # trace.
      batch << LogLineFormatter.call(TextEncoding.utf8(line).chomp)
      next if batch.size < MAX_BATCH && io.wait_readable(0)

      broadcast_batch(stream_id, batch)
    end
  rescue IOError
    # expected when IO is closed during shutdown
  ensure
    # At EOF the IO reads as ready, so the last batch is flushed here.
    broadcast_batch(stream_id, batch)
    io.close unless io.closed?
    reap_process(pid)
  end

  def broadcast_batch(stream_id, batch)
    return if batch.empty?

    ActionCable.server.broadcast(stream_id, { html: batch })
    batch.clear
  end

  # Runs from #unsubscribed, which is called on the connection's single thread
  # and blocks all other commands (including new subscribes with the same
  # identifier) until it returns. Reopening the modal would otherwise see its
  # subscribe ignored — Rails drops duplicate identifiers — and never receive
  # a confirmation, leaving the UI on "Connecting…". Hand off to a background
  # future so #unsubscribed returns immediately.
  def stop_streaming
    io = @io
    pid = @pid
    future = @reader_future

    @cleanup_future = Concurrent::Promises.future do
      io&.close unless io&.closed?
      future&.wait(5)
      kill_process(pid) if pid
    end
  end

  def kill_process(pid)
    Process.kill('TERM', pid)
    wait_for_exit(pid, timeout: 5)
  rescue Errno::ESRCH, Errno::ECHILD
    # Process already exited
  end

  def wait_for_exit(pid, timeout:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      return if Process.wait(pid, Process::WNOHANG)

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        Process.kill('KILL', pid)
        Process.wait(pid)
        return
      end

      sleep 0.1
    end
  rescue Errno::ECHILD
    # Already reaped
  end

  def reap_process(pid)
    Process.wait(pid, Process::WNOHANG)
  rescue Errno::ESRCH, Errno::ECHILD
    # Already reaped or doesn't exist
  end
end
