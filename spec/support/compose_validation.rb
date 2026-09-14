require 'open3'

module ComposeValidationHelpers
  # Services a `depends_on` points at that the same file never declares.
  # `docker compose config` refuses such a project outright, so the export must
  # never produce one: a service whose gate is narrower than the gate of the
  # service depending on it takes the whole stack down with it.
  def dangling_service_dependencies(path)
    services = YAML.safe_load_file(path, aliases: true)['services'] || {}

    services.flat_map do |name, config|
      dependencies = (config || {})['depends_on']
      targets = dependencies.is_a?(Hash) ? dependencies.keys : Array(dependencies)

      (targets - services.keys).map { |target| "#{name} -> #{target}" }
    end
  end
end

RSpec.configure { |config| config.include ComposeValidationHelpers }

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
