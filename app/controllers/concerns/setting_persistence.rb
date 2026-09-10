# Writes a survey payload into the configuration. Every survey carries UI-only
# flags that no section stores, and some drive more than one section, so the
# payload is reshaped before it is saved.
module SettingPersistence
  extend ActiveSupport::Concern

  private

  # Handle the `enabled` UI flag: when false, clear the section entirely;
  # when true, strip the flag and save the remaining data. Borrowed fields
  # (e.g. reverse_proxy's trusted_proxy_ranges) live in a different section,
  # so clearing this one never touches them — Configuration#update routes
  # them to their own section regardless of the toggle.
  def persist_setting(data)
    strip_theme_sentinel!(data)

    return persist_reverse_proxy(data) if setting == 'reverse_proxy'
    return persist_tibber(data) if setting == 'tibber'

    return @configuration.update(setting, {}) if data.key?('enabled') && data.delete('enabled') == false

    preserve_software_owned_image!(data)
    @configuration.update(setting, data)
  end

  # The prices survey drives two services through two UI-only flags. `enabled`
  # owns the Tibber collector (its own section), `charging` owns the SENEC
  # charger, whose fields BORROWED_FIELDS routes into `senec_charger`. Neither
  # flag is stored: whichever is off has its section's fields blanked, and
  # Configuration#update drops a section once its last field goes.
  def persist_tibber(data)
    enabled = data.delete('enabled') == true
    charging = data.delete('charging') == true

    data = {} unless enabled

    # Whether this survey run actually put the charging question on screen:
    # where the charger's dependencies don't hold, Surveys::Tibber::Survey
    # drops the charging pages server-side, so this save must not speak for
    # the charger in either direction (see #blank_senec_charger! /
    # #ignore_senec_charger!).
    if @configuration.senec_charger_configurable?
      blank_senec_charger!(data) unless enabled && charging
    else
      ignore_senec_charger!(data)
    end
    preserve_software_owned_image!(data) if enabled

    @configuration.update('tibber', data)
  end

  # Charging was offered and turned off (or the prices went with it): clear
  # the tuning. Configuration#update drops the section with its last field.
  def blank_senec_charger!(data)
    Configuration::SENEC_CHARGER_SURVEY_FIELDS.each { |field| data[field] = nil }
  end

  # Charging was never offered, so a missing `charging` flag means "not
  # asked", not "switched off". Drop the charger fields from the payload
  # instead: blanking would delete a tuning the user was never shown and
  # cannot re-enter until the dependency returns, while storing would let a
  # payload configure what the survey refused to render.
  def ignore_senec_charger!(data)
    data.except!(*Configuration::SENEC_CHARGER_SURVEY_FIELDS)
  end

  # reverse_proxy uses a tri-state `mode` (none/internal/external) instead of
  # the boolean `enabled` toggle. The mode is stored explicitly: external mode
  # has no required field of its own (bind_ip is optional), so without a
  # persisted marker it would be indistinguishable from `none` and silently
  # collapse on reload. Drop the fields that don't belong to the chosen mode
  # before saving. Borrowed fields (trusted_proxy_ranges, force_ssl) are
  # routed to their own section by Configuration#update.
  def persist_reverse_proxy(data)
    case data['mode']
    when 'external'
      data.delete('app_domain')
      data.delete('letsencrypt_email')
      @configuration.update('reverse_proxy', data)
    when 'internal'
      data.delete('bind_ip')
      # The managed Traefik terminates TLS itself, so the flag is implied and
      # the survey hides it. Blank it, or a value left over from a previous
      # mode would survive invisibly.
      data['force_ssl'] = nil
      @configuration.update('reverse_proxy', data)
    else # 'none' (or missing): clear the whole section
      # `force_ssl` survives: a proxy can terminate TLS without HELIOS
      # knowing a domain, so the survey asks for it in this mode too.
      # Configuration#update routes it into `dashboard` and empties the
      # section with what remains.
      @configuration.update('reverse_proxy', data.slice('force_ssl'))
    end
  end

  # The `image` key on per-service singletons is owned by the Software
  # survey. Per-service surveys don't ship it, but `Configuration#update`
  # replaces the whole section — so re-inject the persisted value before
  # saving to avoid dropping the user's channel choice on every edit.
  def preserve_software_owned_image!(data)
    return unless Configuration::SOFTWARE_IMAGE_OWNERS.include?(setting)
    return if data.key?('image')

    persisted = @configuration.setting_data(setting)['image']
    data['image'] = persisted if persisted.present?
  end
end
