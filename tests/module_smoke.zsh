#!/bin/zsh --no-rcs

# Smoke tests for the lib/*.zsh modules.
#
# The modules are sourced once into a base environment of synthetic globals,
# logging stubs and "tripwire" stubs for the system commands that change a Mac
# (dscl, dseditgroup, launchctl, curl, kill, ...). Each test_* function below
# is one case and runs in its own subshell, so the stubs and globals a case
# changes never reach another case, and its files go in its own folder under
# a private temporary directory. A failed assertion is counted and the case
# carries on. Every case runs; the script exits 1 when an assertion failed, a
# case ended before its last line or a case reached a tripwire.
#
#   zsh tests/module_smoke.zsh                 # every case
#   zsh tests/module_smoke.zsh <name> ...      # only test_<name> ...
#
# Production ReEnroll runs without errexit or nounset, so the modules run the
# same way here. zsh runs a function named like an absolute path (for example
# /usr/bin/dscl) in place of that file, which is how a case stubs a command
# that the modules call by its full path.

set -o pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/reenroll-module-test.XXXXXX")" || exit 1
test_root="${test_root:A}"
trap '/bin/rm -rf -- "${test_root}"' EXIT

# ---------------------------------------------------------------------------
# Assertions. Each failure is counted in the case's subshell.
# ---------------------------------------------------------------------------
typeset -gi failures=0
typeset -g current_case="" case_dir="${test_root}"

function fail() {
    print -u2 -- "Assertion failed [${current_case}]: $1"
    (( failures += 1 ))
    return 1
}

function assert_eq() {
    [[ "$1" == "$2" ]] && return 0
    fail "$3"
    print -u2 -- "  Expected: $2"
    print -u2 -- "  Actual:   $1"
    return 1
}

function assert_contains() {
    [[ "$1" == *"$2"* ]] && return 0
    fail "$3"
    print -u2 -- "  Expected to find: $2"
    print -u2 -- "  Actual:           $1"
    return 1
}

function assert_not_contains() {
    [[ "$1" != *"$2"* ]] && return 0
    fail "$3"
    print -u2 -- "  Must not contain: $2"
    print -u2 -- "  Actual:           $1"
    return 1
}

function assert_true() {
    local message="$1"
    shift
    "$@" && return 0
    fail "${message}"
}

function assert_false() {
    local message="$1"
    shift
    "$@" || return 0
    fail "${message}"
}

# zsh -n expands $(<file) in arguments, so tests read files through cat.
function file_text() { /bin/cat -- "$1" 2>/dev/null; }

# ---------------------------------------------------------------------------
# Base environment, copied into every case.
# ---------------------------------------------------------------------------
typeset -gA STATE=(ComputerSiteID "100" ComputerSite "Original Site")
typeset -g LAST_DRY_RUN="" QUIT_CODE="" ERROR_LOG="" WARNING_LOG=""
typeset -ga QUIT_CALLS=()

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
serialNumber="TEST-SERIAL"
osMajorVersion="11"
jssurl="https://example.invalid/"
folder_path="${test_root}/support"
scriptLog="${folder_path}/ReEnroll.log"
reEnrollConfigFile="${folder_path}/ReEnroll.plist"
tempInventoryLog="${test_root}/inventory.log"
dialogLog="${test_root}/dialog.log"
updateDialogLog="${test_root}/update-dialog.log"
# Function names: a case reaching swiftDialog trips the tripwire below.
dialogBinary="unexpected_dialog"
dialogAppPath="${test_root}/no-such-Dialog.app"
organizationName="company"
organizationReverseDomain="com.example"
computerSiteID="100"
computerSite="Original Site"
newComputerSiteID=""
updateComputerSite="true"
scriptResult=""
errorCount=0
client_id=""
client_secret=""
APIAccess=""
apiBearerToken=""
token_expiration_epoch=0
jamfBinary=""
exempt_users=("Shared" "Guest" "tester")
targeted_users=()
slackURL=""
teamsURL=""
/bin/mkdir -p "${folder_path}"

# Stand-ins for the ReEnroll.sh functions the modules call.
function updateScriptLog() { :; }
function preFlight() { :; }
function notice() { :; }
function infoOut() { :; }
function debugVerbose() { :; }
function errorOut() { :; }
function error() { ERROR_LOG+="$1"$'\n'; (( errorCount += 1 )); }
function warning() { WARNING_LOG+="$1"$'\n'; }
function state_set() { STATE[$1]="$2"; }
function state_get() { print -r -- "${STATE[$1]-}"; }
function quitScript() {
    QUIT_CALLS+=("${1:-auto}")
    QUIT_CODE="${1:-$(( errorCount > 0 ? 1 : 0 ))}"
    return 0
}
function isDryRun() { return 0; }
function dryRunOut() { LAST_DRY_RUN="$1"; }
function liveConsoleUser() { print -r -- "${loggedInUser}"; }
function findJamfBinary() { return 1; }
function sleep() { :; }

# Tripwires: a case that needs one of these defines its own stub. Calls in a
# pipeline run in a subshell, so they are recorded in a file.
function tripwire() { print -r -- "$*" >> "${case_dir}/unexpected-commands"; return 1; }
function unexpected_dialog() { tripwire swiftDialog "$@"; }
function runAsLoggedInUser() { tripwire runAsLoggedInUser "$@"; }
function createMarkerFile() { tripwire createMarkerFile "$@"; }
function /usr/bin/dscl { tripwire /usr/bin/dscl "$@"; }
function dscl { tripwire dscl "$@"; }
function /usr/sbin/dseditgroup { tripwire /usr/sbin/dseditgroup "$@"; }
function dseditgroup { tripwire dseditgroup "$@"; }
function /bin/launchctl { tripwire /bin/launchctl "$@"; }
function launchctl { tripwire launchctl "$@"; }
function /usr/bin/curl { tripwire /usr/bin/curl "$@"; }
function curl { tripwire curl "$@"; }
function /usr/sbin/chown { tripwire /usr/sbin/chown "$@"; }
function /usr/bin/pgrep { tripwire /usr/bin/pgrep "$@"; }
function kill { tripwire kill "$@"; }
function /usr/bin/profiles { tripwire /usr/bin/profiles "$@"; }
function /usr/sbin/installer { tripwire /usr/sbin/installer "$@"; }
function tee { tripwire tee "$@"; }

source "${repo_root}/lib/dialog.zsh"
source "${repo_root}/lib/jamf_api.zsh"
source "${repo_root}/lib/launchd.zsh"
source "${repo_root}/lib/webhooks.zsh"
source "${repo_root}/lib/laps.zsh"
source "${repo_root}/lib/enrollment.zsh"

# dialog.zsh's updateDialog appends to the command file and sleeps, and
# launchd.zsh points the admin guard at /Library/LaunchDaemons.
function updateDialog() { :; }
reenrollLaunchDaemonDirectory="${test_root}/LaunchDaemons"
/bin/mkdir -p "${reenrollLaunchDaemonDirectory}"

inventory_json="$(file_text "${repo_root}/tests/fixtures/computer_inventory.json")"
laps_json="$(file_text "${repo_root}/tests/fixtures/local_admin_password.json")"

# A stand-in Jamf binary that records its arguments and exits as told.
fake_jamf="${test_root}/jamf"
print -r -- '#!/bin/sh' > "${fake_jamf}"
print -r -- 'printf "%s\n" "$*" >> "${FAKE_JAMF_LOG}"' >> "${fake_jamf}"
print -r -- 'exit "${FAKE_JAMF_EXIT:-0}"' >> "${fake_jamf}"
/bin/chmod 700 "${fake_jamf}"
export FAKE_JAMF_LOG="${test_root}/jamf-calls.log"
export FAKE_JAMF_EXIT=0

# A dscl -plist read result, parsed by the real plutil.
function fake_dscl_plist() {
    print -r -- "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>dsAttrTypeStandard:$1</key><array><string>$2</string></array></dict></plist>"
}

