# == Schema Information
#
# Table name: runner_logs
# Database name: primary
#
#  id                 :integer          not null, primary key
#  kind               :string           not null
#  last_error_message :text
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

    def clear!(kind)
      where(kind: kind)
        .where.not(last_error_message: nil)
        .update_all(last_error_message: nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
