module HostStats
  class Component < ViewComponent::Base
    # Defaults to an empty snapshot so a page render never pays for sampling
    # the host (sysctl / /proc / Docker info). The Stimulus controller's
    # polledAt value starts at 0 (treated as "never polled"), so it fires
    # an immediate refresh on connect and the placeholder is only visible
    # for one paint on initial load. Subsequent Turbo Drive navigations
    # keep the previously polled values via the data-turbo-permanent
    # wrapper and skip the connect-time refresh.
    def initialize(snapshot: ::HostStats::EMPTY_SNAPSHOT)
      super()
      @snapshot = snapshot
    end

    private

    attr_reader :snapshot
  end
end