# Replaces curl for jamfApiRequest. Each call records its argv (one argument
# per line) in curl-argv.<n> and the config it reads on stdin in
# curl-config.<n>, writes the body of queue entry n ("status|body") to the
# --output file and prints its status; CURL_EXIT sets the exit code. The call
# runs in a pipeline subshell, so the count is kept in a file. mktemp is
# redirected so response bodies stay in the case folder.
typeset -ga CURL_QUEUE=()
function use_fake_curl() {
    CURL_QUEUE=("$@")
    : > "${case_dir}/curl-calls"
    function /usr/bin/curl {
        local -a args=("$@")
        local call index output="" response
        call=$(( $(/usr/bin/wc -l < "${case_dir}/curl-calls") + 1 ))
        print -r -- "${call}" >> "${case_dir}/curl-calls"
        print -rl -- "${args[@]}" > "${case_dir}/curl-argv.${call}"
        /bin/cat > "${case_dir}/curl-config.${call}"
        for (( index = 1; index < ${#args[@]}; index++ )); do
            [[ "${args[index]}" == "--output" ]] && output="${args[index + 1]}"
        done
        response="${CURL_QUEUE[call]:-000|}"
        [[ -n "${output}" ]] && print -rn -- "${response#*|}" > "${output}"
        print -rn -- "${response%%|*}"
        return "${CURL_EXIT:-0}"
    }
    function /usr/bin/mktemp {
        print -r -- "$*" >> "${case_dir}/mktemp-calls"
        command /usr/bin/mktemp "${case_dir}/reenroll-http.XXXXXX"
    }
}
function curl_calls() { /usr/bin/wc -l < "${case_dir}/curl-calls" | /usr/bin/tr -d '[:space:]'; }

# ---------------------------------------------------------------------------
# Dialog, JSON and status helpers
# ---------------------------------------------------------------------------
function test_version_compare() {
    assert_true "semantic versions should treat 2.10 as newer than 2.5.2" versionAtLeast "2.10.0" "2.5.2"
    assert_false "an older semantic version must not be accepted" versionAtLeast "2.4.9" "2.5.2"
}

function test_dialog_arguments_stay_literal() {
    local help_index
    title='ReEnroll; touch /tmp/should-not-run'
    helpMessage='Help $(touch /tmp/should-not-run)'
    icon="SF=test"
    overlayicon=""
    osVersionFull="26.0"
    buildReEnrollDialog
    assert_eq "${dialogReEnrollArgs[2]}" "${title}" "dialog title should remain one literal argument"
    help_index="${dialogReEnrollArgs[(i)--helpmessage]}"
    assert_eq "${dialogReEnrollArgs[help_index + 1]}" "${helpMessage}" "the help message should remain one literal argument"
}

function test_json_helpers() {
    assert_eq "$(extract_from_json "${inventory_json}" "managementId")" "mdm-12345" "extract_from_json should parse managementId"
    assert_eq "$(get_json_value "${laps_json}" "password")" "local-password-123" "get_json_value should parse password"
    assert_eq "$(get_json_path "${inventory_json}" "general.managementId")" "mdm-12345" "get_json_path should parse nested values"
}

function test_check_status() {
    check_status "202"
    assert_eq "${APIResult}" "Command Sent" "HTTP 202 should be accepted for Jamf framework redeployment"
    check_status "500"
    assert_eq "${APIResult}" "Failure" "HTTP 500 should be classified as a failure"
}

# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------
function test_jmfrdeploy_dry_run() {
    jmfrdeploy
    assert_eq "${APIAccess}" "Success" "jmfrdeploy should simulate successful API access in dry run"
    assert_eq "${management_id}" "dry-run-management-id" "jmfrdeploy should seed a dry-run management ID"
    assert_eq "${STATE[ComputerSiteID]}" "100" "jmfrdeploy should preserve the stored computer site ID in dry run"
}

function test_dry_run_simulates_mutations() {
    LAST_DRY_RUN=""
    deleteLAPSAccount
    assert_contains "${LAST_DRY_RUN}" "Would delete the LAPS account" "deleteLAPSAccount should log a dry-run delete"

    LAST_DRY_RUN=""
    reconLaunchDaemon
    assert_contains "${LAST_DRY_RUN}" "Would create and bootstrap the recon LaunchDaemon workflow" "reconLaunchDaemon should log a dry-run launchd action"

    slackURL="https://example.invalid/slack"
    teamsURL="https://example.invalid/teams"
    function /usr/bin/curl { : > "${case_dir}/curl-called"; }
    webHookMessage
    assert_false "webHookMessage should not invoke curl during dry run" test -e "${case_dir}/curl-called"

    skipLAPSAdminCheck="true"
    checkIn
    assert_eq "${jssAvailable}" "yes" "checkIn should simulate a successful JSS connection in dry run"
    assert_eq "${inventoryStatus}" "yes" "checkIn should simulate a successful inventory status in dry run"
}

function test_updated_inventory_dry_run() {
    newComputerSiteID="200"
    LAST_DRY_RUN=""
    updatedComputerInventoryInfo
    assert_eq "${QUIT_CODE}" "0" "updatedComputerInventoryInfo should exit cleanly in dry run"
    assert_contains "${LAST_DRY_RUN}" "new Jamf site ID '200'" "updatedComputerInventoryInfo should log the target site update in dry run"
}

# ---------------------------------------------------------------------------
# Profiles renew flow (inventoryError)
# ---------------------------------------------------------------------------
function test_handle_renew_profiles_option() {
    typeset -gi INVENTORY_ERROR_CALLS=0
    function inventoryError() { (( INVENTORY_ERROR_CALLS += 1 )); }
    local setting expected
    for setting expected in true 1 false 0 failure 1 other 0; do
        renewProfiles="${setting}"
        INVENTORY_ERROR_CALLS=0
        handleRenewProfilesOption
        assert_eq "${INVENTORY_ERROR_CALLS}" "${expected}" "handleRenewProfilesOption with renewProfiles=${setting}"
    done
}

function test_inventory_error_osascript_fallback() {
    typeset -ga RUN_AS_USER_ARGS=()
    function runAsLoggedInUser() { RUN_AS_USER_ARGS=("$@"); return 0; }
    function triggerEnrollment() { return 0; }
    function isDryRun() { return 1; }
    osMajorVersion="11"
    inventoryError
    assert_eq "${RUN_AS_USER_ARGS[1]-}" "/usr/bin/osascript" "fallback dialog should run in the logged-in user context"
    assert_eq "${RUN_AS_USER_ARGS[2]-}" "-e" "fallback dialog should pass an AppleScript expression"
    assert_contains "${RUN_AS_USER_ARGS[3]-}" "Jamf Update Needed" "fallback dialog should include the enrollment notice"
    assert_eq "${STATE[DeviceEnrolledStatus]-}" "Not Enrolled" "the fallback should clear the enrollment receipt"
    assert_eq "${QUIT_CODE}" "1" "inventory failure should retain its failure exit code"
}

# The swiftDialog branch, selected by macOS 12+ and dialogAppPath. quitScript
# exits in production, so only its first call is the run's exit.
function test_inventory_error_swiftdialog_branch() {
    typeset -ga RENEW_EVENTS=()
    typeset -g MOCK_RC=0 TRIGGER_EXIT=0
    function isDryRun() { return 1; }
    function jamfProfileRenew() { RENEW_EVENTS+=(dialog); return "${MOCK_RC}"; }
    function addAdmin() { RENEW_EVENTS+=(addAdmin); }
    function triggerEnrollment() { RENEW_EVENTS+=(triggerEnrollment); return "${TRIGGER_EXIT}"; }
    function deleteLAPSAccount() { RENEW_EVENTS+=(deleteLAPSAccount); }
    function checkIn() { RENEW_EVENTS+=(checkIn); }
    function runAsLoggedInUser() { RENEW_EVENTS+=(osascript); }
    function run_renew() {
        MOCK_RC="$1"
        skipCheckIN="$2"
        RENEW_EVENTS=()
        QUIT_CALLS=()
        inventoryErrorRan="false"
        deviceEnrolledReceiptRecorded="false"
        STATE=(DeviceEnrolledStatus "${3:-Enrolled Device}")
        inventoryError
    }
    dialogAppPath="${case_dir}/Dialog.app"
    /bin/mkdir -p "${dialogAppPath}"
    osMajorVersion="14"

    run_renew 0 false "Not Enrolled"
    assert_eq "${RENEW_EVENTS[*]}" "dialog addAdmin triggerEnrollment deleteLAPSAccount checkIn" "Update Now should promote, renew enrollment, delete the LAPS account, then check in"
    assert_eq "${STATE[ReEnrollRenewProfilesDialog]-}:${STATE[DeviceEnrolledStatus]-}" "Update Now:Enrolled Device" "an accepted renewal should be recorded"
    assert_eq "${QUIT_CALLS[1]-}" "auto" "Update Now should end the run with the error count's exit code"

    run_renew 0 true "Not Enrolled"
    assert_eq "${RENEW_EVENTS[*]}" "dialog addAdmin triggerEnrollment deleteLAPSAccount" "skipCheckIN=true should skip the check-in"
    assert_eq "${QUIT_CALLS[1]-}" "auto" "Update Now without a check-in should still end the run"

    TRIGGER_EXIT=1
    run_renew 0 true "Not Enrolled"
    assert_eq "${STATE[DeviceEnrolledStatus]-}" "Not Enrolled" "a renewal that could not start must not be recorded as enrolled"
    TRIGGER_EXIT=0

    local rc choice
    for rc choice in 3 "Not Now" 4 "Allowed timer to expire" 20 "Do Not Disturb enabled"; do
        run_renew "${rc}" false
        assert_eq "${RENEW_EVENTS[*]}" "dialog" "dialog exit ${rc} must not promote, renew, delete or check in"
        assert_eq "${STATE[ReEnrollRenewProfilesDialog]-}:${STATE[DeviceEnrolledStatus]-}" "${choice}:Not Enrolled" "dialog exit ${rc} should record '${choice}' and clear the enrollment receipt"
        assert_eq "${QUIT_CALLS[1]-}" "auto" "dialog exit ${rc} should end the run"
    done

    run_renew 7 false
    assert_eq "${RENEW_EVENTS[*]}" "dialog" "an unexpected dialog exit must not promote, renew, delete or check in"
    assert_eq "${QUIT_CALLS[1]-}:${STATE[DeviceEnrolledStatus]-}" "7:Not Enrolled" "an unexpected dialog exit code should become the run's exit code"

    dialogAppPath="${case_dir}/Missing.app"
    run_renew 0 false
    assert_eq "${RENEW_EVENTS[*]}" "triggerEnrollment osascript" "without the swiftDialog app the osascript notice should be used"

    dialogAppPath="${case_dir}/Dialog.app"
    osMajorVersion="11"
    run_renew 0 false
    assert_eq "${RENEW_EVENTS[*]}" "triggerEnrollment osascript" "macOS 11 should use the osascript notice"
}

# ---------------------------------------------------------------------------
# Jamf Pro API client
# ---------------------------------------------------------------------------
function test_write_curl_config() {
    local curl_config="${case_dir}/config"
    writeCurlConfig "${curl_config}" --header 'Authorization: Bearer tok"en' --get --data-urlencode 'client_secret=a\b c'
    assert_eq "$(/usr/bin/sed -n 1p "${curl_config}")" 'header = "Authorization: Bearer tok\"en"' "writeCurlConfig should escape quotes in header values"
    assert_eq "$(/usr/bin/sed -n 2p "${curl_config}")" 'get' "writeCurlConfig should pass value-less --get through"
    assert_eq "$(/usr/bin/sed -n 3p "${curl_config}")" 'data-urlencode = "client_secret=a\\b c"' "writeCurlConfig should escape backslashes in secrets"
    assert_false "writeCurlConfig should reject unsupported options" writeCurlConfig "${curl_config}" --insecure 2>/dev/null
    assert_false "writeCurlConfig should reject an option without a value" writeCurlConfig "${curl_config}" --header 2>/dev/null
}

# The client secret and bearer token reach curl only in the config streamed on
# its stdin, never in its argv (readable by every local user through ps).
function test_jamf_api_request_keeps_secrets_off_argv() {
    local secret='s3cr"et\value with space' token="tok-SECRET-123" argv config
    local -a leftovers
    function isDryRun() { return 1; }
    function date() { print -r -- 5000; }
    use_fake_curl "200|{\"access_token\":\"${token}\",\"expires_in\":600}" '200|{}'
    client_id="client-id-1"
    client_secret="${secret}"

    getAccessToken
    assert_eq "${APIAccess}:${apiBearerToken}" "Success:${token}" "getAccessToken should read the token from the response"
    assert_eq "$(curl_calls)" "2" "getAccessToken should request a token, then check it"
    assert_eq "${token_expiration_epoch}" "5599" "the token should expire expires_in seconds (less one) from now"

    argv="$(file_text "${case_dir}/curl-argv.1")"
    config="$(file_text "${case_dir}/curl-config.1")"
    assert_not_contains "${argv}" "client_secret" "the token request must not put client_secret in curl's argv"
    assert_not_contains "${argv}" "s3cr" "the client secret must not reach curl's argv"
    assert_contains "${argv}" $'--request\nPOST' "the token request should be a POST"
    assert_contains "${argv}" $'--config\n-\nhttps://example.invalid/api/oauth/token' "curl should read its options from stdin"
    assert_contains "${argv}" $'--proto\n=https' "curl should be limited to HTTPS"
    assert_contains "${config}" 'data-urlencode = "client_secret=s3cr\"et\\value with space"' "the client secret should reach curl only through its stdin config"
    assert_contains "${config}" 'data-urlencode = "client_id=client-id-1"' "the client ID should be sent in the stdin config"

    argv="$(file_text "${case_dir}/curl-argv.2")"
    config="$(file_text "${case_dir}/curl-config.2")"
    assert_not_contains "${argv}" "Bearer" "the Authorization header must not reach curl's argv"
    assert_not_contains "${argv}" "${token}" "the bearer token must not reach curl's argv"
    assert_contains "${config}" "header = \"Authorization: Bearer ${token}\"" "the bearer token should reach curl only through its stdin config"
    assert_contains "${argv}" $'--output\n'"${case_dir}/reenroll-http." "curl should write the response to a private temporary file"

    assert_eq "$(file_text "${case_dir}/mktemp-calls")" $'/var/tmp/reenroll-http.XXXXXX\n/var/tmp/reenroll-http.XXXXXX' "each response body should use a unique private temporary file"
    leftovers=("${case_dir}"/reenroll-http.*(N))
    assert_eq "${#leftovers[@]}" "0" "jamfApiRequest should remove its response body files"
    assert_eq "${JAMF_HTTP_BODY_FILE}" "" "jamfApiRequest should forget the removed body file"
}

function test_get_access_token_failures() {
    local rc
    function isDryRun() { return 1; }
    function date() { print -r -- 5000; }
    client_id="client-id-1"
    client_secret="client-secret-1"

    use_fake_curl '000|'
    CURL_EXIT=7
    ERROR_LOG=""
    getAccessToken
    rc=$?
    CURL_EXIT=0
    assert_eq "${rc}:${APIAccess}:${APIResult}" "1:Failure:Failure" "a curl failure should fail getAccessToken"
    assert_contains "${ERROR_LOG}" "HTTP 000, curl 7" "a curl failure should log the curl exit code"

    use_fake_curl '401|{"error":"invalid_client"}'
    ERROR_LOG=""
    getAccessToken
    rc=$?
    assert_eq "${rc}:${APIAccess}:${APIResult}" "1:Failure:Failure" "a rejected token request should fail getAccessToken"
    assert_contains "${ERROR_LOG}" "HTTP 401" "a rejected token request should log its HTTP status"
    assert_eq "$(curl_calls)" "1" "a rejected token request must not be followed by a token check"

    use_fake_curl '200|{"token_type":"Bearer"}'
    apiBearerToken="stale-token"
    ERROR_LOG=""
    getAccessToken
    rc=$?
    assert_eq "${rc}:${APIAccess}:${apiBearerToken}" "1:Failure:" "a response without an access token should fail getAccessToken"
    assert_contains "${ERROR_LOG}" "did not contain an access token" "a response without an access token should be logged"

    use_fake_curl '200|{"access_token":"tok","expires_in":600}' '403|{}'
    token_expiration_epoch=0
    ERROR_LOG=""
    getAccessToken
    assert_eq "${APIAccess}:${APIResult}:${token_expiration_epoch}" "Failure:Failure:0" "a token that fails its check must not be used"
    assert_contains "${ERROR_LOG}" "Invalid permissions" "a token that fails its check should be logged"

    use_fake_curl '200|{"access_token":"tok"}' '200|{}'
    getAccessToken
    assert_eq "${APIAccess}:${token_expiration_epoch}" "Success:6199" "a missing expires_in should fall back to 1200 seconds"

    use_fake_curl '200|{"access_token":"tok","expires_in":"soon"}' '200|{}'
    token_expiration_epoch=0
    getAccessToken
    assert_eq "${APIAccess}:${token_expiration_epoch}" "Success:6199" "a non-numeric expires_in should fall back to 1200 seconds"
}

function test_check_token_status_mapping() {
    local code result explanation
    function isDryRun() { return 1; }
    apiBearerToken="tok"
    use_fake_curl '200|{}' '401|{}' '403|{}' '404|{}' '500|{}'
    for code result explanation in \
        200 "Token Good" "" \
        401 "Failure" "Authentication failed" \
        403 "Failure" "Invalid permissions" \
        404 "Failure" "could not be found" \
        500 "Failure" "Unknown error. Status code: 500"; do
        ERROR_LOG=""
        check_token
        assert_eq "${apitokenCheck}:${APIResult}" "${code}:${result}" "check_token should map HTTP ${code} to ${result}"
        if [[ -z "${explanation}" ]]; then
            assert_eq "${ERROR_LOG}" "" "a valid token should not log an error"
        else
            assert_contains "${ERROR_LOG}" "${explanation}" "check_token should explain HTTP ${code}"
        fi
    done
    assert_eq "$(/usr/bin/tail -n 1 "${case_dir}/curl-argv.1")" "https://example.invalid/api/v1/auth" "check_token should call the auth endpoint"
}

# apiResponse continues to an older API version only after HTTP 400 or 404.
function test_api_response_version_fallback() {
    local rc
    typeset -ga API_RESPONSES=() API_URLS=()
    function jamfApiRequest() {
        API_URLS+=("$2")
        JAMF_HTTP_STATUS="${API_RESPONSES[1]%%|*}"
        JAMF_HTTP_BODY="${API_RESPONSES[1]#*|}"
        API_RESPONSES=("${API_RESPONSES[@]:1}")
        [[ "${JAMF_HTTP_STATUS}" == <200-299> ]]
    }

    API_RESPONSES=('404|{}' '200|{"results":[{"id":"42"}]}')
    computerID=""
    jamfInventoryApiVersion=""
    apiResponse
    assert_eq "${jamfInventoryApiVersion}" "v2" "apiResponse should fall back from a 404 on v3 to v2"
    assert_eq "${computerID}" "42" "apiResponse should read the computer ID from the v2 response"
    assert_eq "${#API_URLS[@]}" "2" "apiResponse should stop after the first successful version"

    API_URLS=()
    API_RESPONSES=('500|{}' '200|{"results":[{"id":"42"}]}')
    apiResponse
    rc=$?
    assert_eq "${rc}" "1" "apiResponse should fail on a server error"
    assert_eq "${#API_URLS[@]}" "1" "apiResponse should not try older API versions after a non-400/404 error"
}

function test_api_response_over_http() {
    local rc
    function isDryRun() { return 1; }
    apiBearerToken="tok"

    use_fake_curl '400|{}' '200|{"results":[{"id":"7"}]}'
    computerID=""
    jamfInventoryApiVersion=""
    apiResponse
    rc=$?
    assert_eq "${rc}:${jamfInventoryApiVersion}:${computerID}" "0:v2:7" "apiResponse should fall back from a 400 on v3 to v2"
    assert_eq "$(/usr/bin/tail -n 1 "${case_dir}/curl-argv.1")" "https://example.invalid/api/v3/computers-inventory" "apiResponse should try v3 first"
    assert_eq "$(/usr/bin/tail -n 1 "${case_dir}/curl-argv.2")" "https://example.invalid/api/v2/computers-inventory" "apiResponse should then try v2"
    assert_contains "$(file_text "${case_dir}/curl-config.2")" 'data-urlencode = "filter=hardware.serialNumber==\"TEST-SERIAL\""' "the serial number filter should be sent URL-encoded"

    use_fake_curl '200|{"results":[]}' '200|{"results":[{"id":"7"}]}'
    computerID=""
    jamfInventoryApiVersion=""
    ERROR_LOG=""
    apiResponse
    rc=$?
    assert_eq "${rc}:${computerID}:$(curl_calls)" "1::1" "a 200 with no results should fail without trying older API versions"
    assert_contains "${ERROR_LOG}" "HTTP 200" "a 200 with no results should be logged"
}

# validatePolicy is polled up to 120 times; each poll copies only the bytes
# appended to jamf.log since the byte offset stored in the marker file.
function test_validate_policy_reads_only_new_log_bytes() {
    local line1 line2 line3 line4 size
    function isDryRun() { return 1; }
    function /usr/bin/tail {
        [[ "${argv[-1]}" == "${jamfLogFile}" ]] && print -r -- "$*" >> "${case_dir}/log-reads"
        command /usr/bin/tail "$@"
    }
    function log_size() { /usr/bin/wc -c < "${jamfLogFile}" | /usr/bin/tr -d '[:space:]'; }
    jamfLogFile="${case_dir}/jamf.log"
    duplicate_log_dir="${case_dir}/duplicate"
    /bin/mkdir -p "${duplicate_log_dir}"
    timestamp="test"
    marker_file="${case_dir}/marker"
    print -r -- "0" > "${marker_file}"
    redeployFramework="true"
    sendEnrollmentInvitation="true"
    renewProfiles="true"
    loggedInUser="tester"
    line1='Mon Oct 12 10:00:00 TestMac jamf[100]: Checking for policy ID 1...'
    line2='Mon Oct 12 10:00:01 TestMac jamf[100]: Checking for policies triggered by "enrollmentComplete" for user "tester"...'
    line3='Mon Oct 12 10:00:02 TestMac jamf[200]: Checking for policy ID 2...'
    line4='Mon Oct 12 10:00:03 TestMac jamf[300]: No patch policies were found.'

    print -r -- "${line1}" > "${jamfLogFile}"
    validatePolicy
    size="$(log_size)"
    assert_eq "$(file_text "${marker_file}")" "${size}" "the marker should hold jamf.log's size in bytes"
    assert_eq "$(file_text "${duplicate_jamfLogFile}")" "${line1}" "the first poll should copy the log"
    assert_eq "${policyStatus}" "unknown" "an unrelated last line should leave the policy status unknown"

    print -r -- "${line2}" >> "${jamfLogFile}"
    : > "${case_dir}/log-reads"
    validatePolicy
    assert_eq "$(file_text "${case_dir}/log-reads")" "-c +$(( size + 1 )) ${jamfLogFile}" "a poll should read jamf.log only from the stored byte offset"
    size="$(log_size)"
    assert_eq "$(file_text "${marker_file}")" "${size}" "the marker should advance to the new size"
    assert_eq "$(file_text "${duplicate_jamfLogFile}")" "${line1}"$'\n'"${line2}" "each new line should be copied once"
    assert_eq "${policyStatus}" "yes" "the enrollmentComplete check-in line should verify the policy check-in"
    assert_eq "${currentPolicyStatus}" 'Checking for policies triggered by "enrollmentComplete" for user "tester"...' "the status should be the last field of the newest line"

    : > "${case_dir}/log-reads"
    validatePolicy
    assert_eq "$(file_text "${case_dir}/log-reads")" "" "an unchanged jamf.log must not be read again"
    assert_eq "$(file_text "${duplicate_jamfLogFile}")" "${line1}"$'\n'"${line2}" "an unchanged jamf.log should copy nothing"
    assert_eq "${policyStatus}" "yes" "an unchanged jamf.log should keep the last status"

    print -r -- "${line3}" > "${jamfLogFile}"
    validatePolicy
    assert_eq "$(file_text "${marker_file}")" "$(log_size)" "a replaced jamf.log should be read from its start"
    assert_eq "$(/usr/bin/tail -n 1 "${duplicate_jamfLogFile}")" "${line3}" "a replaced jamf.log should be copied"
    assert_eq "${policyStatus}" "unknown" "the status should come from the replaced log"

    renewProfiles="false"
    print -r -- "${line4}" >> "${jamfLogFile}"
    validatePolicy
    assert_eq "${policyStatus}" "yes" "with a renew option off, 'No patch policies were found.' verifies the check-in"
}

# ---------------------------------------------------------------------------
# Enrollment invitation, check-in and recon
# ---------------------------------------------------------------------------
# reEnrollInvitation checks the binary before deleting the LAPS account, and
# records the method or rotates LAPS only after a successful enrollment.
function test_reenroll_invitation() {
    local invitation_status
    typeset -gi LAPS_DELETES=0 LAPS_ROTATIONS=0
    function isDryRun() { return 1; }
    function deleteLAPSAccount() { (( LAPS_DELETES += 1 )); }
    function rotateLAPSPassword() { (( LAPS_ROTATIONS += 1 )); }
    function findJamfBinary() { return 1; }
    STATE[ReEnrollMethod]="None"
    STATE[DeviceEnrolledStatus]="Not Enrolled"
    deviceEnrolledReceiptRecorded="false"

    jamfBinary=""
    reEnrollInvitation
    invitation_status=$?
    assert_eq "${invitation_status}" "1" "reEnrollInvitation should fail without a Jamf binary"
    assert_eq "${LAPS_DELETES}" "0" "reEnrollInvitation must not delete the LAPS account when the Jamf binary is missing"
    assert_eq "${STATE[ReEnrollMethod]}" "None" "a missing Jamf binary must not be recorded as an enrollment invitation"
    assert_eq "${STATE[DeviceEnrolledStatus]}" "Not Enrolled" "a missing Jamf binary must not record the device as enrolled"

    jamfBinary="${fake_jamf}"
    FAKE_JAMF_EXIT=3
    reEnrollMethod=""
    reEnrollInvitation
    invitation_status=$?
    assert_eq "${invitation_status}" "1" "reEnrollInvitation should fail when jamf enroll fails"
    assert_eq "$(file_text "${FAKE_JAMF_LOG}")" "enroll -invitation invitation-123 -noRecon -noPolicy" "reEnrollInvitation should run jamf enroll with the invitation"
    assert_eq "${LAPS_ROTATIONS}" "0" "a failed enrollment must not rotate the LAPS password"
    assert_eq "${STATE[ReEnrollMethod]}" "None" "a failed enrollment must not be recorded as an enrollment invitation"
    assert_contains "${reEnrollMethod}" "failed" "the webhook method should report the failed invitation"
    assert_eq "${STATE[DeviceEnrolledStatus]}" "Not Enrolled" "a failed jamf enroll must not record the device as enrolled"

    FAKE_JAMF_EXIT=0
    jamfBinary=""
    function findJamfBinary() { print -r -- "${fake_jamf}"; }
    reEnrollInvitation
    assert_eq "${jamfBinary}" "${fake_jamf}" "reEnrollInvitation should find a Jamf binary installed during the run"
    assert_eq "${LAPS_ROTATIONS}" "1" "a successful enrollment should rotate the LAPS password"
    assert_eq "${STATE[ReEnrollMethod]}" "Enrollment Invitation" "a successful enrollment should be recorded"
    assert_eq "${STATE[DeviceEnrolledStatus]}" "Enrolled Device" "a successful jamf enroll should record the device as enrolled"
}

# Never the jamf process running this policy (an ancestor) or an unrelated
# jamf run; only the enrollment check-in.
function test_terminate_enrollment_checkin() {
    typeset -ga KILLED_PIDS=()
    function /usr/bin/pgrep { print -r -- 4100; print -r -- 4200; print -r -- 4300; print -r -- 4400; print -r -- 4500; }
    function /bin/ps {
        case "$*" in
            "-o ppid= -p $$") print -r -- " 4100" ;;
            "-o ppid= -p 4100") print -r -- "    1" ;;
            "-o args= -p 4100") print -r -- "/usr/local/jamf/bin/jamf policy -event enrollmentComplete" ;;
            "-o args= -p 4200") print -r -- "/usr/local/jamf/bin/jamf policy -event enrollmentComplete" ;;
            "-o args= -p 4300") print -r -- "/usr/local/jamf/bin/jamf launchDaemon -monitorUsage -enforceRestrictions" ;;
            "-o args= -p 4400") print -r -- "/usr/local/jamf/bin/jamf enroll -invitation 123 -noPolicy" ;;
            "-o args= -p 4500") print -r -- "/usr/local/jamf/bin/jamf policy -id 12" ;;
        esac
    }
    function kill { KILLED_PIDS+=("$@"); }
    terminateEnrollmentCheckIn
    assert_eq "${KILLED_PIDS[*]}" "4200 4400" "only non-ancestor enrollment jamf processes should be terminated"
}

