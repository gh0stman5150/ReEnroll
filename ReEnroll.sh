#!/bin/zsh --no-rcs

umask 077
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Script Information
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Script Version
scriptVersion="1.6.1"
# Script Name
scriptName="ReEnroll"
# Temporary inventory log to read
tempInventoryLog="/var/log/tempInventory.log"
# Set the custom folder path for the receipt file
folder_path="/Library/Application Support/ReEnroll"
# Log file for script
scriptLog="$folder_path/ReEnroll.log"
# Property List Path for Extension attribute
reEnrollConfigFile="$folder_path/ReEnroll.plist"
# Cleanup guard
cleanupHasRun="false"
# Longest a temporary admin grant to the console user may last before the
# admin guard LaunchDaemon revokes it, even if the run is still going
adminGrantMaxSeconds="3600"
scriptDirectory="$(cd -- "$(dirname -- "$0")" && pwd -P)"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# API Inormation
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# API information (ReEnroll API Credentials)
# Jamf script parameters are ordinary process arguments and are not an
# appropriate default transport for secrets. Credentials are loaded from the
# System keychain later, after logging is available. Parameter credentials can
# be enabled temporarily for legacy policies with
# REENROLL_ALLOW_PARAMETER_CREDENTIALS=true.
parameter_client_id="${4:-}"
parameter_client_secret="${5:-}"
client_id=""
client_secret=""
reenrollCredentialService="${REENROLL_CREDENTIAL_SERVICE:-ReEnroll}"
reenrollCredentialReader="${REENROLL_CREDENTIAL_READER:-${9:-}}"
reenrollAllowSecurityCliCredentialReader="${REENROLL_ALLOW_SECURITY_CLI_CREDENTIAL_READER:-false}"
reenrollAllowParameterCredentials="${REENROLL_ALLOW_PARAMETER_CREDENTIALS:-false}"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Skip Check-In, LAPS Admin Account Username and User to Exempt/Target for Deletion Options
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Skip Jamf connection verification after enrollment
skipCheckIN="false"                                                 # [ false (default) | true ]
# Skip LAPS admin account verification after enrollment
skipLAPSAdminCheck="false"                                          # [ false (default) | true ]
# LAPS admin account username (add the Jamf managed local admin account username here)
lapsAdminAccount="${6:-}"                                             # [ add the LAPS admin account username here ]
# Skip User Exemption/Targeted Deletion
skipAccountDeletion="false"                                         # [ false (default) | true ]
# Define the exempt user list from being deleted (Add the username in quotes, with a space in between each)
exempt_users=("Shared" "Guest" "$loggedInUser")                     # [ add the exempt user list here ]
# Define the targeted user list to be deleted (Add the username in quotes, with a space in between each)
# A targeted account is deleted only when its UID is above 500, it is not the console user or exempt,
# and it is not an administrator. Its home folder is removed only when it is a real directory directly
# under /Users (not Shared, not a symlink) owned by that account; otherwise it is left in place.
targeted_users=("$lapsAdminAccount" "anotherAccount" )              # [ add the targeted user list here ]
# Jamf Enrollment Invitation ID (https:/company.jamfcloud.com/enroll?invitation=1542270881__;!!KwNVnq) (Invitation ID in this example would be: 1542270881)
enrollmentInvitation="${7:-}"                                        # [ add the Invitation ID here ]

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# ReEnroll Computers Options
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Send redeploy Jamf Management Framework command
redeployFramework="true"                                     # [ true (default) | false ]
# Send enrollment invitation command
sendEnrollmentInvitation="failure"                           # [ true  | false | failure (default) ]
# Send profiles renew -type command
renewProfiles="failure"                                      # [ true | false | failure (default) ]

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Launch Daemon information 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Skip Launch Daemon after script completion 
skipLaunchDaemon="false"                                     # [ false (default) | true ]
# Launch Daemon information
organizationName="company"                                   # [ add the organization name here ] #
organizationReverseDomain="com.company"                      # [ add the organization reverse domain here ]

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Additional Settings
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Add additional logging
debugMode="false"			                                 # Debug Mode [ false (default) | verbose ] Verbose adds additional logging
# Simulate Jamf and system-changing actions without executing them
DRY_RUN="${DRY_RUN:-false}"                                 # Dry Run [ false (default) | true | 1 ]
# Verify and Update Computer Site after enrollment
updateComputerSite="true"                                    # Update Computer Site [ true (default) | false ]
# Move Computer to new Site
newComputerSiteID=""                                         # Move Computer Site [ blank (default) ] (Only used if updateComputerSite is true and newComputerSiteName is set)

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Swift Dialog Settings
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Display a ReEnroll progress dialog
displayReEnrollDialog="${8:-false}"                           # Display ReEnroll Dialog [ true | false (default) ]
# Unattended Exit Options
unattendedExit="true"                                         # Unattended Exit [ true | false (default) ]
# Unattended Exit Seconds
unattendedExitSeconds="30"                                    # Number of seconds to wait until a kill Dialog command is sent
# Minimum version of swiftDialog required to use workflow
swiftDialogMinimumRequiredVersion="2.5.2"                     # Minimum version of swiftDialog required to use workflow
# Version of swiftDialog
if [[ -x "/usr/local/bin/dialog" ]]; then
    dialogVersion=$(/usr/local/bin/dialog --version)
else
    dialogVersion="not installed"
fi
# Timestamp with computer timezone
timestamp=$(date +"%Y-%m-%d %I:%M:%S %p %Z")
# Dialog Binary
dialogBinary="/usr/local/bin/dialog"
# swiftDialog application bundle; its presence selects the swiftDialog
# workflow on macOS 12 and later (otherwise osascript is used)
dialogAppPath="/Library/Application Support/Dialog/Dialog.app"
dialogPid=""
caffeinatePid=""
# Dialog temporary command files
dialogLog=$(mktemp /var/tmp/dialogLog.XXXXXX)
updateDialogLog=$(mktemp /var/tmp/updateDialogLog.XXXXXX)

# Set icon based on whether the Mac is a desktop or laptop
if system_profiler SPPowerDataType | grep -q "Battery Power"; then
    icon="SF=arrow.triangle.2.circlepath.icloud.fill,weight=regular,colour1=black,colour2=white"
else
    icon="SF=arrow.triangle.2.circlepath.icloud.fill,weight=regular,colour1=black,colour2=white"
fi

