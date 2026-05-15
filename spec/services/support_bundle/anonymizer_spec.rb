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
        FORECAST_LATITUDE=52.51627
        FORECAST_LONGITUDE=13.37774
        FORECAST_SOLAR_APIKEY=solar-key
        SOLCAST_APIKEY=solcast-key
        PVNODE_APIKEY=pvnode-key
        TIBBER_TOKEN=s3cr3t-t0k3n
      ENV
    end

    it 'redacts every whitelisted env variable with a descriptive placeholder' do
      result = described_class.anonymize_env_style(all_secrets_env)

      expect(result).to include('POSTGRES_PASSWORD=dummy_postgres_password')
      expect(result).to include('SENEC_USERNAME=dummy_senec_username')
      expect(result).to include('TIBBER_TOKEN=dummy_tibber_token')
    end

    it 'uses realistic dummies for non-string env variables' do
      result = described_class.anonymize_env_style(all_secrets_env)

      expect(result).to include('FORECAST_LATITUDE=0.00000')
      expect(result).to include('FORECAST_LONGITUDE=0.00000')
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

    it 'redacts unrecognized keys whose name matches a sensitive pattern' do
      content = <<~ENV
        STRIPE_API_KEY=sk_live_abcdef
        HONEYBADGER_API_KEY=hb_xxx
        S3_SECRET_ACCESS_KEY=s3-secret
        VENDOR_PRIVATE_KEY=PEM-encoded-key
        PGADMIN_DEFAULT_PASSWORD=adminpw
      ENV

      expect(described_class.anonymize_env_style(content)).to eq(<<~ENV)
        STRIPE_API_KEY=dummy_stripe_api_key
        HONEYBADGER_API_KEY=dummy_honeybadger_api_key
        S3_SECRET_ACCESS_KEY=dummy_s3_secret_access_key
        VENDOR_PRIVATE_KEY=dummy_vendor_private_key
        PGADMIN_DEFAULT_PASSWORD=dummy_pgadmin_default_password
      ENV
    end

    it 'leaves keys with key-shaped substrings that are not secrets alone' do
      content = <<~ENV
        SENEC_LANGUAGE=de
        INFLUX_USERNAME=admin
        MAPPING_0_JSON_KEY=apower
        FORECAST_KWP=9.24
      ENV

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
          forecast_latitude: '52.51627'
          forecast_longitude: '13.37774'
          forecast_roofs: '1'
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['forecast']).to eq(
        'forecast_latitude' => '0.00000',
        'forecast_longitude' => '0.00000',
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

      it 'redacts the dashboard codeword and keeps non-secret fields' do
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

    it 'redacts whitelisted secrets inside unmanaged service env_values' do
      yaml = <<~YAML
        _unmanaged:
          services:
            tibber-collector:
              env_values:
                TIBBER_TOKEN: s3cr3t-t0k3n
                INFLUX_MEASUREMENT_PRICES: prices
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['_unmanaged']['services']['tibber-collector']['env_values']).to eq(
        'TIBBER_TOKEN' => 'dummy_tibber_token',
        'INFLUX_MEASUREMENT_PRICES' => 'prices',
      )
    end

    it 'redacts pattern-matched secrets inside unmanaged service env_values' do
      yaml = <<~YAML
        _unmanaged:
          services:
            vendor-collector:
              env_values:
                VENDOR_API_KEY: vendor-key
                VENDOR_BASE_URL: https://api.vendor.example
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['_unmanaged']['services']['vendor-collector']['env_values']).to eq(
        'VENDOR_API_KEY' => 'dummy_vendor_api_key',
        'VENDOR_BASE_URL' => 'https://api.vendor.example',
      )
    end

    it 'leaves unmanaged env_values that reference compose interpolations alone' do
      yaml = <<~YAML
        _unmanaged:
          services:
            tibber-collector:
              env_values:
                TIBBER_TOKEN: "${TIBBER_TOKEN}"
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['_unmanaged']['services']['tibber-collector']['env_values']).to eq(
        'TIBBER_TOKEN' => '${TIBBER_TOKEN}',
      )
    end
  end

  describe '.anonymize_text' do
    let(:env) do
      <<~ENV
        FORECAST_LATITUDE=52.51627
        FORECAST_LONGITUDE=13.37774
        INFLUX_TOKEN=NWD3vfbwdz8kKXiz
        SENEC_PASSWORD=s3cretpw
        TZ=Europe/Berlin
        # SOLCAST_APIKEY=commented-out
        SHELLY_PASSWORD=${SHELLY_PASSWORD}
      ENV
    end
    let(:redactions) { described_class.log_redactions(env) }

    it 'replaces coordinates inside a forecast collector URL' do
      log = <<~LOG
        Fetching forecast at 2026-05-02T07:38:06+02:00
          0: https://api.forecast.solar/estimate/52.51627/13.37774/29/-50/9.75 ... OK
      LOG

      result = described_class.anonymize_text(log, redactions)

      expect(result).not_to include('52.51627')
      expect(result).not_to include('13.37774')
      expect(result).to include('https://api.forecast.solar/estimate/0.00000/0.00000/29/-50/9.75')
    end

    it 'also catches coordinates that gained extra Float-precision digits' do
      log = "lat=52.51627999 lon=13.37774001\n"

      expect(described_class.anonymize_text(log, redactions)).to eq("lat=0.00000 lon=0.00000\n")
    end

    it 'preserves the surrounding ISO timestamp when scrubbing coordinates' do
      log = "ts=2026-05-02T07:38:06+02:00 lat=52.51627 lon=13.37774\n"

      result = described_class.anonymize_text(log, redactions)

      expect(result).to eq("ts=2026-05-02T07:38:06+02:00 lat=0.00000 lon=0.00000\n")
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
