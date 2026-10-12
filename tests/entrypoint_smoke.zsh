#!/bin/zsh --no-rcs

# Sources ReEnroll.sh without running it (main is skipped when sourced) and
# checks the credential-loading rules from AGENTS.md: keychain first, and
# script-parameter credentials only behind the explicit compatibility switch.

# Production ReEnroll runs without nounset/errexit, so the test sources it the
# same way.
set -o pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
work_dir="$(/usr/bin/mktemp -d /tmp/reenroll-entrypoint.XXXXXX)"
typeset -ga sourced_temp_files
trap '/bin/rm -rf -- "${work_dir}" "${sourced_temp_files[@]}"' EXIT

# Sourcing runs ReEnroll's startup assignments, which create two dialog logs
# in /var/tmp; record them so the EXIT trap removes them.
function source_reenroll() {
    source "${repo_root}/ReEnroll.sh"
    sourced_temp_files+=("${dialogLog}" "${updateDialogLog}")
    scriptLog="${work_dir}/ReEnroll.log"
}

source_reenroll

failures=0
function assert_eq() {
    if [[ "$1" != "$2" ]]; then
        print -u2 -- "Assertion failed: $3"
        print -u2 -- "Expected: $2"
        print -u2 -- "Actual:   $1"
        (( failures += 1 ))
    fi
}

function reset_credentials() {
    client_id=""
    client_secret=""
    parameter_client_id="param-id"
    parameter_client_secret="param-secret"
    reenrollCredentialReader=""
    reenrollAllowSecurityCliCredentialReader="false"
    reenrollAllowParameterCredentials="false"
}

reset_credentials
output="$(loadApiCredentials 2>&1)"
loadApiCredentials >/dev/null 2>&1
assert_eq "$?" "1" "loadApiCredentials should fail without keychain credentials or the compatibility switch"
assert_eq "${client_id}" "" "parameter credentials must not be used unless explicitly allowed"
[[ "${output}" == *"Ignoring Jamf API credentials supplied in script parameters"* ]] || {
    print -u2 -- "Assertion failed: ignored parameter credentials should be reported"; (( failures += 1 )); }

reset_credentials
reenrollAllowParameterCredentials="true"
loadApiCredentials >/dev/null 2>&1
assert_eq "${client_id}:${client_secret}" "param-id:param-secret" "the compatibility switch should allow parameter credentials"

reset_credentials
reenrollAllowParameterCredentials="true"
function readReEnrollSecret() { print -r -- "keychain-$1"; }
loadApiCredentials >/dev/null 2>&1
assert_eq "${client_id}:${client_secret}" "keychain-JamfApiClientID:keychain-JamfApiClientSecret" "keychain credentials should take precedence over parameters"
unfunction readReEnrollSecret
source_reenroll

# A misconfigured reader must yield no secret on stdout: callers capture
# stdout, so a warning printed there would be loaded as the credential.
reset_credentials
reader="${work_dir}/reader"
print -r -- '#!/bin/sh' > "${reader}"
/bin/chmod 755 "${reader}"
reenrollCredentialReader="${reader}"
secret="$(readReEnrollSecret JamfApiClientID 2>/dev/null)"
status_code=$?
assert_eq "${status_code}" "1" "a reader not owned by root should be rejected"
assert_eq "${secret}" "" "a rejected reader must not print anything on stdout"
reenrollCredentialReader="relative/reader"
secret="$(readReEnrollSecret JamfApiClientID 2>/dev/null)"
assert_eq "${secret}" "" "a relative reader path must not print anything on stdout"

# Admin cleanup: every renew setting reaches removeAdmin, and removeAdmin
# leaves an account alone unless ReEnroll recorded promoting it.
typeset -g REMOVE_ADMIN_CALLS=0
function removeAdmin() { (( REMOVE_ADMIN_CALLS += 1 )); }
for renewProfiles in true failure false; do
    cleanupPrivileges >/dev/null 2>&1
done
assert_eq "${REMOVE_ADMIN_CALLS}" "3" "cleanupPrivileges should always call removeAdmin"
unfunction removeAdmin
source_reenroll

typeset -g DSEDITGROUP_CALLS=0
function isDryRun() { return 1; }
function dseditgroup() { (( DSEDITGROUP_CALLS += 1 )); print -r -- "yes alice is a member of admin"; }
function state_get() { print -r -- "someone-else"; }
loggedInUser="alice"
removeAdmin >/dev/null 2>&1
assert_eq "${DSEDITGROUP_CALLS}" "0" "removeAdmin must not touch an admin that ReEnroll did not promote"
source_reenroll

# The renew flow (dialog, profiles renew, LAPS deletion) runs at most once.
typeset -g RENEW_SIDE_EFFECTS=0
function isDryRun() { (( RENEW_SIDE_EFFECTS += 1 )); return 0; }
inventoryErrorRan="true"
inventoryError >/dev/null 2>&1
assert_eq "${RENEW_SIDE_EFFECTS}" "0" "inventoryError should not run a second time in one execution"
source_reenroll

if (( failures > 0 )); then
    print -u2 -- "entrypoint_smoke: ${failures} failure(s)"
    exit 1
fi
print -- "entrypoint_smoke: ok"
