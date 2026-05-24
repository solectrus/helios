module BackupsHelper
  # Localized label for a BackupRepository::InProgress. Covers the S3
  # upload (with percentage) and each phase the backup script marks via
  # backup-phase.txt; falls back to the generic "In progress…" label
  # while no phase is set yet (between container start and the first
  # phase marker write).
  def backup_in_progress_label(in_progress)
    case in_progress.phase
    when :uploading
      t('backups.index.phase_uploading', percent: progress_percent(in_progress))
    when *BackupRunner::KNOWN_PHASES
      t("backups.index.backup_phases.#{in_progress.phase}")
    else
      t('backups.index.in_progress')
    end
  end

  # Localized label for an in-progress restore. Covers the S3 download
  # (with percentage) and each phase the restore script marks via
  # restore-phase.txt; falls back to the generic "Restoring…" label
  # while no phase is set yet (between container start and the first
  # phase marker write).
  def restore_in_progress_label(in_progress)
    case in_progress.phase
    when :downloading
      t('backups.index.phase_downloading', percent: progress_percent(in_progress))
    when *RestoreRunner::KNOWN_PHASES
      t("backups.index.restore_phases.#{in_progress.phase}")
    else
      t('backups.index.restore_in_progress')
    end
  end

  private

  def progress_percent(in_progress)
    number_to_percentage((in_progress.progress || 0.0) * 100, precision: 0)
  end
end
