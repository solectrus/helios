RSpec.describe WatchtowerSchedule do
  subject(:schedule) { described_class.new(Configuration.current) }

  def system(**attributes)
    with_config_yaml('system' => attributes.transform_keys(&:to_s))
  end

  describe 'interval mode' do
    it 'falls back to the daily default without any configuration' do
      system

      expect(schedule.env_key).to eq('WATCHTOWER_POLL_INTERVAL')
      expect(schedule.env_value).to eq(ConfigSchema::DEFAULT_UPDATE_INTERVAL)
    end

    it 'uses the configured interval' do
      system(update_mode: 'interval', update_interval: '3600')

      expect(schedule.env_key).to eq('WATCHTOWER_POLL_INTERVAL')
      expect(schedule.env_value).to eq('3600')
    end
  end

  describe 'fixed-time mode' do
    it 'renders the time as a 6-field cron expression' do
      system(update_mode: 'time', update_time: '04:30')

      expect(schedule.env_key).to eq('WATCHTOWER_SCHEDULE')
      expect(schedule.env_value).to eq('0 30 4 * * *')
    end

    it 'keeps a stored interval out of the way, so both are never set at once' do
      system(update_mode: 'time', update_time: '04:30', update_interval: '3600')

      expect(schedule.env_key).to eq('WATCHTOWER_SCHEDULE')
    end

    it 'defaults the time when the mode is set but no time is stored' do
      system(update_mode: 'time')

      expect(schedule.env_value).to eq('0 0 4 * * *')
    end

    # An invalid cron makes Watchtower exit at startup, so a broken time must
    # not reach the container.
    it 'falls back to interval polling on an unusable time' do
      system(update_mode: 'time', update_time: '25:00', update_interval: '3600')

      expect(schedule.env_key).to eq('WATCHTOWER_POLL_INTERVAL')
      expect(schedule.env_value).to eq('3600')
    end
  end

  describe '.time_of_day' do
    it 'maps a daily cron back to HH:MM' do
      expect(described_class.time_of_day('0 30 4 * * *')).to eq('04:30')
    end

    it 'pads single-digit fields' do
      expect(described_class.time_of_day('0 5 9 * * *')).to eq('09:05')
    end

    it 'ignores a cron that does not run daily at a fixed time' do
      expect(described_class.time_of_day('0 0 */6 * * *')).to be_nil
      expect(described_class.time_of_day('0 0 4 * * 1')).to be_nil
      expect(described_class.time_of_day('0 4 * * *')).to be_nil # 5-field cron
      expect(described_class.time_of_day('@daily')).to be_nil
    end

    it 'ignores an out-of-range time' do
      expect(described_class.time_of_day('0 0 24 * * *')).to be_nil
      expect(described_class.time_of_day('0 60 4 * * *')).to be_nil
    end

    it 'is nil without a cron' do
      expect(described_class.time_of_day(nil)).to be_nil
    end
  end
end
