RSpec.describe SupportBundle::Anonymizer do
  describe '.anonymize_env_style' do
    let(:all_secrets_env) do
      <<~ENV
        ADMIN_PASSWORD=adminpw
        SECRET_KEY_BASE=31daffd9b7e9f511
        LOCKUP_CODEWORD=letmein
        INFLUX_PASSWORD=influxpw
        INFLUX_TOKEN=NWD3vfbwdz8kKXiz
        POSTGRES_PASSWORD=pgpw
        MQTT_USERNAME=mqttuser
        MQTT_PASSWORD=mqttpw
        AWS_ACCESS_KEY_ID=AKIA0000
        AWS_SECRET_ACCESS_KEY=wJalrXUt
        SENEC_USERNAME=user@example.com
        SENEC_PASSWORD=s3cret
        SENEC_TOTP_URI=otpauth://totp/SENEC?secret=ABC
        SENEC_SYSTEM_ID=12345
        SHELLY_AUTH_KEY=abc123
        SHELLY_PASSWORD=shellypw,shellypw2
        FORECAST_LATITUDE=50.92264
        FORECAST_LONGITUDE=6.407
        FORECAST_SOLAR_APIKEY=solar-key
        SOLCAST_APIKEY=solcast-key
        PVNODE_APIKEY=pvnode-key
      ENV
    end

    it 'redacts every whitelisted env variable with a descriptive placeholder' do
      result = described_class.anonymize_env_style(all_secrets_env)

      expect(result).to include('POSTGRES_PASSWORD=dummy_postgres_password')
      expect(result).to include('SENEC_USERNAME=dummy_senec_username')
    end

    it 'uses realistic dummies for non-string env variables' do
      result = described_class.anonymize_env_style(all_secrets_env)

      expect(result).to include('FORECAST_LATITUDE=50.0')
      expect(result).to include('FORECAST_LONGITUDE=10.0')
      expect(result).to include('SENEC_SYSTEM_ID=0')
    end

    it 'leaves non-whitelisted keys untouched' do
      content = <<~ENV
        TZ=Europe/Berlin
        APP_HOST=192.168.178.131
        INFLUX_ORG=solectrus
        INSTALLATION_DATE=2025-01-01
      ENV

      expect(described_class.anonymize_env_style(content)).to eq(content)
    end

    it 'matches env keys case-insensitively (for compose env-list entries)' do
      content = "    - senec_password=literal\n"

      expect(described_class.anonymize_env_style(content)).to eq(
        "    - senec_password=dummy_senec_password\n",
      )
    end

    it 'leaves ${VAR} compose interpolations untouched' do
      content = "    - SENEC_PASSWORD=${SENEC_PASSWORD}\n"

      expect(described_class.anonymize_env_style(content)).to eq(content)
    end

    it 'leaves compose env list entries without value untouched' do
      content = "    - SENEC_PASSWORD\n    - SENEC_USERNAME\n"

      expect(described_class.anonymize_env_style(content)).to eq(content)
    end

    it 'preserves comments and indentation' do
      content = <<~ENV
        # SENEC cloud password
        SENEC_PASSWORD=s3cret

        # trailing comment
      ENV

      expect(described_class.anonymize_env_style(content)).to eq(<<~ENV)
        # SENEC cloud password
        SENEC_PASSWORD=dummy_senec_password

        # trailing comment
      ENV
    end
  end

  describe '.anonymize_yaml' do
    it 'redacts SENEC credentials and leaves other senec fields alone' do
      yaml = <<~YAML
        senec:
          host: senec.fritz.box
          username: user@example.com
          password: s3cret
          totp_uri: otpauth://totp/...
          system_id: '12345'
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['senec']).to eq(
        'host' => 'senec.fritz.box',
        'username' => 'dummy_username',
        'password' => 'dummy_password',
        'totp_uri' => 'dummy_totp_uri',
        'system_id' => '0',
      )
    end

    it 'redacts forecast coordinates and leaves other forecast fields alone' do
      yaml = <<~YAML
        forecast:
          forecast_latitude: '50.92264'
          forecast_longitude: '6.407'
          forecast_roofs: '1'
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['forecast']).to eq(
        'forecast_latitude' => '50.0',
        'forecast_longitude' => '10.0',
        'forecast_roofs' => '1',
      )
    end

    context 'with admin/database/broker secrets' do
      let(:yaml) do
        <<~YAML
          system:
            admin_password: adminpw
            secret_key_base: 31daffd9
            timezone: Europe/Berlin
          dashboard:
            lockup_codeword: letmein
            ui_theme: light
          postgresql: { password: pgpw }
          influxdb: { token: influxtoken, password: influxpw, org: solectrus }
          mqtt: { mqtt_password: mqttpw, mqtt_username: admin }
        YAML
      end
      let(:parsed) { YAML.safe_load(described_class.anonymize_yaml(yaml)) }

      it 'redacts system secrets and keeps non-secret fields' do
        expect(parsed['system']).to eq(
          'admin_password' => 'dummy_admin_password',
          'secret_key_base' => 'dummy_secret_key_base',
          'timezone' => 'Europe/Berlin',
        )
      end

      it 'redacts the dashboard lockup codeword and keeps non-secret fields' do
        expect(parsed['dashboard']).to eq(
          'lockup_codeword' => 'dummy_lockup_codeword',
          'ui_theme' => 'light',
        )
      end

      it 'redacts database and broker secrets' do
        expect(parsed['postgresql']).to eq('password' => 'dummy_password')
        expect(parsed['influxdb']).to eq(
          'token' => 'dummy_token',
          'password' => 'dummy_password',
          'org' => 'solectrus',
        )
        expect(parsed['mqtt']).to eq(
          'mqtt_password' => 'dummy_mqtt_password',
          'mqtt_username' => 'dummy_mqtt_username',
        )
      end
    end

    context 'with shelly, backup and forecast API keys' do
      let(:yaml) do
        <<~YAML
          shelly: { password: shellypw, auth_key: ak123, cloud_server: shelly-11-eu.shelly.cloud }
          backup: { aws_access_key_id: AKIA0000, aws_secret_access_key: wJalrXUt, aws_region: eu-central-1 }
          forecast:
            forecast_solar_apikey: solar-key
            forecast_solcast_api_key: solcast-key
            forecast_pvnode_apikey: pvnode-key
            forecast_roofs: '1'
        YAML
      end
      let(:parsed) { YAML.safe_load(described_class.anonymize_yaml(yaml)) }

      it 'redacts shelly credentials and keeps cloud_server' do
        expect(parsed['shelly']).to eq(
          'password' => 'dummy_password',
          'auth_key' => 'dummy_auth_key',
          'cloud_server' => 'shelly-11-eu.shelly.cloud',
        )
      end

      it 'redacts AWS credentials and keeps region' do
        expect(parsed['backup']).to eq(
          'aws_access_key_id' => 'dummy_aws_access_key_id',
          'aws_secret_access_key' => 'dummy_aws_secret_access_key',
          'aws_region' => 'eu-central-1',
        )
      end

      it 'redacts forecast API keys and keeps non-secret fields' do
        expect(parsed['forecast']).to eq(
          'forecast_solar_apikey' => 'dummy_forecast_solar_apikey',
          'forecast_solcast_api_key' => 'dummy_forecast_solcast_api_key',
          'forecast_pvnode_apikey' => 'dummy_forecast_pvnode_apikey',
          'forecast_roofs' => '1',
        )
      end
    end

    it 'redacts shelly_password per sensor inside the dynamic sensors section' do
      yaml = <<~YAML
        sensors:
          house_power:
            source: shelly
            shelly_host: 192.168.1.10
            shelly_password: s3cret
          grid_power:
            source: senec
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['sensors']['house_power']).to eq(
        'source' => 'shelly',
        'shelly_host' => '192.168.1.10',
        'shelly_password' => 'dummy_shelly_password',
      )
      expect(parsed['sensors']['grid_power']).to eq('source' => 'senec')
    end

    it 'returns unchanged content when the YAML has no matching sections' do
      yaml = "system:\n  timezone: Europe/Berlin\n"

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed).to eq('system' => { 'timezone' => 'Europe/Berlin' })
    end

    it 'leaves empty or missing values alone' do
      yaml = "senec:\n  username: ''\n  password:\n"

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['senec']['username']).to eq('')
      expect(parsed['senec']['password']).to be_nil
    end
  end

  describe '.anonymize_text' do
    let(:env) do
      <<~ENV
        FORECAST_LATITUDE=50.92264
        FORECAST_LONGITUDE=6.407
        INFLUX_TOKEN=NWD3vfbwdz8kKXiz
        SENEC_PASSWORD=s3cretpw
        TZ=Europe/Berlin
        # SOLCAST_APIKEY=commented-out
        SHELLY_PASSWORD=${SHELLY_PASSWORD}
      ENV
    end
    let(:redactions) { described_class.log_redactions(env) }

    it 'replaces coordinates that are logged with extra Float precision' do
      log = <<~LOG
        Fetching forecast at 2026-05-02T07:38:06+02:00
          0: https://api.forecast.solar/estimate/50.922642249999996/6.407003707805423/29/-50/9.75 ... OK
      LOG

      result = described_class.anonymize_text(log, redactions)

      expect(result).not_to include('50.92264')
      expect(result).not_to include('6.407')
      expect(result).to include('https://api.forecast.solar/estimate/50.0/10.0/29/-50/9.75')
    end

    it 'preserves the surrounding ISO timestamp when scrubbing coordinates' do
      log = "ts=2026-05-02T07:38:06+02:00 lat=50.92264 lon=6.407\n"

      result = described_class.anonymize_text(log, redactions)

      expect(result).to eq("ts=2026-05-02T07:38:06+02:00 lat=50.0 lon=10.0\n")
    end

    it 'replaces opaque tokens that leak into log lines' do
      log = "POST /api/v2/write Authorization=Token NWD3vfbwdz8kKXiz failed\n"

      result = described_class.anonymize_text(log, redactions)

      expect(result).to eq("POST /api/v2/write Authorization=Token dummy_influx_token failed\n")
    end

    it 'leaves coordinates alone when only an unrelated number is present' do
      log = "Sleeping until 2026-05-02 08:38:07 +0200\n"

      expect(described_class.anonymize_text(log, redactions)).to eq(log)
    end

    it 'ignores commented and unset values when building redactions' do
      log = "key=commented-out fallback=${SHELLY_PASSWORD}\n"

      expect(described_class.anonymize_text(log, redactions)).to eq(log)
    end

    it 'leaves logs untouched when no redactions apply' do
      expect(described_class.anonymize_text("nothing to redact\n", [])).to eq("nothing to redact\n")
    end
  end
end
