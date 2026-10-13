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

# A root-owned reader must also be neither group- nor world-writable and must
# pass codesign. stat and codesign are stubs (the fixture reader is not
# root-owned); the reader records each run, so a rejected reader is never run.
reader_runs="${work_dir}/reader-runs"
codesign_calls="${work_dir}/codesign-calls"
{
    print -r -- '#!/bin/sh'
    print -r -- "echo run >> '${reader_runs}'"
    print -r -- 'echo "secret-for-$1-$2"'
} > "${reader}"
/bin/chmod 755 "${reader}"
typeset -g STAT_OWNER="root" STAT_MODE="755" CODESIGN_EXIT=0
function /usr/bin/stat {
    case "$2" in
        %Su) print -r -- "${STAT_OWNER}" ;;
        %OLp) print -r -- "${STAT_MODE}" ;;
        *) return 1 ;;
    esac
}
function /usr/bin/codesign { print -r -- "$*" >> "${codesign_calls}"; return "${CODESIGN_EXIT}"; }
function read_secret_with() {
    STAT_OWNER="$1" STAT_MODE="$2" CODESIGN_EXIT="$3"
    : > "${reader_runs}"
    : > "${codesign_calls}"
    reenrollCredentialReader="${reader}"
    secret="$(readReEnrollSecret JamfApiClientID 2>/dev/null)"
    secret_status=$?
    reader_ran="$(/bin/cat -- "${reader_runs}")"
}
for mode in 775 757 722; do
    read_secret_with root "${mode}" 0
    assert_eq "${secret_status}:${secret}:${reader_ran}" "1::" "a group- or world-writable reader (mode ${mode}) must be rejected without running it"
    assert_eq "$(/bin/cat -- "${codesign_calls}")" "" "a writable reader (mode ${mode}) should be rejected before codesign"
done
read_secret_with root "rwx" 0
assert_eq "${secret_status}:${secret}:${reader_ran}" "1::" "an unreadable reader mode must be rejected"
read_secret_with admin 755 0
assert_eq "${secret_status}:${secret}:${reader_ran}" "1::" "a reader owned by another user must be rejected"
read_secret_with root 755 1
assert_eq "${secret_status}:${secret}:${reader_ran}" "1::" "a reader without a valid signature must be rejected without running it"
assert_eq "$(/bin/cat -- "${codesign_calls}")" "--verify --strict ${reader}" "the reader's signature should be verified strictly"
read_secret_with root 755 0
assert_eq "${secret_status}:${secret}:${reader_ran}" "0:secret-for-JamfApiClientID-ReEnroll:run" "a root-owned, signed, non-writable reader should supply the secret"
reset_credentials
reenrollCredentialReader="${reader}"
loadApiCredentials >/dev/null 2>&1
assert_eq "${client_id}:${client_secret}" "secret-for-JamfApiClientID-ReEnroll:secret-for-JamfApiClientSecret-ReEnroll" "loadApiCredentials should load both credentials from a valid reader"
unfunction /usr/bin/stat /usr/bin/codesign
source_reenroll

# syncRuntimeUserConfig drops empty exempt_users entries (the default list
# holds "$loggedInUser" before the console user is known) and exempts the
# console user once.
exempt_users=("Shared" "Guest" "")
loggedInUser="alice"
syncRuntimeUserConfig
assert_eq "${(j:|:)exempt_users}" "Shared|Guest|alice" "syncRuntimeUserConfig should drop empty entries and exempt the console user"
exempt_users=("Shared" "alice" "" "Guest")
syncRuntimeUserConfig
assert_eq "${(j:|:)exempt_users}" "Shared|alice|Guest" "syncRuntimeUserConfig should not add the console user twice"
exempt_users=("" "Guest" "")
loggedInUser=""
syncRuntimeUserConfig
assert_eq "${(j:|:)exempt_users}" "Guest" "without a console user syncRuntimeUserConfig should only drop empty entries"
source_reenroll

