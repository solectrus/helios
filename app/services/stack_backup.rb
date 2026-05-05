class StackBackup
  def self.create!
    backup_file(Compose.path)
    backup_file(Env.path)
  end

  def self.exist?
    File.exist?(backup_path(Compose.path)) && File.exist?(backup_path(Env.path))
  end

  def self.discard!
    FileUtils.rm_f(backup_path(Compose.path))
    FileUtils.rm_f(backup_path(Env.path))
  end

  def self.backup_path(path)
    "#{path}.bak"
  end

  def self.backup_file(path)
    return unless File.exist?(path)

    FileUtils.cp(path, backup_path(path))
  rescue Errno::ENOENT
    nil
  end

  private_class_method :backup_file
end
