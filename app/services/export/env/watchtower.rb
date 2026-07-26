module Export
  class Env
    class Watchtower < Section
      def call
        schedule = WatchtowerSchedule.new(configuration)
        env.add_section('Watchtower (automatic Docker image updates)')
        entry(schedule.env_key, schedule.env_value, schedule.env_comment)
        entry('WATCHTOWER_SCOPE', 'solectrus', 'Only update containers tagged with this scope label')
        entry('WATCHTOWER_CLEANUP', 'true', 'Remove old images after a successful update')
      end
    end
  end
end
