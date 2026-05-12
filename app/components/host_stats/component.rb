module HostStats
  class Component < ViewComponent::Base
    def initialize(snapshot: ::HostStats.snapshot)
      super()
      @snapshot = snapshot
    end

    private

    attr_reader :snapshot
  end
end
