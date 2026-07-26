# When the stack checks for new images. Watchtower offers two mutually
# exclusive ways to say it (it refuses to start when both are set):
#
#   WATCHTOWER_POLL_INTERVAL — seconds between checks, first check whenever
#                              the service happens to start
#   WATCHTOWER_SCHEDULE      — 6-field cron ("sec min hour dom mon dow"),
#                              evaluated in the container's timezone (TZ)
#
# HELIOS exports exactly one of them, picked by `system.update_mode`. The
# cron form is restricted to "every day at HH:MM", which is what the survey
# offers; #time_of_day maps that same shape back for the importer.
class WatchtowerSchedule
  POLL_INTERVAL_KEY = 'WATCHTOWER_POLL_INTERVAL'.freeze
  SCHEDULE_KEY = 'WATCHTOWER_SCHEDULE'.freeze

  ENV_KEYS = [POLL_INTERVAL_KEY, SCHEDULE_KEY].freeze

  # "HH:MM" for a cron expression that means "every day at that time", nil for
  # anything else. Only the daily shape is representable in HELIOS, so an
  # imported stack with a more elaborate cron falls back to the poll interval.
  def self.time_of_day(cron)
    fields = cron.to_s.split
    return nil unless fields.size == 6
    return nil unless fields[3..5] == %w[* * *]
    return nil unless fields[0].match?(/\A\d+\z/) # seconds — not representable

    hour, minute = TimeOfDay.parse("#{fields[2]}:#{fields[1].rjust(2, '0')}")
    return nil unless hour

    format('%<hour>02d:%<minute>02d', hour:, minute:)
  end

  def initialize(configuration)
    @configuration = configuration
  end

  def env_key
    daily_time ? SCHEDULE_KEY : POLL_INTERVAL_KEY
  end

  def env_value
    return interval unless (time = daily_time)

    hour, minute = time
    "0 #{minute} #{hour} * * *"
  end

  def env_comment
    if daily_time
      'Cron expression (second minute hour day month weekday) for the daily update check'
    else
      'Interval between update checks (in seconds)'
    end
  end

  private

  attr_reader :configuration

  # [hour, minute] when the user picked a fixed daily time, nil otherwise. An
  # unparseable time falls back to interval polling instead of feeding
  # Watchtower a cron expression it rejects at startup.
  def daily_time
    return @daily_time if defined?(@daily_time)

    @daily_time =
      if system['update_mode'] == ConfigSchema::UPDATE_MODE_TIME
        TimeOfDay.parse(system['update_time'].presence || ConfigSchema::DEFAULT_UPDATE_TIME)
      end
  end

  def interval
    system['update_interval'].presence || ConfigSchema::DEFAULT_UPDATE_INTERVAL
  end

  def system
    configuration.system
  end
end
