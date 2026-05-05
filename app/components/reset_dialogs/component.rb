module ResetDialogs
  class Component < ViewComponent::Base
    DIALOGS = [
      {
        id: 'reset-confirm',
        key: :reset,
        icon: 'fa-arrow-rotate-left',
        method: :post,
        reasons: %i[reset_reason_user reset_reason_helios],
      },
      {
        id: 'discard-confirm',
        key: :discard,
        icon: 'fa-trash',
        method: :delete,
        reasons: %i[discard_reason_correct discard_reason_diverged],
      },
    ].freeze

    def render?
      StackBackup.exist?
    end

    private

    def compose_filename
      Compose.filename
    end
  end
end
