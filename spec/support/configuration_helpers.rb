module ConfigurationHelpers
  def with_config_yaml(data = {})
    dir = Dir.mktmpdir
    path = File.join(dir, Configuration::YAML_FILENAME)
    File.write(path, YAML.dump(data)) if data.present?
    allow(Rails.configuration).to receive(:helios_stack_path).and_return(dir)
    dir
  end
end

RSpec.configure do |config|
  config.include ConfigurationHelpers
end
