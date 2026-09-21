RSpec.describe Orchestration::DetachedCompose do
  # Unique per parallel worker so concurrent specs don't clobber each other.
  let(:data_path) { Rails.root.join("tmp/detached#{ENV.fetch('TEST_ENV_NUMBER', nil)}").to_s }
  let(:helios_yaml) do
    "name: solectrus\nservices:\n  helios:\n    image: ghcr.io/solectrus/helios:develop\n"
  end
  let(:name) { described_class::CONTAINER_NAME }

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(data_path)
    File.write(File.join(data_path, 'compose.yaml'), helios_yaml)
    allow(Orchestration::Runner).to receive(:host_data_path).and_return('/opt/solectrus')
    allow(Orchestration::DockerCli).to receive(:force_remove_container)
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    allow(Open3).to receive(:capture2e).and_return(['', status])
  end

  after { FileUtils.rm_rf(data_path) }

  def with_helper(state)
    allow(Orchestration::DockerCli).to receive(:inspect_container).with(name)
                                                                  .and_return(state && { 'State' => state })
  end

  describe '.up' do
    # The container of the previous run stays until someone reads its exit code
    # (see SelfComposeReport). Nothing read it, so this run takes the name.
    context 'with the container of a run that ended' do
      before { with_helper('Running' => false, 'ExitCode' => 0) }

      it 'frees the name and starts' do
        described_class.up

        expect(Orchestration::DockerCli).to have_received(:force_remove_container).with(name)
        expect(Open3).to have_received(:capture2e)
      end
    end

    # Two of these runs recreate the same containers, so the second would fight
    # the first for them.
    context 'with a run still in flight' do
      before { with_helper('Running' => true) }

      it 'refuses to start a second one' do
        expect { described_class.up }.to raise_error(Orchestration::Runner::CommandError, /already running/)
      end

      it 'leaves the container alone' do
        expect { described_class.up }.to raise_error(Orchestration::Runner::CommandError)

        expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
      end
    end

    context 'without a previous run' do
      before { with_helper(nil) }

      it 'removes nothing' do
        described_class.up

        expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
      end
    end
  end
end
