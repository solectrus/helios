class StackReset
  def self.perform!
    raise 'Backup files missing — cannot reset' unless StackBackup.exist?

    # Capture paths up front: Compose.path resolves via File.exist?, so the
    # result changes once we delete the file below.
    compose_path = Compose.path
    env_path = Env.path

    # `docker compose down` reads the current compose.yaml to know what
    # to bring down — must run before the file is deleted.
    Orchestration::Runner.down

    Configuration.delete!
    FileUtils.rm_f(compose_path)
    FileUtils.rm_f(env_path)

    # Restore the user's original pre-HELIOS config from the backup. `reimport`
    # re-exports and overwrites compose.yaml / .env below, so this restored copy
    # is transient — only the backup preserves the original. For the same reason
    # we must NOT re-create the backup afterwards: that would clobber the
    # original with the regenerated output (and turn every further reset into a
    # no-op).
    StackBackup.restore(compose_path)
    StackBackup.restore(env_path)

    reimport
    Orchestration::StackStatus.refresh!
  end

  def self.reimport
    reader = Import::StackReader.new(compose_path: Compose.path, env_path: Env.path)
    Import::ConfigurationImporter.new(reader).import!
    Export::Builder.new(Configuration.current).write!
  end
  private_class_method :reimport

  # A reset restores compose.yaml.bak, which still pins the PostgreSQL major
  # from before a major-version upgrade. That major cannot start against the
  # already-migrated data directory, so the reset would break the stack.
  # True when the backed-up compose.yaml pins an older PostgreSQL major than
  # the one currently deployed — the reset is then refused (the user can edit
  # the image line in the .bak file by hand to re-enable it).
  def self.postgresql_downgrade?
    backup_major = DockerImages.postgresql_major(backup_postgresql_image)
    current_major = DockerImages.postgresql_major(Configuration.current.postgresql.image)
    return false unless backup_major && current_major

    backup_major < current_major
  end

  # PostgreSQL image pinned in the backed-up compose.yaml, or nil when the
  # backup file or the PostgreSQL service is absent.
  def self.backup_postgresql_image
    path = StackBackup.backup_path(Compose.path)
    return unless File.exist?(path)

    Compose::File.load(path).services.find('postgresql')&.image
  end
  private_class_method :backup_postgresql_image
end
