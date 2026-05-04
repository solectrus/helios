class LogsChannel < ApplicationCable::Channel
  MAX_SUBSCRIPTIONS = 5

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
    tz = Configuration.current.system.timezone.presence || Time.zone

    @reader_future = Concurrent::Promises.future do
      read_log_stream(io, stream_id, pid, tz)
    end
  end

  def read_log_stream(io, stream_id, pid, timezone)
    Time.zone = timezone
    io.each_line do |line|
      html = LogLineFormatter.call(line.chomp)
      ActionCable.server.broadcast(stream_id, { html: })
    end
  rescue IOError
    # expected when IO is closed during shutdown
  ensure
    io.close unless io.closed?
    reap_process(pid)
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
