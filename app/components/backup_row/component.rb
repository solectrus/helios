module BackupRow
  class Component < ViewComponent::Base
    def initialize(backup:, restore_current:, actions_disabled:)
      super()
      @backup = backup
      @restore_current = restore_current
      @actions_disabled = actions_disabled
    end

    private

    attr_reader :backup

    def restore_current?
      @restore_current
    end

    def actions_disabled?
      @actions_disabled
    end
  end
end