### Overlay Icon ###
useOverlayIcon="true"								# Toggles swiftDialog to use an overlay icon [ true (default) | false ]
overlayicon=""
errorCount=0

### Webhook Options ###

webhookEnabled="false"                                                          # Enables the webhook feature [ all | failures | false (default) ]
teamsURL=""                                                                     # Teams webhook URL                         
slackURL=""                                                                     # Slack webhook URL

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Operating System Variables and Jamf URL
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Current JSS address
jssurl=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)
jssurl="${jssurl%/}/"
jamfBinary=""
jamfInventoryApiVersion="v3"
# Jamf Pro URL for on-prem, multi-node, clustered environments (Used for webhook url button)
case ${jssurl} in
    *"test"*    ) jamfProURL="https://test.jamfcloud.com" ;;
    *"prod"*    ) jamfProURL="https://prod.jamfcloud.com" ;;
    *           ) jamfProURL="https://prod.jamfcloud.com" ;;
esac
# Get Computer Serial Number
serialNumber=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}')
# Get Computer Name
computerName=$( scutil --get ComputerName )
# Jamf Pro Computer URL for Webhook Message
jamfProComputerURL="${jssurl}/computers.html?query=${serialNumber}&queryType=COMPUTERS"
# Get the current major OS version
osVersion=$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d"." -f1)
osVersionFull=$(/usr/bin/sw_vers -productVersion)
osVersionExtra=$(/usr/bin/sw_vers -productVersionExtra)
osBuild=$( sw_vers -buildVersion )
osMajorVersion=$( echo "${osVersion}" | awk -F '.' '{print $1}' )
modelName=$( /usr/libexec/PlistBuddy -c 'Print :0:_items:0:machine_name' /dev/stdin <<< "$(system_profiler -xml SPHardwareDataType)" )

#echo "model name is $modelName"

# Report RSR sub-version if applicable
if [[ -n $osVersionExtra ]] && [[ "${osMajorVersion}" -ge 13 ]]; then osVersion="${osVersion} ${osVersionExtra}"; fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# IT Support Variable
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

### Support Team Details ###


supportTeamName="Add IT Support"
supportTeamPhone="Add IT Phone Number"
supportTeamEmail="Add email"
supportTeamWebsite="Add IT Help site"
supportTeamHyperlink="[${supportTeamWebsite}](https://${supportTeamWebsite})"

# Create the help message based on Support Team variables
helpMessage="If you need assistance, please contact ${supportTeamName}:  \n- **Telephone:** ${supportTeamPhone}  \n- **Email:** ${supportTeamEmail}  \n- **Help Website:** ${supportTeamHyperlink}  \n\n**Computer Information:**  \n- **Operating System:**  $osVersion ($osBuild)  \n- **Serial Number:** $serialNumber  \n- **Dialog:** $dialogVersion  \n- **Started:** $timestamp  \n- **Script Version:** $scriptVersion"

####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
    echo "${scriptName} ($scriptVersion): $(date +%Y-%m-%d\ %H:%M:%S) - ${1}" | tee -a "${scriptLog}"
}

function preFlight() {
    updateScriptLog "[PRE-FLIGHT]      ${1}"
}

function notice() {
    updateScriptLog "[NOTICE]          ${1}"
}

function infoOut() {
    updateScriptLog "[INFO]            ${1}"
}

function debugVerbose() {
    if [[ "$debugMode" == "verbose" ]]; then
        updateScriptLog "[DEBUG VERBOSE]   ${1}"
    fi
}

function debug() {
    # shellcheck disable=SC2317
    if [[ "$debugMode" == "true" ]]; then
        updateScriptLog "[DEBUG]           ${1}"
    fi
}

function errorOut() {
    updateScriptLog "[ERROR]           ${1}"
}

function error() {
    updateScriptLog "[ERROR]           ${1}"
    (( errorCount++ )) || true
}

function warning() {
    updateScriptLog "[WARNING]         ${1}"
}

function fatal() {
    updateScriptLog "[FATAL ERROR]     ${1}"
    exit 1
}

function quitOut() {
    updateScriptLog "[QUIT]            ${1}"
}

function isDryRun() {
    case "${DRY_RUN:l}" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

function dryRunOut() {
    updateScriptLog "[DRY RUN]         ${1}"
}

function runAsLoggedInUser() {
    local userID

    case "${loggedInUser:-}" in
        ""|root|loginwindow|_mbsetupuser)
            warning "No valid GUI user is available for user-context command execution."
            return 1
            ;;
    esac

    userID=$(/usr/bin/id -u "${loggedInUser}" 2>/dev/null) || {
        warning "Unable to resolve the user ID for ${loggedInUser}."
        return 1
    }

    /bin/launchctl asuser "${userID}" /usr/bin/sudo -H -u "${loggedInUser}" "$@"
}

function sourceModule() {
    local modulePath="${scriptDirectory}/lib/${1}"
    if [[ ! -r "${modulePath}" ]]; then
        echo "Missing required module: ${modulePath}" >&2
        exit 1
    fi

    source "${modulePath}"
}

function findJamfBinary() {
    local candidate

    for candidate in /usr/local/bin/jamf /usr/local/jamf/bin/jamf; do
        if [[ -x "${candidate}" ]]; then
            print -r -- "${candidate}"
            return 0
        fi
    done
    return 1
}

