RSpec.describe Export::Env::Dashboard do
  subject(:env) { Export::Env.new(Configuration.current).to_s }

  # The dashboard reads APP_HOST with `.presence` and uses it for the CORS
  # origin alone, so a missing value costs nothing. A guessed one would allow
  # an origin nobody calls the dashboard at.
  describe 'APP_HOST' do
    it 'carries the configured address' do
      with_config_yaml('system' => { 'app_host' => 'solar.example.com' })

      expect(env).to include('APP_HOST=solar.example.com')
    end

    it 'is left out entirely when no address is configured' do
      with_config_yaml

      expect(env).not_to include('APP_HOST')
    end

    # One field holds the address in every mode, so the domain a proxy answers
    # on reaches the dashboard the same way the bare machine address does.
    %w[internal external].each do |mode|
      it "carries the domain behind a #{mode} reverse proxy" do
        with_config_yaml(
          'system' => { 'app_host' => 'demo.example.com' },
          'reverse_proxy' => { 'mode' => mode },
        )

        expect(env).to include('APP_HOST=demo.example.com')
      end
    end
  end

  # FORCE_SSL tells the dashboard that TLS ends in front of it: it then sets
  # secure cookies and emits https URLs. Without it, a login through a
  # TLS-terminating proxy fails (issue #416).
  describe 'FORCE_SSL' do
    it 'is false without a reverse proxy' do
      with_config_yaml

      expect(env).to include('FORCE_SSL=false')
    end

    it 'is true for the HELIOS-managed Traefik' do
      with_config_yaml(
        'system' => { 'app_host' => 'demo.example.com' },
        'reverse_proxy' => { 'mode' => 'internal' },
      )

      expect(env).to include('FORCE_SSL=true')
    end

    it 'is true when the flag is set for a proxy the user runs themselves' do
      with_config_yaml(
        'reverse_proxy' => { 'mode' => 'external', 'bind_ip' => '10.0.0.5' },
        'dashboard' => { 'force_ssl' => true },
      )

      expect(env).to include('FORCE_SSL=true')
    end

    # The flag lives in the `dashboard` section, so it applies with or without a
    # configured domain — an Apache or nginx in front needs no HELIOS routing.
    it 'is true when the flag is set without any reverse-proxy section' do
      with_config_yaml('dashboard' => { 'force_ssl' => true })

      expect(env).to include('FORCE_SSL=true')
    end
  end

  # Unlike the other optional variables, an empty NOMINATIM_URL carries a
  # meaning of its own: it turns the address lookup off.
  describe 'NOMINATIM_URL' do
    it 'is left out by default, so the dashboard asks the public server' do
      with_config_yaml

      expect(env).not_to include('NOMINATIM_URL')
    end

    it 'is written empty when the lookup is off' do
      with_config_yaml('dashboard' => { 'nominatim_url' => '' })

      expect(env).to include("NOMINATIM_URL=\n")
    end

    it 'names a custom server' do
      with_config_yaml('dashboard' => { 'nominatim_url' => 'http://192.168.1.10:8080' })

      expect(env).to include("NOMINATIM_URL=http://192.168.1.10:8080\n")
    end
  end
end
