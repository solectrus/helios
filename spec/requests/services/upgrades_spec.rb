RSpec.describe 'Services::Upgrades', :with_admin_password do
  before do
    login
    with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
    allow(PostgresqlUpgradeJob).to receive(:perform_later)
  end

  after { Orchestration::PendingOperations.clear_all }

  def mock_compose_service(name)
    service = instance_double(
      Compose::Service,
      name: name,
      display_name: name.capitalize,
      image: 'postgres:18-alpine',
      public_port: nil,
      helios?: false,
    )
    collection = mock_service_collection([service])
    allow(collection).to receive(:find).with(name).and_return(service)
    allow(Compose).to receive(:load).and_return(
      instance_double(Compose::File, services: collection),
    )
    service
  end

  def mock_container(service_name)
    instance_double(
      Orchestration::Container,
      service_name: service_name,
      running?: true,
      status: 'running',
      health_status: 'healthy',
      version: '17.5',
      image: 'postgres:17-alpine',
      public_port: nil,
      stoppable?: true,
    )
  end

  describe 'POST /services/:service_id/upgrade' do
    it 'enqueues the upgrade job and returns pending status' do
      mock_compose_service('postgresql')
      container = mock_container('postgresql')
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(container)
      allow(Orchestration::PostgresqlUpgrade).to receive(:available?).and_return(true)

      post service_upgrade_path(service_id: 'postgresql'), as: :turbo_stream

      expect(PostgresqlUpgradeJob).to have_received(:perform_later)
      expect(Orchestration::PendingOperations.get('postgresql')).to eq(:upgrade)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end

    it 'returns 404 when no upgrade is available' do
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(nil)
      allow(Orchestration::PostgresqlUpgrade).to receive(:available?).and_return(false)

      post service_upgrade_path(service_id: 'postgresql')

      expect(PostgresqlUpgradeJob).not_to have_received(:perform_later)
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for non-postgresql services' do
      post service_upgrade_path(service_id: 'redis')

      expect(PostgresqlUpgradeJob).not_to have_received(:perform_later)
      expect(response).to have_http_status(:not_found)
    end
  end
end
