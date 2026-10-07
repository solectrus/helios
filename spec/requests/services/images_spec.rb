RSpec.describe 'Services::Images', :with_admin_password do
  before do
    login
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
      with_startable_config_yaml('influxdb' => { 'image' => 'influxdb:2.5-alpine' })
      install_compose_with('influxdb', 'influxdb:2.5-alpine')

      expect do
        patch service_image_path(service_id: 'influxdb'), as: :turbo_stream
      end.to have_enqueued_job(ComposeJob).with(:recreate, 'influxdb')

      expect(Configuration.current.influxdb.image).to eq(DockerImages.current(:INFLUXDB))
      expect(response).to have_http_status(:ok)
    end

    it 'updates the watchtower repo and the section as a whole' do
      with_startable_config_yaml('watchtower' => { 'image' => 'containrrr/watchtower:1.7.1' })
      install_compose_with('watchtower', 'containrrr/watchtower:1.7.1')

      patch service_image_path(service_id: 'watchtower'), as: :turbo_stream

      expect(Configuration.current.watchtower.image).to eq(DockerImages.current(:WATCHTOWER))
    end

    it 'rejects an update for the helios service' do
      with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
      install_compose_with('helios', 'ghcr.io/solectrus/helios:develop')

      expect { patch service_image_path(service_id: 'helios'), as: :turbo_stream }.not_to have_enqueued_job(ComposeJob)

      expect(response).to have_http_status(:forbidden)
    end

    # A foreign broker keeps its compose entry verbatim, so writing the image
    # into the managed section would change nothing the export renders.
    it 'rejects an update for an unmanaged service' do
      with_startable_config_yaml(
        '_unmanaged' => { 'services' => { 'mosquitto' => { 'image' => 'eclipse-mosquitto:2' } } },
      )
      install_compose_with('mosquitto', 'eclipse-mosquitto:2')

      expect do
        patch service_image_path(service_id: 'mosquitto'), as: :turbo_stream
      end.not_to have_enqueued_job(ComposeJob)

      expect(Configuration.current.mosquitto.image).to be_nil
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 for an unknown service' do
      with_startable_config_yaml
      install_compose_with('foobar', 'foobar:1.0')

      expect { patch service_image_path(service_id: 'foobar'), as: :turbo_stream }.not_to have_enqueued_job(ComposeJob)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
