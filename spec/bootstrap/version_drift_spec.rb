# The installer runs as curl|bash and can't ask git for its release, so it
# hard-codes HELIOS_VERSION. The release skill bumps it on the release branch.
# This spec catches a release that forgot it: the constant must name the
# latest tag reachable from HEAD.
RSpec.describe 'bootstrap installer ↔ release tag drift' do # rubocop:disable RSpec/DescribeClass
  let(:bootstrap_version) { bootstrap_eval('printf \'%s\' "$HELIOS_VERSION"') }
  let(:latest_tag) { `git describe --tags --abbrev=0 --match 'v*' 2>/dev/null`.chomp }

  it 'names the latest release' do
    expect("v#{bootstrap_version}").to eq(latest_tag)
  end
end
