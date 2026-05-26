module BackupProgress
  Completion = Data.define(:kind, :status, :backup, :message, :started_at, :finished_at)

  # Single container for the full backup/restore lifecycle so Turbo can
  # morph the body in place when the operation finishes.
  class Component < ViewComponent::Base
    Step = Data.define(:key, :label, :state, :progress_value)

    PROGRESS_PHASES = %i[uploading downloading].freeze
    AUTO_DISMISS_AFTER_MS = 5_000

    def initialize(kind:, include_s3:, in_progress: nil, completion: nil)
      super()
      @kind = kind
      @include_s3 = include_s3
      @in_progress = in_progress
      @completion = completion
    end

    def running? = @completion.nil?
    def success? = @completion&.status == :success
    def failure? = @completion&.status == :failure

    def steps
      cur = current_index
      phases.each_with_index.map do |phase, idx|
        state = state_for(idx, cur)
        Step.new(
          key: phase,
          label: t(".phases.#{phase}"),
          state: state,
          progress_value: progress_value_for(phase, state),
        )
      end
    end

    def header_icon
      @kind == :backup ? 'fa-solid fa-box-archive' : 'fa-solid fa-arrow-rotate-left'
    end

    def status_color
      return :success if success?
      return :error if failure?

      :primary
    end

    def header_color_class = "text-#{status_color}"
    def header_glow_class = "from-#{status_color}/15"

    def kind_label = t(".kind_label.#{@kind}#{status_suffix}")
    def title = t(".title_#{@kind}#{status_suffix}")
    def running_hint = t(".hint_#{@kind}")

    def started_at_label
      started = @in_progress&.started_at
      return nil unless started

      t('.started_at', date: l(started, format: :backup_date), time: l(started, format: :backup_time))
    end

    def filename
      @in_progress&.filename || @completion&.backup&.filename
    end

    def failure_message
      @completion&.message
    end

    def success_stats
      return nil unless success?

      stats = {}
      stats[:size] = success_size if success_size
      stats[:duration] = success_duration if success_duration
      stats.presence
    end

    def success_size
      bytes = @completion&.backup&.bytes
      return nil unless bytes

      helpers.number_to_human_size(bytes, precision: 0)
    end

    def success_duration
      started = @completion&.started_at
      finished = @completion&.finished_at
      return nil unless started && finished

      format_duration([finished - started, 0].max)
    end

    def dismiss_path
      @kind == :restore ? helpers.backups_restore_failure_path : helpers.backups_failure_path
    end

    private

    def status_suffix
      return '_success' if success?
      return '_failure' if failure?

      ''
    end

    def phases
      @phases ||= build_phases
    end

    def build_phases
      list = []
      list << :downloading if @kind == :restore && @include_s3
      list.concat(script_phases)
      list.push(:uploading, :pruning) if @kind == :backup && @include_s3
      list
    end

    def script_phases
      @kind == :backup ? BackupRunner::KNOWN_PHASES : RestoreRunner::KNOWN_PHASES
    end

    def state_for(idx, cur)
      return :done if success?
      return :pending if failure?
      return :done if idx < cur
      return :current if idx == cur

      :pending
    end

    def current_index
      phases.index(@in_progress&.phase) || phases.index(script_phases.first)
    end

    def progress_value_for(phase, state)
      return nil unless state == :current
      return nil unless PROGRESS_PHASES.include?(phase)
      return nil unless @in_progress&.progress

      (@in_progress.progress * 100).clamp(0, 100).round
    end

    def format_duration(seconds)
      total = seconds.to_i
      if total < 60
        t('.stats.duration_seconds', count: total)
      elsif total < 3600
        t('.stats.duration_minutes', minutes: total / 60, seconds: format('%02d', total % 60))
      else
        t('.stats.duration_hours',
          hours: total / 3600, minutes: format('%02d', (total % 3600) / 60), seconds: format('%02d', total % 60))
      end
    end
  end
end
