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
    redactions = value_redactions

    sources.each do |entry_name, path|
      next unless File.exist?(path)

      zip.put_next_entry(entry_name)
      zip.write(anonymize(entry_name, TextEncoding.utf8(File.read(path)), redactions))
    end
  end

  # One log at a time: each one goes into the zip and is let go of again, so
  # the bundle never holds every service's log at once.
  def write_log_entries(zip)
    redactions = value_redactions
    ContainerLogs.each_log do |entry_name, content|
      zip.put_next_entry(entry_name)
      zip.write(Anonymizer.anonymize_text(content, redactions))
    end
  end

  # Two passes. The structural one knows the file format and masks by key,
  # which is what catches a secret the first time it is seen. The literal
  # one then sweeps the same text for values already masked elsewhere —
  # a compose.yaml carries the domain inside a Traefik rule
  # (`Host(`solectrus.example.com`)`), where no `KEY=value` line exists for
  # the key-based pass to recognize.
  def anonymize(entry_name, content, redactions)
    structural =
      if entry_name == 'config.yaml'
        Anonymizer.anonymize_yaml(content)
      else
        Anonymizer.anonymize_env_style(content)
      end

    Anonymizer.anonymize_text(structural, redactions)
  end

  # Values taken from the live .env, so anything echoed elsewhere (a
  # forecast collector URL with lat/lng in a log, MQTT credentials on a
  # failed connect, the domain inside a Traefik label) gets masked with the
  # same placeholders used in the .env entry.
  def value_redactions
    return [] unless File.exist?(Env.path)

    Anonymizer.value_redactions(TextEncoding.utf8(File.read(Env.path)))
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
