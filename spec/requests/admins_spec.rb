RSpec.describe 'Admin Setup', :without_admin do
  describe 'GET /admin/new' do
    context 'when no admin exists' do
      it 'shows password setup form' do
        get new_admin_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Welcome to SOLECTRUS')
      end
    end

    context 'when admin exists' do
      before { create_admin }

      it 'redirects to root' do
        get new_admin_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'POST /admin' do
    it 'creates admin with valid password' do
      post admin_path,
           params: {
             password: 'secretpassword',
             password_confirmation: 'secretpassword',
           }

      expect(Admin.exists?).to be true
      expect(response).to redirect_to(new_setup_path)
    end

    it 'shows error for blank password' do
      post admin_path, params: { password: '', password_confirmation: '' }

      expect(Admin.exists?).to be false
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Password cannot be blank')
    end

    it 'shows error for mismatched passwords' do
      post admin_path,
           params: {
             password: 'password1',
             password_confirmation: 'password2',
           }

      expect(Admin.exists?).to be false
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Passwords do not match')
    end
  end
end
