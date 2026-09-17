module Export
  class Env
    # The broker HELIOS runs itself. Its credentials live here rather than in
    # the collector's section: the broker owns them, and both services read
    # the same two variables.
    class Mosquitto < Section
      def call
        env.add_section('MQTT broker (managed by HELIOS)')
        volume_path_entry(Services::Mosquitto, 'MQTT broker data')
        credential_entries
      end

      private

      # Both halves or none: without a password the broker writes no password
      # file, and `allow_anonymous false` then turns every client away. A lone
      # username would reach a broker that nobody can log in to.
      def credential_entries
        return unless Services::Mosquitto.authenticated?(configuration)

        mosquitto = configuration.mosquitto
        entry('MQTT_USERNAME', mosquitto.username, 'MQTT broker username')
        entry('MQTT_PASSWORD', mosquitto.password, 'MQTT broker password')
      end
    end
  end
end
