# Writes a survey payload into the configuration. Every survey carries UI-only
# flags that no section stores, and some drive more than one section, so the
# payload is reshaped before it is saved.
module SettingPersistence
  extend ActiveSupport::Concern

  # Which answers each reverse-proxy mode owns. The form shows exactly these
  # per mode (see the visibleIf / requiredIf rules in
  # Surveys::ReverseProxy's survey.json, which a spec holds against this
  # table), and a save stores exactly these. Every other answer is written as
  # empty, because it belongs to a proxy that is no longer there: a mode owns
  # its fields, and nothing survives a mode it is hidden in.
  #
  # `mode` itself is stored for the two modes that name a proxy. It has no
  # required field of its own in the external mode (bind_ip is optional), so
  # without the marker that mode would be indistinguishable from `none` and
  # collapse on reload. The `none` mode owns the address alone, so its section
  # empties and Configuration#update drops it.
  #
  # `force_ssl` belongs to the external mode alone. The managed Traefik implies
  # it, and without a proxy the dashboard would redirect to an HTTPS port
  # nothing serves.
  REVERSE_PROXY_MODE_FIELDS = {
    'none' => %w[app_host].freeze,
    'internal' => %w[mode app_host letsencrypt_email trusted_proxy_ranges].freeze,
    'external' => %w[mode app_host bind_ip force_ssl trusted_proxy_ranges].freeze,
  }.freeze

  # What the section holds beyond the answers above: the compose keys of a
  # Traefik HELIOS adopted on import, its image and the path its certificates
  # live at (see Import::ConfigurationImporter::ReverseProxyExtractor and
  # Export::Services::Traefik#override_or). No form asks for them, so a save
  # carries them through untouched rather than emptying them along with the
  # answers no mode owns.
  #
  # They describe the managed Traefik alone, so they go with the mode that runs
  # it: leaving `internal` drops them like every other field of that mode.
  REVERSE_PROXY_ADOPTED_FIELDS =
    (ConfigSchema::REVERSE_PROXY_FIELDS - REVERSE_PROXY_MODE_FIELDS.values.flatten).freeze

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
  # the boolean `enabled` toggle, and REVERSE_PROXY_MODE_FIELDS says what each
  # mode carries. The payload replaces the section, so a field the mode does
  # not own is cleared by staying out of it.
  #
  # A borrowed field (app_host, trusted_proxy_ranges, force_ssl) is not in that
  # section. Configuration#update routes it into one of its own and only
  # reaches a field the payload names, so all three are named here, the empty
  # ones included. survey-core drops a cleared field from the payload, and this
  # form owns all three, so an answer it does not carry is one the user
  # cleared.
  def persist_reverse_proxy(data)
    mode = reverse_proxy_mode(data)
    owned = REVERSE_PROXY_MODE_FIELDS.fetch(mode)
    borrowed = Configuration::BORROWED_FIELDS.fetch('reverse_proxy').keys

    payload = data.slice(*owned).compact_blank.reverse_merge(borrowed.index_with(nil))
    payload['mode'] = mode if owned.include?('mode')
    preserve_adopted_traefik!(payload) if mode == 'internal'

    @configuration.update('reverse_proxy', payload)
  end

  # Re-inject what REVERSE_PROXY_ADOPTED_FIELDS names, so that a save through
  # the address form keeps the Traefik it found instead of regenerating one
  # from HELIOS defaults: another resolver name, another certificate path and
  # a fresh request for every certificate.
  def preserve_adopted_traefik!(payload)
    persisted = @configuration.reverse_proxy.to_h.slice(*REVERSE_PROXY_ADOPTED_FIELDS)

    payload.merge!(persisted.compact_blank)
  end

  # The mode this save stores, which is the one the stack can run. The managed
  # Traefik routes by host rule, and a rule with nothing in it matches nothing,
  # so a payload that names that mode without an address names no proxy at all
  # and is stored as what it does. The form asks for the address in both modes
  # that name a proxy, so only a request bypassing the form arrives this way.
  def reverse_proxy_mode(data)
    mode = data['mode'].presence_in(REVERSE_PROXY_MODE_FIELDS.keys) || 'none'
    return 'none' if mode == 'internal' && data['app_host'].blank?

    mode
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
