require 'rails_helper'

RSpec.describe 'Dashboard' do
  before do
    Admin.create_admin!(password: 'test')
    post session_path, params: { password: 'test' }
    Configuration.current.complete_setup!
  end

  def mock_compose_services(*names)
    services = names.map { |name| mock_service(name) }
    collection = instance_double(Compose::ServiceCollection)
    allow(collection).to receive(:each) { |&block| services.each(&block) }
    allow(collection).to receive(:sorted).and_return(services)
    allow(Compose).to receive(:load).and_return(
      instance_double(Compose::File, services: collection),
    )
  end

  def mock_service(name)
    instance_double(
      Compose::Service,
      name: name,
      display_name: name,
      image: "#{name}:latest",
      public_port: nil,
      helios?: name == 'helios',
    )
  end

  describe 'GET /' do
    it 'shows dashboard when authenticated and setup completed' do
      allow(DockerHost::Container).to receive(:all).and_return([])
      mock_compose_services

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('HELIOS')
    end

    it 'shows service status' do
      container =
        instance_double(
          DockerHost::Container,
          service_name: 'dashboard',
          running?: true,
          status: 'running',
          public_port: 3001,
        )
      allow(DockerHost::Container).to receive(:all).and_return([container])
      mock_compose_services('dashboard')

      get root_path

      expect(response.body).to include('dashboard')
      # Basic status shown immediately (health loaded lazy via turbo frame)
      expect(response.body).to include('Running')
      expect(response.body).to include('turbo-frame')
      expect(response.body).to include('/services/dashboard/status')
    end

    it 'shows services without containers' do
      allow(DockerHost::Container).to receive(:all).and_return([])
      mock_compose_services('redis', 'postgresql', 'dashboard')

      get root_path

      expect(response.body).to include('redis')
      expect(response.body).to include('postgresql')
      expect(response.body).to include('dashboard')
      expect(response.body).to include('Not created')
    end

    context 'when setup not completed' do
      before do
        Configuration.current.update!(data: { 'setup_completed' => false })
      end

      it 'redirects to setup' do
        get root_path
        expect(response).to redirect_to(new_setup_path)
      end
    end
  end
end
