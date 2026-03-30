class StackBackup
  def self.create!
    backup_file(Compose.path)
    backup_file(Env.path)
  end

  def self.backup_file(path)
    return unless File.exist?(path)

    FileUtils.cp(path, "#{path}.bak")
  rescue Errno::ENOENT
    nil
  end

  private_class_method :backup_file
end
