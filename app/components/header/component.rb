module Header
  class Component < ViewComponent::Base
    TAB_DEFINITIONS = [
      { id: :configuration, path_helper: :sensors_path, icon: 'fa-solid fa-wrench' },
      { id: :services, path_helper: :services_path, icon: 'fa-solid fa-server' },
      {
        id: :backup,
        path_helper: :backups_path,
        icon: 'fa-solid fa-box-archive',
        # Collectors-only stacks have no local databases, so backup never applies.
        visible_if: -> { !Configuration.current.collectors_only? },
      },
    ].freeze

    TAB_BASE_CLASSES = 'flex items-center gap-2 rounded-full px-4 py-1.5 text-sm font-semibold ' \
                       'tracking-widest uppercase transition-colors'.freeze

    def initialize(active_tab:)
      super()
      @active_tab = active_tab
    end

    private

    attr_reader :active_tab

    def tabs
      @tabs ||=
        TAB_DEFINITIONS
        .select { |tab| tab[:visible_if].nil? || tab[:visible_if].call }
        .map { |tab| tab.merge(path: tab_path(tab), label: t(".#{tab[:id]}")) }
    end

    # In collectors_only mode the Sensors page is unreachable; route the
    # Configuration top-level tab straight to Datasources.
    def tab_path(tab)
      if tab[:id] == :configuration && Configuration.current.collectors_only?
        datasources_path
      else
        send(tab[:path_helper])
      end
    end

    def tab_classes(tab)
      class_names(
        TAB_BASE_CLASSES,
        'text-primary bg-primary/10 font-semibold': tab[:id] == active_tab,
        'text-base-content/80 hover:bg-base-content/5 hover:text-base-content': tab[:id] != active_tab,
      )
    end

    # Cache keys for the two fragment-cached regions in the template. The
    # right-side dropdown (HostStats, locale switcher, CSRF logout) stays
    # uncached.
    #
    # NOTE: Rails' template digest does not fingerprint ViewComponent
    # templates (the Digestor can't resolve their virtual path), so neither
    # this template nor the components rendered inside the cached blocks
    # bust the fragments on change. That's acceptable: :memory_store
    # self-clears on every process restart, so a stale fragment can never
    # outlive a deploy. In development with caching enabled, restart the
    # server (or switch locale) after editing the cached templates.
    def tabs_cache_key
      [:header_tabs, active_tab, I18n.locale, Configuration.current.collectors_only?]
    end

    def drawer_cache_key
      [
        :header_drawer,
        I18n.locale,
        Configuration.current.setup_completed?,
        StackBackup.exist?,
      ]
    end
  end
end
