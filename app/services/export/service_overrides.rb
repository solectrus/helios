module Export
  # Applies per-service compose-key overrides (ADR-0015) to the generated
  # service hash. The allowlist is enforced at config-load time
  # (Configuration#sanitize_service_overrides!), so anything that arrives
  # here has already been validated.
  #
  # Strategies, kept deliberately simple:
  #   labels / ports / volumes  — array concat, override appended
  #   environment               — list-form merge, override-wins per name
  #
  # Append-only label semantics (no dedupe) ensures HELIOS-generated
  # routing labels for the dashboard stay authoritative when both sides
  # name the same key — Traefik takes the last value, which is the
  # override, and that is the user's explicit choice.
  class ServiceOverrides
    ALLOWED_KEYS = ConfigSchema::SERVICE_OVERRIDES_ALLOWED_KEYS

    def self.apply(configuration, service_name, service_hash)
      new(configuration).apply(service_name, service_hash)
    end

    def initialize(configuration)
      @configuration = configuration
    end

    def apply(service_name, service_hash)
      overrides = @configuration.service_overrides[service_name.to_s].to_h
      return service_hash if overrides.empty?

      ALLOWED_KEYS.each do |key|
        value = overrides[key]
        next if value.blank?

        service_hash[key.to_sym] = merge(key, service_hash[key.to_sym], value)
      end

      service_hash
    end

    private

    def merge(key, existing, override)
      case key
      when 'environment' then merge_environment(existing, override)
      else Array(existing) + Array(override)
      end
    end

    # `environment:` may arrive as an array of "NAME=value" / bare "NAME"
    # entries (HELIOS template form) or as a hash. Normalize both sides to
    # an ordered list, then apply override-wins on the NAME axis so a user-
    # supplied value replaces a HELIOS-emitted bare reference or assignment
    # for the same variable.
    def merge_environment(existing, override)
      base = Array(existing).map { |entry| env_entry(entry) }
      additions = normalize_env_override(override).map { |entry| env_entry(entry) }
      additions_by_name = additions.to_h { |name, _| [name, true] }

      kept = base.reject { |name, _| additions_by_name[name] }
      (kept + additions).map { |name, value| value.nil? ? name : "#{name}=#{value}" }
    end

    def normalize_env_override(value)
      case value
      when Hash then value.map { |k, v| v.nil? ? k.to_s : "#{k}=#{v}" }
      else Array(value)
      end
    end

    def env_entry(entry)
      case entry
      when Hash then entry.first
      else
        name, value = entry.to_s.split('=', 2)
        [name, value]
      end
    end
  end
end
