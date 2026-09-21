RSpec.describe Orchestration::SelfConverge do
  # Unique per parallel worker so concurrent specs don't clobber each other.
  let(:data_path) { Rails.root.join("tmp/converge#{ENV.fetch('TEST_ENV_NUMBER', nil)}").to_s }
  let(:helios_yaml) do
    "name: solectrus\nservices:\n  helios:\n    image: ghcr.io/solectrus/helios:develop\n"
  end

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(data_path)
    File.write(File.join(data_path, 'compose.yaml'), helios_yaml)
    allow(Orchestration::Runner).to receive(:host_data_path).and_return('/opt/solectrus')
    allow(Orchestration::DetachedContainers).to receive(:sweep)
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    allow(Open3).to receive(:capture2e).and_return(['', status])
  end

  after { FileUtils.rm_rf(data_path) }

  describe '.call' do
    # No service list: only a run that carries HELIOS and the service its port
    # moves to can hand the port over. --remove-orphans takes the Traefik that
    # the way back leaves behind, before HELIOS binds the port it held.
    it 'runs compose up over every service in the helper container' do
      described_class.call

      expect(Open3).to have_received(:capture2e).with(
        'docker', 'run', '-d',
        '--name', 'helios-self-compose',
        '--entrypoint', 'sh',
        '-v', '/var/run/docker.sock:/var/run/docker.sock',
        '-v', '/opt/solectrus:/opt/solectrus',
        'ghcr.io/solectrus/helios:develop',
        '-c', a_string_matching(/up --no-build -d --remove-orphans\z/)
      )
    end

    it 'never forces a recreate, so an unchanged service keeps running' do
      described_class.call

      expect(Open3).not_to have_received(:capture2e).with(
        *anything, '-c', a_string_including('--force-recreate')
      )
    end

    # Same reason as in Runner#compose_up: compose would start a detached
    # container as-is.
    it 'sweeps detached containers first' do
      described_class.call

      expect(Orchestration::DetachedContainers).to have_received(:sweep)
    end
  end
end
