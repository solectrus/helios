RSpec.describe Admin do
  describe '.create_admin!' do
    it 'creates admin with hashed password' do
      admin = described_class.create_admin!(password: 'secretpassword')
      expect(admin).to be_persisted
      expect(admin.password_digest).not_to eq('secretpassword')
    end

    it 'raises error if admin already exists' do
      described_class.create_admin!(password: 'first')
      expect { described_class.create_admin!(password: 'second') }.to raise_error(
        RuntimeError,
        'Admin already exists',
      )
    end
  end

  describe '.current' do
    it 'returns nil if no admin exists' do
      expect(described_class.current).to be_nil
    end

    it 'returns the admin if one exists' do
      admin = described_class.create_admin!(password: 'test')
      expect(described_class.current).to eq(admin)
    end
  end

  describe '.exists?' do
    it 'returns false if no admin exists' do
      expect(described_class.exists?).to be false
    end

    it 'returns true if admin exists' do
      described_class.create_admin!(password: 'test')
      expect(described_class.exists?).to be true
    end
  end

  describe '#authenticate' do
    let(:admin) { described_class.create_admin!(password: 'secretpassword') }

    it 'returns admin for correct password' do
      expect(admin.authenticate('secretpassword')).to eq(admin)
    end

    it 'returns false for incorrect password' do
      expect(admin.authenticate('wrongpassword')).to be false
    end
  end
end
