RSpec.describe Env::File do
  let(:fixture_path) { Rails.root.join('spec/fixtures/import_scenarios/minimal/.env.bak') }
  let(:tmp_path) { Rails.root.join("tmp/test#{ENV.fetch('TEST_ENV_NUMBER', nil)}.env") }

  after { FileUtils.rm_f(tmp_path) }

  def parse(content)
    File.write(tmp_path, content)
    described_class.load(tmp_path)
  end

  describe '.load' do
    it 'loads an existing file' do
      env = described_class.load(fixture_path)
      expect(env['DATABASE_URL']).to eq('postgres://localhost/mydb')
    end

    it 'handles non-existent file' do
      env = described_class.load('/nonexistent/path/.env')
      expect(env.keys).to be_empty
    end

    context 'with a file that is not UTF-8' do
      let(:tmp_path) { Rails.root.join("tmp/latin1#{ENV.fetch('TEST_ENV_NUMBER', nil)}.env") }

      before do
        File.binwrite(tmp_path, "# Sch\xF6nes Wetter\nTZ=Europe/Berlin\nCITY=M\xFCnchen\n")
      end

      it 'parses variables instead of raising' do
        env = described_class.load(tmp_path)

        expect(env['TZ']).to eq('Europe/Berlin')
        expect(env['CITY']).to eq('München')
      end

      it 'repairs the encoding when writing the file back' do
        env = described_class.load(tmp_path)
        env.save

        expect(File.read(tmp_path)).to eq("# Schönes Wetter\nTZ=Europe/Berlin\nCITY=München\n")
      end
    end

    # The realistic case after two editors touched the same file. Repairing it
    # as a whole would rewrite the intact password as "GrÃ¼n123", and the
    # services would then no longer match their data volume.
    context 'with a file that mixes Latin-1 and UTF-8' do
      let(:tmp_path) { Rails.root.join("tmp/mixed#{ENV.fetch('TEST_ENV_NUMBER', nil)}.env") }

      before do
        File.binwrite(tmp_path, "# Sch\xF6nes Wetter\nPOSTGRES_PASSWORD=Grün123\n")
      end

      it 'leaves the already valid value untouched' do
        env = described_class.load(tmp_path)

        expect(env['POSTGRES_PASSWORD']).to eq('Grün123')
      end

      it 'keeps the value when writing the file back' do
        env = described_class.load(tmp_path)
        env.save

        expect(File.read(tmp_path)).to eq("# Schönes Wetter\nPOSTGRES_PASSWORD=Grün123\n")
      end
    end

    # Notepad calls UTF-16 LE "Unicode" and offers it right next to UTF-8.
    context 'with a UTF-16 file' do
      let(:tmp_path) { Rails.root.join("tmp/utf16#{ENV.fetch('TEST_ENV_NUMBER', nil)}.env") }

      before do
        File.binwrite(tmp_path, "\uFEFFTZ=Europe/Berlin\nCITY=München\n".encode(Encoding::UTF_16LE))
      end

      it 'parses variables instead of returning none' do
        env = described_class.load(tmp_path)

        expect(env.to_h).to eq('TZ' => 'Europe/Berlin', 'CITY' => 'München')
      end

      it 'writes the file back as UTF-8' do
        env = described_class.load(tmp_path)
        env.save

        expect(File.read(tmp_path)).to eq("TZ=Europe/Berlin\nCITY=München\n")
      end
    end

    # Editors offer "UTF-8 with BOM" (Synology's does); docker compose ignores
    # the BOM, so the first variable must not go missing here either.
    context 'with a byte order mark' do
      let(:tmp_path) { Rails.root.join("tmp/bom#{ENV.fetch('TEST_ENV_NUMBER', nil)}.env") }

      before { File.write(tmp_path, "\uFEFFTZ=Europe/Berlin\nCITY=Muenchen\n") }

      it 'parses the first variable' do
        env = described_class.load(tmp_path)

        expect(env.to_h).to eq('TZ' => 'Europe/Berlin', 'CITY' => 'Muenchen')
      end

      it 'drops the mark when writing the file back' do
        env = described_class.load(tmp_path)
        env.save

        expect(File.read(tmp_path)).to eq("TZ=Europe/Berlin\nCITY=Muenchen\n")
      end
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

  describe '#add_comment' do
    it 'adds a comment line' do
      env = described_class.new(tmp_path)
      env.add_comment('General')
      env['TZ'] = 'Europe/Berlin'

      expect(env.to_s).to eq("# General\nTZ=Europe/Berlin\n")
    end
  end

  describe '#add_blank_line' do
    it 'adds an empty line' do
      env = described_class.new(tmp_path)
      env['TZ'] = 'Europe/Berlin'
      env.add_blank_line
      env['DEBUG'] = 'true'

      expect(env.to_s).to eq("TZ=Europe/Berlin\n\nDEBUG=true\n")
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
    let(:tmp_path) { Rails.root.join("tmp/quoted#{ENV.fetch('TEST_ENV_NUMBER', nil)}.env") }

    it 'handles double-quoted values' do
      expect(parse('QUOTED="hello world"')['QUOTED']).to eq('hello world')
    end

    it 'handles single-quoted values' do
      expect(parse("QUOTED='hello world'")['QUOTED']).to eq('hello world')
    end

    it 'handles quoted values with inline comments' do
      expect(parse('QUOTED="hello" # a comment')['QUOTED']).to eq('hello')
    end

    it 'unescapes double-quoted values' do
      expect(parse('QUOTED="say \"hi\" \\\\ now"')['QUOTED']).to eq('say "hi" \\ now')
    end

    # Compose reads a quoted value across line breaks, and a donor .env holding
    # a certificate does exactly that. Stopping at the first newline would both
    # truncate the value and turn its remainder into phantom variables.
    { 'double' => '"', 'single' => "'" }.each do |style, quote|
      describe "a value spanning several lines in #{style} quotes" do
        let(:content) { %(CERT=#{quote}-----BEGIN-----\nbody\n-----END-----#{quote}\nAFTER=tail\n) }

        it 'reads the whole block as one value' do
          expect(parse(content)['CERT']).to eq("-----BEGIN-----\nbody\n-----END-----")
        end

        it 'keeps parsing the variables below it' do
          expect(parse(content).to_h.keys).to eq(%w[CERT AFTER])
        end

        it 'writes the file back unchanged' do
          env = parse(content)
          env.save

          expect(File.read(tmp_path)).to eq(content)
        end
      end
    end

    # The escaped quote must not end the value early, otherwise the rest of it
    # is mistaken for an inline comment and grafted onto the next write.
    it 'rewrites a value containing an escaped quote without leaving debris' do
      env = described_class.new(tmp_path)
      env['SECRET'] = %q(a"b'c #d)
      env.save

      reloaded = described_class.load(tmp_path)
      reloaded['SECRET'] = 'new'
      reloaded.save

      expect(File.read(tmp_path)).to eq("SECRET=new\n")
    end
  end

  # Docker Compose expands variable references while reading .env, so an
  # imported value has to be read the same way — otherwise HELIOS persists a
  # secret the running containers never saw (#377).
  describe 'variable interpolation' do
    let(:tmp_path) { Rails.root.join("tmp/interpolation#{ENV.fetch('TEST_ENV_NUMBER', nil)}.env") }

    it 'drops a reference to an undefined variable' do
      expect(parse('INFLUX_ADMIN_TOKEN=abc$myToken123')['INFLUX_ADMIN_TOKEN']).to eq('abc')
    end

    it 'resolves a reference to a variable defined earlier in the file' do
      env = parse("BASE=/srv/solectrus\nDB_VOLUME_PATH=${BASE}/postgresql\n")
      expect(env['DB_VOLUME_PATH']).to eq('/srv/solectrus/postgresql')
    end

    it 'resolves the bare $VAR form' do
      expect(parse("BASE=/srv\nPATH_=$BASE/db\n")['PATH_']).to eq('/srv/db')
    end

    it 'keeps a $$-escaped dollar as a literal' do
      expect(parse('PRICE=10$$')['PRICE']).to eq('10$')
    end

    it 'leaves a dollar that starts no variable name alone' do
      expect(parse('MAPPING_0_JSON_PATH=$.meters.soc')['MAPPING_0_JSON_PATH']).to eq('$.meters.soc')
    end

    it 'substitutes a default for an unset variable' do
      expect(parse('PORT=${HOST_PORT:-8086}')['PORT']).to eq('8086')
    end

    it 'prefers the value over the default when the variable is set' do
      expect(parse("HOST_PORT=18086\nPORT=${HOST_PORT:-8086}\n")['PORT']).to eq('18086')
    end

    # A default is a value in its own right — Compose interpolates the text it
    # falls back to, so the literal `$FALLBACK` never reaches the container.
    it 'expands a bare reference inside a default' do
      expect(parse("FALLBACK=abc\nTOKEN=${TOKEN_EXT:-$FALLBACK}\n")['TOKEN']).to eq('abc')
    end

    it 'expands a braced reference inside a default' do
      env = parse("BASE=/srv\nDB_VOLUME_PATH=${DB_DATA:-${BASE}/postgres}\n")
      expect(env['DB_VOLUME_PATH']).to eq('/srv/postgres')
    end

    it 'expands the alternative of :+ as well' do
      expect(parse("BASE=/srv\nALT=${BASE:+$BASE/data}\n")['ALT']).to eq('/srv/data')
    end

    # Only the empty string is empty to Compose. A separator of one space is a
    # set variable, and treating it as blank would invert both operators.
    it 'counts a whitespace-only value as set' do
      expect(parse("SEP=' '\nLIST=${SEP:-,}\n")['LIST']).to eq(' ')
    end

    it 'takes the alternative for a whitespace-only value' do
      expect(parse("SEP=' '\nALT=${SEP:+yes}\n")['ALT']).to eq('yes')
    end

    it 'does not interpolate inside single quotes' do
      expect(parse("TOKEN='abc$myToken123'")['TOKEN']).to eq('abc$myToken123')
    end

    it 'does interpolate inside double quotes' do
      expect(parse('TOKEN="abc$myToken123"')['TOKEN']).to eq('abc')
    end

    # Escapes and references resolve in one pass, so the backslash takes the
    # dollar out of play instead of handing a bare `$` to a second pass.
    it 'keeps a backslash-escaped reference literal' do
      env = parse(<<~ENV)
        HOME_=/root
        A="literal \\${HOME_} here"
      ENV

      expect(env['A']).to eq('literal ${HOME_} here')
    end

    # HELIOS's own .env has to survive being read back unchanged, whichever
    # quoting form the value forced. A line break is the interesting one: the
    # literal single-quoted form would span lines the parser reads separately,
    # so it has to go out escaped.
    describe 'round-trip through the writer' do
      ['abc$token', "it's secret", "quote\"and'dollar$x", 'back\\slash$y', 'plain',
       "-----BEGIN-----\nabc$def\n-----END-----", "tab\there and 'quote'",
       "carriage\rreturn'"].each do |secret|
        it "preserves #{secret.inspect}" do
          env = described_class.new(tmp_path)
          env['SECRET'] = secret
          env.save

          expect(described_class.load(tmp_path)['SECRET']).to eq(secret)
        end
      end
    end
  end
end
