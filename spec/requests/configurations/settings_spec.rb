RSpec.describe 'Configurations::Settings', :with_admin_password do
  include ActiveSupport::Testing::TimeHelpers

  before do
    with_config_yaml
    login
  end

  describe 'GET /configuration/settings/new' do
    it 'renders the survey form for a sensor' do
      get new_configuration_setting_path(setting: 'sensor', name: 'inverter_power'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'renders the survey form for a singleton' do
      get new_configuration_setting_path(setting: 'system_general'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'renders the survey form for the backup schedule' do
      get new_configuration_setting_path(setting: 'backup_schedule'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'redirects for invalid setting' do
      get new_configuration_setting_path(setting: 'nonexistent')

      expect(response).to redirect_to(sensors_path)
    end

    it 'redirects non-frame requests to the sensor page for sensor settings' do
      get new_configuration_setting_path(setting: 'sensor', name: 'inverter_power')

      expect(response).to redirect_to(sensors_path)
    end

    it 'redirects non-frame requests to the settings page for singleton settings' do
      get new_configuration_setting_path(setting: 'system_general')

      expect(response).to redirect_to(settings_path)
    end
  end

  describe 'POST /configuration/settings' do
    it 'creates a sensor' do
      sensor_data = { 'source' => 'senec' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      expect(response).to redirect_to(sensors_path)

      config = Configuration.current
      expect(config.sensor_config('inverter_power').source).to eq('senec')
    end

    it 'normalizes measurement and field for fixed-source sensors on save' do
      sensor_data = { 'source' => 'senec', 'measurement' => 'WRONG', 'field' => 'wrong' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      config = Configuration.current
      expect(config.sensor_config('inverter_power').measurement).to eq('SENEC')
      expect(config.sensor_config('inverter_power').field).to eq('inverter_power')
    end

    it 'keeps a measurement holding a space, which line protocol escapes' do
      sensor_data = { 'source' => 'external', 'measurement' => 'PQ Inverter', 'field' => 'power' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      expect(Configuration.current.sensor_config('inverter_power').measurement).to eq('PQ Inverter')
    end

    # The survey refuses these client-side; this covers a request going around
    # the UI. A comma would split INFLUX_MEASUREMENT, a colon the sensor
    # mapping, and InfluxDB reserves the leading underscore for itself.
    ['PQ,Inverter', 'PQ:Inverter', '_inverter'].each do |measurement|
      it "refuses to store the measurement #{measurement.inspect}" do
        sensor_data = { 'source' => 'external', 'measurement' => measurement, 'field' => 'power' }

        post configuration_settings_path,
             params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

        expect(response).to redirect_to(sensors_path)
        expect(flash[:alert]).to include(measurement)
        expect(Configuration.current.sensor_config('inverter_power').measurement).to be_nil
      end
    end

    it 'refuses a field starting with the reserved underscore' do
      sensor_data = { 'source' => 'external', 'measurement' => 'inverter', 'field' => '_power' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      expect(flash[:alert]).to include('_power')
      expect(Configuration.current.sensor_config('inverter_power').field).to be_nil
    end

    # A fixed source overwrites measurement and field on save, so the payload's
    # names never reach storage and must not block the save either.
    it 'accepts an unusable measurement when the source overwrites it anyway' do
      sensor_data = { 'source' => 'senec', 'measurement' => 'a,b', 'field' => 'c' }

      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: sensor_data.to_json }

      expect(Configuration.current.sensor_config('inverter_power').measurement).to eq('SENEC')
    end

    it 'auto-activates other SENEC-capable sensors that are not yet configured' do
      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: { 'source' => 'senec' }.to_json }

      config = Configuration.current
      expect(config.sensor_config('grid_import_power').source).to eq('senec')
      expect(config.sensor_config('battery_soc').source).to eq('senec')
    end

    it 'creates a singleton and redirects to the settings page' do
      post configuration_settings_path,
           params: { setting: 'system_general', data: { timezone: 'Europe/Berlin', currency: 'CHF' }.to_json }

      expect(response).to redirect_to(settings_path)

      config = Configuration.current
      expect(config.system.timezone).to eq('Europe/Berlin')
      expect(config.system.currency).to eq('CHF')
    end

    it 'persists the automatic-backup schedule in its own section' do
      post configuration_settings_path,
           params: { setting: 'backup_schedule',
                     data: { schedule_enabled: true, schedule_time: '04:15' }.to_json }

      config = Configuration.current
      expect(config.backup_schedule.schedule_enabled).to be(true)
      expect(config.backup_schedule.schedule_time).to eq('04:15')
    end

    it 'anchors a still-ahead time to run today' do
      # 09:00 in the app timezone; reschedule! reads Time.current in that zone
      travel_to Time.zone.local(2026, 5, 29, 9, 0, 0) do
        BackupScheduler.send(:mark_handled!, Date.new(2026, 5, 29))

        post configuration_settings_path,
             params: { setting: 'backup_schedule', data: { schedule_enabled: true, schedule_time: '10:00' }.to_json }

        expect(BackupScheduler.last_handled_date).to be_nil
      end
    end

    it 'anchors an already-passed time to tomorrow' do
      # 09:00 in the app timezone; reschedule! reads Time.current in that zone
      travel_to Time.zone.local(2026, 5, 29, 9, 0, 0) do
        post configuration_settings_path,
             params: { setting: 'backup_schedule', data: { schedule_enabled: true, schedule_time: '03:00' }.to_json }

        expect(BackupScheduler.last_handled_date).to eq(Date.new(2026, 5, 29))
      end
    end

    it 'edits the schedule without touching the backup destination section' do
      Configuration.current.update('backup', { 'destination' => 'external', 'external_path' => '/mnt/nas' })

      post configuration_settings_path,
           params: { setting: 'backup_schedule', data: { schedule_enabled: true, schedule_time: '02:00' }.to_json }

      config = Configuration.current
      expect(config.backup.destination).to eq('external')
      expect(config.backup.external_path).to eq('/mnt/nas')
      expect(config.backup_schedule.schedule_time).to eq('02:00')
    end

    it 'merges a mini-survey into its parent singleton without dropping siblings' do
      Configuration.current.update('system', { 'admin_password' => 'secret', 'timezone' => 'UTC' })

      post configuration_settings_path,
           params: { setting: 'system_security', data: { admin_password: 'new-secret' }.to_json }

      config = Configuration.current
      expect(config.system.admin_password).to eq('new-secret')
      expect(config.system.timezone).to eq('UTC')
    end
  end

  # bootstrap/install.sh writes no APP_HOST, so a fresh installation has none
  # until someone opens the host form. The first save of any setting takes the
  # host the browser is using instead.
  describe 'POST /configuration/settings and the missing app_host' do
    it 'adopts the request host' do
      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: { 'source' => 'senec' }.to_json },
           headers: { 'HOST' => 'solectrus.fritz.box' }

      expect(Configuration.current.system.app_host).to eq('solectrus.fritz.box')
    end

    it 'keeps the field empty for a loopback host' do
      post configuration_settings_path,
           params: { setting: 'sensor', name: 'inverter_power', data: { 'source' => 'senec' }.to_json },
           headers: { 'HOST' => 'localhost' }

      expect(Configuration.current.system.app_host).to be_blank
    end
  end

  describe 'POST /configuration/settings and a loopback address' do
    # Such an address names the machine to whoever asks, so every address
    # derived from it would send a device or a browser back to itself.
    it 'refuses it' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { 'app_host' => 'localhost' }.to_json }

      expect(flash[:alert]).to include('localhost')
      expect(Configuration.current.system.app_host).to be_blank
    end

    it 'refuses a name below .localhost as well' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { 'app_host' => 'helios.localhost' }.to_json }

      expect(Configuration.current.system.app_host).to be_blank
    end

    it 'takes an address that names the machine to others' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { 'app_host' => 'solectrus.fritz.box' }.to_json }

      expect(Configuration.current.system.app_host).to eq('solectrus.fritz.box')
    end

    # An empty field is an answer of its own, so it stands. The form owns the
    # address, and the host the browser was reached at is not offered behind
    # it: every caller falls back to the published port instead.
    it 'takes an empty address and leaves the field empty' do
      Configuration.current.update('reverse_proxy', { 'app_host' => 'solectrus.fritz.box' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { 'mode' => 'none' }.to_json },
           headers: { 'HOST' => 'solectrus.fritz.box' }

      expect(Configuration.current.system.app_host).to be_blank
    end
  end

  describe 'POST /configuration/settings for the Ingest correction' do
    before do
      Configuration.current.update_sensor('inverter_power_2', {
                                            'source' => 'shelly', 'is_balcony' => true,
                                            'shelly_host' => 'shelly.local',
                                            'measurement' => 'balcony', 'field' => 'power'
                                          })
    end

    it 'stores a switched-off correction' do
      post configuration_settings_path,
           params: { setting: 'ingest_settings', data: { active: false }.to_json }

      expect(Configuration.current.ingest.active).to be false
      expect(Configuration.current.ingest_required?).to be false
    end

    it 'keeps the buffer duration while the correction runs' do
      post configuration_settings_path,
           params: { setting: 'ingest_settings', data: { active: true, retention_hours: '24' }.to_json }

      expect(Configuration.current.ingest.retention_hours).to eq('24')
      expect(Configuration.current.ingest_required?).to be true
    end
  end

  describe 'POST /configuration/settings for the reverse_proxy mode' do
    # The shared network has to be there before the stack can join it, so the
    # save asks Docker for it. The proxy of these examples runs on `edge`.
    before { allow(Orchestration::DockerCli).to receive(:network_names).and_return(%w[bridge edge]) }

    it 'stores the address for the internal Traefik mode' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'internal', app_host: 'demo.example.com' }.to_json }

      config = Configuration.current
      expect(config.system.app_host).to eq('demo.example.com')
      expect(config.reverse_proxy.bind_ip).to be_blank
    end

    it 'stores bind_ip for the external Traefik mode' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', bind_ip: '10.0.0.5', app_host: 'solar.example.com' }.to_json }

      config = Configuration.current
      expect(config.reverse_proxy.bind_ip).to eq('10.0.0.5')
      expect(config.system.app_host).to eq('solar.example.com')
    end

    it 'clears the section for mode none' do
      Configuration.current.update('reverse_proxy',
                                   { 'mode' => 'internal', 'app_host' => 'old.example.com' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'none', app_host: '192.168.1.5' }.to_json }

      expect(Configuration.current.reverse_proxy).to be_empty
      expect(Configuration.current.system.app_host).to eq('192.168.1.5')
    end

    # survey-core sends no key for a field the user emptied, so the form has to
    # speak for the address either way.
    it 'clears the address when the form sends none' do
      Configuration.current.update('reverse_proxy',
                                   { 'mode' => 'internal', 'app_host' => 'old.example.com' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'none' }.to_json }

      expect(Configuration.current.system.app_host).to be_blank
    end

    it 'keeps the external Traefik mode even without a bind_ip' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'external' }.to_json }

      config = Configuration.current
      expect(config.reverse_proxy.mode).to eq('external')
      expect(config.reverse_proxy_external?).to be true
    end

    it 'stores the shared network the external proxy is on' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', app_host: 'solar.example.com', proxy_network: 'edge',
                             proxy_entrypoint: 'websecure', proxy_certresolver: 'le' }.to_json }

      expect(Configuration.current.reverse_proxy)
        .to include('proxy_network' => 'edge', 'proxy_entrypoint' => 'websecure', 'proxy_certresolver' => 'le')
    end

    # Compose declares that network as one another stack owns, so it refuses to
    # start the stack while the network is missing. The services the proxy
    # routes publish no host port to fall back on, HELIOS among them, so the
    # name is refused here rather than at the start that would go down with it.
    it 'refuses a network that does not exist' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', app_host: 'solar.example.com',
                             proxy_network: 'typo' }.to_json }

      expect(Configuration.current.reverse_proxy.proxy_network).to be_blank
      expect(flash[:alert]).to include('typo')
    end

    it 'stores the network while Docker does not answer' do
      allow(Orchestration::DockerCli).to receive(:network_names).and_return(nil)

      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', app_host: 'solar.example.com',
                             proxy_network: 'edge' }.to_json }

      expect(Configuration.current.reverse_proxy.proxy_network).to eq('edge')
    end

    # The two ways the proxy reaches the stack exclude each other. A bind IP
    # left over would bind ports the shared-network stack no longer publishes.
    it 'drops a bind_ip when the proxy is on a shared network' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', app_host: 'solar.example.com',
                             proxy_network: 'edge', bind_ip: '10.0.0.5' }.to_json }

      expect(Configuration.current.reverse_proxy.bind_ip).to be_blank
    end

    it 'drops the router names when the proxy routes host ports' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', app_host: 'solar.example.com', bind_ip: '10.0.0.5',
                             proxy_entrypoint: 'websecure' }.to_json }

      expect(Configuration.current.reverse_proxy.proxy_entrypoint).to be_blank
    end

    # A stack adopted on a parent stack's network keeps it: the form asks about
    # the network in the external mode alone, so a save in another mode never
    # speaks for it.
    it 'keeps an adopted network across a save in another mode' do
      Configuration.current.update('reverse_proxy', { 'proxy_network' => 'containerhafen' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'none', app_host: '192.168.1.5' }.to_json }

      expect(Configuration.current.reverse_proxy.proxy_network).to eq('containerhafen')
    end

    it 'derives the transport from the stored network on reload' do
      Configuration.current.update('reverse_proxy', { 'mode' => 'external', 'proxy_network' => 'edge' })

      get edit_configuration_setting_path(setting: 'reverse_proxy', name: 'reverse_proxy'),
          headers: turbo_frame_headers

      expect(response.body).to include('&quot;proxy_transport&quot;:&quot;network&quot;')
    end

    it 'preselects the external mode on reload after saving it without a bind_ip' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'external' }.to_json }

      get edit_configuration_setting_path(setting: 'reverse_proxy', name: 'reverse_proxy'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('&quot;mode&quot;:&quot;external&quot;')
    end

    # The port the dashboard is published on is asked for on the address form
    # and stored in the `dashboard` section it has always lived in.
    it 'stores the dashboard host port for mode none' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'none', app_host: '192.168.1.5', host_port: '3010' }.to_json }

      config = Configuration.current
      expect(config.dashboard.host_port).to eq('3010')
      expect(config.reverse_proxy.host_port).to be_blank
    end

    # A port already taken on the host stays taken while a proxy routes the
    # dashboard, so the modes that publish no port leave the answer alone
    # instead of clearing it the way they clear the fields a proxy owns.
    it 'keeps the host port through a mode that publishes none' do
      Configuration.current.update('dashboard', { 'host_port' => '3010' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'internal', app_host: 'demo.example.com' }.to_json }

      expect(Configuration.current.dashboard.host_port).to eq('3010')
    end

    it 'keeps the host port for an external proxy on a shared network' do
      Configuration.current.update('dashboard', { 'host_port' => '3010' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', app_host: 'solar.example.com',
                             proxy_network: 'edge' }.to_json }

      expect(Configuration.current.dashboard.host_port).to eq('3010')
    end

    # The modes that do publish the port own the answer, an emptied one
    # included: the export then falls back to 3000.
    it 'clears the host port when the answer is emptied' do
      Configuration.current.update('dashboard', { 'host_port' => '3010' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'none', app_host: '192.168.1.5', host_port: '' }.to_json }

      expect(Configuration.current.dashboard.host_port).to be_blank
    end

    # FORCE_SSL is a dashboard variable, so the survey borrows the field into
    # the `dashboard` section (issue #416).
    it 'stores force_ssl for the external mode' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', bind_ip: '10.0.0.5', force_ssl: true }.to_json }

      config = Configuration.current
      expect(config.dashboard.force_ssl).to be true
      expect(config.reverse_proxy.force_ssl).to be_blank
    end

    # Without a proxy nothing terminates TLS in front of the stack, and the
    # flag would make the dashboard redirect to an HTTPS port nothing serves.
    it 'drops force_ssl for mode none' do
      Configuration.current.update('dashboard', { 'force_ssl' => true })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'none', force_ssl: true }.to_json }

      config = Configuration.current
      expect(config.dashboard.force_ssl).to be_blank
      expect(config.reverse_proxy).to be_empty
    end

    # The ranges belong to a proxy in front of the stack, and the form shows
    # them in the two modes that name one. Left behind, they would keep
    # reaching the dashboard as TRUSTED_PROXY_RANGES, and a request from such a
    # range would still be believed about who sent it.
    it 'drops the trusted proxy ranges for mode none' do
      Configuration.current.update('dashboard', { 'trusted_proxy_ranges' => '10.0.0.0/8' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'none', app_host: '192.168.1.5' }.to_json }

      expect(Configuration.current.dashboard.trusted_proxy_ranges).to be_blank
    end

    it 'keeps the trusted proxy ranges for a mode that names a proxy' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', app_host: 'solar.example.com',
                             trusted_proxy_ranges: '10.0.0.0/8' }.to_json }

      expect(Configuration.current.dashboard.trusted_proxy_ranges).to eq('10.0.0.0/8')
    end

    # The managed Traefik routes by host rule, and a rule with nothing in it
    # matches nothing: the stack would publish its ports and run no proxy,
    # while the form kept saying it runs one. The form asks for the address in
    # that mode, so only a request bypassing it arrives this way.
    it 'stores no managed proxy without an address' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy', data: { mode: 'internal' }.to_json }

      config = Configuration.current
      expect(config.reverse_proxy).to be_empty
      expect(config.app_host_must_be_a_domain?).to be false
    end

    it 'stores no proxy for a mode it does not know' do
      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'nonsense', app_host: '192.168.1.5' }.to_json }

      config = Configuration.current
      expect(config.reverse_proxy).to be_empty
      expect(config.system.app_host).to eq('192.168.1.5')
    end

    # Every setting the section carries beyond the form is kept by nobody: the
    # section is written as the form answers it.
    it 'drops the certificate address when the mode no longer runs a Traefik' do
      Configuration.current.update('reverse_proxy',
                                   { 'mode' => 'internal', 'letsencrypt_email' => 'me@example.com' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', app_host: 'solar.example.com' }.to_json }

      expect(Configuration.current.reverse_proxy.letsencrypt_email).to be_blank
    end

    # The section also carries the Traefik HELIOS adopted on import: its compose
    # keys, its image and the path its certificates live at. No question asks
    # for any of them, and a service regenerated from HELIOS defaults names
    # another resolver, mounts another path and requests every certificate anew.
    it 'keeps the adopted Traefik no question asks about' do
      Configuration.current.update('reverse_proxy',
                                   { 'mode' => 'internal', 'image' => 'traefik:v3.7',
                                     'command' => ['--certificatesresolvers.myresolver.acme.tlschallenge=true'],
                                     'ports' => %w[80:80 443:443 8086:8086],
                                     'labels' => ['com.centurylinklabs.watchtower.scope=solectrus'],
                                     'environment' => ['TZ'], 'volume_path' => '/opt/certs' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'internal', app_host: 'solar.example.com' }.to_json }

      expect(Configuration.current.reverse_proxy.to_h).to include(
        'image' => 'traefik:v3.7',
        'command' => ['--certificatesresolvers.myresolver.acme.tlschallenge=true'],
        'ports' => %w[80:80 443:443 8086:8086],
        'labels' => ['com.centurylinklabs.watchtower.scope=solectrus'],
        'environment' => ['TZ'],
        'volume_path' => '/opt/certs',
      )
    end

    it 'drops the adopted Traefik when the mode no longer runs one' do
      Configuration.current.update('reverse_proxy',
                                   { 'mode' => 'internal', 'image' => 'traefik:v3.7',
                                     'volume_path' => '/opt/certs' })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'external', app_host: 'solar.example.com' }.to_json }

      section = Configuration.current.reverse_proxy
      expect(section.image).to be_blank
      expect(section.volume_path).to be_blank
    end

    it 'drops force_ssl for the internal mode, which implies HTTPS' do
      Configuration.current.update('dashboard', { 'force_ssl' => true })

      post configuration_settings_path,
           params: { setting: 'reverse_proxy',
                     data: { mode: 'internal', app_host: 'demo.example.com', force_ssl: true }.to_json }

      expect(Configuration.current.dashboard.force_ssl).to be_blank
    end

    it 'carries the stored bind_ip into the form when editing' do
      Configuration.current.update('reverse_proxy', { 'mode' => 'external', 'bind_ip' => '10.0.0.5' })

      get edit_configuration_setting_path(setting: 'reverse_proxy', name: 'reverse_proxy'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('&quot;10.0.0.5&quot;')
    end

    # A section left over from an earlier configuration that names no mode has
    # no reverse proxy: the radio preselects "none".
    it 'preselects mode none for a section without a stored mode' do
      Configuration.current.update('reverse_proxy', { 'letsencrypt_email' => 'me@example.com' })

      get edit_configuration_setting_path(setting: 'reverse_proxy', name: 'reverse_proxy'),
          headers: turbo_frame_headers

      expect(response.body).to include('&quot;mode&quot;:&quot;none&quot;')
    end
  end

  describe 'the survey payload' do
    # The dashboard stores "user-selectable" as an empty string, which SurveyJS
    # cannot preselect — the form gets a `user` sentinel instead.
    it 'injects the theme sentinel when no theme is fixed' do
      get edit_configuration_setting_path(setting: 'dashboard_theme', name: 'dashboard_theme'),
          headers: turbo_frame_headers

      expect(response.body).to include('&quot;ui_theme&quot;:&quot;user&quot;')
    end

    # The MQTT pages are driven by UI-only fields derived from the stored
    # mapping, so editing an MQTT sensor reopens on the right page.
    it 'derives the MQTT ui state when editing an MQTT sensor' do
      Configuration.current.update_sensor('house_power', {
                                            'source' => 'mqtt', 'measurement' => 'MQTT',
                                            'field' => 'power', 'json_key' => 'total'
                                          })

      get edit_configuration_setting_path(setting: 'sensor', name: 'house_power'),
          headers: turbo_frame_headers

      expect(response.body).to include('mqtt_extraction_mode')
    end

    # Shared by every survey-backed controller (SurveyData): a body that is
    # not JSON is a client bug, not a validation error.
    it 'answers a malformed JSON body with 400' do
      post configuration_settings_path, params: { setting: 'reverse_proxy', data: 'not json' }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'POST /configuration/settings for the dynamic electricity prices' do
    # The survey drives two services: the Tibber collector (its own section) and,
    # where a local battery and a forecast collector exist, the SENEC charger
    # (borrowed fields).
    def with_charging_preconditions
      with_config_yaml(
        'senec' => { 'adapter' => 'local' },
        'forecast' => { 'forecast' => 'forecast.solar' },
        'sensors' => { 'inverter_power_forecast' => { 'source' => 'forecast', 'measurement' => 'Forecast' } },
      )
    end

    def survey_params(**overrides)
      { enabled: true, charging: true, token: 'abc', measurement: 'Prices', interval: '900',
        price_max: '80', price_time_range: '4', forecast_threshold: '15', dry_run: false }.merge(overrides)
    end

    def post_survey(**overrides)
      post configuration_settings_path, params: { setting: 'tibber', data: survey_params(**overrides).to_json }
    end

    it 'splits the survey into the tibber credentials and the charger tuning' do
      with_charging_preconditions

      post_survey

      config = Configuration.current
      expect(config.tibber.to_h).to eq('token' => 'abc', 'measurement' => 'Prices')
      # dry_run is left out: a blank value clears its key, and the export falls
      # back to the same `false` default.
      expect(config.senec_charger.to_h).to eq(
        'interval' => '900', 'price_max' => '80', 'price_time_range' => '4',
        'forecast_threshold' => '15'
      )
      expect(config.senec_charger_available?).to be(true)
      expect(response).to redirect_to(settings_path)
    end

    it 'stores the test mode when it is switched on' do
      with_charging_preconditions

      post_survey(dry_run: true)

      expect(Configuration.current.senec_charger.dry_run).to be(true)
    end

    it 'collects the prices alone when charging stays off' do
      with_charging_preconditions

      post_survey(charging: false)

      config = Configuration.current
      expect(config.tibber_enabled?).to be(true)
      expect(config.senec_charger_enabled?).to be(false)
    end

    it 'drops the charger tuning when charging is switched back off' do
      with_charging_preconditions
      post_survey

      post_survey(charging: false)

      expect(Configuration.current.senec_charger_enabled?).to be(false)
    end

    it 'supports a stack with no SENEC battery at all, collecting prices for later use' do
      with_config_yaml

      post_survey(charging: false)

      config = Configuration.current
      expect(config.tibber_enabled?).to be(true)
      expect(config.senec_charger_enabled?).to be(false)
    end

    # The charging pages are dropped server-side once a dependency goes, so the
    # payload arrives without a `charging` flag. That is the question never
    # having been asked — reading it as "switched off" would wipe a tuning the
    # user can neither see nor re-enter until the dependency returns.
    it 'keeps the charger tuning when a dependency disappears and the prices are edited' do
      # A configured charger whose forecast collector has since gone: the survey
      # renders the prices half only, so this save carries neither `charging`
      # nor the tuning.
      with_config_yaml(
        'senec' => { 'adapter' => 'local' },
        'tibber' => { 'token' => 'abc', 'measurement' => 'Prices' },
        'senec_charger' => { 'interval' => '900', 'price_max' => '80' },
      )

      post configuration_settings_path,
           params: { setting: 'tibber', data: { enabled: true, token: 'xyz', measurement: 'Prices' }.to_json }

      config = Configuration.current
      expect(config.tibber.token).to eq('xyz')
      expect(config.senec_charger.to_h).to eq('interval' => '900', 'price_max' => '80')
    end

    it 'drops both services when the prices are switched off' do
      with_charging_preconditions
      post_survey

      post configuration_settings_path, params: { setting: 'tibber', data: { enabled: false }.to_json }

      config = Configuration.current
      expect(config.tibber_enabled?).to be(false)
      expect(config.senec_charger_enabled?).to be(false)
    end

    it 'derives both flags from the two sections when editing' do
      with_charging_preconditions
      post_survey

      get edit_configuration_setting_path(setting: 'tibber', name: 'tibber'), headers: turbo_frame_headers

      expect(response.body).to include('&quot;enabled&quot;:true')
      expect(response.body).to include('&quot;charging&quot;:true')
      expect(response.body).to include('&quot;token&quot;:&quot;abc&quot;')
    end

    it 'reports a tibber-only stack as not charging' do
      with_charging_preconditions
      Configuration.current.update('tibber', { 'token' => 'abc' })

      get edit_configuration_setting_path(setting: 'tibber', name: 'tibber'), headers: turbo_frame_headers

      expect(response.body).to include('&quot;enabled&quot;:true')
      expect(response.body).to include('&quot;charging&quot;:false')
    end
  end

  describe 'GET /configuration/:setting/:name/edit' do
    it 'renders the survey form for an existing sensor' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      get edit_configuration_setting_path(setting: 'sensor', name: 'inverter_power'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
    end

    it 'normalizes measurement and field for fixed-source sensors' do
      config = Configuration.current
      config.update_sensor('inverter_power', {
                             'source' => 'senec',
                             'measurement' => 'WRONG',
                             'field' => 'wrong_field',
                           })

      get edit_configuration_setting_path(setting: 'sensor', name: 'inverter_power'),
          headers: turbo_frame_headers

      expect(response.body).to include('&quot;SENEC&quot;')
      expect(response.body).to include('&quot;inverter_power&quot;')
      expect(response.body).not_to include('&quot;WRONG&quot;')
    end

    it 'uses collector measurement when configured' do
      config = Configuration.current
      config.update('senec', { 'measurement' => 'MySENEC', 'adapter' => 'local', 'host' => '1.2.3.4' })
      config.update_sensor('inverter_power', {
                             'source' => 'senec',
                             'measurement' => 'SENEC',
                             'field' => 'inverter_power',
                           })

      get edit_configuration_setting_path(setting: 'sensor', name: 'inverter_power'),
          headers: turbo_frame_headers

      expect(response.body).to include('&quot;MySENEC&quot;')
    end

    it 'renders the survey form for an existing singleton' do
      config = Configuration.current
      config.update('system', { 'timezone' => 'UTC' })

      get edit_configuration_setting_path(setting: 'system_general', name: 'system_general'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /configuration/:setting/:name' do
    it 'updates a sensor' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      sensor_data = { 'source' => 'mqtt', 'mqtt_topic' => 'pv/power' }

      patch configuration_setting_path(setting: 'sensor', name: 'inverter_power'),
            params: { data: sensor_data.to_json }

      expect(response).to redirect_to(sensors_path)

      config = Configuration.current
      expect(config.sensor_config('inverter_power').source).to eq('mqtt')
    end

    # Switching the source hides the whole MQTT page, so SurveyJS clears the
    # name and the survey's own mandatory-field rule cannot bite.
    it 'refuses a source change that would drop an MQTT name a formula reads' do
      config = Configuration.current
      config.update_sensor('house_power',
                           { 'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f',
                             'mqtt_topic' => 'h/p', 'mqtt_name' => 'house' })
      config.add_mqtt_topic('measurement' => 'm', 'field' => 'rest', 'type' => 'integer',
                            'formula' => '{house} - 100', 'name' => 'rest')

      patch configuration_setting_path(setting: 'sensor', name: 'house_power'),
            params: { data: { 'source' => 'external', 'measurement' => 'm', 'field' => 'f' }.to_json }

      expect(Configuration.current.sensor_config('house_power').source).to eq('mqtt')
      expect(flash[:alert]).to include('rest')
    end

    it 'allows renaming, the formulas follow' do
      config = Configuration.current
      config.update_sensor('house_power',
                           { 'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f',
                             'mqtt_topic' => 'h/p', 'mqtt_name' => 'house' })
      config.add_mqtt_topic('measurement' => 'm', 'field' => 'rest', 'type' => 'integer',
                            'formula' => '{house} - 100', 'name' => 'rest')

      patch configuration_setting_path(setting: 'sensor', name: 'house_power'),
            params: { data: { 'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f',
                              'mqtt_topic' => 'h/p', 'mqtt_name' => 'house_total' }.to_json }

      expect(Configuration.current.mqtt_topic(0)['formula']).to eq('{house_total} - 100')
    end

    it 'updates a singleton without changing name' do
      setting_data = { 'timezone' => 'Europe/Berlin' }

      patch configuration_setting_path(setting: 'system_general', name: 'system_general'),
            params: { data: setting_data.to_json }

      expect(response).to redirect_to(settings_path)

      config = Configuration.current
      expect(config.system.timezone).to eq('Europe/Berlin')
    end

    it 'stores the dashboard theme `user` sentinel as an empty string' do
      patch configuration_setting_path(setting: 'dashboard_theme', name: 'dashboard_theme'),
            params: { data: { 'ui_theme' => 'user' }.to_json }

      expect(response).to redirect_to(settings_path)
      expect(Configuration.current.dashboard.ui_theme).to eq('')
    end

    it 'stores a fixed dashboard theme verbatim' do
      patch configuration_setting_path(setting: 'dashboard_theme', name: 'dashboard_theme'),
            params: { data: { 'ui_theme' => 'dark' }.to_json }

      expect(Configuration.current.dashboard.ui_theme).to eq('dark')
    end

    it 'redirects to the backups page after saving the backup destination' do
      patch configuration_setting_path(setting: 'backup', name: 'backup'),
            params: { data: { 'destination' => 'local' }.to_json }

      expect(response).to redirect_to(backups_path)
      expect(Configuration.current.backup.destination).to eq('local')
    end

    it 'preserves existing Backup rows when the destination changes' do
      Configuration.current.update('backup', { 'destination' => 'local' })
      Backup.create!(filename: 'solectrus-backup-20260508-110000.tar', bytes: 100,
                     created_at: Time.zone.parse('2026-05-08 11:00:00'), destination: 'local')

      patch configuration_setting_path(setting: 'backup', name: 'backup'),
            params: { data: { 'destination' => 'external', 'external_path' => '/mnt/nas' }.to_json }

      expect(Backup.where(destination: 'local').count).to eq(1)
    end

    it 'rescopes the visible list to the new destination on switch' do
      Configuration.current.update('backup', { 'destination' => 'local' })
      Backup.create!(filename: 'solectrus-backup-20260508-110000.tar', bytes: 100,
                     created_at: Time.zone.parse('2026-05-08 11:00:00'), destination: 'local')

      patch configuration_setting_path(setting: 'backup', name: 'backup'),
            params: { data: { 'destination' => 'external', 'external_path' => '/mnt/nas' }.to_json }

      expect(BackupRepository.all).to be_empty
      expect(Backup.where(destination: 'local').count).to eq(1)
    end
  end

  describe 'DELETE /configuration/:setting/:name' do
    it 'deletes a sensor' do
      config = Configuration.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      delete configuration_setting_path(setting: 'sensor', name: 'inverter_power')

      expect(response).to redirect_to(sensors_path)
      expect(Configuration.current.sensor_enabled?('inverter_power')).to be false
    end

    # A formula reads the sensor by its MAPPING_X_NAME. Disabling it leaves a
    # reference that no mapping defines, and mqtt-collector refuses to start.
    it 'refuses while a formula reads the MQTT name' do
      config = Configuration.current
      config.update_sensor('house_power',
                           { 'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f',
                             'mqtt_topic' => 'h/p', 'mqtt_name' => 'house' })
      config.add_mqtt_topic('measurement' => 'm', 'field' => 'rest', 'type' => 'integer',
                            'formula' => '{house} - 100', 'name' => 'rest')

      delete configuration_setting_path(setting: 'sensor', name: 'house_power')

      expect(Configuration.current.sensor_enabled?('house_power')).to be true
      expect(flash[:alert]).to include('rest')
    end
  end

  describe 'read-only settings (storage)' do
    it 'renders the edit form' do
      get edit_configuration_setting_path(setting: 'storage', name: 'storage'),
          headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('survey')
    end

    it 'refuses POST' do
      post configuration_settings_path,
           params: { setting: 'storage', data: { 'postgresql' => '/evil' }.to_json }

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses PATCH' do
      patch configuration_setting_path(setting: 'storage', name: 'storage'),
            params: { setting: 'storage', data: { 'postgresql' => '/evil' }.to_json }

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses DELETE' do
      delete configuration_setting_path(setting: 'storage', name: 'storage')

      expect(response).to have_http_status(:forbidden)
    end
  end
end
