load helpers

setup() { in_tmpdir; }

@test "ensure_docker_access prints a green check when the daemon is reachable" {
  docker() { return 0; }
  run ensure_docker_access
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"reachable"* ]]
}

@test "ensure_docker_access hints at the docker group for a non-root user outside it" {
  docker() { return 1; }
  id() {
    case "$1" in
      -u)  echo 1000 ;;
      -un) echo alice ;;
      -Gn) echo "alice users sudo" ;;
    esac
  }
  run ensure_docker_access
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"usermod -aG docker alice"* ]]
}

@test "ensure_docker_access suggests starting the daemon when the user is already in the group" {
  docker() { return 1; }
  id() {
    case "$1" in
      -u)  echo 1000 ;;
      -un) echo alice ;;
      -Gn) echo "alice users docker" ;;
    esac
  }
  run ensure_docker_access
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"systemctl start docker"* ]]
}

@test "ensure_docker_access suggests starting the daemon for root" {
  docker() { return 1; }
  id() {
    case "$1" in
      -u)  echo 0 ;;
      -un) echo root ;;
      -Gn) echo "root" ;;
    esac
  }
  run ensure_docker_access
  [ "$status" -ne 0 ]
  [[ "$output" == *"systemctl start docker"* ]]
  [[ "$output" != *"usermod"* ]]
}
