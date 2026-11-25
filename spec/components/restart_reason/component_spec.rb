RSpec.describe RestartReason::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(change:, new_version:)) }

  let(:change) { build_change }
  let(:new_version) { false }

  def build_change(added: [], removed: [], changed: [], parts: [])
    Orchestration::ConfigFingerprints::Change.new(added:, removed:, changed:, parts:)
  end

  def items
    rendered.css('li').map(&:text)
  end

  before { with_config_yaml }

  context 'with a new, a changed and a removed sensor' do
    let(:change) do
      build_change(
        added: ['INFLUX_SENSOR_GRID_EXPORT_POWER'],
        changed: ['INFLUX_SENSOR_HOUSE_POWER'],
        removed: ['INFLUX_SENSOR_BATTERY_SOC'],
      )
    end

    it 'says that the service must restart' do
      expect(rendered.css('p').text).to eq('Restart required for these changes:')
    end

    it 'names each sensor by its label' do
      expect(items).to eq(
        [
          "New sensor: #{I18n.t('sensors.grid_export_power')}",
          "Sensor changed: #{I18n.t('sensors.house_power')}",
          "Sensor removed: #{I18n.t('sensors.battery_soc')}",
        ],
      )
    end
  end

  context 'with a custom sensor that carries its own name' do
    let(:change) { build_change(added: ['INFLUX_SENSOR_CUSTOM_POWER_01']) }

    before { with_config_yaml('sensors' => { 'custom_power_01' => { 'source' => 'external', 'name' => 'Sauna' } }) }

    it 'uses that name' do
      expect(items).to eq(['New sensor: Sauna'])
    end
  end

  context 'with a new version' do
    let(:change) { build_change(parts: ['image']) }

    it 'says the version changed' do
      expect(items).to eq(['Version changed'])
    end
  end

  context 'with a sensor and other settings' do
    let(:change) { build_change(added: ['INFLUX_SENSOR_GRID_EXPORT_POWER'], changed: ['INFLUX_TOKEN']) }

    it 'adds the other settings as one item' do
      expect(items.last).to eq('Other settings')
    end
  end

  context 'with a variable that only looks like a sensor' do
    let(:change) { build_change(added: %w[INFLUX_SENSOR_GRID_EXPORT_POWER INFLUX_SENSOR_UNKNOWN]) }

    it 'counts it as another setting' do
      expect(items).to eq(["New sensor: #{I18n.t('sensors.grid_export_power')}", 'Other settings'])
    end
  end

  context 'with more changes than fit' do
    let(:change) do
      build_change(added: %w[INFLUX_SENSOR_GRID_EXPORT_POWER INFLUX_SENSOR_HOUSE_POWER INFLUX_SENSOR_BATTERY_SOC
                             INFLUX_SENSOR_WALLBOX_POWER INFLUX_SENSOR_HEATPUMP_POWER])
    end

    it 'shows the first ones and counts the rest' do
      expect(items.size).to eq(4)
      expect(items.last).to eq('and 2 more changes')
    end
  end

  context 'with a newer image besides the changes' do
    let(:change) { build_change(added: ['INFLUX_SENSOR_GRID_EXPORT_POWER']) }
    let(:new_version) { true }

    it 'mentions the new version last' do
      expect(items.last).to eq('New version available')
    end
  end

  context 'with changed storage, network and technical parts' do
    let(:change) { build_change(parts: %w[healthcheck labels logging volumes]) }

    it 'names each category once, technical settings last' do
      expect(items).to eq(
        ['Storage locations changed', 'Address or network changed', 'Docker settings: health check, logging'],
      )
    end
  end

  context 'with technical parts alone' do
    let(:change) { build_change(parts: %w[stop_grace_period entrypoint command]) }

    it 'names them in plain words, the unnamed ones last' do
      expect(items).to eq(['Docker settings: start command, other'])
    end
  end

  context 'with other settings alone' do
    let(:change) { build_change(changed: ['INFLUX_TOKEN']) }

    it 'lists them' do
      expect(items).to eq(['Other settings'])
    end
  end

  context 'with an empty change' do
    it 'renders nothing' do
      expect(rendered.to_html).to be_empty
    end
  end

  context 'without a known change' do
    let(:change) { nil }

    it 'renders nothing' do
      expect(rendered.to_html).to be_empty
    end
  end
end
