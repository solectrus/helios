RSpec.describe 'Sessions', :with_admin_password do
  before { with_config_yaml }

  describe 'GET /session/new' do
    it 'shows login form' do
      get new_session_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('HELIOS')
    end

    it 'redirects to root if already authenticated' do
      login
      get new_session_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe 'POST /session' do
    it 'logs in with correct password' do
      post session_path, params: { password: 'test' }
      expect(response).to redirect_to(root_path)
    end

    it 'shows error for incorrect password' do
      post session_path, params: { password: 'wrongpassword' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Invalid password')
    end

    it 'sets a persistent session cookie that survives browser restarts' do
      post session_path, params: { password: 'test' }

      session_cookie =
        Array(response.headers['Set-Cookie']).find do |c|
          c.start_with?('_helios_session=')
        end

      # An `expires` attribute marks the cookie as persistent; a plain
      # session cookie (the previous behaviour) would not carry one and
      # would be dropped when the browser/PWA context ends.
      expect(session_cookie).to be_present
      expect(session_cookie).to match(/expires=/i)
    end
  end

  describe 'DELETE /session' do
    it 'logs out user' do
      login
      delete session_path
      expect(response).to redirect_to(new_session_path)
    end
  end
end
