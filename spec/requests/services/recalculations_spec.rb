RSpec.describe 'Services::Recalculations', :with_admin_password do
  before do
    login
    with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
    allow(Orchestration::PowerSplitter::Recalculation).to receive(:call).and_return(true)
  end

  describe 'POST /services/:service_id/recalculation' do
    it 'signals the container and redirects with a success notice' do
      container = instance_double(Orchestration::Container)
      allow(Orchestration::Container).to receive(:find).with('power-splitter').and_return(container)

      post service_recalculation_path(service_id: 'power-splitter')

      expect(Orchestration::PowerSplitter::Recalculation).to have_received(:call).with(container)
      expect(response).to redirect_to(services_path)
      expect(flash[:notice]).to be_present
    end

    it 'redirects with an alert when the container cannot be signalled' do
      allow(Orchestration::Container).to receive(:find).with('power-splitter').and_return(nil)
      allow(Orchestration::PowerSplitter::Recalculation).to receive(:call).and_return(false)

      post service_recalculation_path(service_id: 'power-splitter')

      expect(response).to redirect_to(services_path)
      expect(flash[:alert]).to be_present
    end

    it 'returns 404 for other services' do
      post service_recalculation_path(service_id: 'redis')

      expect(Orchestration::PowerSplitter::Recalculation).not_to have_received(:call)
      expect(response).to have_http_status(:not_found)
    end
  end
end