# recon gets -endUsername only with a network user, never an empty one.
function test_checkin_recon_end_username() {
    typeset -gi TERMINATE_CALLS=0
    function isDryRun() { return 1; }
    function terminateEnrollmentCheckIn() { (( TERMINATE_CALLS += 1 )); }
    function jssConnectionStatus() { jssAvailable="yes"; }
    function validatePolicy() { policyStatus="yes"; }
    function validateInventory() { inventoryStatus="yes"; }
    skipLAPSAdminCheck="true"
    displayReEnrollDialog="false"
    tempInventoryLog="${case_dir}/inventory.log"
    jamfBinary="${fake_jamf}"

    networkUser=""
    : > "${FAKE_JAMF_LOG}"
    checkIn
    assert_eq "$(file_text "${FAKE_JAMF_LOG}")" "recon --verbose" "recon must omit -endUsername for a local account"
    assert_eq "${TERMINATE_CALLS}" "1" "checkIn should stop only the enrollment check-in"

    networkUser=$' \n'
    : > "${FAKE_JAMF_LOG}"
    checkIn
    assert_eq "$(file_text "${FAKE_JAMF_LOG}")" "recon --verbose" "recon must omit -endUsername for a blank network user"

    networkUser="netuser@example.invalid"
    : > "${FAKE_JAMF_LOG}"
    checkIn
    assert_eq "$(file_text "${FAKE_JAMF_LOG}")" "recon -endUsername netuser@example.invalid --verbose" "recon should pass the network user"
}