function readReEnrollSecret() {
    local account="$1"
    local readerOwner=""
    local readerMode=""

    # Callers capture stdout as the secret, so diagnostics go to stderr; a
    # warning on stdout would otherwise be loaded as the credential.

    if [[ -n "${reenrollCredentialReader}" ]]; then
        if [[ "${reenrollCredentialReader}" != /* || ! -x "${reenrollCredentialReader}" ]]; then
            warning "Configured ReEnroll credential reader is not an executable absolute path." >&2
            return 1
        fi
        readerOwner=$(/usr/bin/stat -f '%Su' "${reenrollCredentialReader}" 2>/dev/null || true)
        readerMode=$(/usr/bin/stat -f '%OLp' "${reenrollCredentialReader}" 2>/dev/null || true)
        if [[ "${readerOwner}" != "root" || "${readerMode}" != <-> ]]; then
            warning "ReEnroll credential reader must be root-owned and not group/world writable." >&2
            return 1
        fi
        if (( (8#${readerMode} & 8#22) != 0 )); then
            warning "ReEnroll credential reader must be root-owned and not group/world writable." >&2
            return 1
        fi
        if ! /usr/bin/codesign --verify --strict "${reenrollCredentialReader}" >/dev/null 2>&1; then
            warning "ReEnroll credential reader does not have a valid code signature." >&2
            return 1
        fi
        "${reenrollCredentialReader}" "${account}" "${reenrollCredentialService}" 2>/dev/null
        return
    fi

    case "${reenrollAllowSecurityCliCredentialReader:l}" in
        true|1|yes)
            /usr/bin/security find-generic-password -a "${account}" -s "${reenrollCredentialService}" -w \
                /Library/Keychains/System.keychain 2>/dev/null
            return
            ;;
    esac

    return 1
}

function loadApiCredentials() {
    local keychainClientID=""
    local keychainClientSecret=""

    keychainClientID="$(readReEnrollSecret JamfApiClientID || true)"
    keychainClientSecret="$(readReEnrollSecret JamfApiClientSecret || true)"

    if [[ -n "${keychainClientID}" && -n "${keychainClientSecret}" ]]; then
        client_id="${keychainClientID}"
        client_secret="${keychainClientSecret}"
        infoOut "Loaded Jamf API client credentials from the System keychain."
        return 0
    fi

    case "${reenrollAllowParameterCredentials:l}" in
        true|1|yes)
            if [[ -n "${parameter_client_id}" && -n "${parameter_client_secret}" ]]; then
                client_id="${parameter_client_id}"
                client_secret="${parameter_client_secret}"
                warning "Using legacy Jamf script-parameter credentials. Migrate these secrets to the System keychain."
                return 0
            fi
            ;;
    esac

    if [[ -n "${parameter_client_id}" || -n "${parameter_client_secret}" ]]; then
        warning "Ignoring Jamf API credentials supplied in script parameters because REENROLL_ALLOW_PARAMETER_CREDENTIALS is not enabled."
    fi
    return 1
}

function prepareJamfEnvironment() {
    if [[ "${jssurl}" != https://* ]]; then
        fatal "Jamf Pro URL is missing or is not HTTPS. Verify com.jamfsoftware.jamf.plist."
    fi

    jamfBinary="$(findJamfBinary || true)"
    if [[ -n "${jamfBinary}" ]]; then
        infoOut "Detected Jamf binary: ${jamfBinary}"
    else
        warning "The local Jamf binary is not currently installed; API redeployment or enrollment renewal will be required."
    fi

    loadApiCredentials || notice "No usable Jamf API client credentials were found."
}

sourceModule "dialog.zsh"
sourceModule "jamf_api.zsh"
sourceModule "launchd.zsh"
sourceModule "webhooks.zsh"
sourceModule "laps.zsh"
sourceModule "enrollment.zsh"

####################################################################################################
#
# Pre-flight Checks
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Path Related Functions
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function makePath() {
    mkdir -p "$(sed 's/\(.*\)\/.*/\1/' <<< "$1")"
    notice "Path made: $1"
}

function prepareRuntimeArtifacts() {
    if [[ -d "${folder_path}" ]]; then
        preFlight "Specified ${folder_path} path exists"
    else
        mkdir "${folder_path}"
        preFlight "Created specified folder path"
    fi

    if [[ ! -f "${scriptLog}" ]]; then
        touch "${scriptLog}"
        if [[ -f "${scriptLog}" ]]; then
            preFlight "Created specified scriptLog"
        else
            fatal "Unable to create specified scriptLog '${scriptLog}'; exiting.\n\n(Is this script running as 'root' ?)"
        fi
    else
        preFlight "Specified scriptLog exists; writing log entries to it"
    fi

    if [[ ! -f "${dialogLog}" ]]; then
        touch "${dialogLog}"
        if [[ -f "${dialogLog}" ]]; then
            preFlight "Created specified dialogLog"
        else
            fatal "Unable to create specified dialogLog; exiting.\n\n(Is this script running as 'root' ?)"
        fi
    else
        preFlight "Specified dialogLog exists; proceeding …"
    fi

    duplicate_log_dir=$( mktemp -d /var/tmp/jamfTemp.XXXXXX )
    chmod 700 "$duplicate_log_dir"

    if [[ ! -f "${tempInventoryLog}" ]]; then
        touch "${tempInventoryLog}"
        if [[ -f "${tempInventoryLog}" ]]; then
            preFlight "Created specified inventoryLog"
        else
            fatal "Unable to create specified $tempInventoryLog; exiting.\n\n(Is this script running as 'root' ?)"
        fi
    else
        preFlight "Specified $tempInventoryLog exists; proceeding …"
    fi
}

function syncRuntimeUserConfig() {
    local filtered_exempt_users=()
    local exempt_user
    local logged_in_user_present="false"

    for exempt_user in "${exempt_users[@]}"; do
        if [[ -z "${exempt_user}" ]]; then
            continue
        fi

        filtered_exempt_users+=("${exempt_user}")
        if [[ "${exempt_user}" == "${loggedInUser}" ]]; then
            logged_in_user_present="true"
        fi
    done

    if [[ -n "${loggedInUser}" && "${logged_in_user_present}" == "false" ]]; then
        filtered_exempt_users+=("${loggedInUser}")
    fi

    exempt_users=("${filtered_exempt_users[@]}")
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Create Folder Path
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Update Dialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate / Create temp Inventory Log File
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Jamf Log Location
jamfLogFile="/var/log/jamf.log"
duplicate_log_dir=""
# Marker file for last log position
marker_file=""

# Get the PID of the current script for caffeinate
reEnrollPID="$$"

# Create a private marker file for this run.
function createMarkerFile() {
    if [[ -n "${marker_file}" && -f "${marker_file}" ]]; then
        preFlight "Marker file exists, continuing"
        return 0
    fi

    marker_file=$(/usr/bin/mktemp /var/tmp/reenroll-jamf-marker.XXXXXX) || \
        fatal "Unable to create a private Jamf log marker file."
    /bin/chmod 600 "${marker_file}" || fatal "Unable to secure ${marker_file}."
    preFlight "Created private marker file: ${marker_file}"
}

# Create last log position
function createLastLogPosition() {
    
  # Create a timestamp for the current run
    timestamp=$(date +%Y%m%d%H%M%S)
    preFlight "Current time stamp: $timestamp"

    # Create a directory for duplicate log files if it doesn't exist
     if [ ! -d "$duplicate_log_dir" ]; then
        mkdir -p "$duplicate_log_dir"
        preFlight "Creating duplicate log file"
        else
        preFlight "Duplicate log directory exists, continuing"
     fi

      if [[ -z "${marker_file}" || ! -f "${marker_file}" ]]; then
          createMarkerFile
      fi

    # Specify the duplicate log file with a timestamp
    duplicate_jamfLogFile="$duplicate_log_dir/jamf_position_$timestamp.log"
    preFlight "Duplicate Log File location: $duplicate_jamfLogFile"

    # The marker file holds a byte offset into jamf.log; an empty or missing
    # marker starts from the beginning of the log.
    if [[ ! -f $jamfLogFile ]]; then
        preFlight "Creating jamf log file and setting error position as zero"
        touch "$jamfLogFile"
        chmod 755 "$jamfLogFile"
        print -r -- "0" > "$marker_file"
    fi

    # Copy new entries from jamf.log to the duplicate log file and record the
    # new byte offset in the marker file (copyNewJamfLogEntries, jamf_api.zsh)
    if [ -f "$jamfLogFile" ]; then
        : > "$duplicate_jamfLogFile"
        copyNewJamfLogEntries || error "Unable to read the jamf log file"
        preFlight "jamf log file exists. Copied new entries from log file to duplicate log file"
    else
        error "jamf log file not found"
    fi
    preFlight "Updating marker file"

    # Echo out the last position on the marker file
    preFlight "Last position of marker file: $lastPosition"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Checking Last Error Position
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Verify last position location in log file from previous run
function verifyLastPosition(){
 # Find the last position text in scriptLog
   lastPosition_line=$(tail -n 400 "$scriptLog" | grep 'Last position:' | tail -n 1)

    if [ -n "$lastPosition_line" ]; then
        # Extract the last position from the line
        lastPosition=$(echo "$lastPosition_line" | awk -F 'Last position:' '{print $2}' | tr -d '[:space:]')

        echo "$lastPosition" > "$marker_file"

        # Check if last position is less than or equal to zero
        if [[ ! -f "${jamfLogFile}" ]] || [[ "${lastPosition}" -le 0 ]]; then
            preFlight "Last position is less than one or jamf log doesn't exist. Creating position."
            createLastLogPosition
        else
            preFlight "Last position is greater than zero and jamf log file exists. Continuing."
            lastPositionUpdated=$(cat "$marker_file")
            preFlight "Last position: $lastPositionUpdated"
        fi
    else
        preFlight "Last position not found. Setting it to zero and continuing."
        createLastLogPosition
    fi
}

function prepareLogTracking() {
    preFlight "Creating Marker file and checking if last error position exists"
    createMarkerFile
    verifyLastPosition
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm script is running as root
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function rootCheck() {
# Confirm script is running as root
if [[ $(id -u) -ne 0 ]]; then
    fatal "This script must be run as root; exiting."
        quitScript "1"
fi
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm Dock is running / user is at Desktop
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# The account that owns the console right now ("root" at the login window).
function liveConsoleUser() {
    /usr/bin/stat -f '%Su' /dev/console 2>/dev/null
}

# Waits up to dockFinderChecks checks, 2 seconds apart, for Finder and Dock.
# Only the swiftDialog progress UI ($8 true) needs a desktop: without it, a
# run at the login window continues at once and a desktop that never appears
# is logged as a warning, so recurring and enrollment policies stay unattended.
function dockCheck() {
    local dockFinderChecks=10
    local check consoleUser

    preFlight "Checking if Finder & Dock are running"

    for (( check = 1; check <= dockFinderChecks; check++ )); do
        if /usr/bin/pgrep -q -x "Finder" && /usr/bin/pgrep -q -x "Dock"; then
            preFlight "Finder & Dock are running; proceeding"
            return 0
        fi

        if [[ "${displayReEnrollDialog}" != "true" ]]; then
            consoleUser="$(liveConsoleUser)" || consoleUser=""
            case "${consoleUser}" in
                ""|root|loginwindow|_mbsetupuser)
                    preFlight "No user is logged in at the desktop (console: ${consoleUser:-none}); continuing unattended"
                    return 0
                    ;;
            esac
        fi

        if (( check < dockFinderChecks )); then
            preFlight "Finder & Dock are NOT running (check ${check} of ${dockFinderChecks}); pausing for 2 seconds"
            sleep 2
        fi
    done

    if [[ "${displayReEnrollDialog}" == "true" ]]; then
        error "Finder or Dock is still not running after ${dockFinderChecks} checks; the ReEnroll dialog needs a logged-in desktop; exiting"
        quitScript 1
        return 1
    fi

    warning "Finder or Dock is still not running after ${dockFinderChecks} checks; continuing unattended"
    return 0
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Current Logged-in User Function
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getCurrentLoggedInUserAccount() {
    loggedInUserAccount=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
    preFlight "Current Logged-in User: ${loggedInUserAccount}"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Logged-in System Accounts
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Get the currently logged-in user
function currentLoggedInUser() {

    loggedInCounter="1"
    getCurrentLoggedInUserAccount

    until { [[ "${loggedInUserAccount}" != "_mbsetupuser" ]] || [[ "${loggedInCounter}" -gt "180" ]]; } && { [[ "${loggedInUserAccount}" != "loginwindow" ]] || [[ "${loggedInCounter}" -gt "30" ]]; } ; do
    preFlight "Logged-in User Counter: ${loggedInCounter}"
    getCurrentLoggedInUserAccount
    sleep 2
    ((loggedInCounter++))
    done

    if [[ "$debugMode" = "verbose" ]]; then
        loggedInUser=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')
            debugVerbose "Current Logged-in User: ${loggedInUser}"
        uid=$(/usr/bin/id -u "${loggedInUser}")
            debugVerbose "User ID: ${uid}"
        networkUser="$(dscl . -read /Users/"$loggedInUser" | grep "NetworkUser" | cut -d " " -f 2)"
            debugVerbose "Network User is $networkUser"
        loggedInUserFullname=$(id -F "${loggedInUser}")
        loggedInUserFirstname=$(echo "$loggedInUserFullname" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print ( $0 == toupper($0) ? toupper(substr($0,1,1))substr(tolower($0),2) : toupper(substr($0,1,1))substr($0,2) )}')
        loggedInUserLastname=$(echo "$loggedInUserFullname" | sed "s/$loggedInUserFirstname//" | sed 's/,//g')
        loggedInUserID=$(id -u "${loggedInUser}")
            debugVerbose "Current Logged-in User First Name: ${loggedInUserFirstname}"
            debugVerbose "Current Logged-in User Full Name: ${loggedInUserFirstname} ${loggedInUserLastname}"
            debugVerbose "Current Logged-in User ID: ${loggedInUserID}"
    else
        loggedInUser=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')
        uid=$(/usr/bin/id -u "${loggedInUser}")
            preFlight "User ID: ${uid}"
        networkUser="$(dscl . -read /Users/"$loggedInUser" | grep "NetworkUser" | cut -d " " -f 2)"
            preFlight "Network User is $networkUser"
        loggedInUserFullname=$(id -F "${loggedInUser}")
        loggedInUserFirstname=$(echo "$loggedInUserFullname" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print ( $0 == toupper($0) ? toupper(substr($0,1,1))substr(tolower($0),2) : toupper(substr($0,1,1))substr($0,2) )}')
        loggedInUserLastname=$(echo "$loggedInUserFullname" | sed "s/$loggedInUserFirstname//" | sed 's/,//g')
        loggedInUserID=$(id -u "${loggedInUser}")
            preFlight "Current Logged-in User: ${loggedInUser}"
    fi


}

function prepareUserContext() {
    preFlight "Check for Logged-in System Accounts …"
    currentLoggedInUser
    syncRuntimeUserConfig
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Validate / install swiftDialog (Thanks big bunches, @acodega!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Download swiftDialog
function startRuntimeSession() {
    preFlight "Complete!"
    if isDryRun; then
        dryRunOut "Would caffeinate this script for the duration of the run"
    else
        infoOut "Caffeinating this script (PID: $reEnrollPID)"
        caffeinate -dimsu -w "$reEnrollPID" &
        caffeinatePid=$!
    fi
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# "ReEnroll" Dialog Settings and Features
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

title="ReEnroll"
message=""

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Exit the caffeinated script
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function caffeinateExit() {
    if [[ -n "${caffeinatePid}" ]] && kill -0 "${caffeinatePid}" 2>/dev/null; then
        infoOut "Stopping tracked caffeinate process ${caffeinatePid}..."
        kill "${caffeinatePid}" 2>/dev/null || true
        wait "${caffeinatePid}" 2>/dev/null || true
    fi
    caffeinatePid=""
}

function invalidateToken() {
    if [[ -z "${apiBearerToken}" ]]; then
        return
    fi

    if isDryRun; then
        dryRunOut "Would invalidate Jamf Pro API bearer token"
        apiBearerToken=""
        token_expiration_epoch="0"
        return
    fi

    jamfApiRequest POST "${jssurl}api/v1/auth/invalidate-token" \
        --header "Authorization: Bearer ${apiBearerToken}" || true
    if [[ ${JAMF_HTTP_STATUS} == 204 ]]; then
        quitOut "Token successfully invalidated"
        apiBearerToken=""
        token_expiration_epoch="0"
    elif [[ ${JAMF_HTTP_STATUS} == 401 ]]; then
        quitOut "Token already invalid"
    else
        quitOut "Unable to invalidate the token (HTTP ${JAMF_HTTP_STATUS}); clearing the local copy"
    fi
    apiBearerToken=""
}

function rm_if_exists() {
    if [ -n "${1}" ] && [ -e "${1}" ]; then
        /bin/rm -r "${1}"
    fi
}

function cleanupTemporaryArtifacts() {
    # A response body (possibly a LAPS password) left by an interrupted request.
    if [[ -n "${JAMF_HTTP_BODY_FILE:-}" && -f "${JAMF_HTTP_BODY_FILE}" ]]; then
        rm -f -- "${JAMF_HTTP_BODY_FILE}"
        JAMF_HTTP_BODY_FILE=""
    fi

    if [[ -f "${tempInventoryLog}" ]]; then
        quitOut "Removing ${tempInventoryLog} …"
        rm "${tempInventoryLog}"
    fi

    if [[ -d "${duplicate_log_dir}" ]]; then
        quitOut "Removing ${duplicate_log_dir} …"
        rm_if_exists "${duplicate_log_dir}"
    else
        quitOut "Could not delete ${duplicate_log_dir}"
    fi

    if [[ -e "${marker_file}" ]]; then
        quitOut "Removing ${marker_file} …"
        rm "${marker_file}"
    fi

    if [[ -f "${dialogLog}" ]]; then
        infoOut "Removing ${dialogLog} …"
        rm "${dialogLog}"
    fi

    if [[ -f "${updateDialogLog}" ]]; then
        infoOut "Removing ${updateDialogLog} …"
        rm "${updateDialogLog}"
    fi

    if [[ -f "${overlayicon}" ]]; then
        infoOut "Removing ${overlayicon} …"
        rm "${overlayicon}"
    fi
}

# Any renew path (renewProfiles true or the default "failure") can promote the
# console user. removeAdmin acts only on a grant addAdmin recorded in this run,
# so it is always safe to call here. A run that never reaches this trap is
# covered by the admin guard LaunchDaemon and the next run's startup check.
function cleanupPrivileges() {
    infoOut "Removing any admin access granted by ReEnroll"
    removeAdmin
}

function cleanupResources() {
    if [[ "${cleanupHasRun}" == "true" ]]; then
        return
    fi

    cleanupHasRun="true"
    caffeinateExit
    invalidateToken
    dialogExit
    cleanupTemporaryArtifacts
    cleanupPrivileges
    quitOut "Goodbye!"
}

function handleTerminationSignal() {
    local signal_name="$1"
    error "Received ${signal_name} signal, exiting."
    exit 1
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Quit Script
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Quit Script function
function quitScript() {
    local exitCode="${1:-}"

    if [[ -z "${exitCode}" ]]; then
        if (( errorCount > 0 )); then
            exitCode=1
        else
            exitCode=0
        fi
    fi

# WebHook Message
case ${webhookEnabled} in

    "all" ) # Notify on sucess and failure 
        infoOut "Webhook Enabled flag set to: ${webhookEnabled}, continuing ..."
            webHookMessage
    ;;

    "failures" ) # Notify on failures
        if [[ "${errorCount}" -gt 0 ]]; then
            warning "Completed with $errorCount errors."
            infoOut "Webhook Enabled flag set to: ${webhookEnabled} with error count: ${errorCount}, continuing ..."
            webHookMessage
        else
            infoOut "Webhook Enabled flag set to: ${webhookEnabled}, but conditions not met for running webhookMessage."
        fi
    ;;

    "false" ) # Don't notify
        infoOut "Webhook Enabled flag set to: ${webhookEnabled}, skipping ..."
    ;;

    * ) # Catch-all
        infoOut "Webhook Enabled flag set to: ${webhookEnabled}, skipping ..."
        ;;

esac
	
    # Functions for script
    if [ "$displayReEnrollDialog" = "true" ]; then
        infoOut "Display ReEnroll Dialog is set to true, completing ReEnroll Dialog"
        # Complete ReEnroll Dialog Window
        completeReEnrollDialog
    else
        # displayReEnrollDialog was set to false
        notice "No Dialog was displayed, no ReEnroll Dialog to complete"
    fi

    exit "${exitCode}"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Create Property List
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function state_exists() {
    [[ -f "${reEnrollConfigFile}" ]]
}

function state_get() {
    /usr/bin/defaults read "${reEnrollConfigFile}" "${1}" 2>/dev/null
}

function state_set() {
    /usr/bin/defaults write "${reEnrollConfigFile}" "${1}" "${2}"
}

function state_set_date() {
    /usr/bin/defaults write "${reEnrollConfigFile}" "${1}" -date "${2}"
}

function state_delete() {
    /usr/bin/defaults delete "${reEnrollConfigFile}" "${1}" >/dev/null 2>&1 || true
}

# Create Property List
function propertyList() {
    local stateFileExists="false"

    if state_exists; then
        infoOut "Specified ${reEnrollConfigFile} path exists"
        stateFileExists="true"
    else
        infoOut "Created specified folder path"
        touch "${reEnrollConfigFile}"
    fi

    # PLIST creation and population
    infoOut "Checking for "$reEnrollConfigFile""

    if [[ "${stateFileExists}" == "false" ]]; then
        infoOut "ReEnroll configuration profile does not exist, creating now..."
        timestamp="$(date +"%Y-%m-%d %l:%M:%S +0000")"
        state_set "ReEnrollVersion" "$scriptVersion"
        state_set_date "ReEnrollLastRun" "$timestamp"
        state_set "DeviceEnrolledStatus" "Not Enrolled"
        state_set "ReEnrollNotificationStatus" "No Notification"
        state_set "ReEnrollMethod" "None"
        state_set "ComputerSiteID" "None"
        state_set "ComputerSite" "-1"
    else
        infoOut "ReEnroll configuration already exists, continuing..."
        timestamp="$(date +"%Y-%m-%d %H:%M:%S +0000")"
        state_set "ReEnrollVersion" "$scriptVersion"
        state_set_date "ReEnrollLastRun" "$timestamp"
    fi
}

function runInitialChecks() {
    propertyList
    rootCheck
    # Before dockCheck, which exits when the progress dialog is requested and
    # no GUI session is ready, so even such a run revokes rights left by a
    # run that was killed.
    revokeStaleAdminGrant
    dockCheck
}

function prepareStartup() {
    prepareRuntimeArtifacts
    if isDryRun; then
        dryRunOut "Dry-run mode enabled. Jamf API mutations and local system changes will be simulated."
    fi
    prepareOverlayIcon
    prepareLogTracking
    runInitialChecks
    prepareJamfEnvironment
    prepareUserContext
    prepareDialogEnvironment
    buildReEnrollDialog
    startRuntimeSession
}

# Jamf API functions are sourced from lib/jamf_api.zsh

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Add to Admin Group
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Add to Admin Group
function addAdmin() {
    if isDryRun; then
        infoOut "${loggedInUser} admin status will be simulated."
        updateDialog "progresstext: Dry run enabled; ${loggedInUser} admin update will be simulated..."
        dryRunOut "Would add ${loggedInUser} to the admin group"
        return 0
    fi

    # dseditgroup reports "<user> is NOT a member of admin" in upper case, so the
    # match must be case-insensitive or the promotion never happens.
    if dseditgroup -o checkmember -m "$loggedInUser" admin | grep -qi "not a member"; then
        infoOut "${loggedInUser} is not an admin. Adding to the admin group..."
        updateDialog "progresstext: Adding ${loggedInUser} to the admin group..."
        # Record the temporary grant and arm the admin guard LaunchDaemon
        # before promoting, so the grant is revoked even if this run is killed,
        # times out or the Mac restarts before the EXIT trap demotes. Only a
        # recorded account is ever demoted, never a pre-existing administrator.
        recordAdminGrant "$loggedInUser"
        if ! installAdminGuardDaemon; then
            error "Unable to arm the admin guard LaunchDaemon; not granting ${loggedInUser} admin rights."
            revokeAdminGrant "$loggedInUser"
            return 1
        fi
        if ! /usr/sbin/dseditgroup -o edit -a "$loggedInUser" -t user admin; then
            error "Unable to add ${loggedInUser} to the admin group."
            revokeAdminGrant "$loggedInUser"
            return 1
        fi
        infoOut "${loggedInUser} has been added to the admin group."
        updateDialog "progresstext: ${loggedInUser} has been added to the admin group."
    else
        infoOut "${loggedInUser} is already an admin."
        updateDialog "progresstext: ${loggedInUser} is already an admin."
    fi
}

# The grant record: who was promoted, by which ReEnroll process, and when.
function recordAdminGrant() {
    state_set "ReEnrollPromotedUser" "$1"
    state_set "ReEnrollPromotedPID" "${reEnrollPID}"
    state_set "ReEnrollPromotedAt" "$(/bin/date +%s)"
}

function clearAdminGrantRecord() {
    state_delete "ReEnrollPromotedUser"
    state_delete "ReEnrollPromotedPID"
    state_delete "ReEnrollPromotedAt"
}

# Succeeds while another ReEnroll run that recorded the grant is still going:
# this boot began before the grant, its process is alive and the grant is
# younger than adminGrantMaxSeconds. The admin guard applies the same test.
function adminGrantRunActive() {
    local promotedPID promotedAt bootTime now

    promotedPID="$(state_get "ReEnrollPromotedPID")"
    promotedAt="$(state_get "ReEnrollPromotedAt")"
    [[ "${promotedPID}" == <2-> && "${promotedAt}" == <1-> ]] || return 1
    [[ "${promotedPID}" != "${reEnrollPID}" ]] || return 1
    bootTime="$(/usr/sbin/sysctl -n kern.boottime 2>/dev/null)"
    bootTime="${${bootTime#*sec = }%%,*}"
    now="$(/bin/date +%s)"
    [[ "${bootTime}" == <1-> && "${now}" == <1-> ]] || return 1
    (( bootTime <= promotedAt && now - promotedAt < ${adminGrantMaxSeconds:-3600} )) || return 1
    kill -0 "${promotedPID}" 2>/dev/null
}

# Demotes an account ReEnroll recorded as promoted. The record and the admin
# guard are removed only once the account is no longer an administrator, so a
# failed demotion is retried by the guard.
function revokeAdminGrant() {
    local promotedUser="$1"

    if dseditgroup -o checkmember -m "${promotedUser}" admin | grep -q "is a member"; then
        infoOut "${promotedUser} was promoted by ReEnroll. Removing from the admin group..."
        if ! /usr/sbin/dseditgroup -o edit -d "${promotedUser}" -t user admin; then
            error "Unable to remove ${promotedUser} from the admin group; the admin guard LaunchDaemon will retry."
            return 1
        fi
        infoOut "${promotedUser} has been removed from the admin group."
    else
        infoOut "${promotedUser} is not an admin."
    fi
    clearAdminGrantRecord
    removeAdminGuardDaemon
}

# Startup: revoke a grant left by an earlier run that was killed, timed out or
# interrupted by a restart, whatever renewProfiles is set to.
function revokeStaleAdminGrant() {
    local promotedUser

    promotedUser="$(state_get "ReEnrollPromotedUser")"
    [[ -n "${promotedUser}" ]] || return 0

    if isDryRun; then
        dryRunOut "Would remove the admin rights an earlier ReEnroll run granted to ${promotedUser}"
        return 0
    fi

    if adminGrantRunActive; then
        notice "Another ReEnroll run that granted ${promotedUser} admin rights is still running; leaving the grant to that run and the admin guard."
        return 0
    fi

    warning "An earlier ReEnroll run granted ${promotedUser} admin rights and did not remove them; removing them now."
    revokeAdminGrant "${promotedUser}"
}


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Remove from Admin Group
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Remove from Admin Group
function removeAdmin () {
    if isDryRun; then
        dryRunOut "Would remove ${loggedInUser} from the admin group if present"
        return 0
    fi

    # Act only on a grant this run recorded; one left by another run is
    # handled by that run, the admin guard or the next run's startup check.
    if [[ -z "$loggedInUser" || "$(state_get "ReEnrollPromotedUser")" != "$loggedInUser" \
        || "$(state_get "ReEnrollPromotedPID")" != "${reEnrollPID}" ]]; then
        quitOut "ReEnroll did not grant admin rights to ${loggedInUser:-the console user} in this run; leaving group membership unchanged."
        return 0
    fi

    revokeAdminGrant "$loggedInUser"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Find User Accounts and Remove
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Home folders that account cleanup may remove live directly in this folder.
userHomeRoot="/Users"

# Sets removableHomeDirectory to the account's home folder when it is safe to
# remove as root: a real directory (not a symlink, no symlinked or ".."
# component) directly under userHomeRoot, not Shared, and owned by the
# account's UID. Otherwise clears it, sets homeRemovalReason and fails.
function checkRemovableHomeDirectory() {
    local account="$1"
    local accountUID="$2"
    local home folderName homeOwner

    removableHomeDirectory=""
    homeRemovalReason=""

    home="$(localAccountAttribute "${account}" NFSHomeDirectory)" || home=""
    folderName="${home#"${userHomeRoot}"/}"
    if [[ -z "${home}" ]]; then
        homeRemovalReason="the account record has no home folder"
        return 1
    fi
    if [[ "${home}" != "${userHomeRoot}"/* || "${folderName}" == */* \
        || "${folderName}" == (|.|..|Shared) ]]; then
        homeRemovalReason="${home} is not a user folder directly under ${userHomeRoot}"
        return 1
    fi
    if [[ ! -e "${home}" && ! -L "${home}" ]]; then
        homeRemovalReason="${home} does not exist"
        return 1
    fi
    if [[ -L "${home}" || ! -d "${home}" ]]; then
        homeRemovalReason="${home} is not a real directory"
        return 1
    fi
    if [[ "${home:A}" != "${home}" ]]; then
        homeRemovalReason="${home} resolves to ${home:A}"
        return 1
    fi
    homeOwner="$(/usr/bin/stat -f '%u' "${home}" 2>/dev/null)" || homeOwner=""
    if [[ "${homeOwner}" != "${accountUID}" ]]; then
        homeRemovalReason="${home} is owned by UID ${homeOwner:-unknown}, not ${account} (UID ${accountUID})"
        return 1
    fi

    removableHomeDirectory="${home}"
}

# Deletes one targeted account (already checked against exempt_users) and its
# home folder. Refuses an invalid name, a UID of 500 or below, the console
# user and administrators, including when admin membership cannot be read.
function removeTargetedAccount() {
    local user="$1"
    local removable=0 admin_status=0

    localAccountRemovable "$user" || removable=$?
    case ${removable} in
        0) ;;
        2)
            notice "User $user no longer exists; nothing to remove"
            return 0
            ;;
        *)
            warning "Not removing $user: ${accountRemovalReason}"
            return 1
            ;;
    esac
    if (( removableAccountUID <= 500 )); then
        warning "Not removing $user: UID ${removableAccountUID} is not above 500"
        return 1
    fi

    localAccountIsAdmin "$user" || admin_status=$?
    case ${admin_status} in
        0)
            infoOut "User $user was found to be a Local Admin, ignoring..."
            return 0
            ;;
        1) ;;
        *)
            warning "Unable to determine whether $user is a Local Admin; leaving the account in place"
            return 1
            ;;
    esac

    # Read the home folder before the record that names it is deleted.
    checkRemovableHomeDirectory "$user" "$removableAccountUID" || true

    infoOut "Found user $user in targeted list, deleting the account..."
    if ! /usr/bin/dscl . -delete "/Users/$user"; then
        error "Unable to delete user $user; leaving its home folder in place"
        return 1
    fi

    if [[ -n "${removableHomeDirectory}" ]]; then
        infoOut "Deleting ${removableHomeDirectory} for $user"
        /bin/rm -rf -- "${removableHomeDirectory}" || error "Unable to delete ${removableHomeDirectory}"
    else
        warning "Leaving the home folder of $user in place: ${homeRemovalReason}"
    fi
}

# Find User Accounts and Remove
function findUsersandRemove() {
  if isDryRun; then
    dryRunOut "Would evaluate local account cleanup for targeted users: ${targeted_users[*]}"
    dryRunOut "Would preserve exempt users: ${exempt_users[*]}"
    return 0
  fi

  # Demote LAPS admin account
  if [ "$skipAccountDeletion" = "false" ]; then
    notice "Skip Account Deletion is set to false, proceeding"

    # Check if $exempt_users is not empty
    if [ -z "${exempt_users[*]}" ] && [ "$skipAccountDeletion" = "false" ]; then
        error "exempt_users is empty"
    fi

    # Check if $targeted_users is not empty
    if [ -z "${targeted_users[*]}" ] && [ "$skipAccountDeletion" = "false" ]; then
        error "targeted_users is empty"
    fi

    # Check if $lapsAdminAccount is not empty
    if [ -z "$lapsAdminAccount" ] && [ "$skipAccountDeletion" = "false" ]; then
        error "lapsAdminAccount is empty"
    fi

    # Demote the LAPS admin account so the admin check below lets it be
    # removed. The deletion safety checks apply: never the console user, an
    # exempt account or a system account.
    if [[ -n "$lapsAdminAccount" ]]; then
        local laps_removable=0
        localAccountRemovable "$lapsAdminAccount" || laps_removable=$?
        case ${laps_removable} in
            0)
                infoOut "Demoting $lapsAdminAccount account"
                /usr/sbin/dseditgroup -o edit -d "$lapsAdminAccount" -t user admin || \
                    warning "Unable to remove $lapsAdminAccount from the admin group"
                ;;
            2) notice "LAPS admin account $lapsAdminAccount does not exist; nothing to demote" ;;
            *) error "Not demoting $lapsAdminAccount: ${accountRemovalReason}" ;;
        esac
    fi

    local user exempt_user targeted_user is_exempt is_targeted

    # Read the list of users with UniqueID greater than 500
    while read -r user; do
        [[ -n "$user" ]] || continue

        is_exempt=false
        for exempt_user in "${exempt_users[@]}"; do
            if [[ "$user" == "$exempt_user" ]]; then
                is_exempt=true
                break
            fi
        done
        if [[ "$is_exempt" == "true" ]]; then
            infoOut "Found user $user in exempt list, ignoring..."
            continue
        fi

        is_targeted=false
        for targeted_user in "${targeted_users[@]}"; do
            if [[ -n "$targeted_user" && "$user" == "$targeted_user" ]]; then
                is_targeted=true
                break
            fi
        done
        if [[ "$is_targeted" == "true" ]]; then
            removeTargetedAccount "$user" || true
        fi
    done < <(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '$2 > 500 {print $1}')

    elif [ "$skipAccountDeletion" = "" ]; then
        infoOut "Skip Account Deletion is set blank, skipping"
    else
        infoOut "Skip Account Deletion is set to true, skipping"
    fi
}

