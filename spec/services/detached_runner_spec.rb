RSpec.describe DetachedRunner do
  # BackupRunner is the smallest concrete runner; the base class only cares
  # that its subclass names a container.
  let(:runner_class) { BackupRunner }

  describe '.running?' do
    # Deliberately not read from the in_progress cache: a backup and a restore
    # starting in the same window could both observe a stale nil and both
    # launch, and a restore wipes what a backup is still reading.
    it 'asks Docker for the container every time' do
      allow(Orchestration::DockerCli).to receive(:running_container).and_return(
        Orchestration::DockerCli::RunningContainer.new(started_at: Time.current, args: []),
      )

      expect(runner_class).to be_running
      expect(runner_class).to be_running
      expect(Orchestration::DockerCli).to have_received(:running_container)
        .with(runner_class::CONTAINER_NAME).twice
    end

    it 'is false without a running container' do
      allow(Orchestration::DockerCli).to receive(:running_container).and_return(nil)

      expect(runner_class).not_to be_running
    end
  end
end
