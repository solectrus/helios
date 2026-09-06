# The same hazard spec/support/orphaned_services.rb describes: every spec that
# drives a real `compose up` reaches the sweep that runs before it, and the
# sweep would then look at the developer's own `solectrus` stack instead of the
# fixture and force-remove any container of theirs that sits in no network.
#
# Specs that want the sweep itself opt back in with `and_call_original`, and
# scope it to their own project with `stub_const`.
RSpec.configure do |config|
  config.before { allow(Orchestration::DetachedContainers).to receive(:sweep) }
end
