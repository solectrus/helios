module BackupsHelper
  # Localized label for a BackupRepository::InProgress, including the
  # current S3-upload percentage when the run is in the upload phase.
  def backup_in_progress_label(in_progress)
    case in_progress.phase
    when :uploading
      t('backups.index.phase_uploading', percent: progress_percent(in_progress))
    else
      t('backups.index.in_progress')
    end
  end

  # Localized label for an in-progress restore, including the current S3
  # download percentage while HELIOS fetches the tar.
  def restore_in_progress_label(in_progress)
    case in_progress.phase
    when :downloading
      t('backups.index.phase_downloading', percent: progress_percent(in_progress))
    else
      t('backups.index.restore_in_progress')
    end
  end

  private

  def progress_percent(in_progress)
    number_to_percentage((in_progress.progress || 0.0) * 100, precision: 0)
  end
end
