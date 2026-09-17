RSpec.describe 'Restarting', :with_admin_password do
  before { with_config_yaml }

  # Shown while HELIOS restarts itself, so it must render without a session
  # and without the application layout (the assets may be reloading too).
  describe 'GET /restarting' do
    it 'renders the standalone waiting page for an anonymous visitor' do
      get restarting_path(boot_id: 'abc123')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('abc123')
      expect(response.body).to include(I18n.t('restarting.show.title'))
    end

    # An adopted stack restarts HELIOS before the commissioning date is
    # answered, so the gate in front of every other screen must not lead
    # away from the waiting page.
    it 'renders while the commissioning date is still missing' do
      with_config_yaml('system' => { 'installation_date' => nil })

      get restarting_path(boot_id: 'abc123')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('abc123')
    end

    # The screen waits for HELIOS to answer where it stands, which only works
    # while the address stays the same.
    it 'polls for the new boot id' do
      get restarting_path(boot_id: 'abc123')

      expect(response.body).to include('X-Boot-Id')
    end

    # A converge that moves the host port of HELIOS takes the address with it
    # (see Orchestration::SelfPorts), so the screen names the new one instead
    # of waiting at an address nothing serves any more.
    context 'when the address moves' do
      before do
        login
        with_config_yaml(
          'system' => { 'app_host' => 'solectrus.example.com' },
          'reverse_proxy' => { 'mode' => 'internal' },
        )
      end

      it 'names the address HELIOS comes back at' do
        get restarting_path(boot_id: 'abc123', moved: true)

        expect(response.body).to include('https://solectrus.example.com:3999')
        expect(response.body).to include(I18n.t('restarting.show.moved_heading'))
      end

      it 'stops polling the address it is on' do
        get restarting_path(boot_id: 'abc123', moved: true)

        expect(response.body).not_to include('X-Boot-Id')
      end
    end

    # Nothing in the configuration names the machine, so there is no address to
    # send the reader to. The screen keeps waiting where it is.
    context 'when the address moves but nothing names the machine' do
      it 'falls back to waiting on the current address' do
        login

        get restarting_path(boot_id: 'abc123', moved: true)

        expect(response.body).to include('X-Boot-Id')
      end
    end

    # The screen renders without a session, because one cannot be relied on
    # while HELIOS restarts. The address of the installation is not for a
    # caller who never signed in.
    context 'when the address moves and nobody is signed in' do
      before do
        with_config_yaml(
          'system' => { 'app_host' => 'solectrus.example.com' },
          'reverse_proxy' => { 'mode' => 'internal' },
        )
      end

      it 'renders the screen without naming the address' do
        get restarting_path(boot_id: 'abc123', moved: true)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('solectrus.example.com')
      end
    end
  end
end
