class UserPreferences
  COOKIE_NAME = :preferences

  DEFAULTS = {
    'expert_mode' => false,
    'hide_unused' => false,
  }.freeze

  def initialize(cookies)
    raw = cookies[COOKIE_NAME]
    @data = raw ? parse(raw) : {}
  end

  def expert_mode?
    @data.fetch('expert_mode', DEFAULTS['expert_mode'])
  end

  def hide_unused?
    @data.fetch('hide_unused', DEFAULTS['hide_unused'])
  end

  def locale
    @data['locale']
  end

  private

  def parse(raw)
    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end
end
