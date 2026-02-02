class Chapter < ApplicationRecord
  NAMES = %w[devices inverter wallbox heatpump mqtt forecast system].freeze

  belongs_to :configuration

  validates :name,
            presence: true,
            uniqueness: {
              scope: :configuration_id,
            },
            inclusion: {
              in: NAMES,
            }

  def completed?
    data.present?
  end
end
