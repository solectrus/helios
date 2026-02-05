RSpec.describe Env::File do
  let(:fixture_path) { Rails.root.join('spec/fixtures/sample.env') }
  let(:tmp_path) { Rails.root.join('tmp/test.env') }

  after { FileUtils.rm_f(tmp_path) }

  describe '.load' do
    it 'loads an existing file' do
      env = described_class.load(fixture_path)
      expect(env['DATABASE_URL']).to eq('postgres://localhost/mydb')
    end

    it 'handles non-existent file' do
      env = described_class.load('/nonexistent/path/.env')
      expect(env.keys).to be_empty
    end
  end

  describe '#[]' do
    let(:env) { described_class.load(fixture_path) }

    it 'reads variable values' do
      expect(env['DATABASE_URL']).to eq('postgres://localhost/mydb')
      expect(env['REDIS_URL']).to eq('redis://localhost:6379')
    end

    it 'handles empty values' do
      expect(env['EMPTY_VALUE']).to eq('')
    end

    it 'strips inline comments from values' do
      expect(env['API_KEY']).to eq('secret123')
    end

    it 'returns nil for non-existent keys' do
      expect(env['NONEXISTENT']).to be_nil
    end
  end

  describe '#[]=' do
    let(:env) { described_class.load(fixture_path) }

    it 'updates existing variables' do
      env['DEBUG'] = 'false'
      expect(env['DEBUG']).to eq('false')
    end

    it 'adds new variables' do
      env['NEW_VAR'] = 'new_value'
      expect(env['NEW_VAR']).to eq('new_value')
    end

    it 'accepts symbol keys' do
      env[:SYMBOL_KEY] = 'value'
      expect(env['SYMBOL_KEY']).to eq('value')
    end
  end

  describe '#key?' do
    let(:env) { described_class.load(fixture_path) }

    it 'returns true for existing keys' do
      expect(env.key?('DATABASE_URL')).to be true
    end

    it 'returns false for non-existent keys' do
      expect(env.key?('NONEXISTENT')).to be false
    end
  end

  describe '#delete' do
    let(:env) { described_class.load(fixture_path) }

    it 'removes the variable' do
      env.delete('DEBUG')
      expect(env.key?('DEBUG')).to be false
    end
  end

  describe '#save' do
    it 'writes to file' do
      env = described_class.new(tmp_path)
      env['TEST_VAR'] = 'test_value'
      env.save

      expect(File.read(tmp_path)).to include('TEST_VAR=test_value')
    end

    it 'preserves full line comments' do
      FileUtils.cp(fixture_path, tmp_path)
      env = described_class.load(tmp_path)
      env['DEBUG'] = 'false'
      env.save

      content = File.read(tmp_path)
      expect(content).to include('# This is a full line comment')
      expect(content).to include('# Another comment')
      expect(content).to include('# Section: Secrets')
    end

    it 'preserves inline comments' do
      FileUtils.cp(fixture_path, tmp_path)
      env = described_class.load(tmp_path)
      env['API_KEY'] = 'new_secret'
      env.save

      content = File.read(tmp_path)
      expect(content).to include('API_KEY=new_secret # inline comment')
    end

    it 'preserves empty lines' do
      FileUtils.cp(fixture_path, tmp_path)
      env = described_class.load(tmp_path)
      env.save

      original_empty_lines = File.read(fixture_path).scan(/^\s*$/).count
      saved_empty_lines = File.read(tmp_path).scan(/^\s*$/).count
      expect(saved_empty_lines).to eq(original_empty_lines)
    end

    it 'preserves variable order' do
      FileUtils.cp(fixture_path, tmp_path)
      env = described_class.load(tmp_path)
      env['DEBUG'] = 'false'
      env.save

      content = File.read(tmp_path)
      database_pos = content.index('DATABASE_URL')
      redis_pos = content.index('REDIS_URL')
      debug_pos = content.index('DEBUG')

      expect(database_pos).to be < redis_pos
      expect(redis_pos).to be < debug_pos
    end

    it 'appends new variables at the end' do
      FileUtils.cp(fixture_path, tmp_path)
      env = described_class.load(tmp_path)
      env['NEW_VAR'] = 'new_value'
      env.save

      lines = File.readlines(tmp_path)
      expect(lines.last.strip).to eq('NEW_VAR=new_value')
    end
  end

  describe '#to_s' do
    it 'returns the content as string' do
      env = described_class.load(fixture_path)
      content = env.to_s

      expect(content).to include('DATABASE_URL=postgres://localhost/mydb')
      expect(content).to end_with("\n")
    end
  end

  describe 'quoted values' do
    let(:tmp_path) { Rails.root.join('tmp/quoted.env') }

    it 'handles double-quoted values' do
      File.write(tmp_path, 'QUOTED="hello world"')
      env = described_class.load(tmp_path)
      expect(env['QUOTED']).to eq('hello world')
    end

    it 'handles single-quoted values' do
      File.write(tmp_path, "QUOTED='hello world'")
      env = described_class.load(tmp_path)
      expect(env['QUOTED']).to eq('hello world')
    end

    it 'handles quoted values with inline comments' do
      File.write(tmp_path, 'QUOTED="hello" # a comment')
      env = described_class.load(tmp_path)
      expect(env['QUOTED']).to eq('hello')
    end
  end
end