# createLastLogPosition starts the jamf.log copy that validatePolicy continues:
# it copies the log and stores the log's size in bytes as the offset.
jamfLogFile="${work_dir}/jamf.log"
print -rl -- "Mon Oct 12 10:00:00 TestMac jamf[100]: first line" "Mon Oct 12 10:00:01 TestMac jamf[100]: second line" > "${jamfLogFile}"
duplicate_log_dir="${work_dir}/duplicate"
/bin/mkdir -p "${duplicate_log_dir}"
marker_file="${work_dir}/marker"
: > "${marker_file}"
createLastLogPosition >/dev/null 2>&1
assert_eq "$(/bin/cat -- "${marker_file}")" "$(/usr/bin/wc -c < "${jamfLogFile}" | /usr/bin/tr -d '[:space:]')" "createLastLogPosition should store jamf.log's size in bytes"
assert_eq "$(/bin/cat -- "${duplicate_jamfLogFile}")" "$(/bin/cat -- "${jamfLogFile}")" "createLastLogPosition should copy the log"
source_reenroll

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

# Durable demotion. Grant state lives in ADMIN_STATE; every dseditgroup,
# guard and launchd call is a stub that records what it was asked to do.
typeset -gA ADMIN_STATE
typeset -ga ADMIN_EVENTS
function stub_admin_environment() {
    ADMIN_STATE=()
    ADMIN_EVENTS=()
    function isDryRun() { return 1; }
    function updateDialog() { :; }
    function state_set() { ADMIN_STATE[$1]="$2"; }
    function state_get() { print -r -- "${ADMIN_STATE[$1]-}"; }
    function state_delete() { unset "ADMIN_STATE[$1]"; }
    function dseditgroup() {
        if [[ " ${ADMIN_MEMBERS} " == *" $4 "* ]]; then
            print -r -- "yes $4 is a member of admin"
        else
            print -r -- "no $4 is NOT a member of admin"
        fi
    }
    function /usr/sbin/dseditgroup { ADMIN_EVENTS+=("dseditgroup $*"); return "${ADMIN_EDIT_EXIT:-0}"; }
    function installAdminGuardDaemon() {
        ADMIN_EVENTS+=("guard user=${ADMIN_STATE[ReEnrollPromotedUser]-} pid=${ADMIN_STATE[ReEnrollPromotedPID]-}")
        return "${ADMIN_GUARD_EXIT:-0}"
    }
    function removeAdminGuardDaemon() { ADMIN_EVENTS+=("remove-guard"); }
}

# addAdmin records the grant and arms the guard before promoting.
stub_admin_environment
ADMIN_MEMBERS="" ADMIN_GUARD_EXIT=0 ADMIN_EDIT_EXIT=0
loggedInUser="alice"
addAdmin >/dev/null 2>&1
assert_eq "${ADMIN_EVENTS[1]-}" "guard user=alice pid=${reEnrollPID}" "addAdmin should record the grant and arm the guard first"
assert_eq "${ADMIN_EVENTS[2]-}" "dseditgroup -o edit -a alice -t user admin" "addAdmin should promote only after arming the guard"
[[ "${ADMIN_STATE[ReEnrollPromotedAt]-}" == <1-> ]] || {
    print -u2 -- "Assertion failed: addAdmin should record when it granted admin rights"; (( failures += 1 )); }

# No guard, no promotion.
stub_admin_environment
ADMIN_GUARD_EXIT=1
addAdmin >/dev/null 2>&1
assert_eq "$?" "1" "addAdmin should fail when the admin guard cannot be armed"
[[ "${ADMIN_EVENTS[*]}" != *"-o edit -a"* ]] || {
    print -u2 -- "Assertion failed: addAdmin must not promote without the admin guard"; (( failures += 1 )); }
assert_eq "${ADMIN_STATE[ReEnrollPromotedUser]-}" "" "addAdmin should clear the record when it does not promote"
ADMIN_GUARD_EXIT=0

# A pre-existing administrator is never recorded, so never demoted.
stub_admin_environment
ADMIN_MEMBERS="alice"
addAdmin >/dev/null 2>&1
assert_eq "${#ADMIN_EVENTS[@]}:${ADMIN_STATE[ReEnrollPromotedUser]-}" "0:" "addAdmin must not record or arm the guard for an existing administrator"

