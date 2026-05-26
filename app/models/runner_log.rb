# == Schema Information
#
# Table name: runner_logs
# Database name: primary
#
#  id                 :integer          not null, primary key
#  kind               :string           not null
#  last_error_message :text
#  last_finished_at   :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_runner_logs_on_kind  (kind) UNIQUE
#
class RunnerLog < ApplicationRecord
  enum :kind, { backup: 'backup', restore: 'restore' }

  validates :kind, uniqueness: true

  class << self
    def message_for(kind)
      find_by(kind: kind)&.last_error_message.presence
    end

    def messages_for(kinds)
      where(kind: kinds)
        .pluck(:kind, :last_error_message)
        .each_with_object({}) { |(kind, message), result| result[kind.to_sym] = message if message.present? }
    end

    def kind_for(filename)
      filename == RestoreRunner::ERROR_FILENAME ? :restore : :backup
    end

    def record_error!(kind, message)
      entry = find_or_initialize_by(kind: kind)
      return if entry.last_error_message == message

      entry.last_error_message = message
      entry.save!
    end

    # `created_at` marks the start of the run — used by the completion
    # card to compute duration without a separate column.
    def record_started!(kind)
      entry = find_or_initialize_by(kind: kind)
      entry.assign_attributes(created_at: Time.current, last_error_message: nil, last_finished_at: nil)
      entry.save!
    end

    def record_finished!(kind)
      entry = find_or_initialize_by(kind: kind)
      entry.last_finished_at = Time.current
      entry.save!
    end

    def finished_at_for(kind)
      find_by(kind: kind)&.last_finished_at
    end

    def latest_completion_within(kinds, window)
      where(kind: kinds)
        .where(last_finished_at: window.ago..)
        .order(last_finished_at: :desc)
        .first
    end

    def clear!(kind)
      where(kind: kind).update_all(last_error_message: nil, last_finished_at: nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
