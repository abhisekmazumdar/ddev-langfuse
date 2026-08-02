#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs
#
# For local tests, install bats-core, bats-assert, bats-file, bats-support
# and run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests (nothing has been released yet for this add-on):
#   bats ./tests/test.bats --filter-tags '!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=abhisekmazumdar/ddev-langfuse

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
  run ddev start -y
  assert_success
}

health_checks() {
  # .env.langfuse must have been generated with real secrets, not the
  # committed .example placeholders.
  run cat "${TESTDIR}/.ddev/.env.langfuse"
  assert_success
  refute_output --partial "changeme"
  assert_output --partial "LANGFUSE_INIT_PROJECT_PUBLIC_KEY=pk-lf-"

  # All six services should come up and the web app should become healthy.
  # Langfuse's migrations (postgres + clickhouse) can take a while on a cold
  # pull, so allow a generous window before giving up.
  webhealth=""
  for _ in $(seq 1 40); do
    webhealth="$(ddev exec -s langfuse-web "wget -qO- http://127.0.0.1:3000/api/public/health" 2>/dev/null || true)"
    if [ -n "$webhealth" ]; then
      break
    fi
    sleep 5
  done
  assert [ -n "$webhealth" ]

  # The custom host commands should exist and be executable.
  run ddev langfuse-credentials
  assert_success
  assert_output --partial "API keypair"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  # Persist TESTDIR if running inside GitHub Actions. Useful for uploading test result artifacts
  # See example at https://github.com/ddev/github-action-add-on-test#preserving-artifacts
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}