# removeAdmin (EXIT trap) demotes only a grant this run recorded.
stub_admin_environment
ADMIN_MEMBERS="alice"
ADMIN_STATE=(ReEnrollPromotedUser alice ReEnrollPromotedPID "${reEnrollPID}" ReEnrollPromotedAt 1)
removeAdmin >/dev/null 2>&1
assert_eq "${ADMIN_EVENTS[*]}" "dseditgroup -o edit -d alice -t user admin remove-guard" "removeAdmin should demote this run's grant and remove the guard"
assert_eq "${(k)ADMIN_STATE}" "" "removeAdmin should clear the grant record"

stub_admin_environment
ADMIN_MEMBERS="alice"
ADMIN_STATE=(ReEnrollPromotedUser alice ReEnrollPromotedPID 999999 ReEnrollPromotedAt 1)
removeAdmin >/dev/null 2>&1
assert_eq "${#ADMIN_EVENTS[@]}" "0" "removeAdmin must leave a grant recorded by another run to that run and the guard"

# A failed demotion keeps the record and the guard so the guard retries.
stub_admin_environment
ADMIN_MEMBERS="alice" ADMIN_EDIT_EXIT=1
ADMIN_STATE=(ReEnrollPromotedUser alice ReEnrollPromotedPID "${reEnrollPID}" ReEnrollPromotedAt 1)
removeAdmin >/dev/null 2>&1
assert_eq "${ADMIN_STATE[ReEnrollPromotedUser]-}:${ADMIN_EVENTS[*]}" "alice:dseditgroup -o edit -d alice -t user admin" "a failed demotion must keep the record and the guard"
ADMIN_EDIT_EXIT=0

# Startup revokes a grant left by a killed run, whoever is logged in now and
# whatever renewProfiles is set to.
for renewProfiles in true failure false; do
    stub_admin_environment
    function adminGrantRunActive() { return 1; }
    ADMIN_MEMBERS="bob"
    loggedInUser=""
    ADMIN_STATE=(ReEnrollPromotedUser bob ReEnrollPromotedPID 999999 ReEnrollPromotedAt 1)
    revokeStaleAdminGrant >/dev/null 2>&1
    assert_eq "${ADMIN_EVENTS[*]}" "dseditgroup -o edit -d bob -t user admin remove-guard" "startup should revoke a stale grant (renewProfiles=${renewProfiles})"
    assert_eq "${ADMIN_STATE[ReEnrollPromotedUser]-}" "" "startup should clear a stale grant record (renewProfiles=${renewProfiles})"
done

stub_admin_environment
function adminGrantRunActive() { return 0; }
ADMIN_MEMBERS="bob"
ADMIN_STATE=(ReEnrollPromotedUser bob ReEnrollPromotedPID 999999 ReEnrollPromotedAt 1)
revokeStaleAdminGrant >/dev/null 2>&1
assert_eq "${#ADMIN_EVENTS[@]}:${ADMIN_STATE[ReEnrollPromotedUser]-}" "0:bob" "startup must not revoke a grant whose run is still active"

# Startup runs the revocation before dockCheck, which can exit early.
typeset -ga STARTUP_ORDER=()
function propertyList() { STARTUP_ORDER+=(propertyList); }
function rootCheck() { STARTUP_ORDER+=(rootCheck); }
function revokeStaleAdminGrant() { STARTUP_ORDER+=(revokeStaleAdminGrant); }
function dockCheck() { STARTUP_ORDER+=(dockCheck); }
runInitialChecks
assert_eq "${STARTUP_ORDER[*]}" "propertyList rootCheck revokeStaleAdminGrant dockCheck" "startup should revoke stale grants before dockCheck"
source_reenroll

