# Stubs for the shell-outs the services make. `Process::Status` is a value
# object no spec should have to build by hand.
module Open3Helpers
  def process_status(success: true, exitstatus: nil)
    instance_double(Process::Status, success?: success, exitstatus: exitstatus || (success ? 0 : 1))
  end

  def stub_capture2e(output = '', success: true, exitstatus: nil)
    allow(Open3).to receive(:capture2e).and_return([output, process_status(success:, exitstatus:)])
  end
end

RSpec.configure { |config| config.include Open3Helpers }