# Enrollment, LAPS, launchd, and webhook functions are sourced from lib/*.zsh

function main() {
    prepareStartup

    if [ "$displayReEnrollDialog" = "true" ]; then
        evalReEnrollDialog
    else
        notice "Skipping ReEnroll Dialog"
    fi

    findUsersandRemove
    # The "Enrolled Device" receipt is recorded later, by enrollDeviceReceipt,
    # only once this run has evidence of enrollment (see lib/enrollment.zsh).

    if [ -z "$client_id" ] || [ -z "$client_secret" ]; then
        if isDryRun; then
            notice "No API client credentials provided; dry-run placeholders will be used"
            jmfrdeploy
        else
            error "No API client credentials provided"
        fi
    else
        jmfrdeploy
    fi

    case ${sendEnrollmentInvitation} in

        "true" )
            infoOut "Enrollment Invitation set to: ${sendEnrollmentInvitation}"
            reEnrollInvitation
        ;;

        "failure" )
            infoOut "Enrollment Invitation set to: ${sendEnrollmentInvitation}, enrollment invitation will be sent if the Jamf Framework deployment reports failures"
        ;;

        "false" )
            infoOut "Enrollment Invitation set to: ${sendEnrollmentInvitation}, skipping ..."
        ;;

        * )
            infoOut "Enrollment Invitation set to: ${sendEnrollmentInvitation}, skipping ..."
            ;;

        esac

    case ${renewProfiles} in

        "true" )
            infoOut "Profiles Renew set to: ${renewProfiles}"
            inventoryError
        ;;

        "failure" )
            infoOut "Profiles Renew set to: ${renewProfiles}, profiles renew command will be sent if the Jamf Framework deployment reports failures and the ReEnroll Invitation command fails"
        ;;

        "false" )
            infoOut "Profiles Renew set to: ${renewProfiles}, skipping ..."
        ;;

        * )
            infoOut "Enrollment Invitation set to: ${renewProfiles}, skipping ..."
            ;;

        esac

    if [ "$skipCheckIN" = "false" ]; then
        notice "Skipping check-in option is false, sending check-in command"
        checkIn
        if [ "$redeployFramework" = "false" ] || [ "$sendEnrollmentInvitation" = "false" ] || [ "$renewProfiles" = "false" ] || [ "$skipLAPSAdminCheck" = "false" ]; then
            notice "Only check-in command was sent, exiting script"
        else
            notice "All commands were sent"
        fi
    else
        notice "Skipping check-in command"
    fi

    if [ "$skipLAPSAdminCheck" = "false" ]; then
        notice "Skipping LAPS admin check option is false, sending LAPS admin check command"
        checkLAPSAccountStatus
    else
        notice "Skipping LAPS admin check command"
    fi

    if [ -z "$client_id" ] || [ -z "$client_secret" ] || [ "$APIAccess" = "Failure" ]; then
        notice "Client ID and Client Secret not set, skipping computer site update"
        quitScript
    else
        updatedComputerInventoryInfo
    fi

    quitScript
}

# Run only when executed (as Jamf does); sourcing for tests loads the
# functions without starting ReEnroll.
if [[ "${ZSH_EVAL_CONTEXT}" != *:file ]]; then
    trap 'cleanupResources' EXIT
    trap 'handleTerminationSignal "INT"' INT
    trap 'handleTerminationSignal "TERM"' TERM

    main "$@"
fi
