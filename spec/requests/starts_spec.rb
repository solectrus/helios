RSpec.describe 'Starts' do
  describe 'GET /start' do
    context 'when config.yaml already exists' do
      before { with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' }) }

      it 'redirects to services' do
        get start_path
        expect(response).to redirect_to(services_path)
      end
    end

    context 'when config.yaml does not exist' do
      before { with_config_yaml }

      it 'shows the consent page' do
        get start_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('HELIOS')
      end
    end

    context 'when the stack only contains supported services' do
      let(:dir) { with_config_yaml }

      before do
        File.write(File.join(dir, 'compose.yaml'),
                   "services:\n  dashboard:\n    image: ghcr.io/solectrus/solectrus:latest\n")
        File.write(File.join(dir, '.env'), "TZ=Europe/Berlin\n")
      end

      it 'offers the import button' do
        get start_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t('starts.show.agree'))
      end
    end

    # Hand-edited .env files are regularly Latin-1 instead of UTF-8; a single
    # umlaut in a comment used to raise Encoding::CompatibilityError here.
    # docker compose reads such a file fine, so HELIOS has to as well.
    context 'when the .env file is not UTF-8' do
      let(:dir) { with_config_yaml }

      before do
        File.write(File.join(dir, 'compose.yaml'),
                   "services:\n  dashboard:\n    image: ghcr.io/solectrus/solectrus:latest\n")
        File.binwrite(File.join(dir, '.env'), "# Sch\xF6nes Wetter\nTZ=Europe/Berlin\n")
      end

      it 'offers the import button' do
        get start_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t('starts.show.agree'))
      end
    end

    context 'when the stack contains an unsupported service' do
      let(:dir) { with_config_yaml }

      before do
        File.write(File.join(dir, 'compose.yaml'),
                   "services:\n  proxy:\n    image: nginx:alpine\n")
        File.write(File.join(dir, '.env'), "TZ=Europe/Berlin\n")
      end

      it 'names the offending service' do
        get start_path

        expect(response.body).to include('proxy').and include('nginx:alpine')
      end

      it 'does not offer the import button' do
        get start_path

        expect(response.body).not_to include(I18n.t('starts.show.agree'))
      end
    end

    context 'when the stack runs Ingest but an Ingest input is external' do
      let(:dir) { with_config_yaml }

      before do
        # Ingest service present, no collector → inverter_power_2 (the balcony)
        # imports as source: external, which HELIOS can't route through Ingest.
        File.write(File.join(dir, 'compose.yaml'), <<~YAML)
          services:
            dashboard:
              image: ghcr.io/solectrus/solectrus:latest
              environment:
                INFLUX_SENSOR_INVERTER_POWER_1: SENEC:inverter_power
                INFLUX_SENSOR_INVERTER_POWER_2: Balcony:power
                INFLUX_SENSOR_HOUSE_POWER: SENEC:house_power
            ingest:
              image: ghcr.io/solectrus/ingest:latest
        YAML
        File.write(File.join(dir, '.env'), "TZ=Europe/Berlin\n")
      end

      it 'explains the conflict and does not offer the import button' do
        get start_path

        expect(response.body).to include(I18n.t('starts.show.ingest_conflict_reason'))
        expect(response.body).not_to include(I18n.t('starts.show.agree'))
      end
    end

    context 'when the compose file is invalid' do
      let(:dir) { with_config_yaml }

      before do
        # depends_on an undefined service makes `docker compose config` fail.
        File.write(File.join(dir, 'compose.yaml'),
                   "services:\n  dashboard:\n    image: ghcr.io/solectrus/solectrus:latest\n    " \
                   "depends_on:\n      - missing\n")
        File.write(File.join(dir, '.env'), "TZ=Europe/Berlin\n")
      end

      it 'renders the page instead of crashing' do
        get start_path

        expect(response).to have_http_status(:ok)
      end

      it 'explains the problem and does not offer the import button' do
        get start_path

        expect(response.body).to include('missing')
        expect(response.body).not_to include(I18n.t('starts.show.agree'))
      end
    end
  end

  describe 'fresh-install detection on protected routes' do
    let(:dir) { with_config_yaml }

    before do
      File.write(File.join(dir, '.env'), "ADMIN_PASSWORD=x\nSECRET_KEY_BASE=y\n")
    end

    it 'does not redirect to /start when compose.yaml only contains the helios service' do
      File.write(File.join(dir, 'compose.yaml'),
                 "name: solectrus\nservices:\n  helios:\n    image: ghcr.io/solectrus/helios:develop\n")

      get services_path

      expect(response).not_to redirect_to(start_path)
    end

    it 'redirects to /start when compose.yaml contains other services' do
      File.write(File.join(dir, 'compose.yaml'), "services:\n  dashboard:\n    image: foo:latest\n")

      get services_path

      expect(response).to redirect_to(start_path)
    end

    it 'does not redirect to /start when compose.yaml is malformed' do
      File.write(File.join(dir, 'compose.yaml'), "services:\n  : : invalid\n")

      get services_path

      expect(response).not_to redirect_to(start_path)
    end
  end

  describe 'POST /start' do
    context 'when config.yaml already exists' do
      before { with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' }) }

      it 'redirects to services without importing' do
        post start_path
        expect(response).to redirect_to(services_path)
      end
    end

    context 'when config.yaml does not exist' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:dir) { with_config_yaml }
      let(:compose_content) { "services:\n  dashboard:\n    image: test:latest\n" }
      let(:env_content) { "TZ=Europe/Berlin\n" }
      let(:stack_reader) { instance_double(Import::StackReader) }
      let(:importer) { instance_double(Import::ConfigurationImporter) }
      let(:builder) { instance_double(Export::Builder, write!: nil) }

      before do
        File.write(File.join(dir, 'compose.yaml'), compose_content)
        File.write(File.join(dir, '.env'), env_content)

        allow(Import::StackReader).to receive(:new).and_return(stack_reader)
        allow(Import::CompatibilityCheck).to receive(:new).with(stack_reader).and_return(
          instance_double(Import::CompatibilityCheck, call!: nil),
        )
        allow(Import::ConfigurationImporter).to receive(:new).with(stack_reader).and_return(importer)
        allow(importer).to receive(:import!)
        allow(importer).to receive(:ingest_conflict_sensors).and_return([])
        allow(Export::Builder).to receive(:new).and_return(builder)
        # Keep the baseline seeding (issue #291) from shelling out to
        # `docker compose config --hash` in tests that don't care about it.
        allow(Orchestration::Runner).to receive(:config_hashes).and_return({})
      end

      it 'creates backup files' do
        post start_path

        expect(File.exist?(File.join(dir, 'compose.yaml.bak'))).to be true
        expect(File.exist?(File.join(dir, '.env.bak'))).to be true
      end

      it 'performs the import' do
        post start_path

        expect(importer).to have_received(:import!)
      end

      it 'rewrites compose.yaml and .env after import' do
        post start_path

        expect(builder).to have_received(:write!)
      end

      it 'seeds the restart baseline from the pre-import stack before rewriting' do
        allow(Orchestration::Runner).to receive(:config_hashes) do
          # The baseline must capture the adopted (pre-import) compose config,
          # i.e. be taken before Export::Builder rewrites it (issue #291).
          expect(builder).not_to have_received(:write!)
          { 'dashboard' => 'pre-import-hash' }
        end

        post start_path

        expect(Orchestration::AffectedServices.load_deployed_hashes_file)
          .to eq('dashboard' => 'pre-import-hash')
      end

      it 'redirects to services' do
        post start_path

        expect(response).to redirect_to(services_path)
      end
    end

    context 'when the stack contains an unsupported service' do
      let(:dir) { with_config_yaml }

      before do
        File.write(File.join(dir, 'compose.yaml'),
                   "services:\n  proxy:\n    image: nginx:alpine\n")
        File.write(File.join(dir, '.env'), "TZ=Europe/Berlin\n")
      end

      it 'responds with unprocessable content' do
        post start_path

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'names the offending service' do
        post start_path

        expect(response.body).to include('proxy').and include('nginx:alpine')
      end

      it 'does not back up or import the stack' do
        post start_path

        expect(File.exist?(File.join(dir, 'compose.yaml.bak'))).to be false
        expect(File.exist?(Configuration.path)).to be false
      end
    end

    context 'when the compose file is invalid' do
      let(:dir) { with_config_yaml }

      before do
        File.write(File.join(dir, 'compose.yaml'),
                   "services:\n  dashboard:\n    image: ghcr.io/solectrus/solectrus:latest\n    " \
                   "depends_on:\n      - missing\n")
        File.write(File.join(dir, '.env'), "TZ=Europe/Berlin\n")
      end

      it 'responds with unprocessable content' do
        post start_path

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'does not back up or import the stack' do
        post start_path

        expect(File.exist?(File.join(dir, 'compose.yaml.bak'))).to be false
        expect(File.exist?(Configuration.path)).to be false
      end
    end
  end
end
