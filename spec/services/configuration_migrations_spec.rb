RSpec.describe ConfigurationMigrations do
  it 'hands out the migrations above a version, in order, and none above the current one' do
    versions = described_class.pending(0).map(&:version)

    expect(versions).to eq(versions.sort.uniq)
    expect(described_class.current_version).to eq(versions.last)
    expect(described_class.pending(described_class.current_version)).to be_empty
  end
end
