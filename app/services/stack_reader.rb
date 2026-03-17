require 'open3'
require 'tmpdir'
require 'fileutils'
require 'yaml'

class StackReader
  class Error < StandardError; end

  def initialize(compose_path:, env_path:)
    @compose_path = compose_path
    @env_path = env_path
  end

  # Full resolved config hash for a single service (image, ports, volumes, healthcheck, restart, etc.)
  def service(name)
    services[name]
  end

  # All resolved services as { name => config_hash }
  def services
    @services ||= resolved_config['services'] || {}
  end

  # Raw (unresolved) compose config parsed from YAML, preserving ${VAR} references
  def raw_compose
    @raw_compose ||= YAML.safe_load_file(@compose_path, permitted_classes: [Symbol]) || {}
  end

  # Raw environment variables from .env file (unresolved, preserving original values)
  def raw_env
    @raw_env ||= Env::File.load(@env_path)
  end

  private

  def resolved_config
    @resolved_config ||= run_compose_config
  end

  def run_compose_config
    Dir.mktmpdir do |tmpdir|
      FileUtils.cp(@compose_path, File.join(tmpdir, 'compose.yaml'))
      FileUtils.cp(@env_path, File.join(tmpdir, '.env'))

      stdout, stderr, status = Open3.capture3('docker', 'compose', 'config', chdir: tmpdir)
      raise Error, "docker compose config failed: #{stderr.presence || stdout}" unless status.success?

      YAML.safe_load(stdout, permitted_classes: [Symbol]) || {}
    end
  end
end
