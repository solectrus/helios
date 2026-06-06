module Export
  class Env
    class Unmanaged < Section
      def call
        unmanaged = configuration.unmanaged
        service_env_section(unmanaged)
        orphan_env_section(unmanaged)
      end

      private

      # Names of the services the managed exporters render for this
      # configuration — read off the same list Export::Compose renders from.
      def managed_service_names
        @managed_service_names ||= Compose.active_service_classes(configuration).to_set(&:service_name)
      end

      def service_env_section(unmanaged)
        return if unmanaged.services.blank?

        unmanaged.services.each do |name, config|
          # A managed service of the same name wins, so Export::Compose leaves
          # this one out of compose.yaml entirely — writing its environment to
          # .env would describe a container that isn't in the stack. Mirrors the
          # skip in Export::Compose#add_unmanaged_services.
          next if managed_service_names.include?(name)

          values = config&.env_values
          next if values.blank?

          fresh_groups = fresh_groups(values)
          next if fresh_groups.empty?

          env.add_section("#{name} — service environment")
          render_grouped_env_values(fresh_groups)
        end
      end

      # Render env values in logical groups (MQTT_*, SENEC_*, MAPPING_<N>_*, …),
      # each group led by a `--- Group` separator. Keys within a group stay
      # tight; a blank line separates groups. Single-group lists skip the
      # separator since the enclosing section header is already descriptive.
      def render_grouped_env_values(groups)
        groups.each do |title, entries|
          env.add_comment("--- #{title}") if groups.size > 1
          entries.each { |key, value| env[key] = value }
          env.add_blank_line
        end
      end

      # Group env_values by logical prefix, then drop entries already written
      # by an earlier service section (env[]= updates the existing line in
      # place, so re-rendering them only leaves an empty group header behind).
      def fresh_groups(values)
        values.group_by { |key, _| env_key_group_title(key) }
              .filter_map do |title, entries|
                fresh = entries.reject { |key, _| env.key?(key) }
                [title, fresh] unless fresh.empty?
              end
      end

      def env_key_group_title(key)
        if (match = key.match(/\AMAPPING_(\d+)_/))
          "Mapping #{match[1]}"
        else
          key.split('_', 2).first
        end
      end

      # Orphan .env lines, rendered last. Keys a managed section already wrote
      # are skipped: `env[]=` updates in place, so the stale orphan would
      # silently win over the value HELIOS just derived from the configuration.
      # An orphan can only hold a managed key if it was captured before HELIOS
      # managed it (TIBBER_TOKEN and CHARGER_* predate their sections) — by
      # then it is a leftover, never the source of truth.
      def orphan_env_section(unmanaged)
        return if unmanaged.env_vars.blank?

        fresh = unmanaged.env_vars.reject { |key, _| env.key?(key) }
        return if fresh.empty?

        env.add_section('Unmanaged variables (preserved from existing installation)')
        fresh.each do |key, value|
          env[key] = value
          env.add_blank_line
        end
      end
    end
  end
end