# The recon LaunchDaemon script follows the same rule, with the user literal.
function test_recon_daemon_script() {
    local recon_script
    sendEnrollmentInvitation="false"
    jamfBinary="/usr/local/bin/jamf"
    networkUser=""
    recon_script="$(printReconDaemonScript)"
    assert_contains "${recon_script}" "'/usr/local/bin/jamf' recon >>" "the recon daemon should run recon without -endUsername for a local account"
    assert_not_contains "${recon_script}" "recon -endUsername" "the recon daemon must not pass an empty -endUsername"

    networkUser='evil"user $(touch /tmp/should-not-run)'
    printReconDaemonScript > "${case_dir}/jamf-recon.zsh"
    assert_contains "$(file_text "${case_dir}/jamf-recon.zsh")" "recon -endUsername 'evil\"user \$(touch /tmp/should-not-run)' >>" "the recon daemon should quote the network user"
    assert_true "the generated recon daemon script should be valid zsh" zsh -n "${case_dir}/jamf-recon.zsh"
}

# ---------------------------------------------------------------------------
# Computer site
# ---------------------------------------------------------------------------
# Site restore sends the original site ID and stops on a failed lookup.
function test_site_restore() {
    local site_status inventory_moved
    typeset -ga PATCH_BODIES=()
    function isDryRun() { return 1; }
    function getAccessToken() { :; }
    function checkTokenExpiration() { :; }
    function jamfApiRequest() {
        [[ "$1" == "PATCH" ]] && PATCH_BODIES+=("${argv[-1]}")
        JAMF_HTTP_STATUS="200"
        return 0
    }
    updateComputerSite="true"
    newComputerSiteID=""
    jamfInventoryApiVersion="v3"
    inventory_moved='{"general":{"name":"Mac","site":{"id":"300","name":"Moved Site"}},"hardware":{"serialNumber":"TEST-SERIAL","model":"Test Mac"}}'

    function apiResponse() { return 1; }
    function computerIDLookup() { computerID="42"; inventoryDetailJson="${inventory_moved}"; return 0; }
    QUIT_CODE=""
    updatedComputerInventoryInfo
    site_status=$?
    assert_eq "${site_status}" "1" "updatedComputerInventoryInfo should stop when apiResponse fails"
    assert_eq "${#PATCH_BODIES[@]}" "0" "no site PATCH should be sent after a failed lookup"
    assert_eq "${STATE[ComputerSiteID]}:${STATE[ComputerSite]}" "100:Original Site" "a failed lookup must keep the recorded original site"
    assert_true "a failed lookup should end the run through quitScript" test -n "${QUIT_CODE}"

    function apiResponse() { computerID="42"; return 0; }
    function computerIDLookup() { return 1; }
    updatedComputerInventoryInfo
    site_status=$?
    assert_eq "${site_status}" "1" "updatedComputerInventoryInfo should stop when computerIDLookup fails"
    assert_eq "${#PATCH_BODIES[@]}" "0" "no site PATCH should be sent after a failed inventory lookup"

    function computerIDLookup() { inventoryDetailJson="${inventory_moved}"; return 0; }
    updatedComputerInventoryInfo
    assert_eq "${#PATCH_BODIES[@]}" "1" "a moved computer should get one site PATCH"
    assert_contains "${PATCH_BODIES[1]-}" '"siteId": "100"' "the PATCH should restore the original site ID"
    assert_eq "${computerSiteID}" "300" "the live site should still be read for comparison"
    assert_eq "${STATE[ComputerSiteID]}:${STATE[ComputerSite]}" "100:Original Site" "reading the live site must not overwrite the recorded original"

    PATCH_BODIES=()
    function computerIDLookup() {
        inventoryDetailJson='{"general":{"name":"Mac","site":{"id":"100","name":"Original Site"}},"hardware":{}}'
        return 0
    }
    updatedComputerInventoryInfo
    assert_eq "${#PATCH_BODIES[@]}" "0" "no PATCH is needed when the computer is already in its original site"

    PATCH_BODIES=()
    STATE[ComputerSiteID]="1"
    function computerIDLookup() { inventoryDetailJson="${inventory_moved}"; return 0; }
    updatedComputerInventoryInfo
    assert_contains "${PATCH_BODIES[1]-}" '"siteId": "1"' "site ID 1 is a real site and should be restored"
}

