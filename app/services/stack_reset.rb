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

    FileUtils.mv(StackBackup.backup_path(compose_path), compose_path)
    FileUtils.mv(StackBackup.backup_path(env_path), env_path)

    reimport
    StackBackup.create!
    Orchestration::StackStatus.refresh!
  end

  def self.reimport
    reader = Import::StackReader.new(compose_path: Compose.path, env_path: Env.path)
    Import::ConfigurationImporter.new(reader).import!
    Export::Builder.new(Configuration.current).write!
  end
  private_class_method :reimport
end
