RSpec.describe 'Parameter filtering', :with_admin_password do
  # The surveys post their answers as one JSON string in `data`, so the
  # key-based filters alone would log every secret in it verbatim.
  describe 'survey answers' do
    before do
      with_config_yaml
      login
    end

    it 'masks secrets inside the answers' do
      data = {
        'source' => 'shelly', 'measurement' => 'oven', 'field' => 'power',
        'shelly_host' => '192.168.1.50', 'shelly_password' => 'geheim123'
      }

      log = captured_log do
        patch configuration_setting_path(setting: 'sensor', name: 'custom_power_01'),
              params: { data: data.to_json }
      end

      expect(log).not_to include('geheim123')
      expect(log).to include('192.168.1.50')
    end

    it 'masks secrets in nested answers' do
      data = { 'services' => [{ 'forecast_pvnode_apikey' => 'pvnode-secret' }] }

      log = captured_log do
        patch configuration_setting_path(setting: 'forecast', name: 'forecast'), params: { data: data.to_json }
      end

      expect(log).not_to include('pvnode-secret')
    end

    it 'masks a body that is not a JSON object' do
      log = captured_log { get services_path, params: { data: '"geheim123"' } }

      expect(log).not_to include('geheim123')
    end

    it 'masks a body that is not JSON at all' do
      log = captured_log { get services_path, params: { data: 'geheim123' } }

      expect(log).not_to include('geheim123')
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