# computerInventoryInfo must not replace the recorded site with an empty one.
function test_inventory_without_site_keeps_record() {
    inventoryDetailJson='{"general":{"name":"Mac"},"hardware":{}}'
    computerInventoryInfo
    assert_eq "${STATE[ComputerSiteID]}:${STATE[ComputerSite]}" "100:Original Site" "an inventory without a site must not erase the recorded site"
}

# ---------------------------------------------------------------------------
# Webhooks
# ---------------------------------------------------------------------------
# Interpolated values are JSON-escaped and cannot add blocks.
function test_webhook_payload_escaping() {
    typeset -g SLACK_PAYLOAD="" TEAMS_PAYLOAD=""
    function isDryRun() { return 1; }
    function /usr/bin/curl {
        local payload="" url=""
        while (( $# > 0 )); do
            case "$1" in
                -d|--data) payload="$2"; shift 2; continue ;;
            esac
            url="$1"
            shift
        done
        case "${url}" in
            *slack*) SLACK_PAYLOAD="${payload}" ;;
            *teams*) TEAMS_PAYLOAD="${payload}" ;;
        esac
        return 0
    }
    slackURL="https://example.invalid/slack"
    teamsURL="https://example.invalid/teams"
    supportTeamHyperlink=""
    computerName=$'Evil "Mac" \\ <!channel>\n\t\x01'
    loggedInUserFirstname='Mallory"}]},{"type":"actions'
    loggedInUserLastname=$'Back\\slash'
    loggedInUser="tester"
    webhookStatus="ReEnroll without notification"
    reEnrollMethod="Sending Silent Enrollment Invitation"
    jamfProComputerURL="https://example.invalid/computers.html?query=TEST-SERIAL&queryType=COMPUTERS"
    webHookMessage
    assert_eq "$(get_json_path "${TEAMS_PAYLOAD}" "sections.0.facts.0.value")" "${computerName} (${serialNumber})" "Teams should carry the computer name verbatim"
    assert_eq "$(get_json_path "${TEAMS_PAYLOAD}" "sections.0.facts.2.value")" "${loggedInUserFirstname} ${loggedInUserLastname} (User ID: ${loggedInUser})" "Teams should carry the user name verbatim"
    assert_eq "$(get_json_path "${TEAMS_PAYLOAD}" "potentialAction.length")" "1" "a crafted value must not add Teams actions"
    assert_eq "$(get_json_path "${SLACK_PAYLOAD}" "blocks.length")" "4" "a crafted value must not add Slack blocks"
    assert_eq "$(get_json_path "${SLACK_PAYLOAD}" "blocks.2.fields.length")" "6" "a crafted value must not add Slack fields"
    assert_eq "$(get_json_path "${SLACK_PAYLOAD}" "blocks.2.fields.0.text")" \
        $'>*Serial Number and Computer Name:*\n>TEST-SERIAL on Evil "Mac" \\ &lt;!channel&gt;\n\t\x01' \
        "Slack mrkdwn should escape &, < and > and keep the rest verbatim"
    assert_eq "$(get_json_path "${SLACK_PAYLOAD}" "blocks.3.elements.0.url")" "${jamfProComputerURL}" "the Slack button URL should be unchanged"
}

# ---------------------------------------------------------------------------
# Admin guard LaunchDaemon
# ---------------------------------------------------------------------------
# Installed with a valid plist; removeAdminGuardDaemon removes it again.
function test_admin_guard_daemon_install() {
    local guard_label="com.example.reenroll-admin-guard" guard_plist guard_script
    typeset -ga LAUNCHCTL_CALLS=()
    function isDryRun() { return 1; }
    function /usr/sbin/chown { :; }
    function /bin/launchctl { LAUNCHCTL_CALLS+=("$*"); return 0; }
    folder_path="${case_dir}"
    reenrollLaunchDaemonDirectory="${case_dir}/LaunchDaemons"
    /bin/mkdir -p "${reenrollLaunchDaemonDirectory}"
    adminGrantMaxSeconds="3600"
    guard_plist="${reenrollLaunchDaemonDirectory}/${guard_label}.plist"
    guard_script="${case_dir}/ReEnrollAdminGuard.zsh"

    installAdminGuardDaemon
    assert_true "the admin guard plist should be valid" /usr/bin/plutil -lint -s "${guard_plist}"
    assert_eq "$(/usr/bin/plutil -extract Label raw -o - "${guard_plist}")" "${guard_label}" "the admin guard label"
    assert_eq "$(/usr/bin/plutil -extract ProgramArguments.2 raw -o - "${guard_plist}")" "${guard_script}" "the admin guard should run its script"
    assert_eq "$(/usr/bin/plutil -extract RunAtLoad raw -o - "${guard_plist}")" "true" "the admin guard should run at load and at boot"
    assert_eq "$(/usr/bin/plutil -extract StartInterval raw -o - "${guard_plist}")" "60" "the admin guard should re-check every minute"
    assert_eq "$(/usr/bin/stat -f '%OLp' "${guard_script}")" "700" "the admin guard script should be private"
    assert_true "the admin guard script should be valid zsh" zsh -n "${guard_script}"
    assert_eq "${LAUNCHCTL_CALLS[*]}" "bootout system/${guard_label} bootstrap system ${guard_plist}" "the admin guard should replace any earlier guard and bootstrap"

    removeAdminGuardDaemon
    assert_true "removeAdminGuardDaemon should delete the plist" test ! -e "${guard_plist}"
    assert_true "removeAdminGuardDaemon should delete the script" test ! -e "${guard_script}"
}

