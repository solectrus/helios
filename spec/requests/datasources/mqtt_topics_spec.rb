RSpec.describe 'Datasources::MqttTopics', :with_admin_password do
  let(:basic_topic) do
    { 'topic' => 'sensors/power', 'measurement' => 'house', 'field' => 'power', 'type' => 'integer' }
  end

  before do
    with_config_yaml
    login
  end

  describe 'GET /datasources/mqtt-topics' do
    it 'renders the index page with no topics configured' do
      get datasources_mqtt_topics_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('datasources.mqtt_topics.index.empty'))
    end

    it 'lists existing topics' do
      Configuration.current.add_mqtt_topic(basic_topic)

      get datasources_mqtt_topics_path

      expect(response.body).to include('sensors/power').and include('house').and include('power')
    end

    # A mapping imported before HELIOS cast the flags still holds the env
    # string, and in Ruby "false" is true.
    it 'treats a stored "false" as off' do
      Configuration.current.add_mqtt_topic(basic_topic.merge('null_to_zero' => 'false'))

      get datasources_mqtt_topics_path

      expect(response.body).not_to include(I18n.t('datasources.mqtt_topics.filters.null_to_zero'))
    end

    it 'omits the polling controller wiring in collectors_only mode' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })
      Configuration.current.add_mqtt_topic(basic_topic)

      get datasources_mqtt_topics_path

      expect(response.body).not_to include('data-controller="sensors-polling"')
      expect(response.body).not_to include('mqtt-topic-value-0')
    end
  end

  describe 'GET /datasources/mqtt-topics/new' do
    it 'renders the survey form within the modal frame' do
      get new_datasources_mqtt_topic_path, headers: turbo_frame_headers('setting-modal-content')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'redirects non-frame requests to the index' do
      get new_datasources_mqtt_topic_path

      expect(response).to redirect_to(datasources_mqtt_topics_path)
    end
  end

  describe 'GET /datasources/mqtt-topics/:id/edit' do
    before { Configuration.current.add_mqtt_topic(basic_topic) }

    it 'renders the survey form pre-filled with the existing topic' do
      get edit_datasources_mqtt_topic_path(0), headers: turbo_frame_headers('setting-modal-content')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('sensors/power')
    end

    it 'redirects to the index when the topic does not exist' do
      get edit_datasources_mqtt_topic_path(99), headers: turbo_frame_headers('setting-modal-content')

      expect(response).to redirect_to(datasources_mqtt_topics_path)
    end
  end

  describe 'POST /datasources/mqtt-topics' do
    it 'persists the new topic' do
      post datasources_mqtt_topics_path, params: { data: basic_topic.to_json }

      expect(response).to redirect_to(datasources_mqtt_topics_path)
      expect(Configuration.current.mqtt_topics).to contain_exactly(basic_topic)
    end
  end

  describe 'PATCH /datasources/mqtt-topics/:id' do
    before { Configuration.current.add_mqtt_topic(basic_topic) }

    it 'updates the existing topic' do
      updated = basic_topic.merge('field' => 'energy')

      patch datasources_mqtt_topic_path(0), params: { data: updated.to_json }

      expect(response).to redirect_to(datasources_mqtt_topics_path)
      expect(Configuration.current.mqtt_topic(0)['field']).to eq('energy')
    end
  end

  describe 'DELETE /datasources/mqtt-topics/:id' do
    before { Configuration.current.add_mqtt_topic(basic_topic) }

    it 'removes the topic' do
      delete datasources_mqtt_topic_path(0)

      expect(response).to redirect_to(datasources_mqtt_topics_path)
      expect(Configuration.current.mqtt_topics).to be_empty
    end
  end
end
