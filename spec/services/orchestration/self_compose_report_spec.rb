RSpec.describe Orchestration::SelfComposeReport do
  subject(:collect) { described_class.collect! }

  let(:name) { Orchestration::DetachedCompose::CONTAINER_NAME }

  def with_helper(state)
    allow(Orchestration::DockerCli).to receive(:inspect_container).with(name)
                                                                  .and_return(state && { 'State' => state })
    allow(Orchestration::DockerCli).to receive(:force_remove_container)
    allow(Orchestration::DockerCli).to receive(:log_tail).and_return('')
  end

  context 'without a helper container' do
    before { with_helper(nil) }

    it { is_expected.to be_nil }

    it 'removes nothing' do
      collect

      expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
    end
  end

  # The run is still going, and HELIOS is up again before its own container is
  # recreated. Reading the exit code now would report a run that has not ended.
  context 'with a helper container that still runs' do
    before { with_helper('Running' => true, 'ExitCode' => 0) }

    it { is_expected.to be_nil }

    it 'keeps it' do
      collect

      expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
    end
  end

  context 'with a run that succeeded' do
    before { with_helper('Running' => false, 'ExitCode' => 0) }

    it { is_expected.to be_nil }

    it 'clears the container' do
      collect

      expect(Orchestration::DockerCli).to have_received(:force_remove_container).with(name)
    end
  end

  context 'with a run that failed' do
    before do
      with_helper('Running' => false, 'ExitCode' => 1)
      allow(Orchestration::DockerCli).to receive(:log_tail).and_return(
        " Container solectrus-traefik-1  Creating\nError response from daemon: port is already allocated\n",
      )
    end

    it 'names the last line of the run' do
      expect(collect).to eq('Error response from daemon: port is already allocated')
    end

    # Once. The container goes with the answer, so the next screen does not
    # report the same failure again.
    it 'clears the container' do
      collect

      expect(Orchestration::DockerCli).to have_received(:force_remove_container).with(name)
    end
  end

  context 'with a failed run that logged nothing' do
    before { with_helper('Running' => false, 'ExitCode' => 137) }

    it 'names the exit code' do
      expect(collect).to eq('exit code 137')
    end
  end
end
