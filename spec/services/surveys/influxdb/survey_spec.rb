RSpec.describe Surveys::Influxdb::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    context 'when running in full mode (locally managed InfluxDB)' do
      it 'shows only the local Network section with the publish_port toggle' do
        expect(section_names(result)).to eq(['p_local'])
      end

      it 'exposes a boolean publish_port element with a false default' do
        element = find_survey_element(result, 'publish_port')
        expect(element).to include('type' => 'boolean', 'defaultValue' => false)
      end

      it 'offers a host_port input gated by the publish_port toggle' do
        element = find_survey_element(result, 'host_port')
        expect(element).to include(
          'type' => 'text',
          'defaultValue' => '8086',
          'visibleIf' => '{publish_port} = true',
        )
      end

      it 'strips the visibleIfMode marker from the rendered output' do
        expect(result['pages'].first).not_to have_key('visibleIfMode')
      end
    end

    context 'with a managed Traefik (app_domain configured)' do
      before do
        Configuration.current.update('reverse_proxy', { 'app_domain' => 'solar.example.com' })
      end

      it 'replaces the LAN copy with the Traefik routing copy' do
        element = find_survey_element(result, 'publish_port')
        expect(element['title']['de']).to include('Traefik')
        expect(element['title']['default']).to include('Traefik')
      end

      it 'names the resulting public HTTPS URL' do
        description = find_survey_element(result, 'publish_port')['description']
        expect(description['de']).to include('https://solar.example.com:8086')
        expect(description['default']).to include('https://solar.example.com:8086')
      end

      it 'uses the configured host port in the URL' do
        Configuration.current.update('influxdb', { 'host_port' => '18086' })

        description = find_survey_element(result, 'publish_port')['description']
        expect(description['de']).to include('https://solar.example.com:18086')
      end
    end

    # An imported custom Traefik (captured command) keeps the direct host
    # port, so the default LAN copy stays accurate.
    context 'with an imported custom Traefik' do
      before do
        Configuration.current.update('reverse_proxy', {
                                       'app_domain' => 'solar.example.com',
                                       'command' => ['--providers.docker=true'],
                                     })
      end

      it 'keeps the default LAN copy' do
        element = find_survey_element(result, 'publish_port')
        expect(element['title']['de']).to include('lokalen Netzwerk')
      end
    end

    context 'when running in collectors_only mode (external InfluxDB)' do
      before { Configuration.current.update('deployment', { 'mode' => 'collectors_only' }) }

      it 'shows the connection + credentials pages and hides the local Network page' do
        expect(section_names(result)).to contain_exactly('p_connection', 'p_credentials')
      end

      it 'strips the visibleIfMode marker from every surviving page' do
        result['pages'].each { |page| expect(page).not_to have_key('visibleIfMode') }
      end
    end

    context 'when running in dashboard_only mode' do
      before { Configuration.current.update('deployment', { 'mode' => 'dashboard_only' }) }

      # The port is force-published anyway, so asking the user is misleading.
      # Both the local and the external pages are mode-gated away.
      it 'hides every section (nothing for the user to configure)' do
        expect(section_names(result)).to be_empty
      end
    end
  end
end
