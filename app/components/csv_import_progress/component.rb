module CsvImportProgress
  # Single panel for the full CSV-import lifecycle. Modelled after
  # BackupProgress::Component — four live phases the user sees as a
  # check-list: preparing → importing → flushing → truncating. The
  # csv-importer image emits per-file `Done, …` log lines we already
  # parse, so the importing phase additionally carries a live X/Y
  # progress bar.
  class Component < ViewComponent::Base
    Step = Data.define(:key, :label, :state)

    PHASES = %i[preparing importing flushing truncating].freeze

    # Literal Tailwind class names so the v4 content scanner picks them up;
    # `from-#{status_color}/15` interpolation would not emit success/error
    # variants into the built stylesheet.
    HEADER_GLOW_CLASSES = {
      success: 'from-success/15',
      error: 'from-error/15',
      primary: 'from-primary/15',
    }.freeze

    def initialize(state:, progress: nil, success_count: nil, error_message: nil)
      super()
      @state = state
      @progress = progress || { phase: :importing, done: 0, total: 0 }
      @success_count = success_count
      @error_message = error_message
    end

    def running? = @state == :running
    def succeeded? = @state == :succeeded
    def failed? = @state == :failed

    # The failed state shows only the error message — the checklist would
    # otherwise have to guess where the failure happened (preparing vs
    # importing) and would mislead the user when wrong.
    def show_steps? = !failed?

    def steps
      PHASES.map { |key| Step.new(key: key, label: t(".phases.#{key}"), state: state_for(key)) }
    end

    def importing_progress_value
      return nil unless running? && current_phase == :importing && @progress[:total].to_i.positive?

      ((@progress[:done] * 100.0) / @progress[:total]).round.clamp(0, 100)
    end

    def heading
      return t('.heading_succeeded') if succeeded?
      return t('.heading_failed') if failed?

      t('.heading_running')
    end

    def status_color
      return :success if succeeded?
      return :error if failed?

      :primary
    end

    def header_glow_class = HEADER_GLOW_CLASSES.fetch(status_color)

    def success_summary
      return nil unless succeeded? && @success_count

      t('.success_summary', count: @success_count)
    end

    def error_message_text = @error_message

    private

    def current_phase
      @progress[:phase] || :importing
    end

    def state_for(phase)
      return :done if succeeded?

      idx = PHASES.index(phase)
      cur_idx = PHASES.index(current_phase)
      return :done if idx < cur_idx
      return :pending if idx > cur_idx

      :current
    end
  end
end
