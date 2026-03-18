RSpec.describe 'Setup Wizard', :with_admin do
  let(:tmp_dir) { Rails.configuration.helios_stack_path }

  before do
    with_config_yaml
    login
  end

  describe 'GET /setup/new' do
    it 'shows setup form when authenticated' do
      get new_setup_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Setup SOLECTRUS')
    end

    context 'when setup already completed' do
      before do
        config = Configuration.current
        config.update('system', { 'timezone' => 'Europe/Berlin' })
      end

      it 'redirects to dashboard' do
        get new_setup_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'POST /setup' do
    let(:valid_params) do
      { installation_date: '2024-01-15', timezone: 'Europe/Berlin' }
    end

    it 'saves configuration' do
      post setup_path, params: valid_params

      config = Configuration.current
      expect(config.system.installation_date).to eq('2024-01-15')
      expect(config.system.timezone).to eq('Europe/Berlin')
    end

    it 'generates compose.yaml and .env' do
      post setup_path, params: valid_params

      expect(File.exist?(File.join(tmp_dir, 'compose.yaml'))).to be true
      expect(File.exist?(File.join(tmp_dir, '.env'))).to be true
    end

    it 'marks setup as completed' do
      post setup_path, params: valid_params

      expect(Configuration.current.setup_completed?).to be true
    end

    it 'redirects to dashboard' do
      post setup_path, params: valid_params

      expect(response).to redirect_to(root_path)
    end

    it 'shows error for missing installation date' do
      post setup_path, params: { timezone: 'Europe/Berlin' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Installation date is required')
    end

    it 'shows error for missing timezone' do
      post setup_path, params: { installation_date: '2024-01-15' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Timezone is required')
    end
  end
end
