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
                       'tracking-[0.1em] uppercase transition-colors'.freeze

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
    # NOTE: Rails' template digest only fingerprints this template, not the
    # ConfigNav::Component rendered inside the drawer cache. With
    # :memory_store this self-clears on every process restart, so a stale
    # drawer can never outlive a deploy. If the cache store ever moves to a
    # persistent backend (Redis, Memcached, file store), add a version
    # element to the keys and bump it whenever ConfigNav's template or
    # render-affecting logic changes.
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
