RSpec.describe ConfigurationMigrations::DropServiceOverrides do
  subject(:up) { described_class.new.up(data) }

  # The shape an import wrote before HELIOS owned the routers of its own
  # services: the labels of the running stack, rescued verbatim.
  def data_with(overrides, influxdb: {}, command: nil)
    {
      'influxdb' => { 'bucket' => 'solectrus' }.merge(influxdb),
      'reverse_proxy' => { 'mode' => 'internal', 'command' => command }.compact,
      'service_overrides' => overrides,
    }
  end

  def influxdb_router(entrypoint: 'influxdb')
    [
      'traefik.enable=true',
      'traefik.http.routers.influxdb-solectrus.rule=Host(`solar.example.com`)',
      "traefik.http.routers.influxdb-solectrus.entrypoints=#{entrypoint}",
    ]
  end

  context 'without the section' do
    let(:data) { { 'influxdb' => { 'bucket' => 'solectrus' } } }

    it 'changes nothing' do
      expect(up).to eq('influxdb' => { 'bucket' => 'solectrus' })
    end
  end

  context 'with labels that only name a middleware' do
    let(:data) do
      data_with({ 'dashboard' => { 'labels' => ['traefik.http.middlewares.rl.ratelimit.average=100'] } })
    end

    it 'drops the section' do
      expect(up).not_to have_key('service_overrides')
    end

    it 'leaves InfluxDB inside the stack' do
      expect(up['influxdb']).to eq('bucket' => 'solectrus')
    end
  end

  # Without this the database would lose its route, the entrypoint that router
  # named and the port that entrypoint published, all three without a word.
  context 'with a router on the InfluxDB service' do
    let(:data) { data_with({ 'influxdb' => { 'labels' => influxdb_router } }) }

    it 'drops the section' do
      expect(up).not_to have_key('service_overrides')
    end

    it 'keeps the database reachable' do
      expect(up['influxdb']).to include('publish_port' => true)
    end

    it 'stores no port for the canonical one' do
      expect(up['influxdb']).not_to have_key('host_port')
    end
  end

  context 'with an InfluxDB entrypoint on another port' do
    let(:data) do
      data_with({ 'influxdb' => { 'labels' => influxdb_router } },
                command: ['--entrypoints.influxdb.address=:18086'])
    end

    it 'stores that port' do
      expect(up['influxdb']).to include('publish_port' => true, 'host_port' => '18086')
    end
  end

  context 'with an InfluxDB entrypoint on the canonical port' do
    let(:data) do
      data_with({ 'influxdb' => { 'labels' => influxdb_router } },
                command: ['--entrypoints.influxdb.address=:8086'])
    end

    it 'stores no port' do
      expect(up['influxdb']).not_to have_key('host_port')
    end
  end

  context 'with an answer the configuration already carries' do
    let(:data) do
      data_with({ 'influxdb' => { 'labels' => influxdb_router } },
                influxdb: { 'publish_port' => false, 'host_port' => '9086' },
                command: ['--entrypoints.influxdb.address=:18086'])
    end

    it 'leaves it alone' do
      expect(up['influxdb']).to include('publish_port' => false, 'host_port' => '9086')
    end
  end

  context 'without an influxdb section' do
    let(:data) { { 'service_overrides' => { 'influxdb' => { 'labels' => influxdb_router } } } }

    it 'creates one' do
      expect(up['influxdb']).to eq('publish_port' => true)
    end
  end

  context 'with a section of another shape' do
    let(:data) { { 'influxdb' => 'nonsense', 'service_overrides' => 'nonsense' } }

    it 'drops the section and changes nothing else' do
      expect(up).to eq('influxdb' => 'nonsense')
    end
  end
end
