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

  describe 'the MQTT card' do
    let(:setting) { 'mqtt' }

    # The broker is what a user goes looking for, and the card is the only
    # place its address can be changed. So the card names whose broker it is
    # and where it answers, rather than only saying "configured".
    it 'names the broker HELIOS runs, with the address devices publish to' do
      Configuration.current.update('system', { 'app_host' => 'solectrus.local' })
      Configuration.current.update('mqtt', { 'broker_managed' => true })
      Configuration.current.update('mosquitto', { 'port' => 1884 })

      expect(rendered).to have_text(I18n.t('configurations.show.broker_managed'))
      expect(rendered).to have_text('solectrus.local:1884')
    end

    # Nothing names the host of the machine on a fresh install, and a port
    # without a host would read as an address that goes nowhere.
    it 'falls back to the port alone while no host is known' do
      Configuration.current.update('mqtt', { 'broker_managed' => true })

      expect(rendered).to have_text(
        I18n.t('configurations.show.broker_port', port: Export::Services::Mosquitto::CONTAINER_PORT),
      )
    end

    # No survey names the encrypted port any more, so the card is where it
    # has to stand. Only the domain reaches it, never the host address.
    it 'names the encrypted port where Traefik serves the broker' do
      Configuration.current.update('reverse_proxy', { 'mode' => 'internal', 'app_host' => 'pv.example.com' })
      Configuration.current.update('mqtt', { 'broker_managed' => true })

      expect(rendered).to have_text('pv.example.com:1883')
      expect(rendered).to have_text("pv.example.com:#{Export::Services::Mosquitto::TLS_HOST_PORT}")
    end

    it 'names no encrypted port without that proxy' do
      Configuration.current.update('system', { 'app_host' => 'solectrus.local' })
      Configuration.current.update('mqtt', { 'broker_managed' => true })

      expect(rendered.css('.fa-lock')).to be_empty
    end

    # A zero reads as a word, everything else as the number itself.
    it 'counts the topics behind the card' do
      Configuration.current.update('mqtt',
                                   { 'broker_managed' => true,
                                     'mappings' => [{ 'topic' => 'a/b', 'type' => 'float', 'name' => 'foo' }] })

      expect(rendered).to have_text(I18n.t('datasources.mqtt_topics.inline.additional_label'))
      expect(rendered).to have_text('1')
    end

    it 'names a broker of the user with its own address' do
      Configuration.current.update('mqtt',
                                   { 'broker_managed' => false, 'mqtt_host' => 'broker.local', 'mqtt_port' => 1883 })

      expect(rendered).to have_text(I18n.t('configurations.show.broker_external'))
      expect(rendered).to have_text('broker.local:1883')
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
