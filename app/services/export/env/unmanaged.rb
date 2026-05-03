module Export
  class Env
    class Unmanaged < Section
      def call
        unmanaged = configuration.unmanaged
        service_env_section(unmanaged)
        orphan_env_section(unmanaged)
      end

      private

      def service_env_section(unmanaged)
        return if unmanaged.services.blank?

        unmanaged.services.each do |name, config|
          values = config&.env_values
          next if values.blank?

          env.add_section("#{name} — service environment")
          render_grouped_env_values(values)
        end
      end

      # Render env values in logical groups (MQTT_*, SENEC_*, MAPPING_<N>_*, …),
      # each group led by a `--- Group` separator. Keys within a group stay
      # tight; a blank line separates groups. Single-group lists skip the
      # separator since the enclosing section header is already descriptive.
      def render_grouped_env_values(values)
        groups = group_env_values(values)
        groups.each do |title, entries|
          env.add_comment("--- #{title}") if groups.size > 1
          entries.each { |key, value| env[key] = value }
          env.add_blank_line
        end
      end

      def group_env_values(values)
        values.group_by { |key, _| env_key_group_title(key) }
      end

      def env_key_group_title(key)
        if (match = key.match(/\AMAPPING_(\d+)_/))
          "Mapping #{match[1]}"
        else
          key.split('_', 2).first
        end
      end

      def orphan_env_section(unmanaged)
        return if unmanaged.env_vars.blank?

        env.add_section('Unmanaged variables (preserved from existing installation)')
        unmanaged.env_vars.each do |key, value|
          env[key] = value
          env.add_blank_line
        end
      end
    end
  end
end
