RSpec.describe Orchestration::SelfUpdate do
  let(:data_path) { Rails.root.join('tmp/stack').to_s }
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
