module ConfigurationMigrations
  # Lifts tibber-collector and senec-charger out of `_unmanaged` into their own
  # managed sections. Both shipped as verbatim passthrough before HELIOS learned
  # to configure them, so existing installations carry them under
  # `_unmanaged.services` and would keep them there forever — the import that
  # promotes them runs only when a stack is adopted.
  #
  # Leaving them is not merely cosmetic: `Export::Compose` renders unmanaged
  # services after the managed ones and both write the same `services:` key, so
  # the stale passthrough silently overwrites a service configured through the
  # prices survey. The survey would report success while the container kept
  # running the old inline environment.
  #
  # Promotion is per service and strictly conservative: a service is lifted out
  # only when the managed export would actually reproduce it, asked of the real
  # export gates rather than a copy of them. Anything that doesn't round-trip —
  # a token that can't be resolved from the stored environment, a charger
  # without its dependencies, a mode that never exports it — stays untouched as
  # passthrough, exactly as it was before this migration.
  class PromoteTibberAndSenecCharger < Base
    version 4

    def up(data)
      services = data.dig(Configuration::UNMANAGED_KEY, 'services')
      return data unless services.is_a?(Hash)

      # Tibber first: the charger's export gate requires the prices it reads,
      # so its own promotion depends on tibber's having happened.
      promote(data, services, 'tibber-collector', 'tibber', Export::Services::TibberCollector) do |env|
        tibber_section(env)
      end
      promote(data, services, 'senec-charger', 'senec_charger', Export::Services::SenecCharger) do |env|
        senec_charger_section(env)
      end

      prune_unmanaged!(data)
      data
    end

    private

    def promote(data, services, service_name, section_key, service_class)
      service = services[service_name]
      return unless service.is_a?(Hash)

      section = yield(resolved_env(data, service)).merge(image_of(service)).compact.presence
      return unless section

      # Test the promotion on a candidate copy first: only commit the section
      # (and drop the passthrough) once the managed export would actually
      # reproduce the service. Otherwise leave both untouched — dropping the
      # passthrough would delete a running container.
      candidate = data.merge(section_key => section)
      return unless service_class.enabled?(Configuration.from_data(candidate))

      data[section_key] = section
      services.delete(service_name)
    end

    # Mirrors Import::ConfigurationImporter::TibberExtractor#section_data.
    def tibber_section(env)
      {
        'token' => env['TIBBER_TOKEN'],
        'measurement' => env['INFLUX_MEASUREMENT'],
      }
    end

    # Mirrors Import::ConfigurationImporter::SenecChargerExtractor#section_data,
    # including its boolean dry_run: the survey's boolean question can't read
    # back the raw 'true' string and would render an imported test mode as off.
    def senec_charger_section(env)
      section = Export::Env::SenecCharger::ENTRIES.to_h { |key, (field, *)| [field, env[key]] }
      section['dry_run'] = section['dry_run'].to_s == 'true' if section['dry_run'].present?
      section
    end

    # The image pins the release channel the user chose. Without carrying it
    # over, promotion would silently move a `:develop` service onto the
    # `DockerImages` default on the next export.
    def image_of(service)
      { 'image' => Compose.normalize_image(service['image']) }
    end

    # Values for the service's `environment:` entries as the container sees
    # them. A bare `KEY` takes its value from the service's `env_values` (the
    # .env lines HELIOS renders for it), an inline `KEY=value` carries it
    # directly, and `KEY=${OTHER}` indirects through either — real-world stacks
    # reference the measurement as `${INFLUX_MEASUREMENT_TIBBER}` or
    # `${INFLUX_MEASUREMENT_PRICES}` rather than spelling it out. Unresolvable
    # entries stay nil and are compacted away, which blocks the promotion.
    def resolved_env(data, service)
      lookup = env_lookup(data, service)

      Array(service['environment']).each_with_object({}) do |entry, env|
        key, value = entry.to_s.split('=', 2)
        env[key] = value.nil? ? lookup.call(key) : interpolate(value, lookup)
      end
    end

    def env_lookup(data, service)
      env_values = service['env_values'] || {}
      orphans = data.dig(Configuration::UNMANAGED_KEY, 'env_vars') || {}
      ->(key) { env_values[key].presence || orphans[key].presence }
    end

    def interpolate(value, lookup)
      (key = value[/\A\$\{([A-Z_][A-Z0-9_]*)\}\z/, 1]) ? lookup.call(key) : value
    end

    # Mirrors Configuration#update_unmanaged: drop the key entirely once the
    # last unmanaged service goes, so no dangling `_unmanaged:` line remains.
    def prune_unmanaged!(data)
      unmanaged = data[Configuration::UNMANAGED_KEY]
      return unless unmanaged.is_a?(Hash)

      unmanaged.delete('services') if unmanaged['services'].blank?
      data.delete(Configuration::UNMANAGED_KEY) if unmanaged.blank?
    end
  end
end
