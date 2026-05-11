RSpec.describe Surveys::Influxdb::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    def page_names(survey)
      survey['pages'].pluck('name')
    end

    context 'when running in full mode (locally managed InfluxDB)' do
      it 'shows only the local Network page with the publish_port toggle' do
        expect(page_names(result)).to eq(['p_local'])
      end

      it 'exposes a boolean publish_port element with a false default' do
        element = result['pages'].first['elements'].find { |e| e['name'] == 'publish_port' }
        expect(element).to include('type' => 'boolean', 'defaultValue' => false)
      end

      it 'offers a host_port input gated by the publish_port toggle' do
        element = result['pages'].first['elements'].find { |e| e['name'] == 'host_port' }
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

    context 'when running in collectors_only mode (external InfluxDB)' do
      before { Configuration.current.update('deployment', { 'mode' => 'collectors_only' }) }

      it 'shows the connection + credentials pages and hides the local Network page' do
        expect(page_names(result)).to contain_exactly('p_connection', 'p_credentials')
      end

      it 'strips the visibleIfMode marker from every surviving page' do
        result['pages'].each { |page| expect(page).not_to have_key('visibleIfMode') }
      end
    end

    context 'when running in dashboard_only mode' do
      before { Configuration.current.update('deployment', { 'mode' => 'dashboard_only' }) }

      # The port is force-published anyway, so asking the user is misleading.
      # Both the local and the external pages are mode-gated away.
      it 'hides every page (nothing for the user to configure)' do
        expect(result['pages']).to be_empty
      end
    end
  end
end
