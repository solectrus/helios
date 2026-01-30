module SetupHelper
  COMMON_TIMEZONES = [
    'Europe/Berlin',
    'Europe/Vienna',
    'Europe/Zurich',
    'Europe/Amsterdam',
    'Europe/Paris',
    'Europe/London',
    'America/New_York',
    'America/Los_Angeles',
    'Asia/Tokyo',
    'Australia/Sydney',
  ].freeze

  def timezone_options
    common = COMMON_TIMEZONES.map { |tz| [tz, tz] }
    all_others =
      ActiveSupport::TimeZone
      .all
      .map { |tz| [tz.name, tz.tzinfo.identifier] }
      .reject { |_, id| COMMON_TIMEZONES.include?(id) }

    [['--- Common ---', nil]] + common + [['--- All Timezones ---', nil]] +
      all_others
  end
end
