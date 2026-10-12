RSpec.describe Export::Env::Sensors do
  subject(:env) { Export::Env.new(Configuration.current).to_s }

  describe 'car sensors' do
    before do
      with_config_yaml('mqtt' => { 'mqtt_host' => 'broker.local', 'mqtt_port' => '1883' })
      config = Configuration.current
      config.update_sensor('car_connected', { 'source' => 'mqtt', 'mqtt_topic' => 'car/plug' })
      config.update_sensor('car_odometer_2', { 'source' => 'external' })
    end

    it 'writes car 1 without its number and car 2 with it' do
      expect(env).to include('INFLUX_SENSOR_CAR_CONNECTED=car:connected')
      expect(env).to include('INFLUX_SENSOR_CAR_ODOMETER_2=car_2:odometer')
    end

    it 'lets mqtt-collector write the plug state as yes/no' do
      expect(env).to match(%r{^MAPPING_0_TOPIC=car/plug$})
      expect(env).to match(/^MAPPING_0_TYPE=boolean$/)
    end

    it 'passes both to the dashboard' do
      yaml = Export::Compose.new(Configuration.current).to_yaml

      expect(yaml).to match(/^\s*- INFLUX_SENSOR_CAR_CONNECTED$/)
      expect(yaml).to match(/^\s*- INFLUX_SENSOR_CAR_ODOMETER_2$/)
    end
  end
end
