RSpec.describe Header::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(active_tab: :services)) }

  let(:sign) { rendered.css('a i.fa-triangle-exclamation') }
  let(:marked_link) { rendered.css('a').find { |a| a.css('i.fa-triangle-exclamation').any? } }

  # The configuration entry carries the sign the side column puts on the
  # single settings, so an open setting is visible from every screen.
  context 'with a setting still open' do
    before { with_config_yaml }

    it 'marks the configuration tab in the warning color' do
      expect(sign.attr('class').value).to include('text-warning')
    end

    it 'names the state for a reader that cannot see the icon' do
      expect(rendered.css('a .sr-only').text).to include(I18n.t('configurations.show.incomplete'))
    end
  end

  # The tab opens the screen its own sign marks. The side column then carries
  # the sign again, on the entry that leads on.
  context 'with an open data source' do
    before do
      with_config_yaml(
        'system' => { 'installation_date' => '2024-01-15' },
        'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
      )
    end

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

    before { with_config_yaml }

    it 'holds the sign back' do
      expect(sign.attr('class').value).to include(described_class::MUTED_WARNING_CLASSES)
      expect(sign.attr('class').value).not_to include('text-warning')
    end
  end

  # Production caches the tab strip. With a required setting and a data source
  # both open, filling in the setting moves the target of the tab and changes
  # nothing else about the strip, so the sign alone cannot key the fragment.
  describe 'the key of the cached tab strip' do
    def cache_key_for(data)
      with_config_yaml(data)
      Current.configuration = nil

      component = described_class.new(active_tab: :services)
      render_inline(component)
      component.send(:tabs_cache_key)
    end

    it 'follows the target of the configuration tab' do
      sensors = { 'sensors' => { 'inverter_power' => { 'source' => 'senec' } } }

      both_open = cache_key_for(sensors)
      source_open = cache_key_for(sensors.merge('system' => { 'installation_date' => '2024-01-15' }))

      expect(both_open).not_to eq(source_open)
    end
  end
end
