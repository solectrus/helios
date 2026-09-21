# Contract test between the two halves of a sensor mapping.
#
# A collector writes into the measurement HELIOS names in
# `INFLUX_MEASUREMENT_<SOURCE>`, and the dashboard reads from the measurement
# HELIOS names in `INFLUX_SENSOR_<SENSOR>`. Nothing fails when the two
# disagree: the collector writes, the dashboard reads elsewhere, and the
# sensor stays empty. A scenario snapshot records such a stack without
# complaint, because it holds what HELIOS produces and not what is right.
#
# So check the exported pair of files of every scenario: for a source whose
# collector dictates one measurement for all of its sensors, every sensor of
# that source must read from the measurement the collector was given.
RSpec.describe 'Sensor mapping contract' do
  def self.snapshots
    Pathname.glob(Rails.root.join('spec/scenarios/*/**/snapshot/helios/config.yaml')).sort
  end

  def self.scenario_name(config_path)
    config_path.dirname.parent.parent.relative_path_from(Rails.root.join('spec/scenarios'))
  end

  def config_of(config_path)
    YAML.safe_load_file(config_path, permitted_classes: [Date]) || {}
  end

  def env_of(config_path)
    Env::File.load(config_path.dirname.parent.join('.env')).to_h
  end

  # What the collector of a fixed source was told to write into.
  def collector_measurement(env, source)
    env["INFLUX_MEASUREMENT_#{source.upcase}"]
  end

  # What a sensor reads, taken apart from `measurement:field`.
  def sensor_measurement(env, sensor)
    env["INFLUX_SENSOR_#{sensor.upcase}"]&.split(':', 2)&.first
  end

  def sensors_of(config, source)
    (config['sensors'] || {}).select { |_, sensor| (sensor || {})['source'] == source }.keys
  end

  snapshots.each do |config_path|
    it "holds for #{scenario_name(config_path)}" do
      config = config_of(config_path)
      env = env_of(config_path)

      mismatched = SensorMappings::FIXED_SOURCES.flat_map do |source|
        written = collector_measurement(env, source)
        next [] if written.blank?

        sensors_of(config, source).filter_map do |sensor|
          read = sensor_measurement(env, sensor)
          "#{sensor}: reads #{read}, #{source} writes #{written}" if read && read != written
        end
      end

      expect(mismatched).to be_empty,
                            "Sensors reading a measurement their collector never writes to:\n" \
                            "#{mismatched.join("\n")}"
    end
  end
end
