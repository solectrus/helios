RSpec.describe Export::Env::SenecCharger do
  subject(:env) { Export::Env.new(Configuration.current).to_s }

  # Everything the charger's export gate needs: a local battery, Tibber prices
  # and a running forecast collector.
  def config(senec: {}, sensors: {})
    with_config_yaml(
      'deployment' => { 'mode' => 'full' },
      'influxdb' => { 'org' => 'solectrus', 'bucket' => 'solectrus', 'token_read' => 'read-token' },
      'senec' => { 'adapter' => 'local', 'host' => '192.168.178.42', 'version' => 'v3' }.merge(senec),
      'tibber' => { 'token' => 'abc' },
      'forecast' => { 'forecast' => 'forecast.solar' },
      'sensors' => { 'inverter_power_forecast' => { 'source' => 'forecast', 'measurement' => 'Forecast' } }
        .merge(sensors),
      'senec_charger' => { 'interval' => '900', 'price_max' => '80' },
    )
  end

  it 'emits the CHARGER_* table, defaulting what the survey left out' do
    config
    expect(env).to include('CHARGER_INTERVAL=900', 'CHARGER_PRICE_MAX=80',
                           'CHARGER_PRICE_TIME_RANGE=4', 'CHARGER_FORECAST_THRESHOLD=20',
                           'CHARGER_DRY_RUN=false')
  end

  # The charger declares SENEC_HOST/SENEC_SCHEMA as bare passthroughs, but the
  # 'SENEC collector' section that normally writes them is gated on the
  # collector running — which it doesn't here (no sensor uses the senec source,
  # e.g. after moving them to another vendor). Without this the container would
  # start against an unresolved reference and die on ENV.fetch("SENEC_HOST").
  context 'when no senec-collector runs to write the device vars' do
    it 'emits the device address itself' do
      config
      expect(Export::Services::SenecCollector.enabled?(Configuration.current)).to be(false)
      expect(env).to include('SENEC_HOST=192.168.178.42', 'SENEC_SCHEMA=https')
    end
  end

  context 'when the senec-collector already wrote them' do
    it 'leaves them to the collector section rather than emitting twice' do
      config(sensors: { 'battery_soc' => { 'source' => 'senec' } })
      expect(Export::Services::SenecCollector.enabled?(Configuration.current)).to be(true)
      expect(env.scan(/^SENEC_HOST=/).size).to eq(1)
    end
  end
end
