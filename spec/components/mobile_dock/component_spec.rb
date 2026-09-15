RSpec.describe MobileDock::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(active_tab: :services)) }

  let(:dot) { rendered.css('.dock .rounded-full') }

  # The dock has room for a dot only, but it reports the same state as the
  # warning sign in the top navigation.
  context 'with a setting still open' do
    before { with_config_yaml }

    it 'marks the configuration item in the warning color' do
      expect(dot.attr('class').value).to include('bg-warning')
    end

    it 'names the state for a reader that cannot see the dot' do
      expect(rendered.css('.dock .sr-only').text).to include(I18n.t('configurations.show.incomplete'))
    end
  end

  context 'with every required setting filled in' do
    before { with_startable_config_yaml }

    it 'leaves the configuration item plain' do
      expect(dot).to be_empty
    end
  end

  # Same rule as in the top navigation: the color belongs to the level that
  # still leads somewhere.
  context 'when the configuration is open' do
    subject(:rendered) { render_inline(described_class.new(active_tab: :configuration)) }

    before { with_config_yaml }

    it 'holds the dot back' do
      expect(dot.attr('class').value).not_to include('bg-warning')
    end
  end
end
