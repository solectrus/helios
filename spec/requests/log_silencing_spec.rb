RSpec.describe 'Log silencing', :with_admin_password do
  # The UI polls a few endpoints every five seconds for as long as a page is
  # open. Logging them floods the log and pushes the diagnostic history out
  # within minutes: in a real support bundle the 500 captured lines covered
  # 11 minutes, nearly all of it /host-stats. Configured in config/application.rb.
  describe 'polling requests' do
    before { login }

    it 'keeps /host-stats out of the log' do
      allow(HostStats).to receive(:snapshot).and_return(
        HostStats::Snapshot.new(
          cpu_percent: 42,
          cpu_cores: 2,
          ram_percent: 75,
          ram_free: 2_000_000_000,
          ram_total: 8_000_000_000,
        ),
      )

      expect(captured_log { get host_stats_path, as: :turbo_stream }).to be_empty
    end

    it 'still logs regular requests' do
      expect(captured_log { get services_path }).to include('Started GET "/services"')
    end
  end

  # Attaches a second logger to the broadcast for the duration of the block, so
  # what the request actually wrote can be inspected.
  def captured_log
    sink = StringIO.new
    logger = ActiveSupport::Logger.new(sink)
    Rails.logger.broadcast_to(logger)
    yield
    sink.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end
end
