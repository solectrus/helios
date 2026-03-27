RSpec.describe 'Services::OrphanedTasks', :with_admin_password do
  before do
    login
    with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
    allow(OrphanedStopJob).to receive(:perform_later)
  end

  def mock_container(service_name, stoppable: true)
    instance_double(
      Orchestration::Container,
      service_name: service_name,
      running?: stoppable,
      status: stoppable ? 'running' : 'exited',
      stoppable?: stoppable,
      image: "ghcr.io/solectrus/#{service_name}:latest",
    )
  end

  describe 'DELETE /services/:service_id/orphaned_task (stop)' do
    it 'enqueues an orphaned stop job' do
      container = mock_container('forecast-collector')
      allow(Orchestration::Container).to receive(:find)
        .with('forecast-collector')
        .and_return(container)

      delete service_orphaned_task_path(service_id: 'forecast-collector')

      expect(OrphanedStopJob).to have_received(:perform_later)
        .with('forecast-collector')
      expect(response).to redirect_to(services_path)
    end

    it 'returns turbo_stream response when requested' do
      container = mock_container('forecast-collector')
      allow(Orchestration::Container).to receive(:find)
        .with('forecast-collector')
        .and_return(container)

      delete service_orphaned_task_path(service_id: 'forecast-collector'),
             as: :turbo_stream

      expect(OrphanedStopJob).to have_received(:perform_later)
        .with('forecast-collector')
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end

    it 'redirects when container is not stoppable' do
      container = mock_container('forecast-collector', stoppable: false)
      allow(Orchestration::Container).to receive(:find)
        .with('forecast-collector')
        .and_return(container)

      delete service_orphaned_task_path(service_id: 'forecast-collector')

      expect(OrphanedStopJob).not_to have_received(:perform_later)
      expect(response).to redirect_to(services_path)
    end

    it 'redirects when container is not found' do
      allow(Orchestration::Container).to receive(:find)
        .with('forecast-collector')
        .and_return(nil)

      delete service_orphaned_task_path(service_id: 'forecast-collector')

      expect(OrphanedStopJob).not_to have_received(:perform_later)
      expect(response).to redirect_to(services_path)
    end
  end
end
