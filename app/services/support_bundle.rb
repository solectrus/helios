require 'zip'

# Collects the user's configuration files into a single zip archive
# suitable for attaching to a support forum post. All sensitive values
# (passwords, API keys, tokens, geolocation) are replaced with placeholders.
module SupportBundle
  module_function

  def build
    io = Zip::OutputStream.write_buffer do |zip|
      sources.each do |entry_name, path|
        next unless File.exist?(path)

        zip.put_next_entry(entry_name)
        zip.write(anonymize(entry_name, File.read(path)))
      end

      zip.put_next_entry('system-info.txt')
      zip.write(SystemInfo.collect)

      ContainerLogs.collect.each do |entry_name, content|
        zip.put_next_entry(entry_name)
        zip.write(content)
      end
    end

    io.string
  end

  def anonymize(entry_name, content)
    if entry_name == 'config.yaml'
      Anonymizer.anonymize_yaml(content)
    else
      Anonymizer.anonymize_env_style(content)
    end
  end

  def filename
    "helios-support-#{Time.current.strftime('%Y%m%d-%H%M%S')}.zip"
  end

  # Compose.path may resolve to docker-compose.yaml; inside the archive
  # we always use compose.yaml for readability.
  def sources
    compose_path = Compose.path
    env_path = Env.path

    {
      'compose.yaml' => compose_path,
      '.env' => env_path,
      'config.yaml' => Configuration.path,
      'compose.yaml.bak' => "#{compose_path}.bak",
      '.env.bak' => "#{env_path}.bak",
    }
  end
end