# adminGrantRunActive: same boot, process alive, inside the time limit.
stub_admin_environment
typeset -g ALIVE_PID=4242 FAKE_NOW=2000
function /usr/sbin/sysctl { print -r -- "{ sec = 1000, usec = 0 } Thu Jan  1 00:16:40 1970"; }
function /bin/date { print -r -- "${FAKE_NOW}"; }
function kill { [[ "$1" == "-0" && "$2" == "${ALIVE_PID}" ]]; }
function grant_active() { adminGrantRunActive && print active || print ended; }
ADMIN_STATE=(ReEnrollPromotedUser bob ReEnrollPromotedPID 4242 ReEnrollPromotedAt 1500)
assert_eq "$(grant_active)" "active" "a live run in this boot inside the limit is active"
ALIVE_PID=1
assert_eq "$(grant_active)" "ended" "a killed run is not active"
ALIVE_PID=4242
ADMIN_STATE[ReEnrollPromotedAt]=500
assert_eq "$(grant_active)" "ended" "a grant from before the last restart is not active"
ADMIN_STATE[ReEnrollPromotedAt]=1500
FAKE_NOW=$(( 1500 + adminGrantMaxSeconds ))
assert_eq "$(grant_active)" "ended" "a grant older than adminGrantMaxSeconds is not active"
FAKE_NOW=2000
ADMIN_STATE[ReEnrollPromotedPID]="${reEnrollPID}"
ALIVE_PID="${reEnrollPID}"
assert_eq "$(grant_active)" "ended" "a record carrying this run's PID before it promoted is stale"
unfunction /usr/sbin/sysctl /bin/date kill /usr/sbin/dseditgroup
source_reenroll

# dockCheck retries, and only the progress dialog needs a desktop: an
# unattended run at the login window continues instead of exiting.
typeset -g DOCK_SLEEPS=0 DOCK_UP_AT=99 DOCK_CONSOLE="" DOCK_QUIT=""
# Bare names are stubbed too, so no form of the call reaches the real command.
function /usr/bin/pgrep { (( DOCK_SLEEPS + 1 >= DOCK_UP_AT )); }
function pgrep { /usr/bin/pgrep "$@"; }
function sleep { (( DOCK_SLEEPS += 1 )); }
function liveConsoleUser() { print -r -- "${DOCK_CONSOLE}"; }
function quitScript() { DOCK_QUIT="$1"; }
function run_dock_check() {
    displayReEnrollDialog="$1"
    DOCK_CONSOLE="$2"
    DOCK_UP_AT="$3"
    DOCK_SLEEPS=0
    DOCK_QUIT=""
    errorCount=0
    dockCheck >/dev/null 2>&1
    dock_status=$?
}
run_dock_check false alice 1
assert_eq "${dock_status}:${DOCK_SLEEPS}:${DOCK_QUIT}" "0:0:" "dockCheck should proceed at once when Finder and Dock are running"
run_dock_check false root 99
assert_eq "${dock_status}:${DOCK_SLEEPS}:${DOCK_QUIT}:${errorCount}" "0:0::0" "an unattended run at the login window should continue without exiting"
run_dock_check false loginwindow 99
assert_eq "${dock_status}:${DOCK_QUIT}" "0:" "an unattended run with loginwindow on the console should continue"
run_dock_check false alice 3
assert_eq "${dock_status}:${DOCK_SLEEPS}:${DOCK_QUIT}" "0:2:" "dockCheck should retry until Finder and Dock start"
run_dock_check false alice 99
assert_eq "${dock_status}:${DOCK_SLEEPS}:${DOCK_QUIT}:${errorCount}" "0:9::0" "an unattended run should continue after ten checks without a desktop"
run_dock_check true alice 4
assert_eq "${dock_status}:${DOCK_SLEEPS}:${DOCK_QUIT}" "0:3:" "the dialog run should also retry until Finder and Dock start"
run_dock_check true root 99
assert_eq "${DOCK_SLEEPS}:${DOCK_QUIT}" "9:1" "a dialog run without a desktop should exit after ten checks"
unfunction /usr/bin/pgrep pgrep sleep
source_reenroll

