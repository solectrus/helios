RSpec.describe SettingSection::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(setting:, configuration: Configuration.current)) }

  describe 'the forecast card' do
    let(:setting) { 'forecast' }

    # The provider decides where the data comes from, so the card names it
    # instead of only saying "configured".
    it 'names the configured provider' do
      Configuration.current.update('forecast', { 'forecast' => 'solcast', 'forecast_latitude' => '51.3' })

      expect(rendered).to have_text(I18n.t('configurations.show.provider'))
      expect(rendered).to have_text('Solcast')
    end

    it 'falls back to the plain label for a provider it does not know' do
      Configuration.current.update('forecast', { 'forecast' => 'something-new', 'forecast_latitude' => '51.3' })

      expect(rendered).to have_text(I18n.t('configurations.show.configured'))
    end

    it 'reads as not configured while the section is empty' do
      expect(rendered).to have_text(I18n.t('configurations.settings.not_configured'))
    end
  end

  # Local or cloud decides what the collector can read, so the card says which
  # one it is.
  describe 'the collector cards that reach a device' do
    {
      'shelly' => { field: 'connection', extra: { 'devices' => [{ 'name' => 'Plug' }] } },
      'senec' => { field: 'adapter', extra: { 'host' => 'senec.local' } },
    }.each do |name, setup|
      context "with the #{name} card" do
        let(:setting) { name }

        it 'names local access' do
          Configuration.current.update(name, setup[:extra].merge(setup[:field] => 'local'))

          expect(rendered).to have_text(I18n.t('configurations.show.access'))
          expect(rendered).to have_text(I18n.t('configurations.show.access_local'))
        end

        it 'names cloud access' do
          Configuration.current.update(name, setup[:extra].merge(setup[:field] => 'cloud'))

          expect(rendered).to have_text(I18n.t('configurations.show.access'))
          expect(rendered).to have_text(I18n.t('configurations.show.access_cloud'))
        end

        # `connection` is what marks the shelly section complete, so an empty
        # one never reaches this label. A value HELIOS does not know does.
        it 'falls back to the plain label for an access it does not know' do
          Configuration.current.update(name, setup[:extra].merge(setup[:field] => 'something-new'))

          expect(rendered).to have_text(I18n.t('configurations.show.configured'))
        end
      end
    end
  end
end
