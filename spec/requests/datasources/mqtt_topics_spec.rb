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

    # The removal would be refused anyway, so the list says so beforehand.
    it 'disables the delete button while a formula reads the name' do
      Configuration.current.add_mqtt_topic(basic_topic.merge('name' => 'washer'))
      Configuration.current.add_mqtt_topic('measurement' => 'm', 'field' => 'rest', 'type' => 'integer',
                                           'formula' => '{washer} * 2')

      get datasources_mqtt_topics_path

      expect(response.body).to include(I18n.t('datasources.mqtt_topics.index.delete_blocked', names: 'm:rest'))
      expect(response.body).to include('disabled')
    end

    it 'keeps the delete button enabled while nothing reads the name' do
      Configuration.current.add_mqtt_topic(basic_topic.merge('name' => 'washer'))

      get datasources_mqtt_topics_path

      expect(response.body).not_to include('delete_blocked')
      expect(response.body).not_to include('disabled')
    end

    # A mapping imported before HELIOS cast the flags still holds the env
    # string, and in Ruby "false" is true.
    it 'treats a stored "false" as off' do
      Configuration.current.add_mqtt_topic(basic_topic.merge('dedup' => 'false', 'null_to_zero' => 'false'))

      get datasources_mqtt_topics_path

      expect(response.body).not_to include(I18n.t('datasources.mqtt_topics.write_behavior.dedup_tip', seconds: 60))
      expect(response.body).not_to include(I18n.t('datasources.mqtt_topics.filters.null_to_zero'))
    end

    it 'shows the write behavior of a throttled topic' do
      Configuration.current.add_mqtt_topic(
        basic_topic.merge('aggregate_interval' => '60', 'dedup' => true, 'heartbeat_interval' => '900'),
      )

      get datasources_mqtt_topics_path

      expect(response.body)
        .to include(I18n.t('datasources.mqtt_topics.write_behavior.aggregate', seconds: '60'))
        .and include(I18n.t('datasources.mqtt_topics.write_behavior.dedup_tip', seconds: '900'))
    end

    # Without a heartbeat of its own, the collector falls back to 60 seconds.
    it 'names the default heartbeat when deduplication runs without one' do
      Configuration.current.add_mqtt_topic(basic_topic.merge('dedup' => true))

      get datasources_mqtt_topics_path

      expect(response.body).to include(I18n.t('datasources.mqtt_topics.write_behavior.dedup_tip', seconds: 60))
    end

    it 'omits the write behavior when no option is set' do
      Configuration.current.add_mqtt_topic(basic_topic)

      get datasources_mqtt_topics_path

      expect(response.body).not_to include(I18n.t('datasources.mqtt_topics.write_behavior.dedup_tip', seconds: 60))
      expect(response.body).not_to include(I18n.t('datasources.mqtt_topics.write_behavior.aggregate', seconds: '60'))
    end

    it 'shows a calculated entry by its formula, with no topic to show' do
      Configuration.current.add_mqtt_topic(
        'measurement' => 'Household', 'field' => 'base_load', 'type' => 'integer',
        'formula' => '{house_power} - 100', 'name' => 'base_load', 'max_age' => '300'
      )

      get datasources_mqtt_topics_path

      expect(response.body)
        .to include('{house_power} - 100')
        .and include(I18n.t('datasources.mqtt_topics.computed.label'))
        .and include(I18n.t('datasources.mqtt_topics.naming.max_age_tip', seconds: '300'))
    end

    it 'shows that a memory-only entry has no InfluxDB target' do
      Configuration.current.add_mqtt_topic('topic' => 'w/p', 'type' => 'integer', 'name' => 'wallbox',
                                           'skip_write' => true)

      get datasources_mqtt_topics_path

      expect(response.body).to include(I18n.t('datasources.mqtt_topics.target.skip_write'))
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

    # Removing it would leave a reference that no mapping defines, and
    # mqtt-collector refuses to start on that.
    it 'refuses while a formula reads the name' do
      Configuration.current.update_mqtt_topic(0, basic_topic.merge('name' => 'washer'))
      Configuration.current.add_mqtt_topic('measurement' => 'm', 'field' => 'rest', 'type' => 'integer',
                                           'formula' => '{washer} * 2')

      delete datasources_mqtt_topic_path(0)

      expect(Configuration.current.mqtt_topics.size).to eq(2)
      expect(flash[:alert]).to include('m:rest')
    end
  end
end
