# Loaded by every *.bats file in this directory via `load helpers`.
# Sources install.sh so its functions are available to assertions, and
# provides a tmpdir helper for tests that mutate files.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=SCRIPTDIR/../../../bootstrap/install.sh
source "$REPO_ROOT/bootstrap/install.sh"

# Switch into the per-test tmpdir bats provisions and point ENV_FILE there.
# Use from `setup()` for tests that read or write .env / compose.yaml.
in_tmpdir() {
  cd "$BATS_TEST_TMPDIR"
  ENV_FILE=".env"
}
