require 'open3'

# The form of a fixed source must not move its collector.
#
# Such a form asks for the measurement the collector writes into, and the field
# carries a default because it is mandatory. A user who opens the form to read
# it, or to change something else on it, saves that default along with the rest,
# and a default that differs from what HELIOS derives writes the collector into
# another measurement. Every reading taken so far stays behind under the old
# name, and the sensors that read it go empty.
#
# So walk the form the way the browser does, with survey-core filling in what
# the user leaves alone (see spec/support/survey_walk.mjs), and compare the
# files before and after. A form opened and saved unchanged has to leave every
# generated file byte for byte the same.
RSpec.describe 'Measurement round trip of a fixed source' do
  let(:walker) { Rails.root.join('spec/support/survey_walk.mjs') }

  # A complete forecast section, as an import leaves it: every question the form
  # asks is answered, except the measurement. That one the donated stack never
  # named, so its collector writes into the name compiled into it.
  let(:forecast_section) do
    {
      'forecast' => 'forecast.solar',
      'forecast_roofs' => '1',
      'forecast_latitude' => '50.00000',
      'forecast_longitude' => '6.00000',
      'forecast_declination1' => '30',
      'forecast_azimuth1' => '29',
      'forecast_kwp1' => '9.24',
      'forecast_interval' => '900',
    }
  end

  let(:config_data) do
    {
      'system' => { 'installation_date' => '2024-01-15', 'timezone' => 'Europe/Berlin' },
      'forecast' => forecast_section,
      'sensors' => { 'inverter_power_forecast' => { 'source' => 'forecast' } },
    }
  end

  def walk(survey, answers)
    stdout, stderr, status = Open3.capture3(
      'bun', walker.to_s, stdin_data: { survey:, answers: }.to_json, chdir: Rails.root.to_s
    )
    raise "survey_walk.mjs failed: #{stderr}" unless status.success?

    JSON.parse(stdout)
  end

  # What the form posts when the user answers nothing it does not already hold.
  def submit_unchanged(setting)
    survey = "Surveys::#{setting.camelize}::Survey".constantize.new.call
    result = walk(survey, Configuration.current.setting_data(setting).to_h)
    raise "Survey '#{setting}' stayed incomplete: #{result['errors'].join(', ')}" unless result['completed']

    Configuration.current.update(setting, result['data'])
  end

  before { with_config_yaml(config_data) }

  it 'leaves the .env unchanged when the forecast form is saved untouched' do
    before_env = Export::Env.new(Configuration.current).to_s

    submit_unchanged('forecast')

    expect(Export::Env.new(Configuration.current).to_s).to eq(before_env)
  end

  it 'keeps the collector on the measurement it writes into' do
    submit_unchanged('forecast')

    expect(Configuration.current.forecast.measurement)
      .to eq(SensorMappings::DEFAULT_MEASUREMENTS['forecast'])
  end
end
