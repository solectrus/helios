RSpec.describe 'Health' do
  describe 'GET /up' do
    it 'responds successfully' do
      get '/up'
      expect(response).to have_http_status(:ok)
    end

    it 'sets the X-Boot-Id header' do
      get '/up'
      expect(response.headers['X-Boot-Id']).to eq(
        Rails.application.config.boot_id,
      )
    end

    it 'sets the X-Version header' do
      get '/up'
      expect(response.headers['X-Version']).to eq(
        Rails.application.config.x.git.commit_version,
      )
    end
  end
end
