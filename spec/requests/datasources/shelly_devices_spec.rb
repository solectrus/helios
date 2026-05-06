RSpec.describe 'Datasources::ShellyDevices', :with_admin_password do
  let(:local_device) do
    { 'name' => 'Heat pump', 'host' => 'shelly-hp.local', 'measurement' => 'shelly_hp' }
  end
  let(:cloud_device) do
    { 'name' => 'Plug', 'device_id' => 'shellyplug-AABBCC', 'measurement' => 'plug' }
  end

  before do
    with_config_yaml(
      'deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
      'shelly' => { 'connection' => 'local' },
    )
    login
  end

  describe 'GET /datasources/shelly-devices' do
    it 'renders the index page with no devices configured' do
      get datasources_shelly_devices_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('datasources.shelly_devices.index.empty'))
    end

    it 'lists existing devices with the host identifier in local mode' do
      Configuration.current.add_shelly_device(local_device)

      get datasources_shelly_devices_path

      expect(response.body).to include('Heat pump').and include('shelly-hp.local').and include('shelly_hp')
    end

    it 'shows the cloud device id when shelly is configured in cloud mode' do
      Configuration.current.update('shelly', { 'connection' => 'cloud' })
      Configuration.current.add_shelly_device(cloud_device)

      get datasources_shelly_devices_path

      expect(response.body).to include('shellyplug-AABBCC')
      expect(response.body).to include(I18n.t('datasources.shelly_devices.table.device_id'))
    end
  end

  describe 'GET /datasources/shelly-devices/new' do
    it 'renders the survey form within the modal frame' do
      get new_datasources_shelly_device_path, headers: turbo_frame_headers('setting-modal-content')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'redirects non-frame requests to the index' do
      get new_datasources_shelly_device_path

      expect(response).to redirect_to(datasources_shelly_devices_path)
    end
  end

  describe 'GET /datasources/shelly-devices/:id/edit' do
    before { Configuration.current.add_shelly_device(local_device) }

    it 'renders the survey form pre-filled with the existing device' do
      get edit_datasources_shelly_device_path(0), headers: turbo_frame_headers('setting-modal-content')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('shelly-hp.local')
    end

    it 'redirects to the index when the device does not exist' do
      get edit_datasources_shelly_device_path(99), headers: turbo_frame_headers('setting-modal-content')

      expect(response).to redirect_to(datasources_shelly_devices_path)
    end
  end

  describe 'POST /datasources/shelly-devices' do
    it 'persists the new device' do
      post datasources_shelly_devices_path, params: { data: local_device.to_json }

      expect(response).to redirect_to(datasources_shelly_devices_path)
      expect(Configuration.current.shelly_devices).to contain_exactly(local_device)
    end
  end

  describe 'PATCH /datasources/shelly-devices/:id' do
    before { Configuration.current.add_shelly_device(local_device) }

    it 'updates the existing device' do
      updated = local_device.merge('measurement' => 'shelly_hp_v2')

      patch datasources_shelly_device_path(0), params: { data: updated.to_json }

      expect(response).to redirect_to(datasources_shelly_devices_path)
      expect(Configuration.current.shelly_device(0)['measurement']).to eq('shelly_hp_v2')
    end
  end

  describe 'DELETE /datasources/shelly-devices/:id' do
    before { Configuration.current.add_shelly_device(local_device) }

    it 'removes the device' do
      delete datasources_shelly_device_path(0)

      expect(response).to redirect_to(datasources_shelly_devices_path)
      expect(Configuration.current.shelly_devices).to be_empty
    end
  end
end
