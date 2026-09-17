# Writes a survey payload into the configuration. Every survey carries UI-only
# flags that no section stores, and some drive more than one section, so the
# payload is reshaped before it is saved.
module SettingPersistence
  extend ActiveSupport::Concern

  # The broker half of the MQTT survey, which drives a section of its own.
  include SettingPersistence::Broker

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
    'external' => %w[
      mode app_host bind_ip proxy_network proxy_entrypoint proxy_certresolver force_ssl trusted_proxy_ranges
    ].freeze,
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

  # What a saved survey triggers besides the write itself. Both screens that
  # render a survey run it, so a step added here reaches the commissioning
  # screen and the settings modal alike.
  #
  # The dashboard link and the address external sources write to both need a
  # host, and the browser is the only one here that can name it.
  def finish_setting_save!
    adopt_request_host!
    Orchestration::StackStatus.mark_config_changed!
  end

  # Never after a save through the form that asks for the address itself. The
  # payload is the answer there, an empty one included, and an address taken
  # from the browser behind it would put back what the user just cleared.
  def adopt_request_host!
    return if Configuration.asks_for_app_host?(setting)

    @configuration.adopt_request_host!(request.host)
  end

  # Handle the `enabled` UI flag: when false, clear the section entirely;
  # when true, strip the flag and save the remaining data. Borrowed fields
  # (e.g. reverse_proxy's trusted_proxy_ranges) live in a different section,
  # so clearing this one never touches them — Configuration#update routes
  # them to their own section regardless of the toggle.
  def persist_setting(data)
    strip_theme_sentinel!(data)

    return persist_deployment(data) if setting == 'deployment'
    return persist_reverse_proxy(data) if setting == 'reverse_proxy'
    return persist_tibber(data) if setting == 'tibber'
    return persist_mqtt(data) if setting == 'mqtt'

    return @configuration.update(setting, {}) if data.key?('enabled') && data.delete('enabled') == false

    preserve_software_owned_image!(data)
    @configuration.update(setting, data)
  end

  # The deployment survey asks for the external InfluxDB along with the mode
  # that writes to one, and BORROWED_FIELDS routes those answers into the
  # `influxdb` section. In every other mode the questions are off screen, and
  # the values SurveyJS echoes back must not reach that section: org, bucket
  # and token are generated for the InfluxDB this host runs, and a blank from
  # a hidden question would delete them.
  def persist_deployment(data)
    unless data['mode'] == ConfigSchema::MODE_COLLECTORS_ONLY
      data.except!(*Configuration::DEPLOYMENT_INFLUXDB_FIELDS)
    end

    @configuration.update('deployment', data)
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

  # The "user-selectable" theme is stored as an empty string (the dashboard's
  # UI_THEME convention). The survey carries a `user` sentinel instead, because
  # SurveyJS cannot preselect a radio option with an empty value, so translate
  # it back on the way in (see SettingsController#inject_theme_sentinel! for
  # the way out).
  def strip_theme_sentinel!(data)
    return unless setting == 'dashboard_theme'

    data['ui_theme'] = '' if data['ui_theme'] == 'user'
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
  # cleared. host_port is borrowed as well but belongs to no mode, so it is
  # handled on its own (see #carry_host_port!).
  def persist_reverse_proxy(data)
    mode = reverse_proxy_mode(data)
    owned = REVERSE_PROXY_MODE_FIELDS.fetch(mode)
    borrowed = Configuration::BORROWED_FIELDS.fetch('reverse_proxy').keys

    payload = data.slice(*owned).compact_blank.reverse_merge(borrowed.index_with(nil))
    payload['mode'] = mode if owned.include?('mode')
    drop_unused_transport!(payload)
    carry_host_port!(payload, data, mode)
    preserve_adopted_network!(payload) unless mode == 'external'
    preserve_adopted_traefik!(payload) if mode == 'internal'

    @configuration.update('reverse_proxy', payload)
  end

  # The port the dashboard is published on describes the host, not the proxy in
  # front of it: a port already taken on that machine stays taken when the
  # routing changes. So the field is not one a mode owns. A mode that publishes
  # no port (see Export::Services::Dashboard) hides the question and leaves the
  # stored answer alone, and the modes that do publish one take the answer of
  # the form, a cleared one included.
  #
  # The call sits before #preserve_adopted_network!, so the network name in the
  # payload is still the one the external mode asked for rather than one
  # carried over from another mode.
  def carry_host_port!(payload, data, mode)
    if mode != 'internal' && payload['proxy_network'].blank?
      payload['host_port'] = data['host_port'].presence
    else
      payload.delete('host_port')
    end
  end

  # A network the stack was adopted on, kept across a save that never asked
  # about it. The form asks in the external mode alone, where the network is
  # how the proxy reaches the stack; in the other two the stack merely lives on
  # a parent stack's network (see Configuration#reverse_proxy_network), and a
  # save of the address would otherwise cut every service off it.
  def preserve_adopted_network!(payload)
    network = @configuration.reverse_proxy.proxy_network.presence
    payload['proxy_network'] = network if network
  end

  # The two ways an external proxy reaches the stack exclude each other, and
  # the stored network name is what tells them apart (see
  # Configuration#reverse_proxy_on_shared_network?). A bind IP left over beside
  # it would bind ports the shared-network stack no longer publishes, and would
  # come back the moment the user switches away from the network again.
  #
  # The form already hides whichever field the choice does not own, and
  # survey-core clears a hidden answer. This says the same thing where it is
  # enforced, for a payload that never went through the form.
  def drop_unused_transport!(payload)
    if payload['proxy_network'].present?
      payload.delete('bind_ip')
    else
      payload.except!('proxy_entrypoint', 'proxy_certresolver')
    end
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
