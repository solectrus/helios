module Env
  def self.load
    return nil unless ::File.exist?(path)

    File.load(path)
  end

  def self.path
    ::File.join(Rails.configuration.data_path, '.env')
  end

  # Environment adjustments for any child process that renders a compose
  # config, to be passed as the leading Hash of Open3/Process.spawn.
  #
  # Docker Compose resolves the bare `environment: - KEY` form (and `${KEY}`)
  # from the *process* environment before it consults --env-file. HELIOS' own
  # container receives TZ, ADMIN_PASSWORD and SECRET_KEY_BASE, frozen at the
  # moment it was created — so those stale values silently beat the current
  # .env in every compose command HELIOS shells out to. A changed admin
  # password would never reach the services, and `config --hash` could not
  # even see the change, leaving the service unflagged for restart.
  #
  # Mapping every key the file owns to nil drops it from the child's
  # environment, which makes .env the single source of truth and keeps the
  # rendered config independent of when HELIOS was last recreated.
  def self.spawn_overrides(env_path = path)
    return {} unless ::File.exist?(env_path)

    File.load(env_path).keys.index_with(nil)
  end
end