# The generated guard script demotes the recorded user only once the granting
# run has ended. It runs with its system commands stubbed; grant state lives
# in a key=value file and calls are logged to a file (it runs in a subshell).
function test_admin_guard_script() {
    local guard_label="com.example.reenroll-admin-guard" guard_status
    local guard_plist="${case_dir}/LaunchDaemons/${guard_label}.plist"
    local guard_script="${case_dir}/ReEnrollAdminGuard.zsh"
    local guard_state="${case_dir}/guard-state"
    local guard_calls="${case_dir}/guard-calls"
    scriptLog="${case_dir}/ReEnroll.log"
    writeAdminGuardScript "${guard_script}" "${guard_label}" "${guard_plist}"

    function run_guard() {
        : > "${guard_calls}"
        (
            # launchd runs the guard with zsh defaults, not this test's options.
            set +o pipefail
            function /usr/bin/defaults {
                local line
                local -a kept
                case "$1" in
                    read)
                        while IFS= read -r line; do
                            [[ "${line%%=*}" == "$3" ]] && { print -r -- "${line#*=}"; return 0; }
                        done < "${guard_state}"
                        return 1
                        ;;
                    delete)
                        while IFS= read -r line; do
                            [[ "${line%%=*}" == "$3" ]] || kept+=("${line}")
                        done < "${guard_state}"
                        print -rl -- "${kept[@]}" > "${guard_state}"
                        ;;
                esac
            }
            function /usr/sbin/sysctl { print -r -- "{ sec = ${GUARD_BOOT}, usec = 0 } Thu Jan  1 00:00:00 1970"; }
            function /bin/date { [[ "${1:-}" == "+%s" ]] && print -r -- "${GUARD_NOW}" || print -r -- "2026-01-01 00:00:00"; }
            function kill { [[ "$1" == "-0" && "$2" == "${GUARD_ALIVE_PID}" ]]; }
            function /usr/sbin/dseditgroup {
                print -r -- "dseditgroup $*" >> "${guard_calls}"
                case "$2" in
                    checkmember) [[ "${GUARD_IS_ADMIN}" == "true" ]] && print -r -- "yes $4 is a member of admin" || print -r -- "no $4 is NOT a member of admin" ;;
                    edit) return "${GUARD_EDIT_EXIT:-0}" ;;
                esac
            }
            function /bin/rm { print -r -- "rm $*" >> "${guard_calls}"; }
            function /bin/launchctl { print -r -- "launchctl $*" >> "${guard_calls}"; }
            source "${guard_script}"
        )
    }
    function set_grant() {
        print -rl -- "ReEnrollPromotedUser=alice" "ReEnrollPromotedPID=4242" "ReEnrollPromotedAt=2000" > "${guard_state}"
    }
    GUARD_BOOT=1000 GUARD_NOW=2100 GUARD_ALIVE_PID=4242 GUARD_IS_ADMIN=true GUARD_EDIT_EXIT=0

    set_grant
    run_guard
    guard_status=$?
    assert_eq "${guard_status}" "0" "the guard should wait quietly while the granting run is active"
    assert_eq "$(file_text "${guard_calls}")" "" "the guard must not demote while the granting run is active"
    assert_contains "$(file_text "${guard_state}")" "ReEnrollPromotedUser=alice" "the guard must keep the record while the run is active"

    GUARD_ALIVE_PID=1
    run_guard
    guard_status=$?
    assert_eq "${guard_status}" "0" "the guard should finish after demoting"
    assert_contains "$(file_text "${guard_calls}")" "dseditgroup -o edit -d alice -t user admin" "the guard should demote after the granting run was killed"
    assert_contains "$(file_text "${guard_calls}")" "rm -f -- ${guard_plist} ${guard_script}" "the guard should remove itself"
    assert_contains "$(file_text "${guard_calls}")" "launchctl bootout system/${guard_label}" "the guard should unload itself"
    assert_eq "$(file_text "${guard_state}")" "" "the guard should clear the grant record"

    set_grant
    GUARD_ALIVE_PID=4242 GUARD_BOOT=3000
    run_guard
    assert_contains "$(file_text "${guard_calls}")" "dseditgroup -o edit -d alice -t user admin" "the guard should demote after a restart even if the PID is reused"

    set_grant
    GUARD_BOOT=1000 GUARD_NOW=5600
    run_guard
    assert_contains "$(file_text "${guard_calls}")" "dseditgroup -o edit -d alice -t user admin" "the guard should demote once the grant exceeds the limit"

    set_grant
    GUARD_NOW=2100 GUARD_ALIVE_PID=1 GUARD_EDIT_EXIT=1
    run_guard
    guard_status=$?
    assert_eq "${guard_status}" "1" "a failed demotion should make the guard retry"
    assert_contains "$(file_text "${guard_state}")" "ReEnrollPromotedUser=alice" "a failed demotion must keep the record"
    assert_not_contains "$(file_text "${guard_calls}")" "rm -f" "a failed demotion must keep the guard installed"

    GUARD_EDIT_EXIT=0 GUARD_IS_ADMIN=false
    set_grant
    run_guard
    assert_not_contains "$(file_text "${guard_calls}")" "-o edit" "the guard must not edit the admin group for a non-admin"
    assert_eq "$(file_text "${guard_state}")" "" "the guard should clear the record when the user is no longer an admin"

    : > "${guard_state}"
    GUARD_IS_ADMIN=true
    run_guard
    assert_not_contains "$(file_text "${guard_calls}")" "dseditgroup" "the guard must not touch the admin group without a recorded grant"
    assert_contains "$(file_text "${guard_calls}")" "launchctl bootout system/${guard_label}" "the guard should remove itself when nothing is recorded"
}

# ---------------------------------------------------------------------------
# LAPS
# ---------------------------------------------------------------------------
# A stand-in local directory: dscl -plist reads print the record as a plist
# (parsed by the real plutil) and deletes are recorded, never performed. Reads
# run in a pipeline subshell, so every call is also logged to a file.
function test_delete_laps_account() {
    typeset -gA FAKE_UIDS=(managedadmin 502 alice 501 bob 504 svcaccount 300 exemptadmin 503)
    typeset -ga DSCL_DELETES=()
    typeset -g LIVE_CONSOLE="alice" DSCL_DELETE_EXIT=0 laps_delete_status=""
    function isDryRun() { return 1; }
    function /usr/bin/dscl {
        print -r -- "$*" >> "${case_dir}/dscl-calls"
        if [[ "$1" == "-plist" && "$3" == "-read" ]]; then
            local name="${4#/Users/}"
            if [[ -z "${FAKE_UIDS[$name]-}" ]]; then
                print -u2 -- "DS Error: -14136 (eDSRecordNotFound)"
                return 56
            fi
            fake_dscl_plist "$5" "${FAKE_UIDS[$name]}"
            return 0
        fi
        if [[ "$2" == "-delete" ]]; then
            DSCL_DELETES+=("$3")
            return "${DSCL_DELETE_EXIT}"
        fi
        return 1
    }
    function liveConsoleUser() { print -r -- "${LIVE_CONSOLE}"; }
    function delete_laps() {
        lapsAdminAccount="$1"
        DSCL_DELETES=()
        ERROR_LOG=""
        : > "${case_dir}/dscl-calls"
        deleteLAPSAccount
        laps_delete_status=$?
    }
    exempt_users=("Shared" "Guest" "exemptadmin" "alice")
    loggedInUser="alice"
    skipAccountDeletion="false"

    delete_laps managedadmin
    assert_eq "${laps_delete_status}:${DSCL_DELETES[*]}" "0:/Users/managedadmin" "deleteLAPSAccount should delete a valid LAPS account"
    delete_laps alice
    assert_eq "${laps_delete_status}:${#DSCL_DELETES[@]}" "1:0" "deleteLAPSAccount must not delete the console user"
    assert_contains "${ERROR_LOG}" "is the console user" "deleteLAPSAccount should log why it refused the console user"
    LIVE_CONSOLE="bob"
    delete_laps bob
    assert_eq "${laps_delete_status}:${#DSCL_DELETES[@]}" "1:0" "deleteLAPSAccount must not delete whoever owns the console now"
    LIVE_CONSOLE="alice"
    delete_laps svcaccount
    assert_eq "${laps_delete_status}:${#DSCL_DELETES[@]}" "1:0" "deleteLAPSAccount must not delete a system account"
    assert_contains "${ERROR_LOG}" "below UID 500" "deleteLAPSAccount should log the UID refusal"
    delete_laps exemptadmin
    assert_eq "${laps_delete_status}:${#DSCL_DELETES[@]}" "1:0" "deleteLAPSAccount must not delete an exempt account"
    delete_laps "../Groups/admin"
    assert_eq "${laps_delete_status}:${#DSCL_DELETES[@]}" "1:0" "deleteLAPSAccount must reject a name that is not a plain account name"
    delete_laps missingadmin
    assert_eq "${laps_delete_status}:${#DSCL_DELETES[@]}:${ERROR_LOG}" "0:0:" "a missing LAPS account is not an error and nothing is deleted"
    delete_laps ""
    assert_eq "${laps_delete_status}:$(file_text "${case_dir}/dscl-calls")" "0:" "an empty LAPS account name should be skipped without a lookup"
    DSCL_DELETE_EXIT=1
    delete_laps managedadmin
    assert_eq "${laps_delete_status}" "1" "deleteLAPSAccount should report a failed dscl delete"
    assert_contains "${ERROR_LOG}" "Unable to delete LAPS account managedadmin" "deleteLAPSAccount should log a failed dscl delete"
    DSCL_DELETE_EXIT=0

    local setting
    for setting in true ""; do
        skipAccountDeletion="${setting}"
        delete_laps managedadmin
        assert_eq "${laps_delete_status}:$(file_text "${case_dir}/dscl-calls")" "0:" "skipAccountDeletion='${setting}' must not read or delete any account"
    done
}

