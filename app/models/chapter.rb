class Chapter < ApplicationRecord
  # Devices can exist multiple times (e.g. two inverters)
  DEVICE_KINDS = %w[inverter battery wallbox car heatpump consumer].freeze

  # Singletons exist at most once per configuration
  SINGLETON_KINDS = %w[forecast system reverse_proxy backup sensors].freeze

  # All valid chapter kinds (used for DB validation)
  KINDS = (DEVICE_KINDS + SINGLETON_KINDS).freeze

  def self.device_kind?(kind)
    kind.to_s.in?(DEVICE_KINDS)
  end

  def self.singleton_kind?(kind)
    kind.to_s.in?(SINGLETON_KINDS)
  end

  def self.valid_kind?(kind)
    kind.to_s.in?(KINDS)
  end

  belongs_to :configuration

  validates :kind,
            presence: true,
            inclusion: { in: KINDS }

  validates :name,
            presence: true,
            uniqueness: { scope: %i[configuration_id kind] }

  def completed?
    data.present?
  end

  def singleton?
    kind.in?(SINGLETON_KINDS)
  end

  def device?
    kind.in?(DEVICE_KINDS)
  end
end
