RSpec.describe Header::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(active_tab: :services)) }

  let(:sign) { rendered.css('a i.fa-triangle-exclamation') }
  let(:marked_link) { rendered.css('a').find { |a| a.css('i.fa-triangle-exclamation').any? } }

  # The configuration entry carries the sign the side column puts on the single
  # data sources, so an open source is visible from every screen. It is the one
  # state left: what the Settings screen holds is asked for before any screen
  # opens (see CommissioningController).
  context 'with an open data source' do
    before { with_config_yaml('sensors' => { 'inverter_power' => { 'source' => 'senec' } }) }

    it 'marks the configuration tab in the warning color' do
      expect(sign.attr('class').value).to include('text-warning')
    end

    it 'names the state for a reader that cannot see the icon' do
      expect(rendered.css('a .sr-only').text).to include(I18n.t('configurations.show.incomplete'))
    end

    # The tab opens the screen its own sign marks. The side column then carries
    # the sign again, on the entry that leads on.
    it 'points the configuration tab at the data sources' do
      expect(marked_link['href']).to eq('/datasources')
    end
  end

  context 'with every required setting filled in' do
    before { with_startable_config_yaml }

    it 'leaves the configuration tab plain' do
      expect(sign).to be_empty
    end
  end

  # Inside the configuration the side column marks the entry that leads on, so
  # the tab keeps the sign as a trail and hands the color over.
  context 'when the configuration is open' do
    subject(:rendered) { render_inline(described_class.new(active_tab: :configuration)) }

    before { with_config_yaml('sensors' => { 'inverter_power' => { 'source' => 'senec' } }) }

    it 'holds the sign back' do
      expect(sign.attr('class').value).to include(described_class::MUTED_WARNING_CLASSES)
      expect(sign.attr('class').value).not_to include('text-warning')
    end
  end

  # Production caches the tab strip, and the tab links to the screen the
  # configuration should open. That target moves with the mode and with what is
  # still open, so the key carries it rather than a sign derived from it.
  describe 'the key of the cached tab strip' do
    def cache_key_for(data)
      with_config_yaml(data)
      Current.configuration = nil

      component = described_class.new(active_tab: :services)
      render_inline(component)
      component.send(:tabs_cache_key)
    end

    it 'carries the sensors as the target of a full installation' do
      expect(cache_key_for({})).to include('/sensors')
    end

    it 'carries the data sources where the sensors screen has no meaning' do
      key = cache_key_for('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
                          'influxdb' => { 'host' => 'influx.example.com' })

      expect(key).to include('/datasources')
    end
  end
end
