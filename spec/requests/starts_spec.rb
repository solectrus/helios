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
        allow(Import::ConfigurationImporter).to receive(:new).with(stack_reader).and_return(importer)
        allow(importer).to receive(:import!)
        allow(Export::Builder).to receive(:new).and_return(builder)
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

      it 'redirects to services' do
        post start_path

        expect(response).to redirect_to(services_path)
      end
    end
  end
end
