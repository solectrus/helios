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
