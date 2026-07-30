RSpec.describe TextEncoding do
  describe '.utf8' do
    it 'passes valid UTF-8 through unchanged' do
      expect(described_class.utf8('Schönes Wetter — ok')).to eq('Schönes Wetter — ok')
    end

    it 'recovers Latin-1 umlauts' do
      latin1 = "Sch\xF6nes Wetter".dup.force_encoding(Encoding::UTF_8)

      expect(described_class.utf8(latin1)).to eq('Schönes Wetter')
    end

    it 'recovers CP1252 punctuation' do
      cp1252 = "\x93quoted\x94 \x96 dash".dup.force_encoding(Encoding::UTF_8)

      expect(described_class.utf8(cp1252)).to eq('“quoted” – dash')
    end

    # A file edited by two different editors: repairing it as a whole would
    # transcode the intact umlaut a second time, into "GrÃ¼n".
    it 'keeps valid UTF-8 intact while repairing Latin-1 bytes around it' do
      mixed = "# Sch\xF6nes Wetter\nPW=Grün123\n".dup.force_encoding(Encoding::UTF_8)

      expect(described_class.utf8(mixed)).to eq("# Schönes Wetter\nPW=Grün123\n")
    end

    it 'always returns valid UTF-8, even for bytes undefined in CP1252' do
      result = described_class.utf8("\x81\x8D\x90\x9D".dup.force_encoding(Encoding::UTF_8))

      expect(result).to be_valid_encoding
      expect(result.encoding).to eq(Encoding::UTF_8)
    end

    it 'converts binary input to UTF-8' do
      result = described_class.utf8("Sch\xF6n".dup.force_encoding(Encoding::BINARY))

      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result).to eq('Schön')
    end

    it 'drops a byte order mark' do
      expect(described_class.utf8("\uFEFFTZ=Europe/Berlin")).to eq('TZ=Europe/Berlin')
    end

    it 'drops a byte order mark from content that also needs transcoding' do
      marked_latin1 = "\uFEFFCITY=M\xFCnchen".dup.force_encoding(Encoding::UTF_8)

      expect(described_class.utf8(marked_latin1)).to eq('CITY=München')
    end

    # Notepad's "Unicode" is UTF-16 LE; without decoding it, every second byte
    # is a NUL and not a single variable survives the parser.
    it 'decodes UTF-16 LE' do
      utf16 = "\uFEFFTZ=Europe/Berlin\nCITY=München\n".encode(Encoding::UTF_16LE).b

      expect(described_class.utf8(utf16)).to eq("TZ=Europe/Berlin\nCITY=München\n")
    end

    it 'decodes UTF-16 BE' do
      utf16 = "\uFEFFTZ=Europe/Berlin\nCITY=München\n".encode(Encoding::UTF_16BE).b

      expect(described_class.utf8(utf16)).to eq("TZ=Europe/Berlin\nCITY=München\n")
    end

    it 'keeps the readable part of a truncated UTF-16 file' do
      truncated = "#{"\uFEFFTZ=Europe/Berlin\n".encode(Encoding::UTF_16LE).b}C"

      expect(described_class.utf8(truncated)).to start_with("TZ=Europe/Berlin\n")
    end

    it 'keeps a mark that is not at the start' do
      expect(described_class.utf8("TZ=Europe\uFEFF")).to eq("TZ=Europe\uFEFF")
    end

    it 'handles frozen strings' do
      expect(described_class.utf8('frozen')).to eq('frozen')
    end

    it 'handles nil' do
      expect(described_class.utf8(nil)).to eq('')
    end
  end
end
