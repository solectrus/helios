module ConfigNav
  class Component < ViewComponent::Base
    TAB_DEFINITIONS = [
      { id: :sensors, path_helper: :sensors_path, icon: 'fa-solid fa-gauge-high' },
      { id: :datasources, path_helper: :datasources_path, icon: 'fa-solid fa-satellite-dish' },
      { id: :advanced, path_helper: :advanced_path, icon: 'fa-solid fa-sliders' },
    ].freeze

    def initialize(active_tab: nil, compact: false, only: nil)
      super()
      @active_tab = active_tab
      @compact = compact
      @only = only
    end

    private

    attr_reader :only

    def compact?
      @compact
    end

    def show_tabs?
      only != :files
    end

    def show_files?
      only != :tabs
    end

    def active_tab
      @active_tab ||= begin
        controller_id = helpers.controller_name.to_sym
        controller_id if TAB_DEFINITIONS.any? { |t| t[:id] == controller_id }
      end
    end

    def tabs
      @tabs ||= TAB_DEFINITIONS.map { |tab| tab.merge(path: send(tab[:path_helper]), label: t(".#{tab[:id]}")) }
    end

    def active?(tab)
      tab[:id] == active_tab
    end

    def item_classes(tab)
      base =
        if compact?
          'flex items-center gap-3 rounded-lg px-3 py-2 text-base transition-colors'
        else
          'group flex items-center gap-4 rounded-xl px-4 py-3 transition-colors'
        end

      class_names(
        base,
        'bg-primary/15 text-primary font-semibold': active?(tab),
        'text-base-content/70 hover:bg-base-content/5 hover:text-base-content': !active?(tab) && compact?,
        'text-base-content/80 hover:bg-base-content/5 hover:text-base-content': !active?(tab) && !compact?,
      )
    end

    def icon_box_classes(tab)
      return 'w-5 text-center text-base' if compact?

      class_names(
        'flex h-12 w-12 shrink-0 items-center justify-center rounded-lg text-2xl',
        'bg-primary/20 text-primary': active?(tab),
        'bg-base-300/70 text-base-content/60 group-hover:text-base-content': !active?(tab),
      )
    end

    def file_link_classes
      if compact?
        'flex items-center gap-3 rounded-lg px-3 py-2 hover:bg-base-content/5 ' \
          'text-base-content/70 transition-colors'
      else
        'btn btn-ghost btn-block bg-base-content/5 hover:bg-base-content/10 justify-start gap-3 font-mono'
      end
    end

    def show_warning?(tab)
      tab[:id] == :datasources && Configuration.current.incomplete?
    end

    def show_reset?
      only != :tabs && StackBackup.exist?
    end

    def reset_actions
      ResetDialogs::Component::DIALOGS
    end

    def reset_link_classes
      'flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors ' \
        'text-error/80 hover:bg-error/10 hover:text-error'
    end
  end
end
