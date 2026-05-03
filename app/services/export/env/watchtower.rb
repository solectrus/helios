module Export
  class Env
    class Watchtower < Section
      def call
        interval = configuration.system.update_interval.presence || ConfigSchema::DEFAULT_UPDATE_INTERVAL
        env.add_section('Watchtower (automatic Docker image updates)')
        entry('WATCHTOWER_POLL_INTERVAL', interval, 'Interval between update checks (in seconds)')
        entry('WATCHTOWER_SCOPE', 'solectrus', 'Only update containers tagged with this scope label')
        entry('WATCHTOWER_CLEANUP', 'true', 'Remove old images after a successful update')
      end
    end
  end
end
