RSpec.describe 'Sessions', :with_admin_password do
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
  end

  describe 'DELETE /session' do
    it 'logs out user' do
      login
      delete session_path
      expect(response).to redirect_to(new_session_path)
    end
  end
end
