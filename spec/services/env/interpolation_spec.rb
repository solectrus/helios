RSpec.describe Env::Interpolation do
  # Resolution itself is covered end-to-end through Env::File; what needs
  # pinning here is the scanner the importer uses to decide which variables a
  # compose file still depends on.
  describe '.references' do
    it 'finds both the braced and the bare form' do
      expect(described_class.references('${BASE_DIR}/data:$TARGET')).to eq(%w[BASE_DIR TARGET])
    end

    it 'ignores an escaped dollar, which references nothing' do
      expect(described_class.references('/data/$${LITERAL}')).to be_empty
    end

    it 'finds a reference carrying a default' do
      expect(described_class.references('${HOST_PORT:-8086}')).to eq(%w[HOST_PORT])
    end

    # Both names are dependencies: the value comes from DATA when it is set and
    # from BASE when it is not. A caller seeing only one would drop the other as
    # unreferenced and break the service that reads it.
    it 'finds names nested inside a default' do
      expect(described_class.references('${DATA:-${BASE}/x}')).to eq(%w[DATA BASE])
    end

    it 'finds a bare name inside a default' do
      expect(described_class.references('${TOKEN_EXT:-$FALLBACK}')).to eq(%w[TOKEN_EXT FALLBACK])
    end

    it 'ignores a dollar that starts no variable name' do
      expect(described_class.references('$.meters.soc')).to be_empty
    end

    it 'returns nothing for a value without references' do
      expect(described_class.references('/srv/solectrus')).to be_empty
    end
  end
end
