class UserPreferences
  COOKIE_NAME = :preferences

  DEFAULTS = { 'hide_unused' => false }.freeze

  def initialize(cookies)
    raw = cookies[COOKIE_NAME]
    @data = raw ? parse(raw) : {}
  end

  def hide_unused?
    @data.fetch('hide_unused', DEFAULTS['hide_unused'])
  end

  def locale
    @data['locale']
  end

  def resolved_locale(accept_language)
    locale&.to_sym ||
      AcceptLanguage.parse(accept_language).match(*I18n.available_locales) ||
      I18n.default_locale
  end

  private

  def parse(raw)
    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end
end
