module ConfigurationHelpers
  # What every installation carries once it is past the commissioning screen.
  # HELIOS asks for the commissioning date before any screen opens (see
  # ApplicationController#require_commissioning), so a configuration without
  # one is a state the UI cannot reach.
  COMMISSIONING_BASELINE = { 'system' => { 'installation_date' => '2024-01-15' } }.freeze

  # Point HELIOS at a data directory of this example's own and write `data`
  # into its config.yaml, on top of COMMISSIONING_BASELINE.
  def with_config_yaml(data = {})
    with_raw_config_yaml(COMMISSIONING_BASELINE.deep_merge(data))
  end

  # The same, but writing `data` as it stands. For the examples that are about
  # what a section holds, and for the state before commissioning is answered.
  #
  # The file is written even for an empty hash: an installation whose
  # config.yaml is missing has never been configured at all, and
  # `without_config_yaml` sets up that state.
  def with_raw_config_yaml(data = {})
    password = admin_password_for_config if respond_to?(:admin_password_for_config)
    if password
      data = data.dup
      data['system'] = (data['system'] || {}).merge('admin_password' => password)
    end

    without_config_yaml
    FileUtils.mkdir_p(File.dirname(Configuration.path))
    File.write(Configuration.path, YAML.dump(data))
    @config_yaml_dir
  end

  # A data directory without a config.yaml: a fresh installation, before the
  # first setting is saved and before an existing stack is imported.
  def without_config_yaml
    @config_yaml_dir = Dir.mktmpdir
    allow(Rails.configuration).to receive(:data_path).and_return(@config_yaml_dir)
    @config_yaml_dir
  end

  def config_yaml_dir
    @config_yaml_dir
  end

  # Minimal configuration that satisfies Configuration#configuration_complete?:
  # one enabled sensor with a complete source plus the mandatory installation
  # date. Lets start-path request specs exercise the happy path without the
  # require_configuration_complete guard blocking them. Pass `extra` to deep
  # merge additional sections.
  def with_startable_config_yaml(extra = {})
    with_config_yaml(
      {
        'system' => { 'timezone' => 'Europe/Berlin' },
        'senec' => { 'version' => '4' },
        'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
      }.deep_merge(extra),
    )
  end
end

RSpec.configure do |config|
  config.include ConfigurationHelpers

  config.after { Current.reset }
end