# A failed check sends one enrollment invitation, and the invitation's nested
# rotate/verify must not restart the loop.
function test_verify_laps_credentials_sends_one_invitation() {
    typeset -gi LAPS_CHECKS=0 LAPS_INVITES=0
    function isDryRun() { return 1; }
    function checkLAPSAccount() { (( LAPS_CHECKS += 1 )); return 1; }
    function reEnrollInvitation() { (( LAPS_INVITES += 1 )); verifyLAPSCredentials; }
    management_id="dry-run-management-id"
    lapsPassword=""
    lapsReEnrollInvitationSent="false"
    verifyLAPSCredentials
    assert_eq "${LAPS_INVITES}" "1" "verifyLAPSCredentials should send at most one enrollment invitation per run"
    assert_eq "${LAPS_CHECKS}" "4" "the outer and nested verification should each stop after two checks"
    assert_eq "${lap_Status}" "1" "verifyLAPSCredentials should report failure when the account never validates"
}

# verifyLAPSCredentials checks at once and pauses only between failed checks,
# still at most two checks per call and one invitation per run.
function test_verify_laps_credentials_timing() {
    typeset -ga LAPS_EVENTS=() LAPS_RESULTS=()
    typeset -g INVITE_NESTED="false"
    function isDryRun() { return 1; }
    function sleep() { LAPS_EVENTS+=("sleep $1"); }
    function checkLAPSAccount() {
        local result="${LAPS_RESULTS[1]:-1}"
        LAPS_EVENTS+=(check)
        LAPS_RESULTS=("${LAPS_RESULTS[@]:1}")
        return "${result}"
    }
    function reEnrollInvitation() {
        LAPS_EVENTS+=(invite)
        [[ "${INVITE_NESTED}" == "true" ]] && verifyLAPSCredentials
        return 0
    }
    function run_laps_verify() {
        LAPS_EVENTS=()
        LAPS_RESULTS=("$@")
        lapsReEnrollInvitationSent="false"
        verifyLAPSCredentials
    }

    run_laps_verify 0
    assert_eq "${LAPS_EVENTS[*]}:${lap_Status}" "check:0" "a valid LAPS account should be confirmed at once without waiting"
    run_laps_verify 1 0
    assert_eq "${LAPS_EVENTS[*]}:${lap_Status}" "check invite sleep 60 check:0" "a failed check should invite once, pause, then re-check"
    INVITE_NESTED="true"
    run_laps_verify
    assert_eq "${LAPS_EVENTS[*]}:${lap_Status}" "check invite check sleep 60 check sleep 60 check:1" "verification should stay bounded with one invitation"
    run_laps_verify 1 0
    assert_eq "${LAPS_EVENTS[*]}:${lap_Status}" "check invite check:0" "a pass in the invitation's own verification should end the outer wait"
}

function test_check_laps_account_status_runs_once() {
    typeset -gi LAPS_VERIFY_CALLS=0
    function verifyLAPSCredentials() { (( LAPS_VERIFY_CALLS += 1 )); lap_Status=0; }
    lapsAccountStatusChecked="false"
    skipLaunchDaemon="true"
    checkLAPSAccountStatus
    checkLAPSAccountStatus
    assert_eq "${LAPS_VERIFY_CALLS}" "1" "checkLAPSAccountStatus should verify LAPS credentials only once per run"
}

# validate_password reads the LAPS password from Jamf Pro and checks it
# through verifyLocalAccountPassword (osascript is a recording stub here).
function test_validate_password() {
    local rc calls_before
    typeset -ga LAPS_API_URLS=() OSA_ARGS=()
    typeset -g LAPS_API_STATUS=200 OSA_EXIT=0 OSA_USER="" OSA_PASSWORD=""
    typeset -gi OSA_CALLS=0
    function isDryRun() { return 1; }
    function checkTokenExpiration() { :; }
    function check_user_exists() { return 0; }
    function jamfApiRequest() {
        LAPS_API_URLS+=("$2")
        JAMF_HTTP_STATUS="${LAPS_API_STATUS}"
        JAMF_HTTP_BODY="${laps_json}"
        [[ "${JAMF_HTTP_STATUS}" == <200-299> ]]
    }
    # get_json_value calls the bare name, so only verifyLocalAccountPassword's
    # /usr/bin/osascript reaches this stub.
    function /usr/bin/osascript {
        (( OSA_CALLS += 1 ))
        OSA_ARGS=("$@")
        OSA_USER="${REENROLL_AUTH_USER-}"
        OSA_PASSWORD="${REENROLL_AUTH_PASSWORD-}"
        return "${OSA_EXIT}"
    }
    management_id="mdm-12345"
    lapsAdminAccount="managedadmin"

    validate_password
    assert_eq "${authResult}:${lapsPassword}" "0:local-password-123" "validate_password should accept the escrowed password"
    assert_eq "${LAPS_API_URLS[1]-}" "https://example.invalid/api/v2/local-admin-password/mdm-12345/account/managedadmin/password" "validate_password should read the escrowed password"
    assert_eq "${OSA_USER}:${OSA_PASSWORD}" "managedadmin:local-password-123" "the account and password should reach osascript through its environment"
    assert_not_contains "${OSA_ARGS[*]}" "local-password-123" "the LAPS password must not reach osascript's argv"
    assert_true "checkLAPSAccount should pass with a valid password" checkLAPSAccount

    OSA_EXIT=1
    ERROR_LOG=""
    validate_password
    assert_eq "${authResult}" "1" "a wrong password should fail validation"
    assert_contains "${ERROR_LOG}" "managedadmin authentication failed" "a wrong password should be logged"
    assert_false "checkLAPSAccount should fail with a wrong password" checkLAPSAccount

    OSA_EXIT=2
    validate_password
    assert_eq "${authResult}" "2" "a missing account record should be reported as exit 2"
    assert_false "checkLAPSAccount should fail when the account record is missing" checkLAPSAccount

    # A failed password lookup after a success must not leave the success.
    OSA_EXIT=0
    validate_password
    LAPS_API_STATUS=500
    calls_before="${OSA_CALLS}"
    validate_password
    rc=$?
    assert_eq "${rc}:${authResult}:${OSA_CALLS}" "1:1:${calls_before}" "a failed password lookup should reset authResult without checking a password"
    assert_false "checkLAPSAccount should fail after a failed password lookup" checkLAPSAccount
}

# The real OpenDirectory query, read-only: an account that does not exist
# exits 2 ($.exit needs ObjC.import("stdlib")). No real account's password is
# checked, because a wrong password counts as a failed login for that account.
function test_verify_local_account_password_lookup() {
    verifyLocalAccountPassword "reenroll-test-no-such-user-$$" "not-a-password"
    assert_eq "$?" "2" "verifyLocalAccountPassword should exit 2 when the local account does not exist"
}

function test_update_laps_password_body() {
    local rc
    typeset -ga PUT_REQUESTS=()
    typeset -g PUT_STATUS=200 PUT_BODY="" LOOKUP_EXIT=0
    function isDryRun() { return 1; }
    function checkTokenExpiration() { :; }
    function apiResponse() { return "${LOOKUP_EXIT}"; }
    function computerIDLookup() { return 0; }
    function jamfApiRequest() {
        PUT_REQUESTS+=("$1 $2")
        PUT_BODY="${argv[-1]}"
        JAMF_HTTP_STATUS="${PUT_STATUS}"
        [[ "${JAMF_HTTP_STATUS}" == <200-299> ]]
    }
    management_id="mdm-12345"
    lapsAdminAccount="managedadmin"

    updateLAPSPassword
    rc=$?
    assert_eq "${rc}:${PUT_REQUESTS[*]}" "0:PUT https://example.invalid/api/v2/local-admin-password/mdm-12345/set-password" "updateLAPSPassword should PUT the new password"
    assert_eq "${#randomPassword}" "30" "the new LAPS password should be 30 characters"
    assert_eq "$(get_json_path "${PUT_BODY}" "lapsUserPasswordList.length")" "1" "the body should be valid JSON with one account"
    assert_eq "$(get_json_path "${PUT_BODY}" "lapsUserPasswordList.0.username")" "managedadmin" "the body should name the LAPS account"
    assert_eq "$(get_json_path "${PUT_BODY}" "lapsUserPasswordList.0.password")" "${randomPassword}" "the body should carry the generated password"

    PUT_STATUS=500
    ERROR_LOG=""
    updateLAPSPassword
    rc=$?
    assert_eq "${rc}" "1" "updateLAPSPassword should fail when Jamf Pro rejects the password"
    assert_contains "${ERROR_LOG}" "HTTP 500" "a rejected password should log the HTTP status"

    PUT_REQUESTS=()
    LOOKUP_EXIT=1
    updateLAPSPassword
    rc=$?
    assert_eq "${rc}:${#PUT_REQUESTS[@]}" "1:0" "no password should be sent when the computer lookup fails"
}

# rotateLAPSPassword waits for escrow before its verification.
function test_rotate_laps_password() {
    local rc
    typeset -ga LAPS_EVENTS=() LAPS_RESULTS=()
    function isDryRun() { return 1; }
    function checkTokenExpiration() { :; }
    function sleep() { LAPS_EVENTS+=("sleep $1"); }
    function updateLAPSPassword() { LAPS_EVENTS+=(update); }
    function checkLAPSAccount() {
        local result="${LAPS_RESULTS[1]:-1}"
        LAPS_EVENTS+=(check)
        LAPS_RESULTS=("${LAPS_RESULTS[@]:1}")
        return "${result}"
    }
    function reEnrollInvitation() { LAPS_EVENTS+=(invite); }
    lapsReEnrollInvitationSent="false"
    jamfBinary="${fake_jamf}"

    LAPS_RESULTS=(0)
    rotateLAPSPassword
    assert_eq "${LAPS_EVENTS[*]}" "update sleep 10 sleep 60 check" "rotateLAPSPassword should wait for escrow, then verify once"
    assert_eq "$(file_text "${FAKE_JAMF_LOG}")" "rotateManagementAccountPassword" "rotateLAPSPassword should rotate through the Jamf binary"

    LAPS_EVENTS=()
    jamfBinary=""
    rotateLAPSPassword
    rc=$?
    assert_eq "${rc}:${LAPS_EVENTS[*]}" "1:update sleep 10" "without the Jamf binary rotateLAPSPassword should stop before verifying"
}

