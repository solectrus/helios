RSpec.describe Orchestration::SelfUpdate do
  # Unique per parallel worker so concurrent specs don't clobber each other.
  let(:data_path) { Rails.root.join("tmp/stack#{ENV.fetch('TEST_ENV_NUMBER', nil)}").to_s }
  let(:helios_yaml) do
    "name: solectrus\nservices:\n  helios:\n    image: ghcr.io/solectrus/helios:develop\n"
  end

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(data_path)
    allow(Orchestration::Runner).to receive(:host_data_path).and_return('/opt/solectrus')
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    allow(Open3).to receive(:capture2e).and_return(['', status])
  end

  after { FileUtils.rm_rf(data_path) }

  describe '.call' do
    it 'runs compose up + image prune in the helper container' do
      File.write(File.join(data_path, 'compose.yaml'), helios_yaml)

      described_class.call

      expect(Open3).to have_received(:capture2e).with(
        'docker', 'run', '--rm', '-d',
        '--entrypoint', 'sh',
        '-v', '/var/run/docker.sock:/var/run/docker.sock',
        '-v', '/opt/solectrus:/opt/solectrus',
        'ghcr.io/solectrus/helios:develop',
        '-c',
        a_string_matching(
          %r{-f /opt/solectrus/compose\.yaml .* --force-recreate helios && docker image prune -f\z},
        )
      )
    end

    # Compose reads .env for the variables the helios service interpolates, so
    # the helper container has to be pointed at it explicitly.
    it 'passes the env file when one exists' do
      File.write(File.join(data_path, 'compose.yaml'), helios_yaml)
      File.write(File.join(data_path, '.env'), "TZ=Europe/Berlin\n")

      described_class.call

      expect(Open3).to have_received(:capture2e).with(
        'docker', 'run', '--rm', '-d',
        '--entrypoint', 'sh',
        '-v', '/var/run/docker.sock:/var/run/docker.sock',
        '-v', '/opt/solectrus:/opt/solectrus',
        'ghcr.io/solectrus/helios:develop',
        '-c',
        a_string_including('--env-file /opt/solectrus/.env')
      )
    end

    it 'raises with the docker output when the helper container cannot start' do
      File.write(File.join(data_path, 'compose.yaml'), helios_yaml)
      # The pull succeeded; only launching the helper fails.
      allow(Orchestration::Runner).to receive(:pull)
      allow(Open3).to receive(:capture2e).and_return(
        ['no such image', instance_double(Process::Status, success?: false, exitstatus: 125)],
      )

      expect { described_class.call }.to raise_error(
        Orchestration::Runner::CommandError, /Self-update failed: no such image/
      )
    end

    it 'passes the actual compose filename to the helper container' do
      File.write(File.join(data_path, 'compose.yml'), helios_yaml)

      described_class.call

      expect(Open3).to have_received(:capture2e).with(
        'docker', 'run', '--rm', '-d',
        '--entrypoint', 'sh',
        '-v', '/var/run/docker.sock:/var/run/docker.sock',
        '-v', '/opt/solectrus:/opt/solectrus',
        'ghcr.io/solectrus/helios:develop',
        '-c', a_string_matching(%r{-f /opt/solectrus/compose\.yml })
      )
    end
  end
end
