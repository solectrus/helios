# `Orchestration::PROJECT_NAME` is `solectrus` in the test environment too, and
# specs that drive real Docker (runner_spec) or open a real cable connection
# (connection_spec) reach the automatic orphan removal. It would then compare
# the developer's own running stack against the spec's compose fixture, find
# every container orphaned, and delete them for real — it destroyed a local
# PostgreSQL container once before this guard existed.
#
# Specs that want the removal itself opt back in with `and_call_original`.
RSpec.configure do |config|
  config.before do
    # Class-level state, so a claim taken by one example would otherwise make
    # the next one skip its removal.
    Orchestration::PendingOperations.clear_all
    allow(Orchestration::OrphanedServices).to receive(:prune!)
  end
end
