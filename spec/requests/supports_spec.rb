RSpec.describe 'Supports', :with_admin_password do
  before { login }

  describe 'GET /support/new' do
    it 'renders the support modal inside a turbo frame' do
      get new_support_path, headers: turbo_frame_headers('support-modal-content')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('support-modal-content')
      expect(response.body).to include(I18n.t('supports.new.title'))
      expect(response.body).to include(I18n.t('supports.new.download'))
      expect(response.body).to include('https://github.com/orgs/solectrus/discussions')
    end

    it 'redirects direct hits to the services page' do
      get new_support_path

      expect(response).to redirect_to(services_path)
    end
  end

  describe 'POST /support' do
    it 'returns a zip archive as an attachment' do
      post support_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/zip')
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.headers['Content-Disposition']).to match(/helios-support-\d{8}-\d{6}\.zip/)
    end
  end
end
