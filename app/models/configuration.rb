class Configuration < ApplicationRecord
  has_many :chapters, dependent: :destroy

  def self.current
    includes(:chapters).first_or_create!(data: default_data)
  end

  def self.default_data
    { 'setup_completed' => false }
  end

  def chapter(name)
    chapters.find_by(name:)&.data || {}
  end

  def update_chapter(name, chapter_data)
    record = chapters.find_or_initialize_by(name:)
    record.data = chapter_data
    record.save!
  end

  def chapter_completed?(name)
    chapters.find { |c| c.name == name.to_s }&.completed? || false
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
