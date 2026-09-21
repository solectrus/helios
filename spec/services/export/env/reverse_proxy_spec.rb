RSpec.describe Export::Env::ReverseProxy do
  subject(:env) { Export::Env.new(Configuration.current).to_s }

  # An imported Traefik keeps its own command and volumes, and they decide
  # which names the stack reads back. The section follows them, so .env never
  # defines a name nothing reads.
  def with_traefik(reverse_proxy)
    with_config_yaml(
      'system' => { 'app_host' => 'solar.example.com' },
      'reverse_proxy' => { 'mode' => 'internal' }.merge(reverse_proxy),
    )
  end

  # The routers carry the domain in the host rule itself (see
  # Export::Services::Dashboard), and the import reads it back from there.
  it 'never writes APP_DOMAIN' do
    with_traefik({})

    expect(env).not_to include('APP_DOMAIN')
  end

  # HELIOS builds the command itself and puts the address into it, so the
  # variable would carry a value the stack never reads.
  it 'writes no address for a command HELIOS builds' do
    with_traefik({})

    expect(env).not_to include('LETSENCRYPT_EMAIL')
  end

  it 'writes the address for an imported command that reads it' do
    with_traefik(
      'command' => ['--certificatesresolvers.myresolver.acme.email=${LETSENCRYPT_EMAIL}'],
      'letsencrypt_email' => 'mail@example.org',
    )

    expect(env).to include('LETSENCRYPT_EMAIL=mail@example.org')
  end

  it 'writes the volume path for the mount HELIOS builds' do
    with_traefik({})

    expect(env).to include('TRAEFIK_VOLUME_PATH=./traefik')
  end

  it 'writes no volume path for imported volumes that carry the path' do
    with_traefik(
      'command' => ['--log.level=INFO'],
      'volumes' => ['./letsencrypt:/letsencrypt', '/var/run/docker.sock:/var/run/docker.sock:ro'],
    )

    expect(env).not_to include('TRAEFIK_VOLUME_PATH')
  end

  # Nothing left to define, so not even the heading is written: it would
  # announce a group of settings that is not there.
  it 'drops the whole section when the stack reads none of its names' do
    with_traefik(
      'command' => ['--certificatesresolvers.myresolver.acme.email=mail@example.org'],
      'volumes' => ['./letsencrypt:/letsencrypt'],
    )

    expect(env).not_to include('Reverse Proxy')
  end
end
