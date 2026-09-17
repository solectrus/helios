RSpec.describe Export::Services::Mosquitto do
  def config_with(mqtt:, mosquitto: nil, mode: 'full')
    Configuration.from_data(
      {
        'deployment' => { 'mode' => mode },
        'system' => { 'timezone' => 'Europe/Berlin' },
        'influxdb' => { 'org' => 'solectrus', 'bucket' => 'solectrus' },
        'sensors' => {
          'house_power' => {
            'source' => 'mqtt', 'measurement' => 'MQTT', 'field' => 'house', 'mqtt_topic' => 'home/power'
          },
        },
        'mqtt' => mqtt,
        'mosquitto' => mosquitto,
      }.compact,
    )
  end

  def managed_config(mosquitto = { 'port' => 1883 })
    config_with(mqtt: { 'broker_managed' => true }, mosquitto:)
  end

  def managed_config_in_mode(mode)
    config_with(mqtt: { 'broker_managed' => true }, mosquitto: { 'port' => 1883 }, mode:)
  end

  # A Traefik HELIOS wrote itself carries no `command` of its own; an
  # imported one does (ADR-0015).
  def config_behind_traefik(reverse_proxy = {})
    config = managed_config('port' => 1884)
    config.update('reverse_proxy',
                  { 'mode' => 'internal', 'app_host' => 'pv.example.com' }.merge(reverse_proxy))
    config
  end

  # MQTT carries no host name of its own, so Traefik cannot serve plain and
  # TLS on one entrypoint: a router without TLS matches everything on its
  # entrypoint, only a TLS router reads the name from the SNI handshake.
  describe 'behind a Traefik of HELIOS' do
    subject(:service) { described_class.new(config_behind_traefik).to_h }

    it 'publishes no port of its own' do
      expect(service).not_to have_key(:ports)
    end

    it 'routes plain MQTT and MQTTS to the same broker' do
      expect(service[:labels]).to eq(
        [
          'traefik.enable=true',
          'traefik.tcp.routers.mqtt.rule=HostSNI(`*`)',
          'traefik.tcp.routers.mqtt.entrypoints=mqtt',
          'traefik.tcp.routers.mqtt.service=mqtt',
          'traefik.tcp.routers.mqtts.rule=HostSNI(`pv.example.com`)',
          'traefik.tcp.routers.mqtts.entrypoints=mqtts',
          'traefik.tcp.routers.mqtts.tls.certresolver=letsencrypt',
          'traefik.tcp.routers.mqtts.service=mqtt',
          'traefik.tcp.services.mqtt.loadbalancer.server.port=1883',
        ],
      )
    end
  end

  # An adopted Traefik carries a command of its own and knows no `mqtt`
  # entrypoint. HELIOS owns the routers of its own services, so it adds the
  # entrypoint and routes the broker through it, the same way it does for
  # InfluxDB and Ingest (see Export::Services::Traefik::OWNED_ENTRYPOINTS).
  describe 'behind an adopted Traefik' do
    subject(:service) { described_class.new(config_behind_traefik('command' => ['--providers.docker=true'])).to_h }

    it 'routes the broker instead of publishing its port', :aggregate_failures do
      expect(service).not_to have_key(:ports)
      expect(service[:labels]).to include('traefik.tcp.routers.mqtt.entrypoints=mqtt')
    end
  end

  describe '.enabled?' do
    it 'runs once the broker is managed and the collector needs it' do
      expect(described_class.enabled?(managed_config)).to be(true)
    end

    it 'stays off for a foreign broker' do
      config = config_with(mqtt: { 'mqtt_host' => 'mqtt.fritz.box' })
      expect(described_class.enabled?(config)).to be(false)
    end

    # The devices publish before HELIOS reads: whoever hands the broker to
    # HELIOS gets a running broker, mapping or not.
    it 'runs without an MQTT sensor or topic' do
      config = Configuration.from_data(
        'deployment' => { 'mode' => 'full' },
        'mqtt' => { 'broker_managed' => true },
      )
      expect(described_class.enabled?(config)).to be(true)
    end

    it 'stays off in a dashboard-only stack' do
      expect(described_class.enabled?(managed_config_in_mode('dashboard_only'))).to be(false)
    end
  end

  describe '#to_h' do
    it 'publishes the configured host port and persists to the bind mount' do
      service = described_class.new(managed_config('port' => 1884)).to_h

      expect(service[:image]).to eq('eclipse-mosquitto:2.1-alpine')
      expect(service[:ports]).to eq(['1884:1883'])
      expect(service[:volumes]).to eq(['${MOSQUITTO_VOLUME_PATH}:/mosquitto/data'])
      expect(service[:command].last).to include('persistence_location /mosquitto/data/')
    end

    it 'falls back to the container port when none is configured' do
      expect(described_class.new(managed_config({})).to_h[:ports]).to eq(['1883:1883'])
    end

    it 'keeps a custom image from an import' do
      config = managed_config('port' => 1883, 'image' => 'eclipse-mosquitto:2')
      expect(described_class.new(config).to_h[:image]).to eq('eclipse-mosquitto:2')
    end

    # A broker HELIOS runs always demands a login. The survey asks for both
    # halves, so only a hand-edited config.yaml gets here, and a half pair
    # leaves HELIOS unable to write the password file (`mosquitto_passwd -b`
    # refuses an empty user name). The broker must not fall back to taking
    # messages from anyone: it starts and turns every client away instead.
    {
      'with a user name and no password' => { 'username' => 'solectrus' },
      'with a password and no user name' => { 'password' => 'secret' },
    }.each do |half_a_login, mosquitto|
      context half_a_login do
        let(:service) { described_class.new(managed_config(mosquitto)).to_h }

        it 'turns every client away' do
          expect(service[:command].last).to include('allow_anonymous false')
          expect(service[:command].last).not_to include('password_file')
          expect(service[:command].last).not_to include('mosquitto_passwd')
        end

        it 'passes no credentials to the container' do
          expect(service[:environment]).to eq(['TZ'])
        end
      end
    end

    context 'with a password' do
      let(:service) do
        described_class.new(managed_config('username' => 'solectrus', 'password' => 'secret')).to_h
      end

      it 'demands a login and builds the password file at start' do
        command = service[:command].last
        expect(command).to include('allow_anonymous false', 'password_file /mosquitto/config/helios.passwd')
        # -c refuses an existing file, and a restarted container still has one.
        expect(command.lines.first(2)).to eq(
          [
            "rm -f /mosquitto/config/helios.passwd\n",
            %(mosquitto_passwd -b -c /mosquitto/config/helios.passwd "$$MQTT_USERNAME" "$$MQTT_PASSWORD"\n),
          ],
        )
        # The broker drops to its own user, so the file has to change hands.
        expect(command).to include('chown 1883:1883 /mosquitto/config/helios.passwd')
      end

      # A failing line must not leave a broker running on a half-written
      # configuration, so the shell aborts at the first one.
      it 'runs the script with sh -e' do
        expect(service[:command].first(2)).to eq(%w[sh -ec])
      end

      it 'reads the credentials from .env, never from compose.yaml' do
        expect(service[:environment]).to include('MQTT_USERNAME', 'MQTT_PASSWORD')
        expect(service[:command].last).to include('"$$MQTT_USERNAME"', '"$$MQTT_PASSWORD"')
        expect(service[:command].last).not_to include('secret')
      end

      # A subscribing healthcheck would log a connection every few seconds and
      # bury the devices the user is looking for.
      it 'checks the listening socket instead of connecting to it' do
        expect(service[:healthcheck][:test]).to eq(['CMD-SHELL', "netstat -ltn | grep -q ':1883 '"])
      end
    end
  end

  describe '#data_directories' do
    it 'names the relative source HELIOS creates up-front' do
      expect(described_class.new(managed_config).data_directories).to eq(['./mosquitto'])
    end

    it 'leaves a user-owned absolute path alone' do
      config = managed_config('port' => 1883, 'volume_path' => '/volume1/mosquitto')
      expect(described_class.new(config).data_directories).to be_empty
    end
  end
end
