require 'open3'

RSpec.shared_examples 'valid Docker Compose configuration' do
  it 'generates a valid Docker Compose configuration' do
    cmd = [
      'docker', 'compose',
      '-f', compose_path,
      '--env-file', env_path,
      'config', '--quiet'
    ]
    output, status = Open3.capture2e(*cmd)
    expect(status).to be_success, "docker compose config failed:\n#{output}"
  end
end
