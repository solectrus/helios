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
end

RSpec.configure do |config|
  config.include ConfigurationHelpers

  config.after { Current.configuration = nil }
end
