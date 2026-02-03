module DialogModal
  class Component < ViewComponent::Base
    attr_reader :id, :turbo_frame

    def initialize(id:, turbo_frame:)
      super()
      @id = id
      @turbo_frame = turbo_frame
    end
  end
end
