RSpec.describe 'GeneratedFiles', :with_admin_password do
  before do
    with_config_yaml
    login
  end

  describe 'GET /generated_files' do
    context 'with expert mode enabled' do
      before { cookies[:preferences] = { expert_mode: true }.to_json }

      it 'renders the generated files page' do
        get generated_files_path

        expect(response).to have_http_status(:ok)
      end

      it 'displays compose.yaml content' do
        get generated_files_path

        expect(response.body).to include('compose.yaml')
        expect(response.body).to include('solectrus')
      end

      it 'displays .env content' do
        get generated_files_path

        expect(response.body).to include('.env')
      end
    end

    context 'without expert mode' do
      it 'redirects to services' do
        get generated_files_path

        expect(response).to redirect_to(services_path)
      end
    end
  end
end
