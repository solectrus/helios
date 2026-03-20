module ThemeToggle
  class Component < ViewComponent::Base
    delegate :preferences, to: :helpers
  end
end
