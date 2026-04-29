RSpec.describe ConfigurationMigrations::Base do
  # Define a throwaway migration class per example so the DSL can be
  # exercised in isolation without affecting the real registry.
  def migration_class(&)
    Class.new(described_class).tap { |klass| klass.class_eval(&) }
  end

  describe '.version' do
    it 'records and returns the version number' do
      klass = migration_class { version 7 }
      expect(klass.version).to eq(7)
    end

    it 'returns nil when not set' do
      klass = migration_class { nil }
      expect(klass.version).to be_nil
    end
  end

  describe '.move' do
    it 'moves a single field from one section to another' do
      klass = migration_class { move 'foo', from: 'a', to: 'b' }
      data = { 'a' => { 'foo' => 1, 'other' => 2 }, 'b' => { 'existing' => 3 } }

      result = klass.new.up(data)

      expect(result['a']).to eq('other' => 2)
      expect(result['b']).to eq('existing' => 3, 'foo' => 1)
    end

    it 'moves an array of fields' do
      klass = migration_class { move %w[foo bar], from: 'a', to: 'b' }
      data = { 'a' => { 'foo' => 1, 'bar' => 2, 'keep' => 3 } }

      result = klass.new.up(data)

      expect(result['a']).to eq('keep' => 3)
      expect(result['b']).to eq('foo' => 1, 'bar' => 2)
    end

    it 'creates the destination section if it does not exist' do
      klass = migration_class { move 'foo', from: 'a', to: 'b' }
      data = { 'a' => { 'foo' => 1 } }

      result = klass.new.up(data)

      expect(result['b']).to eq('foo' => 1)
    end

    it 'does not create the destination section when nothing was moved' do
      klass = migration_class { move 'foo', from: 'a', to: 'b' }
      data = { 'a' => { 'other' => 2 } }

      result = klass.new.up(data)

      expect(result).not_to have_key('b')
    end

    it 'does not clobber a non-nil value already at the destination' do
      klass = migration_class { move 'foo', from: 'a', to: 'b' }
      data = { 'a' => { 'foo' => 'old' }, 'b' => { 'foo' => 'new' } }

      result = klass.new.up(data)

      expect(result['b']).to eq('foo' => 'new')
      expect(result['a']).to eq({})
    end

    it 'is a no-op when the source section is missing' do
      klass = migration_class { move 'foo', from: 'a', to: 'b' }
      data = { 'b' => { 'existing' => 1 } }

      result = klass.new.up(data)

      expect(result).to eq('b' => { 'existing' => 1 })
    end

    it 'is a no-op when the field is missing in the source section' do
      klass = migration_class { move 'foo', from: 'a', to: 'b' }
      data = { 'a' => { 'other' => 2 } }

      result = klass.new.up(data)

      expect(result).to eq('a' => { 'other' => 2 })
    end

    it 'applies multiple operations in declaration order' do
      klass = migration_class do
        move 'foo', from: 'a', to: 'b'
        move 'bar', from: 'b', to: 'c'
      end
      data = { 'a' => { 'foo' => 1 }, 'b' => { 'bar' => 2 } }

      result = klass.new.up(data)

      expect(result['a']).to eq({})
      expect(result['b']).to eq('foo' => 1)
      expect(result['c']).to eq('bar' => 2)
    end

    it 'keeps operations isolated per subclass' do
      a = migration_class { move 'foo', from: 'x', to: 'y' }
      b = migration_class { move 'bar', from: 'x', to: 'y' }

      expect(a.operations.size).to eq(1)
      expect(b.operations.size).to eq(1)
    end
  end
end
