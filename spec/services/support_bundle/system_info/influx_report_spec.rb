RSpec.describe SupportBundle::SystemInfo::InfluxReport do
  let(:query_url) { 'http://influxdb:8086/api/v2/query?org=org' }

  before do
    with_config_yaml(
      'influxdb' => {
        'token_read' => 'tok', 'org' => 'org', 'bucket' => 'bkt',
        'host' => 'influxdb', 'port' => '8086', 'schema' => 'http'
      },
    )
  end

  def stub_flux(matcher, body)
    stub_request(:post, query_url).with(body: matcher).to_return(status: 200, body:)
  end

  def measurements_csv(*names)
    rows = names.map { |n| ",_result,0,#{n}" }.join("\n")
    ",result,table,_value\n#{rows}\n"
  end

  describe '.overview' do
    it 'reports schema counts and masks bucket/org with 5-letter dummies' do
      stub_flux(/schema\.measurements/, measurements_csv('SENEC', 'Forecast'))
      stub_flux(/schema\.fieldKeys/, measurements_csv('power', 'soc', 'temp'))
      stub_flux(/schema\.tagKeys/, measurements_csv('host', 'region'))

      result = described_class.overview

      expect(result).to include(
        'Target' => 'http://influxdb:8086',
        'Org' => match(/\A[A-Z]{5}\z/),
        'Bucket' => match(/\A[A-Z]{5}\z/),
        'Measurements' => '2',
        'Field keys (total)' => '3',
        'Tag keys (total)' => '2',
      )
    end

    it 'masks longer bucket/org values to the same 5-letter dummy' do
      with_config_yaml(
        'influxdb' => {
          'token_read' => 'tok', 'org' => 'my-org-name', 'bucket' => 'berlin-solar',
          'host' => 'influxdb', 'port' => '8086', 'schema' => 'http'
        },
      )
      stub_request(:post, 'http://influxdb:8086/api/v2/query?org=my-org-name')
        .to_return(status: 200, body: measurements_csv('SENEC'))

      result = described_class.overview

      expect(result['Org']).to match(/\A[A-Z]{5}\z/)
      expect(result['Bucket']).to match(/\A[A-Z]{5}\z/)
    end

    it 'masks a public FQDN in the InfluxDB endpoint URL' do
      with_config_yaml(
        'influxdb' => {
          'token_read' => 'tok', 'org' => 'org', 'bucket' => 'bkt',
          'host' => 'influx.example.com', 'port' => '8086', 'schema' => 'https'
        },
      )
      stub_request(:post, 'https://influx.example.com:8086/api/v2/query?org=org')
        .to_return(status: 200, body: measurements_csv('SENEC'))

      result = described_class.overview

      expect(result['Target']).to match(%r{\Ahttps://[A-Z]{5}:8086\z})
    end

    it 'keeps private IPs in the InfluxDB endpoint URL' do
      with_config_yaml(
        'influxdb' => {
          'token_read' => 'tok', 'org' => 'org', 'bucket' => 'bkt',
          'host' => '192.168.1.10', 'port' => '8086', 'schema' => 'http'
        },
      )
      stub_request(:post, 'http://192.168.1.10:8086/api/v2/query?org=org')
        .to_return(status: 200, body: measurements_csv('SENEC'))

      expect(described_class.overview['Target']).to eq('http://192.168.1.10:8086')
    end

    it 'reports the bucket data size when the directory exists' do
      stub_request(:post, query_url).to_return(status: 200, body: measurements_csv)
      dir = File.join(config_yaml_dir, 'influxdb')
      FileUtils.mkdir_p(dir)
      allow(SupportBundle::SystemInfo::OutputFormatter).to receive(:capture)
        .with('du', '-sk', dir).and_return("2048\t#{dir}")

      expect(described_class.overview['Bucket data size']).to eq('2 MB')
    end

    it 'reports "not on this host" when the bucket directory is absent (collectors_only)' do
      stub_request(:post, query_url).to_return(status: 200, body: measurements_csv)

      expect(described_class.overview['Bucket data size']).to eq('not on this host')
    end

    it 'surfaces "unreachable" when InfluxDB is down' do
      stub_request(:post, query_url).to_raise(Errno::ECONNREFUSED)

      result = described_class.overview

      expect(result).to include('Target' => 'http://influxdb:8086', 'Status' => 'unreachable')
      expect(result).not_to have_key('Measurements')
    end

    it 'returns a friendly notice when no bucket is configured' do
      with_config_yaml('influxdb' => {})

      expect(described_class.overview).to eq('InfluxDB not configured.')
    end

    it 'degrades gracefully on unexpected errors' do
      stub_request(:post, query_url).to_return(status: 500, body: 'boom')

      expect(described_class.overview).to start_with('unavailable: InfluxDb::ConnectionError:')
    end
  end
end