# findUsersandRemove: a stand-in local directory and admin group. dscl reads
# print plists (parsed by the real plutil); deletes, demotions and home
# removals are recorded, never performed. Home folders are real directories
# in the test folder, which stands in for /Users.
typeset -gA FAKE_UIDS FAKE_HOMES
typeset -ga FAKE_USERS DIRECTORY_EVENTS
typeset -g FAKE_ADMINS="" FAKE_ADMIN_UNKNOWN="" LIVE_CONSOLE=""
function fake_dscl_plist() {
    print -r -- "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>dsAttrTypeStandard:$1</key><array><string>$2</string></array></dict></plist>"
}
function /usr/bin/dscl {
    local name
    if [[ "$1" == "-plist" && "$3" == "-read" ]]; then
        name="${4#/Users/}"
        [[ -n "${FAKE_UIDS[$name]-}" ]] || return 56
        case "$5" in
            UniqueID) fake_dscl_plist UniqueID "${FAKE_UIDS[$name]}" ;;
            NFSHomeDirectory) fake_dscl_plist NFSHomeDirectory "${FAKE_HOMES[$name]}" ;;
        esac
        return 0
    fi
    case "$2" in
        -list) for name in "${FAKE_USERS[@]}"; do print -r -- "${name} ${FAKE_UIDS[$name]}"; done ;;
        -delete) DIRECTORY_EVENTS+=("delete $3") ;;
    esac
}
function /usr/sbin/dseditgroup {
    case "$2" in
        checkmember)
            # Only "-o checkmember -m <user> admin" names the member to check;
            # -u is dseditgroup's authenticating user, so any other form is a
            # usage error here, as it is for the real tool.
            if [[ $# -ne 5 || "$3" != "-m" || "$5" != "admin" ]]; then
                print -u2 -- "dseditgroup: invalid checkmember arguments: $*"
                return 64
            fi
            if [[ " ${FAKE_ADMIN_UNKNOWN} " == *" $4 "* ]]; then
                print -r -- "Unable to find the user record"
                return 64
            elif [[ " ${FAKE_ADMINS} " == *" $4 "* ]]; then
                print -r -- "yes $4 is a member of admin"
            else
                print -r -- "no $4 is NOT a member of admin"
                return 67
            fi
            ;;
        edit)
            DIRECTORY_EVENTS+=("demote $4")
            FAKE_ADMINS=" ${FAKE_ADMINS} "
            FAKE_ADMINS="${FAKE_ADMINS// $4 / }"
            ;;
    esac
}
function /bin/rm { DIRECTORY_EVENTS+=("rm $*"); }
# Bare names are stubbed too, so no form of the call reaches the real command.
function dscl { /usr/bin/dscl "$@"; }
function dseditgroup { /usr/sbin/dseditgroup "$@"; }
function rm { /bin/rm "$@"; }
function liveConsoleUser() { print -r -- "${LIVE_CONSOLE}"; }
function isDryRun() { return 1; }

home_root="${work_dir:A}/Users"
my_uid="$(/usr/bin/id -u)"
/bin/mkdir -p "${home_root}/lapsadmin" "${home_root}/olduser" "${home_root}/Spaced User" \
    "${home_root}/foreign" "${work_dir:A}/elsewhere" "${work_dir:A}/outside"
/bin/ln -s "${work_dir:A}/elsewhere" "${home_root}/linked"
userHomeRoot="${home_root}"
FAKE_USERS=(lapsadmin olduser spaced adminuser unknownadm linked outside foreign consoleguy exempted bystander)
FAKE_UIDS=(lapsadmin "${my_uid}" olduser "${my_uid}" spaced "${my_uid}" adminuser 601 unknownadm 602
    linked "${my_uid}" outside "${my_uid}" foreign 777 consoleguy "${my_uid}" exempted "${my_uid}" bystander "${my_uid}")
FAKE_HOMES=(lapsadmin "${home_root}/lapsadmin" olduser "${home_root}/olduser" spaced "${home_root}/Spaced User"
    adminuser "${home_root}/adminuser" unknownadm "${home_root}/unknownadm" linked "${home_root}/linked"
    outside "${work_dir:A}/outside" foreign "${home_root}/foreign" consoleguy "${home_root}/consoleguy"
    exempted "${home_root}/exempted" bystander "${home_root}/bystander")
