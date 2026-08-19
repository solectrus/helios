RSpec.describe Export::Env::Dashboard do
  subject(:env) { Export::Env.new(Configuration.current).to_s }

  # FORCE_SSL tells the dashboard that TLS ends in front of it: it then sets
  # secure cookies and emits https URLs. Without it, a login through a
  # TLS-terminating proxy fails (issue #416).
  describe 'FORCE_SSL' do
    it 'is false without a reverse proxy' do
      with_config_yaml

      expect(env).to include('FORCE_SSL=false')
    end

    it 'is true for the HELIOS-managed Traefik' do
      with_config_yaml('reverse_proxy' => { 'mode' => 'internal', 'app_domain' => 'demo.example.com' })

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
end
