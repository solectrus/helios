RSpec.describe StoragePaths do
  describe '.call' do
    it 'returns default paths under host_data_path when volume_path is unset' do
      dir = with_config_yaml

      paths = described_class.call

      expect(paths).to eq(
        'postgresql' => "#{dir}/postgresql",
        'influxdb' => "#{dir}/influxdb",
        'redis' => "#{dir}/redis",
        'ingest' => "#{dir}/ingest",
        'reverse_proxy' => "#{dir}/traefik",
      )
    end

    it 'uses absolute volume_path verbatim' do
      with_config_yaml(
        'postgresql' => { 'volume_path' => '/mnt/disk1/postgres' },
        'influxdb' => { 'volume_path' => '/mnt/disk2/influx' },
      )

      paths = described_class.call

      expect(paths['postgresql']).to eq('/mnt/disk1/postgres')
      expect(paths['influxdb']).to eq('/mnt/disk2/influx')
    end

    it 'renders Docker named volumes as a localized label' do
      with_config_yaml('redis' => { 'volume_path' => 'redis-data' })

      expect(described_class.call['redis']).to eq(
        I18n.t('storage_paths.docker_volume', name: 'redis-data'),
      )
    end

    it 'expands relative volume_path against host_data_path' do
      dir = with_config_yaml('postgresql' => { 'volume_path' => './pgdata' })

      expect(described_class.call['postgresql']).to eq("#{dir}/pgdata")
    end

    it 'maps reverse_proxy to the traefik default directory' do
      dir = with_config_yaml

      expect(described_class.call['reverse_proxy']).to eq("#{dir}/traefik")
    end
  end
end
