RSpec.describe ConnectionTesting do
  describe '.run' do
    it 'reports an error for an unknown target' do
      expect(described_class.run(target: 'nope', check: 'reachability', values: {}))
        .to have_attributes(ok: false, reason: :error)
    end
  end
end