# ---------------------------------------------------------------------------
# The "Enrolled Device" receipt is recorded only with evidence of enrollment.
# ---------------------------------------------------------------------------
function test_enrolled_receipt() {
    typeset -ga LAPS_RESULTS=()
    typeset -g REDEPLOY_STATUS="500" POLICY_RESULT="unknown"
    function reset_receipt() {
        STATE[DeviceEnrolledStatus]="Not Enrolled"
        deviceEnrolledReceiptRecorded="false"
    }

    reset_receipt
    LAST_DRY_RUN=""
    enrollDeviceReceipt "a test"
    assert_eq "${STATE[DeviceEnrolledStatus]}" "Not Enrolled" "a dry run must not record the device as enrolled"
    assert_contains "${LAST_DRY_RUN}" "Would record the device enrolled receipt" "a dry run should log the receipt it would record"

    function isDryRun() { return 1; }
    function jamfApiRequest() {
        JAMF_HTTP_STATUS="${REDEPLOY_STATUS}"
        JAMF_HTTP_BODY="{}"
        [[ "${JAMF_HTTP_STATUS}" == <200-299> ]]
    }
    displayReEnrollDialog="false"
    computerID="42"
    reset_receipt
    redeployJamfFramework
    assert_eq "${STATE[DeviceEnrolledStatus]}" "Not Enrolled" "a rejected framework redeploy must not record the device as enrolled"
    REDEPLOY_STATUS="202"
    redeployJamfFramework
    assert_eq "${STATE[DeviceEnrolledStatus]}" "Enrolled Device" "an accepted framework redeploy should record the device as enrolled"

    # checkIn records the receipt once the policy check-in is verified, before
    # the recon that reports it. reconEndUsername runs just before the recon,
    # so it reports the receipt it saw through the recon's -endUsername.
    function jssConnectionStatus() { jssAvailable="yes"; }
    function validatePolicy() { policyStatus="${POLICY_RESULT}"; }
    function validateInventory() { inventoryStatus="yes"; }
    function terminateEnrollmentCheckIn() { :; }
    function reconEndUsername() { print -r -- "receipt:${STATE[DeviceEnrolledStatus]// /-}"; }
    jamfBinary="${fake_jamf}"
    tempInventoryLog="${case_dir}/inventory.log"
    skipLAPSAdminCheck="true"
    renewProfiles="false"
    reset_receipt
    : > "${FAKE_JAMF_LOG}"
    checkIn
    assert_eq "${STATE[DeviceEnrolledStatus]}" "Not Enrolled" "an unverified policy check-in must not record the device as enrolled"
    assert_eq "$(file_text "${FAKE_JAMF_LOG}")" "recon -endUsername receipt:Not-Enrolled --verbose" "the recon should still run after an unverified policy check-in"
    POLICY_RESULT="yes"
    reset_receipt
    : > "${FAKE_JAMF_LOG}"
    checkIn
    assert_eq "$(file_text "${FAKE_JAMF_LOG}")" "recon -endUsername receipt:Enrolled-Device --verbose" "a verified check-in should record the receipt before the recon"

    # A verified LAPS account records it; a failed verification does not.
    function checkLAPSAccount() {
        local result="${LAPS_RESULTS[1]:-1}"
        LAPS_RESULTS=("${LAPS_RESULTS[@]:1}")
        return "${result}"
    }
    skipLaunchDaemon="true"
    reset_receipt
    lapsAccountStatusChecked="false"
    lapsReEnrollInvitationSent="false"
    LAPS_RESULTS=(0)
    checkLAPSAccountStatus
    assert_eq "${STATE[DeviceEnrolledStatus]}" "Enrolled Device" "verified LAPS credentials should record the device as enrolled"
    reset_receipt
    lapsAccountStatusChecked="false"
    lapsReEnrollInvitationSent="true"
    LAPS_RESULTS=(1 1)
    checkLAPSAccountStatus
    assert_eq "${STATE[DeviceEnrolledStatus]}" "Not Enrolled" "failed LAPS verification must not record the device as enrolled"
}

# ---------------------------------------------------------------------------
# Extension attributes report each stored value in full. Each one runs under
# /bin/bash against a copy whose folder_path points at a test folder, with a
# stand-in defaults command on PATH.
# ---------------------------------------------------------------------------
function test_extension_attributes() {
    local ea_source_dir="${repo_root}/Extras/Extension Attributes"
    local ea_root="${case_dir}/ea"
    local ea_values="${case_dir}/ea/values"
    local ea_name
    local -a ea_files
    /bin/mkdir -p "${ea_root}/bin" "${ea_root}/support"
    : > "${ea_root}/support/ReEnroll.plist"
    {
        print -r -- '#!/bin/sh'
        print -r -- '[ "$1" = "read" ] || exit 1'
        print -r -- 'while IFS= read -r line; do'
        print -r -- '    case "$line" in "$3="*) printf "%s\n" "${line#*=}"; exit 0 ;; esac'
        print -r -- 'done < "$FAKE_DEFAULTS_VALUES"'
        print -r -- 'echo "The domain/default pair of ($2, $3) does not exist" >&2'
        print -r -- 'exit 1'
    } > "${ea_root}/bin/defaults"
    /bin/chmod 700 "${ea_root}/bin/defaults"
    print -rl -- \
        "ReEnrollNotificationStatus=ReEnroll with notification" \
        "DeviceEnrolledStatus=Enrolled Device" \
        "ComputerSite=College of Liberal Arts and Sciences Mac Lab" \
        "ReEnrollMethod=Redeploy Jamf Framework" \
        "ReEnrollRenewProfilesDialog=Errror: Something else happened" \
        "ReEnrollVersion=1.6.1" \
        "ReEnrollLastRun=2026-10-12 17:00:00 +0000" > "${ea_values}"

    function run_ea() {
        local ea_copy="${ea_root}/ea.sh"
        /usr/bin/sed "s|^folder_path=.*|folder_path=\"${ea_root}/support\"|" "${ea_source_dir}/$1" > "${ea_copy}"
        [[ "$(file_text "${ea_copy}")" == *"folder_path=\"${ea_root}/support\""* ]] || print -r -- "copy of $1 does not use the test folder"
        PATH="${ea_root}/bin:${PATH}" FAKE_DEFAULTS_VALUES="${ea_values}" /bin/bash "${ea_copy}" 2>"${ea_root}/stderr"
    }

    typeset -gA EA_EXPECTED=(
        "Device ReEnroll Computer Site" "<result>College of Liberal Arts and Sciences Mac Lab</result>"
        "Device ReEnroll Last Run" "<result>2026-10-12 17:00:00</result>"
        "Device ReEnroll Method" "<result>Redeploy Jamf Framework</result>"
        "Device ReEnroll Notification Status" "<result>ReEnroll with notification</result>"
        "Device ReEnroll PList" "<result>ReEnroll Property List Exists</result>"
        "Device ReEnroll Profiles Renew Status" "<result>Errror: Something else happened</result>"
        "Device ReEnroll Status" "<result>Enrolled Device</result>"
        "Device ReEnroll Version" "<result>1.6.1</result>"
    )
    ea_files=("${ea_source_dir}"/*(N.:t))
    assert_eq "${#ea_files[@]}" "${#EA_EXPECTED[@]}" "every extension attribute should have an expected result"
    for ea_name in "${ea_files[@]}"; do
        assert_eq "$(run_ea "${ea_name}")" "${EA_EXPECTED[${ea_name}]-missing expectation}" "${ea_name} should report the stored value in full"
    done

    print -r -- "ReEnrollNotificationStatus=ReEnroll without notification" > "${ea_values}"
    assert_eq "$(run_ea "Device ReEnroll Notification Status")" "<result>ReEnroll without notification</result>" "the notification status should not be truncated"
    assert_eq "$(run_ea "Device ReEnroll Status")" "<result>No last discovery</result>" "a missing status key should report the fallback"
    assert_eq "$(file_text "${ea_root}/stderr")" "" "a missing key should not leak defaults errors"
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
typeset -ga case_names failed_cases=()
if (( $# > 0 )); then
    case_names=("$@")
else
    case_names=(${${(ok)functions[(I)test_*]}#test_})
fi

for current_case in "${case_names[@]}"; do
    if (( ! ${+functions[test_${current_case}]} )); then
        print -u2 -- "No such case: test_${current_case}"
        failed_cases+=("${current_case}")
        continue
    fi
    case_dir="${test_root}/cases/${current_case}"
    /bin/mkdir -p "${case_dir}" || exit 1
    (
        FAKE_JAMF_LOG="${case_dir}/jamf-calls.log"
        : > "${FAKE_JAMF_LOG}"
        "test_${current_case}"
        if [[ -s "${case_dir}/unexpected-commands" ]]; then
            fail "unstubbed commands were reached: $(file_text "${case_dir}/unexpected-commands")"
        fi
        : > "${case_dir}/.completed"
        exit $(( failures > 0 ? 1 : 0 ))
    )
    case_exit=$?
    if [[ ! -f "${case_dir}/.completed" ]]; then
        print -u2 -- "Case ${current_case} ended before its last line (exit ${case_exit})"
        failed_cases+=("${current_case}")
    elif (( case_exit != 0 )); then
        failed_cases+=("${current_case}")
    fi
done

if (( ${#failed_cases[@]} > 0 )); then
    print -u2 -- "module_smoke: ${#failed_cases[@]} of ${#case_names[@]} case(s) failed: ${failed_cases[*]}"
    exit 1
fi
print -- "module_smoke: ok (${#case_names[@]} cases)"
