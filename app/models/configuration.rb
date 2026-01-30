class Configuration < ApplicationRecord
  def self.current
    first_or_create!(data: default_data)
  end

  def self.default_data
    {
      'general' => {
        'installation_date' => nil,
        'timezone' => nil,
      },
      'setup_completed' => false,
    }
  end

  def installation_date
    data.dig('general', 'installation_date')
  end

  def installation_date=(value)
    data['general'] ||= {}
    data['general']['installation_date'] = value
  end

  def timezone
    data.dig('general', 'timezone')
  end

  def timezone=(value)
    data['general'] ||= {}
    data['general']['timezone'] = value
  end

  def setup_completed?
    data['setup_completed'] == true
  end

  def complete_setup!
    data['setup_completed'] = true
    save!
  end
end
