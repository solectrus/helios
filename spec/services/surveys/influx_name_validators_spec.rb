# The surveys refuse a bad measurement or field in the browser, the controllers
# refuse it again on a request that skips the UI. Both sides must agree: a name
# the survey lets through and the controller then rejects is a dead end for the
# user, and the reverse silently stores something unusable.
describe 'InfluxDB name validators' do
  let(:sensor_survey) { Rails.root.join('app/services/surveys/sensor/survey.json') }
  let(:shelly_device_survey) { Rails.root.join('app/services/surveys/shelly_device/survey.json') }

  # Line protocol escapes `,`, `=` and space, so those survive a round trip and
  # stay legal. Only what HELIOS itself splits on, plus the underscore InfluxDB
  # reserves, is out.
  # https://docs.influxdata.com/influxdb/v2/reference/syntax/line-protocol/
  let(:names) do
    ['SENEC', 'Lüfter_Garage', 'PQ Inverter', 'PQ-Inverter', 'heat.pump', 'a=b', 'PQ,Inverter', 'PQ:Inverter',
     '_inverter']
  end

  it 'validates the measurement in the sensor survey exactly as SensorMappings does' do
    expect_agreement(sensor_survey, 'measurement', :valid_measurement?)
  end

  it 'validates the measurement in the shelly-device survey exactly as SensorMappings does' do
    expect_agreement(shelly_device_survey, 'measurement', :valid_measurement?)
  end

  it 'validates the field in the sensor survey exactly as SensorMappings does' do
    expect_agreement(sensor_survey, 'field', :valid_field?)
  end

  def expect_agreement(survey_path, question, predicate)
    regex = survey_regex(survey_path, question)

    names.each do |name|
      expect(name.match?(regex)).to eq(SensorMappings.public_send(predicate, name)),
                                    "#{name.inspect}: #{survey_path.basename} and SensorMappings disagree"
    end
  end

  def survey_regex(survey_path, question)
    validator = text_question(survey_path, question)&.dig('validators')&.find { |v| v['type'] == 'regex' }
    expect(validator).to be_present, "no regex validator on #{question.inspect} in #{survey_path}"

    Regexp.new(validator['regex'])
  end

  def text_question(survey_path, question)
    found = nil

    walk = lambda do |node|
      case node
      when Hash
        found ||= node if node['name'] == question && node['type'] == 'text'
        node.each_value { |child| walk.call(child) }
      when Array
        node.each { |child| walk.call(child) }
      end
    end
    walk.call(JSON.parse(File.read(survey_path)))

    found
  end
end
