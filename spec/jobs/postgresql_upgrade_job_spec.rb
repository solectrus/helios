RSpec.describe PostgresqlUpgradeJob do
  after do
    Orchestration::ErrorStore.clear_all
    Orchestration::PendingOperations.clear_all
    Orchestration::StackStatus.reset!
  end

  describe '#perform' do
    context 'when the upgrade succeeds' do
      before { allow(Orchestration::PostgresqlUpgrade).to receive(:call).and_return(true) }

      it 'runs the upgrade and clears the pending flag' do
        Orchestration::PendingOperations.set('postgresql', :upgrade)

        described_class.perform_now

        expect(Orchestration::PostgresqlUpgrade).to have_received(:call)
        expect(Orchestration::PendingOperations.get('postgresql')).to be_nil
        expect(Orchestration::ErrorStore.get('postgresql')).to be_nil
      end
    end

    context 'when the upgrade fails' do
      before do
        allow(Orchestration::PostgresqlUpgrade).to receive(:call)
          .and_raise(Orchestration::PostgresqlUpgrade::UpgradeError, 'something went wrong')
      end

      it 'stores the error message and clears the pending flag' do
        Orchestration::PendingOperations.set('postgresql', :upgrade)

        described_class.perform_now

        expect(Orchestration::ErrorStore.get('postgresql')).to eq('something went wrong')
        expect(Orchestration::PendingOperations.get('postgresql')).to be_nil
      end
    end

    context 'when recovering an interrupted upgrade' do
      before do
        allow(Orchestration::PostgresqlUpgrade).to receive_messages(recover!: true, call: true)
      end

      it 'recovers instead of starting a new upgrade' do
        described_class.perform_now(recover: true)

        aggregate_failures do
          expect(Orchestration::PostgresqlUpgrade).to have_received(:recover!)
          expect(Orchestration::PostgresqlUpgrade).not_to have_received(:call)
        end
      end

      it 'stores what the recovery had to report' do
        allow(Orchestration::PostgresqlUpgrade).to receive(:recover!)
          .and_raise(Orchestration::PostgresqlUpgrade::UpgradeError, 'reverted to 17')

        described_class.perform_now(recover: true)

        expect(Orchestration::ErrorStore.get('postgresql')).to eq('reverted to 17')
      end
    end

    describe '.recover_later' do
      before { allow(described_class).to receive(:perform_later) }

      it 'does nothing when no upgrade was interrupted' do
        allow(Orchestration::PostgresqlUpgrade).to receive(:interrupted?).and_return(false)

        described_class.recover_later

        aggregate_failures do
          expect(described_class).not_to have_received(:perform_later)
          expect(Orchestration::PendingOperations.get('postgresql')).to be_nil
        end
      end

      # The pending flag is set synchronously so the first render after boot
      # cannot offer an upgrade for a database the recovery is taking over.
      it 'marks the service pending and enqueues the recovery' do
        allow(Orchestration::PostgresqlUpgrade).to receive(:interrupted?).and_return(true)

        described_class.recover_later

        aggregate_failures do
          expect(described_class).to have_received(:perform_later).with(recover: true)
          expect(Orchestration::PendingOperations.get('postgresql')).to eq(:upgrade)
        end
      end
    end

    describe 'the update pause' do
      before do
        allow(Orchestration::UpdatePause).to receive(:pause!)
        allow(Orchestration::UpdatePause).to receive(:resume_if_idle!)
      end

      it 'holds it for the whole run' do
        allow(Orchestration::PostgresqlUpgrade).to receive(:call) do
          expect(Orchestration::UpdatePause).to have_received(:pause!).with(:postgresql_upgrade)
          expect(Orchestration::UpdatePause).not_to have_received(:resume_if_idle!)
          true
        end

        described_class.perform_now

        expect(Orchestration::UpdatePause).to have_received(:resume_if_idle!)
      end

      it 'releases it only after the pending flag is cleared' do
        allow(Orchestration::PostgresqlUpgrade).to receive(:call).and_return(true)
        Orchestration::PendingOperations.set('postgresql', :upgrade)
        allow(Orchestration::UpdatePause).to receive(:resume_if_idle!) do
          expect(Orchestration::PendingOperations.get('postgresql')).to be_nil
        end

        described_class.perform_now

        expect(Orchestration::UpdatePause).to have_received(:resume_if_idle!)
      end

      it 'releases it when the upgrade fails' do
        allow(Orchestration::PostgresqlUpgrade).to receive(:call)
          .and_raise(Orchestration::PostgresqlUpgrade::UpgradeError, 'boom')

        described_class.perform_now

        expect(Orchestration::UpdatePause).to have_received(:resume_if_idle!)
      end
    end
  end
end
