# The bootstrap installer refuses to install on a Docker Engine older than
# HELIOS supports, so the user learns about it before the install rather than
# from HELIOS' own 503 startup fail screen afterwards. A curl|bash installer
# can't read the Ruby constant, so it hard-codes the same floor — and this
# spec is the guard that keeps both in sync. If they drift, the installer
# either waves through a daemon HELIOS then refuses to run on, or blocks a
# host that would have worked.
RSpec.describe 'bootstrap installer ↔ MIN_ENGINE_VERSION drift' do # rubocop:disable RSpec/DescribeClass
  let(:bootstrap_min_version) { bootstrap_eval('printf \'%s\' "$MIN_ENGINE_VERSION"') }

  it 'enforces the same minimum engine version as HELIOS itself' do
    expect(bootstrap_min_version).to eq(Orchestration::Connection::MIN_ENGINE_VERSION.to_s)
  end
end