FAKE_ADMINS="lapsadmin adminuser"
FAKE_ADMIN_UNKNOWN="unknownadm"
LIVE_CONSOLE="consoleguy"
loggedInUser="alice"
lapsAdminAccount="lapsadmin"
skipAccountDeletion="false"
exempt_users=("Shared" "Guest" "exempted" "alice")
targeted_users=(lapsadmin olduser spaced adminuser unknownadm linked outside foreign consoleguy exempted)
DIRECTORY_EVENTS=()
findUsersandRemove >/dev/null 2>&1
expected_events=(
    "demote lapsadmin"
    "delete /Users/lapsadmin" "rm -rf -- ${home_root}/lapsadmin"
    "delete /Users/olduser" "rm -rf -- ${home_root}/olduser"
    "delete /Users/spaced" "rm -rf -- ${home_root}/Spaced User"
    "delete /Users/linked"
    "delete /Users/outside"
    "delete /Users/foreign"
)
assert_eq "${(j:|:)DIRECTORY_EVENTS}" "${(j:|:)expected_events}" "findUsersandRemove should skip admins, exempt and console users and remove only safe home folders"

# The dscl listing already skips UID 500 and below; removeTargetedAccount
# refuses UID 500 itself too, so no other caller can reach a delete with it.
FAKE_UIDS[firstuser]=500
FAKE_HOMES[firstuser]="${home_root}/olduser"
DIRECTORY_EVENTS=()
removeTargetedAccount firstuser >/dev/null 2>&1
assert_eq "$?:${DIRECTORY_EVENTS[*]}" "1:" "removeTargetedAccount must not delete an account with UID 500"

# The LAPS account is never demoted when it is the console user.
lapsAdminAccount="alice"
FAKE_UIDS[alice]="${my_uid}"
FAKE_HOMES[alice]="${home_root}/alice"
FAKE_USERS=(alice)
FAKE_ADMINS="alice"
targeted_users=(alice)
DIRECTORY_EVENTS=()
findUsersandRemove >/dev/null 2>&1
assert_eq "${DIRECTORY_EVENTS[*]}" "" "findUsersandRemove must not demote or delete the console user named as the LAPS account"

# skipAccountDeletion true or blank leaves every account alone; the "false"
# run after it shows the same accounts would otherwise be removed.
lapsAdminAccount="lapsadmin"
FAKE_USERS=(lapsadmin olduser)
targeted_users=(lapsadmin olduser)
for skipAccountDeletion in true ""; do
    FAKE_ADMINS="lapsadmin"
    DIRECTORY_EVENTS=()
    findUsersandRemove >/dev/null 2>&1
    assert_eq "${DIRECTORY_EVENTS[*]}" "" "skipAccountDeletion='${skipAccountDeletion}' must not demote or delete any account"
done
skipAccountDeletion="false"
FAKE_ADMINS="lapsadmin"
DIRECTORY_EVENTS=()
findUsersandRemove >/dev/null 2>&1
expected_events=(
    "demote lapsadmin"
    "delete /Users/lapsadmin" "rm -rf -- ${home_root}/lapsadmin"
    "delete /Users/olduser" "rm -rf -- ${home_root}/olduser"
)
assert_eq "${(j:|:)DIRECTORY_EVENTS}" "${(j:|:)expected_events}" "with skipAccountDeletion=false the same targets should be removed"
unfunction /usr/bin/dscl /usr/sbin/dseditgroup /bin/rm dscl dseditgroup rm
source_reenroll

# main no longer records "Enrolled Device" up front: a run that fails before
# any enrollment evidence (here, no API credentials) leaves the receipt alone.
typeset -ga MAIN_STATE_WRITES=()
function prepareStartup() { :; }
function findUsersandRemove() { :; }
function isDryRun() { return 1; }
function state_set() { MAIN_STATE_WRITES+=("$1=$2"); }
function quitScript() { :; }
function updatedComputerInventoryInfo() { :; }
client_id=""
client_secret=""
displayReEnrollDialog="false"
sendEnrollmentInvitation="failure"
renewProfiles="failure"
skipCheckIN="true"
skipLAPSAdminCheck="true"
main >/dev/null 2>&1
[[ "${MAIN_STATE_WRITES[*]}" != *"DeviceEnrolledStatus=Enrolled Device"* ]] || {
    print -u2 -- "Assertion failed: main must not record the device as enrolled before any enrollment evidence"; (( failures += 1 )); }
source_reenroll

if (( failures > 0 )); then
    print -u2 -- "entrypoint_smoke: ${failures} failure(s)"
    exit 1
fi
print -- "entrypoint_smoke: ok"
