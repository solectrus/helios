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

  describe 'POST /start' do
    context 'when config.yaml already exists' do
      before { with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' }) }

      it 'redirects to services without importing' do
        post start_path
        expect(response).to redirect_to(services_path)
      end
    end

    context 'when config.yaml does not exist' do
      let(:dir) { with_config_yaml }
      let(:compose_content) { "services:\n  dashboard:\n    image: test:latest\n" }
      let(:env_content) { "TZ=Europe/Berlin\n" }
      let(:stack_reader) { instance_double(Import::StackReader) }
      let(:importer) { instance_double(Import::ConfigurationImporter) }

      before do
        File.write(File.join(dir, 'compose.yaml'), compose_content)
        File.write(File.join(dir, '.env'), env_content)

        allow(Import::StackReader).to receive(:new).and_return(stack_reader)
        allow(Import::ConfigurationImporter).to receive(:new).with(stack_reader).and_return(importer)
        allow(importer).to receive(:import!)
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

      it 'redirects to services' do
        post start_path

        expect(response).to redirect_to(services_path)
      end
    end
  end
end
