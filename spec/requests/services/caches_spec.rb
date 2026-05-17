RSpec.describe 'Services::Caches', :with_admin_password do
  before do
    login
    with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
    allow(Orchestration::RedisCacheFlush).to receive(:call).and_return(true)
  end

  describe 'DELETE /services/:service_id/cache' do
    it 'flushes the cache and redirects with a success notice' do
      container = instance_double(Orchestration::Container)
      allow(Orchestration::Container).to receive(:find).with('redis').and_return(container)

      delete service_cache_path(service_id: 'redis')

      expect(Orchestration::RedisCacheFlush).to have_received(:call).with(container)
      expect(response).to redirect_to(services_path)
      expect(flash[:notice]).to be_present
    end

    it 'redirects with an alert when the flush fails' do
      allow(Orchestration::Container).to receive(:find).with('redis').and_return(nil)
      allow(Orchestration::RedisCacheFlush).to receive(:call).and_return(false)

      delete service_cache_path(service_id: 'redis')

      expect(response).to redirect_to(services_path)
      expect(flash[:alert]).to be_present
    end

    it 'returns 404 for non-redis services' do
      delete service_cache_path(service_id: 'postgresql')

      expect(Orchestration::RedisCacheFlush).not_to have_received(:call)
      expect(response).to have_http_status(:not_found)
    end
  end
end
