RSpec.describe 'Files', :with_admin_password do
  before do
    with_config_yaml
    login
  end

  describe 'GET /services/files/:id' do
    it 'renders compose.yaml content' do
      get file_path('compose'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('compose.yaml')
      expect(response.body).to include('solectrus')
    end

    it 'renders .env content' do
      get file_path('env'), headers: turbo_frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('.env')
    end

    it 'does not write compose.yaml/.env to disk' do
      get file_path('compose'), headers: turbo_frame_headers
      get file_path('env'), headers: turbo_frame_headers

      aggregate_failures do
        expect(File).not_to exist(Compose.path)
        expect(File).not_to exist(Env.path)
      end
    end

    it 'returns not found for unknown file' do
      get file_path('unknown'), headers: turbo_frame_headers

      expect(response).to have_http_status(:not_found)
    end

    context 'with the traefik file' do
      it 'is not found unless the external Traefik mode is active' do
        get file_path('traefik'), headers: turbo_frame_headers

        expect(response).to have_http_status(:not_found)
      end

      it 'renders the file-provider config in external Traefik mode' do
        Configuration.current.update('reverse_proxy', { 'bind_ip' => '10.0.0.5' })

        get file_path('traefik'), headers: turbo_frame_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('traefik.yml')
        expect(response.body).to include('10.0.0.5')
      end
    end

    it 'redirects non-frame requests to services' do
      get file_path('compose')

      expect(response).to redirect_to(services_path)
    end
  end
end
