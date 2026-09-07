RSpec.describe SettingSection::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(setting:, configuration: Configuration.current)) }

  describe 'the forecast card' do
    let(:setting) { 'forecast' }

    # The provider decides where the data comes from, so the card names it
    # instead of only saying "configured".
    it 'names the configured provider' do
      Configuration.current.update('forecast', { 'forecast' => 'solcast', 'forecast_latitude' => '51.3' })

      expect(rendered).to have_text(I18n.t('configurations.show.configured_for', provider: 'Solcast'))
    end

    it 'falls back to the plain label for a provider it does not know' do
      Configuration.current.update('forecast', { 'forecast' => 'something-new', 'forecast_latitude' => '51.3' })

      expect(rendered).to have_text(I18n.t('configurations.show.configured'))
    end

    it 'reads as not configured while the section is empty' do
      expect(rendered).to have_text(I18n.t('configurations.settings.not_configured'))
    end
  end

  describe 'the deployment card' do
    let(:setting) { 'deployment' }

    it 'shows the active mode' do
      expect(rendered).to have_text(I18n.t('configurations.settings.deployment.modes.full'))
    end
  end
end
