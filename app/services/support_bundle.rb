require 'zip'

# Collects the user's configuration files into a single zip archive
# suitable for attaching to a support forum post. All sensitive values
# (passwords, API keys, tokens, geolocation) are replaced with placeholders.
module SupportBundle
  module_function

  def build
    Anonymizer.reset_registry!

    Zip::OutputStream.write_buffer do |zip|
      write_config_entries(zip)
      zip.put_next_entry('system-info.txt')
      zip.write(SystemInfo.collect)
      write_log_entries(zip)
    end.string
  end

  def write_config_entries(zip)
    sources.each do |entry_name, path|
      next unless File.exist?(path)

      zip.put_next_entry(entry_name)
      zip.write(anonymize(entry_name, TextEncoding.utf8(File.read(path))))
    end
  end

  def write_log_entries(zip)
    redactions = log_redactions
    ContainerLogs.collect.each do |entry_name, content|
      zip.put_next_entry(entry_name)
      zip.write(Anonymizer.anonymize_text(content, redactions))
    end
  end

  def anonymize(entry_name, content)
    if entry_name == 'config.yaml'
      Anonymizer.anonymize_yaml(content)
    else
      Anonymizer.anonymize_env_style(content)
    end
  end

  # Container logs run through the live .env so any secret a service
  # echoes (forecast collector logging the URL with lat/lng, MQTT clients
  # logging credentials on connect failures, …) gets masked with the same
  # placeholders used in the .env entry.
  def log_redactions
    return [] unless File.exist?(Env.path)

    Anonymizer.log_redactions(TextEncoding.utf8(File.read(Env.path)))
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
      'compose.yaml.bak' => StackBackup.backup_path(compose_path),
      '.env.bak' => StackBackup.backup_path(env_path),
    }
  end
end
