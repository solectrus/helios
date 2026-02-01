require 'rails_helper'

RSpec.describe 'Setup Wizard' do
  let(:tmp_dir) { Rails.root.join('tmp/test_stack') }

  before do
    Admin.create_admin!(password: 'test')
    post session_path, params: { password: 'test' }

    FileUtils.mkdir_p(tmp_dir)
    allow(Rails.configuration).to receive(:helios_stack_path).and_return(
      tmp_dir.to_s,
    )
  end

  after { FileUtils.rm_rf(tmp_dir) }

  describe 'GET /setup/new' do
    it 'shows setup form when authenticated' do
      get new_setup_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Setup SOLECTRUS')
    end

    context 'when setup already completed' do
      before { Configuration.current.complete_setup! }

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
      allow(Compose::Runner).to receive(:up)

      post setup_path, params: valid_params

      config = Configuration.current
      expect(config.installation_date).to eq('2024-01-15')
      expect(config.timezone).to eq('Europe/Berlin')
    end

    it 'generates compose.yaml and .env' do
      allow(Compose::Runner).to receive(:up)

      post setup_path, params: valid_params

      expect(File.exist?(tmp_dir.join('compose.yaml'))).to be true
      expect(File.exist?(tmp_dir.join('.env'))).to be true
    end

    it 'starts services' do
      allow(Compose::Runner).to receive(:up)

      post setup_path, params: valid_params

      expect(Compose::Runner).to have_received(:up)
    end

    it 'marks setup as completed' do
      allow(Compose::Runner).to receive(:up)

      post setup_path, params: valid_params

      expect(Configuration.current.setup_completed?).to be true
    end

    it 'redirects to dashboard' do
      allow(Compose::Runner).to receive(:up)

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
