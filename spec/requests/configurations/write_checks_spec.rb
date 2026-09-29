RSpec.describe 'Configurations::WriteChecks', :with_admin_password do
  before do
    with_config_yaml('sensors' => {
                       'custom_power_04' => { 'source' => 'shelly', 'measurement' => 'CUSTOM', 'field' => 'power',
                                              'shelly_host' => '10.0.0.1' },
                     })
    login
  end

  def check(owner, data)
    post configuration_write_check_path(owner:), params: { data: data.to_json }
    response.parsed_body['message']
  end

  describe 'POST /configuration/write_check' do
    it 'names only the measurement for a Shelly device, whose field is fixed' do
      expect(check('sensor:custom_power_05', 'source' => 'shelly', 'measurement' => 'CUSTOM',
                                             'shelly_host' => '10.0.0.2'))
        .to eq(I18n.t('sensors.errors.shelly_measurement_taken', measurement: 'CUSTOM'))
    end

    it 'names the measurement:field for a writer that picks its field' do
      expect(check('mqtt_topic:new', 'measurement' => 'CUSTOM', 'field' => 'temp'))
        .to eq(I18n.t('sensors.errors.influx_target_taken', target: 'CUSTOM:temp'))
    end

    it 'refuses a collector section on a measurement another writer uses' do
      expect(check('tibber', 'measurement' => 'CUSTOM'))
        .to eq(I18n.t('sensors.errors.measurement_taken', measurement: 'CUSTOM',
                                                          name: I18n.t('configurations.settings.tibber.title')))
    end

    it 'answers nothing for a free measurement:field' do
      expect(check('mqtt_topic:new', 'measurement' => 'CUSTOM', 'field' => 'dryer')).to be_nil
    end

    it 'answers 400 for answers that are not JSON' do
      post configuration_write_check_path(owner: 'shelly_device:new'), params: { data: '{' }

      expect(response).to have_http_status(:bad_request)
    end
  end
end
