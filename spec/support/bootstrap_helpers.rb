require 'shellwords'

# Shared harness for the bootstrap drift specs in spec/bootstrap/. A curl|bash
# installer can't read Ruby constants, so bootstrap/install.sh hard-codes values
# that HELIOS also defines on the Ruby side. Those specs guard against drift by
# sourcing the installer in a clean shell and reading the value back out.
module BootstrapHelpers
  INSTALL_SH = Rails.root.join('bootstrap/install.sh').freeze

  # Source install.sh in a clean bash and run `snippet`, returning its stdout.
  # `env` prefixes shell statements (e.g. `unset HELIOS_IMAGE`) so the installer
  # sees a pristine environment rather than this process's. stderr is discarded
  # to keep shell noise out of the value, which is why empty output raises:
  # without it, "install.sh stopped being sourceable" would surface as a
  # confusing empty-string comparison failure instead of an actionable error.
  def bootstrap_eval(snippet, env: nil)
    script = [env, "source #{INSTALL_SH.to_s.shellescape}", snippet].compact.join('; ')
    output = `bash -c #{script.shellescape} 2>/dev/null`
    raise "`#{snippet}` produced no output (is #{INSTALL_SH} sourceable?)" if output.strip.empty?

    output
  end
end

RSpec.configure { |config| config.include BootstrapHelpers }
