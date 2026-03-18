class Configuration < ApplicationRecord
  has_many :chapters, dependent: :destroy

  def self.current
    includes(:chapters).first_or_create!(data: default_data)
  end

  def self.default_data
    { 'setup_completed' => false }
  end

  # Look up chapter data by kind (and optionally name for devices)
  # Uses in-memory search when chapters are preloaded to avoid extra DB queries
  def chapter(kind, name = nil)
    record = chapters.find do |c|
      c.kind == kind.to_s && (name.nil? || c.name == name.to_s)
    end
    record&.data || {}
  end

  # Create or update a chapter. For singletons, name defaults to kind.
  def update_chapter(kind, chapter_data, name: kind)
    record = chapters.find_or_initialize_by(kind:, name:)
    record.data = chapter_data
    record.save!
    chapters.reload
  end

  def chapter_completed?(kind, name = nil)
    found =
      if name
        chapters.find { |c| c.kind == kind.to_s && c.name == name.to_s }
      else
        chapters.find { |c| c.kind == kind.to_s }
      end
    found&.completed? || false
  end

  # All chapters of a given kind (useful for device kinds)
  def chapters_of_kind(kind)
    chapters.select { |c| c.kind == kind.to_s }
  end

  # Add a new device chapter
  def add_device(kind, name, data = {})
    unless kind.to_s.in?(Chapter::DEVICE_KINDS)
      raise ArgumentError, "#{kind} is not a device kind"
    end

    chapters.create!(kind:, name:, data:)
  end

  # Remove a device chapter
  def remove_device(kind, name)
    chapters.find_by!(kind:, name:).destroy!
  end

  # Check if any device uses MQTT as data source
  def mqtt_required?
    chapters.any? do |c|
      c.data['data_source'] == 'mqtt' ||
        c.data['power_source'] == 'mqtt' ||
        c.data['details_source'] == 'mqtt'
    end
  end

  # Check if Ingest service is needed
  def ingest_required?
    inverters = chapters_of_kind('inverter')
    inverters.size > 1 ||
      inverters.any? { |c| c.data['house_power_known'] == false }
  end

  # Deduplicated SENEC hosts across all chapters
  def senec_hosts
    chapters.filter_map do |c|
      c.data['senec_host'] if c.data['data_source']&.start_with?('senec')
    end.uniq
  end

  # Default sensor mappings derived from device chapters
  def computed_sensor_mappings
    SensorDefaults.for_chapters(chapters)
  end

  # Effective sensor mappings (computed + overrides from sensors chapter)
  def effective_sensor_mappings
    computed_sensor_mappings.merge(chapter('sensors'))
  end

  # Device names for each sensor (e.g. 'INFLUX_SENSOR_CUSTOM_POWER_01' => 'Geschirrspüler')
  def sensor_device_names
    SensorDefaults.device_names_for_chapters(chapters)
  end

  # Legacy accessors for backward compatibility
  def installation_date
    chapter('system')['installation_date']
  end

  def installation_date=(value)
    current = chapter('system')
    update_chapter('system', current.merge('installation_date' => value))
  end

  def timezone
    chapter('system')['timezone']
  end

  def timezone=(value)
    current = chapter('system')
    update_chapter('system', current.merge('timezone' => value))
  end

  def setup_completed?
    data['setup_completed'] == true
  end

  def complete_setup!
    data['setup_completed'] = true
    save!
  end
end
