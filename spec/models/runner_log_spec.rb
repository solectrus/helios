# == Schema Information
#
# Table name: runner_logs
# Database name: primary
#
#  id                 :integer          not null, primary key
#  kind               :string           not null
#  last_error_message :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_runner_logs_on_kind  (kind) UNIQUE
#
RSpec.describe RunnerLog do
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

  describe '.clear!' do
    it 'wipes the message but leaves the row in place' do
      described_class.record_error!(:backup, 'oops')

      expect { described_class.clear!(:backup) }.not_to change(described_class, :count)
      expect(described_class.message_for(:backup)).to be_nil
    end

    it 'is a no-op when no row exists for the kind' do
      expect { described_class.clear!(:backup) }.not_to raise_error
      expect(described_class.message_for(:backup)).to be_nil
    end
  end
end
