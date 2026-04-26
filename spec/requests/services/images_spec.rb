RSpec.describe 'Services::Images', :with_admin_password do
  before do
    login
    allow(ComposeJob).to receive(:perform_later)
    allow(Orchestration::StackStatus).to receive(:mark_starting!)
  end

  def install_compose_with(service_name, image)
    File.write(Compose.path, YAML.dump('name' => 'solectrus',
                                       'services' => { service_name => { 'image' => image } }))
    allow(Orchestration::Container).to receive(:find)
      .with(service_name)
      .and_return(stub_container(service_name, image))
  end

  def stub_container(service_name, image)
    instance_double(
      Orchestration::Container,
      service_name: service_name, image: image,
      running?: true, status: 'running', health_status: 'healthy',
      version: nil, public_port: nil, stoppable?: true
    )
  end

  describe 'PATCH /services/:service_id/image' do
    it 'writes the recommended image to config.yaml and recreates the service' do
      with_config_yaml(
        'system' => { 'timezone' => 'Europe/Berlin' },
        'influxdb' => { 'image' => 'influxdb:2.5-alpine' },
      )
      install_compose_with('influxdb', 'influxdb:2.5-alpine')

      patch service_image_path(service_id: 'influxdb'), as: :turbo_stream

      expect(Configuration.current.influxdb.image).to eq(DockerImages.current(:INFLUXDB))
      expect(ComposeJob).to have_received(:perform_later).with(:recreate, 'influxdb')
      expect(response).to have_http_status(:ok)
    end

    it 'updates the watchtower repo and the section as a whole' do
      with_config_yaml(
        'system' => { 'timezone' => 'Europe/Berlin' },
        'watchtower' => { 'image' => 'containrrr/watchtower:1.7.1' },
      )
      install_compose_with('watchtower', 'containrrr/watchtower:1.7.1')

      patch service_image_path(service_id: 'watchtower'), as: :turbo_stream

      expect(Configuration.current.watchtower.image).to eq(DockerImages.current(:WATCHTOWER))
    end

    it 'writes the new image into the nested backup section' do
      with_config_yaml(
        'system' => { 'timezone' => 'Europe/Berlin' },
        'backup' => {
          'aws_bucket' => 'my-bucket',
          'influxdb' => { 'image' => 'ghcr.io/solectrus/influxdb2-s3-backup:0.1.0' },
        },
      )
      install_compose_with('influxdb-backup', 'ghcr.io/solectrus/influxdb2-s3-backup:0.1.0')

      patch service_image_path(service_id: 'influxdb-backup'), as: :turbo_stream

      backup = Configuration.current.backup
      expect(backup.influxdb.image).to eq(DockerImages.current(:INFLUXDB_BACKUP))
      expect(backup.aws_bucket).to eq('my-bucket')
    end

    it 'rejects an update for the helios service' do
      with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
      install_compose_with('helios', 'ghcr.io/solectrus/helios:develop')

      patch service_image_path(service_id: 'helios'), as: :turbo_stream

      expect(ComposeJob).not_to have_received(:perform_later)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 422 for an unknown service' do
      with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
      install_compose_with('foobar', 'foobar:1.0')

      patch service_image_path(service_id: 'foobar'), as: :turbo_stream

      expect(ComposeJob).not_to have_received(:perform_later)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
