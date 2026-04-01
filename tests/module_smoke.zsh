#!/bin/zsh --no-rcs

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"

typeset -gA STATE
typeset -g LAST_DRY_RUN=""
typeset -g QUIT_CODE=""
typeset -g CURL_CALLED=0
typeset -g INVENTORY_ERROR_CALLED=0

DRY_RUN="true"
scriptName="ReEnroll"
scriptVersion="test"
debugMode="false"
displayReEnrollDialog="false"
redeployFramework="true"
skipLAPSAdminCheck="true"
skipLaunchDaemon="false"
skipCheckIN="false"
skipAccountDeletion="false"
renewProfiles="false"
sendEnrollmentInvitation="true"
enrollmentInvitation="invitation-123"
lapsAdminAccount="managedadmin"
uid="501"
modelName="Test Mac"
computerName="Test Computer"
loggedInUser="tester"
loggedInUserFirstname="Test"
loggedInUserLastname="User"
jamfProComputerURL="https://example.invalid/computer/1"
networkUser="tester"
tempInventoryLog="/tmp/reenroll-test-inventory.log"
jssurl="https://example.invalid/"
dialogLog="/tmp/reenroll-dialog.log"
updateDialogLog="/tmp/reenroll-update-dialog.log"
computerSiteID="100"
computerSite="Original Site"
newComputerSiteID=""
scriptResult=""
errorCount=0
client_id=""
client_secret=""
APIAccess=""
apiBearerToken=""
token_expiration_epoch=0

STATE[ComputerSiteID]="100"
STATE[ComputerSite]="Original Site"

function updateScriptLog() { :; }
function preFlight() { :; }
function notice() { :; }
function infoOut() { :; }
function debugVerbose() { :; }
function errorOut() { :; }
function error() { :; }
function warning() { :; }
function updateDialog() { :; }
function state_set() { STATE[$1]="$2"; }
function state_get() { print -r -- "${STATE[$1]-}"; }
function quitScript() { QUIT_CODE="$1"; return 0; }
function isDryRun() { return 0; }
function dryRunOut() { LAST_DRY_RUN="$1"; }
function curl() { CURL_CALLED=1; return 0; }

function assert_eq() {
    local actual="$1"
    local expected="$2"
    local message="$3"
    if [[ "${actual}" != "${expected}" ]]; then
        print -u2 -- "Assertion failed: ${message}"
        print -u2 -- "Expected: ${expected}"
        print -u2 -- "Actual:   ${actual}"
        exit 1
    fi
}

function assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        print -u2 -- "Assertion failed: ${message}"
        print -u2 -- "Expected to find: ${needle}"
        print -u2 -- "Actual:           ${haystack}"
        exit 1
    fi
}

source "${repo_root}/lib/dialog.zsh"
source "${repo_root}/lib/jamf_api.zsh"
source "${repo_root}/lib/launchd.zsh"
source "${repo_root}/lib/webhooks.zsh"
source "${repo_root}/lib/laps.zsh"
source "${repo_root}/lib/enrollment.zsh"

inventory_json="$(<"${repo_root}/tests/fixtures/computer_inventory.json")"
laps_json="$(<"${repo_root}/tests/fixtures/local_admin_password.json")"

assert_eq "$(extract_from_json "${inventory_json}" "managementId")" "mdm-12345" "extract_from_json should parse managementId"
assert_eq "$(get_json_value "${laps_json}" "password")" "local-password-123" "get_json_value should parse password"

jmfrdeploy
assert_eq "${APIAccess}" "Success" "jmfrdeploy should simulate successful API access in dry run"
assert_eq "${management_id}" "dry-run-management-id" "jmfrdeploy should seed a dry-run management ID"
assert_eq "${STATE[ComputerSiteID]}" "100" "jmfrdeploy should preserve the stored computer site ID in dry run"

LAST_DRY_RUN=""
deleteLAPSAccount
assert_contains "${LAST_DRY_RUN}" "Would delete the LAPS account" "deleteLAPSAccount should log a dry-run delete"

LAST_DRY_RUN=""
reconLaunchDaemon
assert_contains "${LAST_DRY_RUN}" "Would create and bootstrap the recon LaunchDaemon workflow" "reconLaunchDaemon should log a dry-run launchd action"

slackURL="https://example.invalid/slack"
teamsURL="https://example.invalid/teams"
CURL_CALLED=0
webHookMessage
assert_eq "${CURL_CALLED}" "0" "webHookMessage should not invoke curl during dry run"

function inventoryError() {
    INVENTORY_ERROR_CALLED=1
    return 0
}

renewProfiles="true"
INVENTORY_ERROR_CALLED=0
handleRenewProfilesOption
assert_eq "${INVENTORY_ERROR_CALLED}" "1" "handleRenewProfilesOption should route true to inventoryError"

renewProfiles="false"
INVENTORY_ERROR_CALLED=0
handleRenewProfilesOption
assert_eq "${INVENTORY_ERROR_CALLED}" "0" "handleRenewProfilesOption should not call inventoryError when renewProfiles is false"

skipLAPSAdminCheck="true"
checkIn
assert_eq "${jssAvailable}" "yes" "checkIn should simulate a successful JSS connection in dry run"
assert_eq "${inventoryStatus}" "yes" "checkIn should simulate a successful inventory status in dry run"

newComputerSiteID="200"
LAST_DRY_RUN=""
QUIT_CODE=""
updatedComputerInventoryInfo
assert_eq "${QUIT_CODE}" "0" "updatedComputerInventoryInfo should exit cleanly in dry run"
assert_contains "${LAST_DRY_RUN}" "new Jamf site ID '200'" "updatedComputerInventoryInfo should log the target site update in dry run"

print -- "module_smoke: ok"
