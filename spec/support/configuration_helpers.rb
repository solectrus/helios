module ConfigurationHelpers
  def with_config_yaml(data = {})
    password = admin_password_for_config if respond_to?(:admin_password_for_config)
    if password
      data = data.dup
      data['system'] = (data['system'] || {}).merge('admin_password' => password)
    end

    @config_yaml_dir = Dir.mktmpdir
    allow(Rails.configuration).to receive(:data_path).and_return(@config_yaml_dir)
    if data.present?
      FileUtils.mkdir_p(File.dirname(Configuration.path))
      File.write(Configuration.path, YAML.dump(data))
    end
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
        'system' => { 'installation_date' => '2024-01-15', 'timezone' => 'Europe/Berlin' },
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
