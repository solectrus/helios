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

    # The reset would restore an older PostgreSQL major that can no longer
    # start against the migrated data directory — see StackReset. Only the
    # reset dialog is affected; discarding the backup stays available.
    def reset_blocked?(dialog)
      dialog[:key] == :reset && postgresql_downgrade?
    end

    private

    def postgresql_downgrade?
      return @postgresql_downgrade if defined?(@postgresql_downgrade)

      @postgresql_downgrade = StackReset.postgresql_downgrade?
    end

    def compose_filename
      Compose.filename
    end
  end
end
