module BackupProgress
  # Final state of a finished backup or restore — what BackupProgress::Component
  # renders once the operation has stopped running. Built by
  # BackupsController#completion_for from the persisted RunnerLog row, lives
  # there until the user dismisses the card.
  Completion = Data.define(:kind, :status, :backup, :message, :started_at, :finished_at)
end
