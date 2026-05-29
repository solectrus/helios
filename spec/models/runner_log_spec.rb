# == Schema Information
#
# Table name: runner_logs
# Database name: primary
#
#  id                 :integer          not null, primary key
#  automatic          :boolean          default(FALSE), not null
#  kind               :string           not null
#  last_error_message :text
#  last_finished_at   :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_runner_logs_on_kind  (kind) UNIQUE
#
RSpec.describe RunnerLog do
  include ActiveSupport::Testing::TimeHelpers

  describe 'kind enum' do
    it 'accepts the two known kinds' do
      expect { described_class.create!(kind: :backup) }.not_to raise_error
      expect { described_class.create!(kind: :restore) }.not_to raise_error
    end

    it 'raises on an unknown kind' do
      expect { described_class.create!(kind: :other) }.to raise_error(ArgumentError)
    end
  end

  describe '.message_for' do
    it 'returns nil when no row exists for that kind' do
      expect(described_class.message_for(:backup)).to be_nil
    end

    it 'returns the recorded message' do
      described_class.create!(kind: :backup, last_error_message: 'Disk full')

      expect(described_class.message_for(:backup)).to eq('Disk full')
    end

    it 'returns nil when the message is blank — not an empty string' do
      described_class.create!(kind: :backup, last_error_message: '')

      expect(described_class.message_for(:backup)).to be_nil
    end
  end

  describe '.messages_for' do
    it 'returns a kind-keyed hash, skipping blanks and missing kinds' do
      described_class.create!(kind: :backup, last_error_message: 'Disk full')
      described_class.create!(kind: :restore, last_error_message: '')

      expect(described_class.messages_for(%i[backup restore])).to eq(backup: 'Disk full')
    end
  end

  describe '.kind_for' do
    it 'returns :restore for the restore error filename' do
      expect(described_class.kind_for(RestoreRunner::ERROR_FILENAME)).to eq(:restore)
    end

    it 'returns :backup for any other filename' do
      expect(described_class.kind_for(BackupRepository::ERROR_FILENAME)).to eq(:backup)
    end
  end

  describe '.record_error!' do
    it 'creates a new row when none exists for the kind' do
      expect { described_class.record_error!(:backup, 'oops') }.to change(described_class, :count).by(1)
      expect(described_class.message_for(:backup)).to eq('oops')
    end

    it 'upserts — the same kind never produces a second row' do
      described_class.record_error!(:backup, 'first')

      expect { described_class.record_error!(:backup, 'second') }.not_to change(described_class, :count)
      expect(described_class.message_for(:backup)).to eq('second')
    end
  end

  describe '.record_finished!' do
    it 'creates a new row stamped with the current time' do
      freeze_time do
        expect { described_class.record_finished!(:backup) }.to change(described_class, :count).by(1)
        expect(described_class.find_by(kind: :backup).last_finished_at).to eq(Time.current)
      end
    end

    it 'updates the existing row instead of creating a new one' do
      described_class.record_error!(:backup, 'oops')

      expect { described_class.record_finished!(:backup) }.not_to change(described_class, :count)
      expect(described_class.find_by(kind: :backup).last_finished_at).to be_present
      expect(described_class.message_for(:backup)).to eq('oops')
    end
  end

  describe '.record_started!' do
    it 'updates created_at to the new start time on re-record' do
      described_class.record_started!(:backup)

      travel 5.seconds
      described_class.record_started!(:backup)

      expect(described_class.find_by(kind: :backup).created_at).to be_within(1.second).of(Time.current)
    end

    it 'wipes a previous error message and finish stamp' do
      described_class.record_error!(:backup, 'oops')
      described_class.record_finished!(:backup)

      described_class.record_started!(:backup)

      row = described_class.find_by(kind: :backup)
      expect(row.last_error_message).to be_nil
      expect(row.last_finished_at).to be_nil
    end

    it 'defaults automatic to false and records it when set' do
      described_class.record_started!(:backup)
      expect(described_class.find_by(kind: :backup).automatic).to be(false)

      described_class.record_started!(:backup, automatic: true)
      expect(described_class.find_by(kind: :backup).automatic).to be(true)
    end

    it 'preserves the automatic flag through finish' do
      described_class.record_started!(:backup, automatic: true)
      described_class.record_finished!(:backup)

      expect(described_class.find_by(kind: :backup).automatic).to be(true)
    end
  end

  describe '.latest_completion' do
    it 'returns the most recently finished row, skipping never-finished kinds' do
      described_class.record_started!(:backup)
      described_class.record_finished!(:backup)
      described_class.record_error!(:restore, 'oops') # row exists but no finish stamp

      row = described_class.latest_completion(%i[backup restore])

      expect(row.kind.to_sym).to eq(:backup)
      expect(row.last_finished_at).to be_within(1.second).of(Time.current)
    end

    it 'still returns a row days after the finish — the card sticks until the user dismisses' do
      described_class.record_finished!(:backup)
      travel 3.days

      expect(described_class.latest_completion(%i[backup restore])).to be_present
    end

    it 'picks the most recently finished kind when several rows exist' do
      described_class.record_finished!(:backup)
      travel 1.second
      described_class.record_finished!(:restore)

      row = described_class.latest_completion(%i[backup restore])
      expect(row.kind.to_sym).to eq(:restore)
    end
  end

  describe '.clear!' do
    it 'deletes the row so no phantom record lingers' do
      described_class.record_error!(:backup, 'oops')

      expect { described_class.clear!(:backup) }.to change(described_class, :count).by(-1)
      expect(described_class.message_for(:backup)).to be_nil
    end

    it 'also drops the row of a failed run so the completion card disappears' do
      described_class.record_error!(:backup, 'oops')
      described_class.record_finished!(:backup)

      described_class.clear!(:backup)

      expect(described_class.find_by(kind: :backup)).to be_nil
    end

    it 'also drops the row of a successful run (no error message present)' do
      described_class.record_started!(:backup)
      described_class.record_finished!(:backup)

      described_class.clear!(:backup)

      expect(described_class.find_by(kind: :backup)).to be_nil
    end

    it 'is a no-op when no row exists for the kind' do
      expect { described_class.clear!(:backup) }.not_to raise_error
      expect(described_class.message_for(:backup)).to be_nil
    end
  end
end
