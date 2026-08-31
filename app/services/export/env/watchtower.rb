module Export
  class Env
    class Watchtower < Section
      def call
        schedule = WatchtowerSchedule.new(configuration)
        env.add_section('Watchtower (automatic Docker image updates)')
        entry(schedule.env_key, schedule.env_value, schedule.env_comment)
        entry('WATCHTOWER_SCOPE', 'solectrus', 'Only update containers tagged with this scope label')
        entry('WATCHTOWER_CLEANUP', 'true', 'Remove old images after a successful update')
        entry(
          'WATCHTOWER_TIMEOUT',
          Services::Base::STOP_GRACE_PERIOD,
          'Time a container gets to stop before it is killed (Watchtower ignores stop_grace_period)',
        )
      end
    end
  end
end
