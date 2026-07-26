# Wall-clock time of day, as the SurveyJS `inputType: "time"` inputs store it
# ("HH:MM"). Used wherever a stored time drives scheduling — the automatic
# backup (BackupScheduler) and the daily update check (WatchtowerSchedule).
module TimeOfDay
  # [hour, minute], or nil when the value is missing or unusable. Callers treat
  # nil as "not scheduled" instead of guessing a time.
  def self.parse(value)
    match = value.to_s.match(/\A(\d{1,2}):(\d{2})\z/)
    return nil unless match

    hour = match[1].to_i
    minute = match[2].to_i
    return nil unless hour.between?(0, 23) && minute.between?(0, 59)

    [hour, minute]
  end
end
