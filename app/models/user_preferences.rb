class UserPreferences
  COOKIE_NAME = :preferences

  DEFAULTS = {
    'theme' => 'light',
    'expert_mode' => false,
    'show_all_sensors' => false,
    'locale' => 'en',
  }.freeze

  def initialize(cookies)
    raw = cookies[COOKIE_NAME]
    @data = raw ? parse(raw) : {}
  end

  def theme
    @data.fetch('theme', DEFAULTS['theme'])
  end

  def dark_theme?
    theme == 'aqua'
  end

  def expert_mode?
    @data.fetch('expert_mode', DEFAULTS['expert_mode'])
  end

  def show_all_sensors?
    @data.fetch('show_all_sensors', DEFAULTS['show_all_sensors'])
  end

  def locale
    @data.fetch('locale', DEFAULTS['locale'])
  end

  private

  def parse(raw)
    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end
end
