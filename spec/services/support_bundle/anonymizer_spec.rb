RSpec.describe SupportBundle::Anonymizer do
  describe '.mask' do
    it 'replaces a string with a fixed 5-letter run of a single letter' do
      expect(described_class.mask('geheim')).to eq('AAAAA')
    end

    it 'always returns the same length, regardless of input length' do
      expect(described_class.mask('a').length).to eq(5)
      expect(described_class.mask('a-much-longer-secret').length).to eq(5)
    end

    it 'returns the same mask for repeated calls with the same value' do
      first = described_class.mask('shared-secret')
      second = described_class.mask('shared-secret')

      expect(second).to eq(first)
    end

    it 'gives different values different letters' do
      first = described_class.mask('alpha')
      second = described_class.mask('beta')

      expect(first[0]).not_to eq(second[0])
    end

    it 'preserves empty strings' do
      expect(described_class.mask('')).to eq('')
    end

    it 'masks well-known words too — the allowlist is applied by callers, not here' do
      expect(described_class.mask('solectrus')).to match(/\A[A-Z]{5}\z/)
    end

    it 'cycles letters after exhausting A-Z so the 27th value reuses A' do
      26.times { |i| described_class.mask("value-#{i}") }

      expect(described_class.mask('overflow')[0]).to eq('A')
    end
  end

  describe '.coord_mask' do
    it 'keeps the integer part and zeroes the decimals' do
      expect(described_class.coord_mask('52.51627')).to eq('52.00000')
    end

    it 'preserves a negative sign' do
      expect(described_class.coord_mask('-3.14159')).to eq('-3.00000')
    end

    it 'handles longer decimal tails (e.g. float-precision tails in logs)' do
      expect(described_class.coord_mask('52.5162799')).to eq('52.0000000')
    end

    it 'falls back to the 5-letter mask for non-coordinate strings' do
      expect(described_class.coord_mask('not-a-coord')).to match(/\A[A-Z]{5}\z/)
    end
  end

  describe '.anonymize_env_style' do
    it 'masks every whitelisted env variable to the 5-letter dummy' do
      content = <<~ENV
        ADMIN_PASSWORD=adminpw
        SENEC_PASSWORD=s3cret
        TIBBER_TOKEN=s3cr3t-t0k3n
      ENV

      result = described_class.anonymize_env_style(content)

      expect(result).to eq(<<~ENV)
        ADMIN_PASSWORD=AAAAA
        SENEC_PASSWORD=BBBBB
        TIBBER_TOKEN=CCCCC
      ENV
    end

    it 'reuses the same letter when a value repeats across lines' do
      content = <<~ENV
        INFLUX_TOKEN=example-influx-token
        INFLUX_TOKEN_WRITE=example-influx-token
      ENV

      result = described_class.anonymize_env_style(content)

      expect(result).to eq(<<~ENV)
        INFLUX_TOKEN=AAAAA
        INFLUX_TOKEN_WRITE=AAAAA
      ENV
    end

    it 'keeps coordinates as their integer part with zeroed decimals' do
      result = described_class.anonymize_env_style(<<~ENV)
        FORECAST_LATITUDE=52.51627
        FORECAST_LONGITUDE=13.37774
        SENEC_SYSTEM_ID=12345
      ENV

      expect(result).to include('FORECAST_LATITUDE=52.00000')
      expect(result).to include('FORECAST_LONGITUDE=13.00000')
      expect(result).to include('SENEC_SYSTEM_ID=0')
    end

    it 'masks Solcast site IDs while keeping distinct sites distinguishable' do
      content = <<~ENV
        SOLCAST_SITE=1111-2222-3333-4444
        SOLCAST_0_SITE=1111-2222-3333-4444
        SOLCAST_1_SITE=5555-6666-7777-8888
      ENV

      # The shared value maps to one mask, the second site to another, so
      # support can still tell the two planes point at different sites.
      expect(described_class.anonymize_env_style(content)).to eq(<<~ENV)
        SOLCAST_SITE=AAAAA
        SOLCAST_0_SITE=AAAAA
        SOLCAST_1_SITE=BBBBB
      ENV
    end

    it 'leaves non-whitelisted keys untouched' do
      content = <<~ENV
        TZ=Europe/Berlin
        APP_HOST=192.168.178.131
        INSTALLATION_DATE=2025-01-01
      ENV

      expect(described_class.anonymize_env_style(content)).to eq(content)
    end

    it 'masks custom INFLUX_BUCKET and INFLUX_ORG names' do
      content = <<~ENV
        INFLUX_BUCKET=my-solectrus-bucket
        INFLUX_ORG=berlin-pv
      ENV

      expect(described_class.anonymize_env_style(content)).to eq(<<~ENV)
        INFLUX_BUCKET=AAAAA
        INFLUX_ORG=BBBBB
      ENV
    end

    it 'keeps well-known org/bucket names (default + vendor, case-insensitive)' do
      content = <<~ENV
        INFLUX_BUCKET=SeNeC
        INFLUX_ORG=solectrus
      ENV

      expect(described_class.anonymize_env_style(content)).to eq(content)
    end

    it 'still masks a secret even when its value equals a safe word' do
      content = "INFLUX_PASSWORD=solectrus\n"

      expect(described_class.anonymize_env_style(content)).to eq("INFLUX_PASSWORD=AAAAA\n")
    end

    it 'masks *_HOST values that are public FQDNs' do
      content = <<~ENV
        APP_HOST=solar.example.com
        INFLUX_HOST=influx.mydomain.de
      ENV

      expect(described_class.anonymize_env_style(content)).to eq(<<~ENV)
        APP_HOST=AAAAA
        INFLUX_HOST=BBBBB
      ENV
    end

    it 'leaves *_HOST values that are private IPs, container names, or local zones alone' do
      content = <<~ENV
        APP_HOST=192.168.178.131
        INFLUX_HOST=influxdb
        MQTT_HOST=10.0.0.5
        SENEC_HOST=senec.fritz.box
        SHELLY_HOST=shelly-heatpump.fritz.box
        APP_HOST=localhost
      ENV

      expect(described_class.anonymize_env_style(content)).to eq(content)
    end

    it 'leaves a private IP with a trailing inline comment alone' do
      content = "SENEC_HOST=192.168.178.34 # change this!!!\n"

      expect(described_class.anonymize_env_style(content)).to eq(content)
    end

    it 'masks the whole SHELLY_HOST list when any entry is a public FQDN' do
      content = "SHELLY_HOST=192.168.1.10,solar.example.com,192.168.1.11\n"

      expect(described_class.anonymize_env_style(content))
        .to eq("SHELLY_HOST=AAAAA\n")
    end

    it 'matches env keys case-insensitively (for compose env-list entries)' do
      content = "    - senec_password=literal\n"

      expect(described_class.anonymize_env_style(content))
        .to eq("    - senec_password=AAAAA\n")
    end

    it 'leaves ${VAR} compose interpolations untouched' do
      content = "    - SENEC_PASSWORD=${SENEC_PASSWORD}\n"

      expect(described_class.anonymize_env_style(content)).to eq(content)
    end

    it 'leaves compose env list entries without value untouched' do
      content = "    - SENEC_PASSWORD\n    - SENEC_USERNAME\n"

      expect(described_class.anonymize_env_style(content)).to eq(content)
    end

    it 'masks unrecognized keys whose name matches a sensitive pattern' do
      content = <<~ENV
        STRIPE_API_KEY=sk_live_abcdef
        PGADMIN_DEFAULT_PASSWORD=adminpw
      ENV

      expect(described_class.anonymize_env_style(content)).to eq(<<~ENV)
        STRIPE_API_KEY=AAAAA
        PGADMIN_DEFAULT_PASSWORD=BBBBB
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
        SENEC_PASSWORD=AAAAA

        # trailing comment
      ENV
    end
  end

  describe '.anonymize_yaml' do
    it 'masks SENEC credentials and leaves other senec fields alone' do
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
        'username' => 'AAAAA',
        'password' => 'BBBBB',
        'totp_uri' => 'CCCCC',
        'system_id' => '0',
      )
    end

    it 'replaces forecast coordinates with parseable placeholders and leaves other forecast fields alone' do
      yaml = <<~YAML
        forecast:
          forecast_latitude: '52.51627'
          forecast_longitude: '13.37774'
          forecast_roofs: '1'
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['forecast']).to eq(
        'forecast_latitude' => '52.00000',
        'forecast_longitude' => '13.00000',
        'forecast_roofs' => '1',
      )
    end

    it 'masks Solcast site IDs in the forecast section' do
      yaml = <<~YAML
        forecast:
          forecast_solcast_id1: 1111-2222-3333-4444
          forecast_solcast_id2: 5555-6666-7777-8888
          forecast_roofs: '2'
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['forecast']['forecast_solcast_id1']).to match(/\A[A-Z]{5}\z/)
      expect(parsed['forecast']['forecast_solcast_id2']).to match(/\A[A-Z]{5}\z/)
      expect(parsed['forecast']['forecast_solcast_id1'])
        .not_to eq(parsed['forecast']['forecast_solcast_id2'])
      expect(parsed['forecast']['forecast_roofs']).to eq('2')
    end

    it 'masks database and broker secrets with consistent letters per value' do
      yaml = <<~YAML
        postgresql: { password: pgpw }
        influxdb: { token: influxtoken, password: pgpw, org: solectrus }
        mqtt: { mqtt_password: mqttpw, mqtt_username: admin }
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      # pgpw appears twice → same letter, same mask
      expect(parsed['postgresql']['password']).to eq(parsed['influxdb']['password'])
      expect(parsed['postgresql']['password']).to match(/\A[A-Z]{5}\z/)

      # Distinct values get distinct letters
      letters = parsed.values_at('postgresql', 'influxdb', 'mqtt').flat_map(&:values).pluck(0)
      expect(letters.uniq.size).to be > 1
    end

    it 'masks a custom influxdb bucket and a public FQDN host, keeps container hostnames and the default org' do
      yaml = <<~YAML
        influxdb:
          host: influxdb
          bucket: my-solectrus-bucket
          org: solectrus
        mqtt:
          host: broker.example.com
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['influxdb']['host']).to eq('influxdb')
      expect(parsed['influxdb']['bucket']).to match(/\A[A-Z]{5}\z/)
      expect(parsed['influxdb']['org']).to eq('solectrus') # well-known name kept
      expect(parsed['mqtt']['host']).to match(/\A[A-Z]{5}\z/)
    end

    it 'masks a public shelly_host per sensor, keeps fritz.box and private IPs' do
      yaml = <<~YAML
        sensors:
          house_power:
            source: shelly
            shelly_host: 192.168.1.10
          heatpump_power:
            source: shelly
            shelly_host: shelly-heatpump.fritz.box
          cloud_shelly:
            source: shelly
            shelly_host: shelly.example.com
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['sensors']['house_power']['shelly_host']).to eq('192.168.1.10')
      expect(parsed['sensors']['heatpump_power']['shelly_host']).to eq('shelly-heatpump.fritz.box')
      expect(parsed['sensors']['cloud_shelly']['shelly_host']).to match(/\A[A-Z]{5}\z/)
    end

    it 'masks AWS credentials and keeps region' do
      yaml = <<~YAML
        backup: { aws_access_key_id: AKIA0000, aws_secret_access_key: wJalrXUt, aws_region: eu-central-1 }
      YAML

      parsed = YAML.safe_load(described_class.anonymize_yaml(yaml))

      expect(parsed['backup']['aws_access_key_id']).to match(/\A[A-Z]{5}\z/)
      expect(parsed['backup']['aws_secret_access_key']).to match(/\A[A-Z]{5}\z/)
      expect(parsed['backup']['aws_region']).to eq('eu-central-1')
    end

    it 'masks shelly_password per sensor inside the dynamic sensors section' do
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
        'shelly_password' => 'AAAAA',
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

    it 'masks whitelisted secrets inside unmanaged service env_values' do
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
        'TIBBER_TOKEN' => 'AAAAA',
        'INFLUX_MEASUREMENT_PRICES' => 'prices',
      )
    end

    it 'masks pattern-matched secrets inside unmanaged service env_values' do
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
        'VENDOR_API_KEY' => 'AAAAA',
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
        INFLUX_TOKEN=example-influx-token
        SENEC_PASSWORD=s3cretpw
        TZ=Europe/Berlin
        # SOLCAST_APIKEY=commented-out
        SHELLY_PASSWORD=${SHELLY_PASSWORD}
      ENV
    end
    let(:redactions) { described_class.log_redactions(env) }

    it 'replaces coordinates inside a forecast collector URL with zeroed decimals' do
      log = <<~LOG
        Fetching forecast at 2026-05-02T07:38:06+02:00
          0: https://api.forecast.solar/estimate/52.51627/13.37774/29/-50/9.75 ... OK
      LOG

      result = described_class.anonymize_text(log, redactions)

      expect(result).not_to include('52.51627')
      expect(result).not_to include('13.37774')
      expect(result).to include('https://api.forecast.solar/estimate/52.00000/13.00000/29/-50/9.75')
    end

    it 'catches coordinates that gained extra Float-precision digits while keeping the integer part' do
      log = "lat=52.51627999 lon=13.37774001\n"

      expect(described_class.anonymize_text(log, redactions)).to eq("lat=52.00000000 lon=13.00000000\n")
    end

    it 'preserves the surrounding ISO timestamp when scrubbing coordinates' do
      log = "ts=2026-05-02T07:38:06+02:00 lat=52.51627 lon=13.37774\n"

      result = described_class.anonymize_text(log, redactions)

      expect(result).to eq("ts=2026-05-02T07:38:06+02:00 lat=52.00000 lon=13.00000\n")
    end

    it 'masks a Solcast site ID that leaks into a forecast collector URL' do
      env_redactions = described_class.log_redactions("SOLCAST_0_SITE=1111-2222-3333-4444\n")
      log = "  0: https://api.solcast.com.au/rooftop_sites/1111-2222-3333-4444/forecasts ... OK\n"

      result = described_class.anonymize_text(log, env_redactions)

      expect(result).not_to include('1111-2222-3333-4444')
      expect(result).to include('/rooftop_sites/AAAAA/forecasts')
    end

    it 'masks opaque tokens that leak into log lines, consistent with the .env mask' do
      env_redactions = described_class.log_redactions("INFLUX_TOKEN=example-influx-token\n")
      env_mask = described_class.mask('example-influx-token')
      log = "POST /api/v2/write Authorization=Token example-influx-token failed\n"

      result = described_class.anonymize_text(log, env_redactions)

      expect(result).to eq("POST /api/v2/write Authorization=Token #{env_mask} failed\n")
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

    it 'masks custom bucket and org names that leak into log lines' do
      env = <<~ENV
        INFLUX_BUCKET=my-solectrus-bucket
        INFLUX_ORG=my-org-name
      ENV
      redactions = described_class.log_redactions(env)
      log = "writing to bucket my-solectrus-bucket org my-org-name failed\n"

      bucket_mask = described_class.mask('my-solectrus-bucket')
      org_mask = described_class.mask('my-org-name')
      expect(described_class.anonymize_text(log, redactions))
        .to eq("writing to bucket #{bucket_mask} org #{org_mask} failed\n")
    end

    it 'masks only the public FQDN entries of a SHELLY_HOST list in logs' do
      env = "SHELLY_HOST=192.168.1.10,solar.example.com\n"
      redactions = described_class.log_redactions(env)
      log = "probing 192.168.1.10 and solar.example.com\n"

      host_mask = described_class.mask('solar.example.com')
      expect(described_class.anonymize_text(log, redactions))
        .to eq("probing 192.168.1.10 and #{host_mask}\n")
    end

    it 'does not add log redactions for *_HOST values that are private IPs' do
      env = "INFLUX_HOST=192.168.1.10\nMQTT_HOST=broker\n"

      expect(described_class.log_redactions(env)).to be_empty
    end
  end

  describe '.reset_registry!' do
    it 'clears the value→letter mapping so the next bundle starts at A again' do
      described_class.mask('first')
      described_class.mask('second')

      described_class.reset_registry!

      expect(described_class.mask('fresh')).to eq('AAAAA')
    end
  end
end
