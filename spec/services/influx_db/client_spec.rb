RSpec.describe InfluxDb::Client do
  let(:client) do
    described_class.new(
      token: 'test-token',
      org: 'test-org',
      bucket: 'test-bucket',
      host: 'influxdb.test',
      port: 8086,
    )
  end

  let(:query_url) { 'http://influxdb.test:8086/api/v2/query?org=test-org' }

  describe '.from_configuration' do
    before { with_config_yaml('influxdb' => { 'token' => 'tok', 'org' => 'org', 'bucket' => 'bkt' }) }

    it 'creates client from configuration' do
      client = described_class.from_configuration(Configuration.current)

      expect(client).to be_a(described_class)
    end

    it 'targets the external InfluxDB in collectors_only mode' do
      with_config_yaml(
        'deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
        'influxdb' => {
          'token' => 'tok', 'org' => 'org', 'bucket' => 'bkt',
          'host' => 'remote.example', 'port' => '9000', 'schema' => 'https'
        },
      )
      stub_request(:post, 'https://remote.example:9000/api/v2/query?org=org')
        .to_return(status: 200, body: '')

      described_class.from_configuration(Configuration.current)
                     .query_all_latest('p' => 'm:f')

      expect(WebMock).to have_requested(:post, 'https://remote.example:9000/api/v2/query?org=org')
    end
  end

  describe '#query_all_latest' do
    it 'returns parsed sensor readings' do
      csv = <<~CSV
        #group,false,false
        ,result,table,_time,_value,_field,_measurement
        ,_result,0,2026-03-21T10:00:00Z,4200.5,inverter_power,SENEC
      CSV
      stub_request(:post, query_url).to_return(status: 200, body: csv)

      result = client.query_all_latest('inverter_power' => 'SENEC:inverter_power')

      expect(result['inverter_power'].value).to eq(4200.5)
      expect(result['inverter_power'].time).to be_a(ActiveSupport::TimeWithZone)
    end

    it 'skips invalid mappings without field separator' do
      result = client.query_all_latest('bad' => 'SENEC')

      expect(result).to be_empty
    end

    it 'returns nil for empty response' do
      stub_request(:post, query_url).to_return(status: 200, body: '')

      result = client.query_all_latest('inverter_power' => 'SENEC:inverter_power')

      expect(result['inverter_power']).to be_nil
    end

    it 'handles non-numeric values' do
      csv = <<~CSV
        ,result,table,_time,_value,_field,_measurement
        ,_result,0,2026-03-21T10:00:00Z,INITIAL,current_state,SENEC
      CSV
      stub_request(:post, query_url).to_return(status: 200, body: csv)

      result = client.query_all_latest('system_status' => 'SENEC:current_state')

      expect(result['system_status'].value).to eq('INITIAL')
    end

    it 'decodes binary HTTP bodies with multibyte characters as UTF-8' do
      # Net::HTTP returns the body as ASCII-8BIT, regardless of what the server sent.
      csv = ",_time,_value\n,2026-03-21T10:00:00Z,LÄDT ⚡\n"
      stub_request(:post, query_url).to_return(status: 200, body: csv.b)

      value = client.query_all_latest('system_status' => 'SENEC:current_state')['system_status'].value

      expect(value).to eq('LÄDT ⚡')
    end

    it 'returns nil and logs warning on HTTP error' do
      stub_request(:post, query_url).to_return(status: 500, body: 'Internal Server Error')

      result = client.query_all_latest('inverter_power' => 'SENEC:inverter_power')

      expect(result['inverter_power']).to be_nil
    end

    it 'returns nil and logs warning on connection refused' do
      stub_request(:post, query_url).to_raise(Errno::ECONNREFUSED)

      result = client.query_all_latest('inverter_power' => 'SENEC:inverter_power')

      expect(result['inverter_power']).to be_nil
    end

    # When the host is unreachable, retrying for every remaining sensor
    # only piles timeout on timeout. We want a single fast-fail so polling
    # stays responsive even with a broken InfluxDB.
    it 'aborts the batch on the first connection error and logs once' do
      stub_request(:post, query_url).to_raise(SocketError.new('getaddrinfo failed'))
      allow(Rails.logger).to receive(:warn)

      result = client.query_all_latest('a' => 'm:f1', 'b' => 'm:f2', 'c' => 'm:f3')

      expect(result).to eq({})
      expect(WebMock).to have_requested(:post, query_url).once
      expect(Rails.logger).to have_received(:warn)
        .with(%r{InfluxDB unreachable at http://influxdb\.test:8086}).once
    end

    it 'reuses one HTTP session across multiple sensors' do
      csv = ",result,table,_time,_value,_field,_measurement\n,_result,0,2026-03-21T10:00:00Z,1,f,m\n"
      stub_request(:post, query_url).to_return(status: 200, body: csv)

      client.query_all_latest('a' => 'm:f1', 'b' => 'm:f2', 'c' => 'm:f3')

      expect(WebMock).to have_requested(:post, query_url).times(3)
    end

    it 'returns nil and logs warning on timeout' do
      stub_request(:post, query_url).to_raise(Net::ReadTimeout)

      result = client.query_all_latest('inverter_power' => 'SENEC:inverter_power')

      expect(result['inverter_power']).to be_nil
    end

    it 'sends correct authorization header' do
      stub_request(:post, query_url).to_return(status: 200, body: '')

      client.query_all_latest('inverter_power' => 'SENEC:inverter_power')

      expect(
        a_request(:post, query_url).with(headers: { 'Authorization' => 'Token test-token' }),
      ).to have_been_made
    end

    it 'sends Flux query in request body' do
      stub_request(:post, query_url).to_return(status: 200, body: '')

      client.query_all_latest('inverter_power' => 'SENEC:inverter_power')

      expect(
        a_request(:post, query_url).with(body: /from\(bucket: "test-bucket"\)/),
      ).to have_been_made
    end
  end
end
