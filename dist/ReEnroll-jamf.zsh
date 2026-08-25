#!/bin/zsh --no-rcs
# GENERATED FILE: run scripts/build_jamf_artifact.py; do not edit directly.

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

    if [[ -n "${reenrollCredentialReader}" ]]; then
        if [[ "${reenrollCredentialReader}" != /* || ! -x "${reenrollCredentialReader}" ]]; then
            warning "Configured ReEnroll credential reader is not an executable absolute path."
            return 1
        fi
        readerOwner=$(/usr/bin/stat -f '%Su' "${reenrollCredentialReader}" 2>/dev/null || true)
        readerMode=$(/usr/bin/stat -f '%OLp' "${reenrollCredentialReader}" 2>/dev/null || true)
        if [[ "${readerOwner}" != "root" || "${readerMode}" != <-> ]]; then
            warning "ReEnroll credential reader must be root-owned and not group/world writable."
            return 1
        fi
        if (( (8#${readerMode} & 8#22) != 0 )); then
            warning "ReEnroll credential reader must be root-owned and not group/world writable."
            return 1
        fi
        if ! /usr/bin/codesign --verify --strict "${reenrollCredentialReader}" >/dev/null 2>&1; then
            warning "ReEnroll credential reader does not have a valid code signature."
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

# BEGIN INLINED MODULE: dialog.zsh

function prepareOverlayIcon() {
    if [[ "$useOverlayIcon" == "true" ]]; then
        local selfServicePath
        selfServicePath=$(defaults read /Library/Preferences/com.jamfsoftware.jamf self_service_app_path 2>/dev/null || true)
        overlayicon=$(mktemp /var/tmp/reenroll-overlay.XXXXXX) || overlayicon=""
        if [[ -z "${selfServicePath}" || -z "${overlayicon}" ]] || \
            ! xxd -p -s 260 "${selfServicePath}"/Icon$'\r'/..namedfork/rsrc 2>/dev/null | \
                xxd -r -p > "${overlayicon}" || [[ ! -s "${overlayicon}" ]]; then
            [[ -n "${overlayicon}" ]] && /bin/rm -f -- "${overlayicon}"
            overlayicon=""
            warning "Unable to prepare the optional Self Service overlay icon."
        fi
    else
        overlayicon=""
    fi
}

function updateDialog() {
    echo "${1}" >> "${dialogLog}"
    sleep 0.4
}

function buildInfoTextScriptVersion() {
    case ${debugMode} in
        "true" ) infoTextScriptVersion="DEBUG MODE | Dialog: v${dialogVersion} • ${scriptName}: v${scriptVersion}" ;;
        "verbose" ) infoTextScriptVersion="VERBOSE DEBUG MODE | Dialog: v${dialogVersion} • ${scriptName}: v${scriptVersion}" ;;
        "false" ) infoTextScriptVersion="${scriptVersion}" ;;
    esac
}

function versionAtLeast() {
    emulate -L zsh
    local current="${1%%[^0-9.]*}"
    local required="${2%%[^0-9.]*}"
    local -a currentParts requiredParts
    local index

    currentParts=("${(@s:.:)current}")
    requiredParts=("${(@s:.:)required}")
    for index in 1 2 3 4; do
        if (( ${currentParts[$index]:-0} > ${requiredParts[$index]:-0} )); then
            return 0
        fi
        if (( ${currentParts[$index]:-0} < ${requiredParts[$index]:-0} )); then
            return 1
        fi
    done
    return 0
}

function dialogInstall() {
    if isDryRun; then
        dialogVersion="${swiftDialogMinimumRequiredVersion}"
        dryRunOut "Would install or update swiftDialog to at least version ${swiftDialogMinimumRequiredVersion}"
        return 0
    fi

    # Get the URL of the latest PKG From the Dialog GitHub repo
    if ! dialogURL=$(/usr/bin/curl --location --silent --show-error --fail \
        --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 2 --retry-all-errors \
        "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" |
        awk -F '"' '/browser_download_url/ && /pkg"/ { print $4; exit }'); then
        errorOut "Unable to query the swiftDialog release API."
        return 1
    fi
    if [[ -z "$dialogURL" || "$dialogURL" != https://github.com/swiftDialog/swiftDialog/releases/download/*/*.pkg ]]; then
        errorOut "The swiftDialog release API returned an unexpected package URL."
        return 1
    fi

    # Expected Team ID of the downloaded PKG
    expectedDialogTeamID="PWA5E9TQ59"

    preFlight "Installing swiftDialog..."

    # Create temporary working directory
    workDirectory=$(/usr/bin/basename "$0")
    tempDirectory=$(/usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX") || return 1

    # Download the installer package
    if ! /usr/bin/curl --location --silent --show-error --fail \
        --connect-timeout 10 --max-time 600 --retry 3 --retry-delay 2 --retry-all-errors \
        "$dialogURL" -o "$tempDirectory/Dialog.pkg"; then
        errorOut "Unable to download swiftDialog."
        /bin/rm -Rf -- "$tempDirectory"
        return 1
    fi

    # Verify the download
    teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')

    # Install the package if Team ID validates
    if [[ "$expectedDialogTeamID" == "$teamID" ]]; then
        if ! /usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /; then
            errorOut "swiftDialog package installation failed."
            /bin/rm -Rf -- "$tempDirectory"
            return 1
        fi
        sleep 2
        dialogVersion=$(/usr/local/bin/dialog --version)
        preFlight "swiftDialog version ${dialogVersion} installed; proceeding..."
    else
        errorOut "Unable to verify the swiftDialog team ID. Not installing or updating."
        /bin/rm -Rf -- "$tempDirectory"
        return 1
    fi

    /bin/rm -Rf -- "$tempDirectory"
}

function dialogCheck() {
    if isDryRun; then
        dialogVersion="${dialogVersion:-${swiftDialogMinimumRequiredVersion}}"
        preFlight "Dry run enabled; swiftDialog install and version checks will be simulated"
        return 0
    fi

    if [ "$osMajorVersion" -lt 12 ]; then
        swiftDialogMinimumRequiredVersion="2.4.2"
    else
        swiftDialogMinimumRequiredVersion="2.5.2"
    fi

    if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then
        preFlight "swiftDialog not found. Installing..."
        dialogInstall
    else
        dialogVersion=$(/usr/local/bin/dialog --version)
        if ! versionAtLeast "$dialogVersion" "$swiftDialogMinimumRequiredVersion"; then
            preFlight "swiftDialog version ${dialogVersion} found but swiftDialog ${swiftDialogMinimumRequiredVersion} or newer is required; updating..."
            dialogInstall
        else
            preFlight "swiftDialog version ${dialogVersion} found; proceeding..."
        fi
    fi
}

function prepareDialogEnvironment() {
    preFlight "Check for macOS ${osMajorVersion}..."
    if [[ "${osMajorVersion}" -ge 12 ]]; then
        preFlight "macOS ${osMajorVersion} installed; proceeding ..."
        dialogCheck
    else
        preFlight "macOS ${osMajorVersion} installed; Using osascript"
    fi
}

function buildReEnrollDialog() {
    inventoryProgressText="Initializing …"
    buildInfoTextScriptVersion

    typeset -ga dialogReEnrollArgs
    dialogReEnrollArgs=(
        --title "$title"
        --titlefont "name=Arial, size=25"
        --icon "$icon"
        --message ""
        --overlayicon "$overlayicon"
        --helpmessage "$helpMessage"
        --height 450
        --width 725
        --windowbuttons min
        --position center
        --ontop
        --button1text "Close"
        --moveable
        --listitem "ReEnroll in progress …"
        --progress
        --titlefont size=20
        --messagefont size=14
        --infobox "**Computer Name:**  \n\n • $computerName  \n\n **macOS Version:**  \n\n • $osVersionFull"
        --progresstext "$inventoryProgressText"
        --infotext "$infoTextScriptVersion"
        --quitkey K
        --commandfile "$dialogLog"
    )
}

function evalReEnrollDialog() {
    if isDryRun; then
        notice "Create ReEnroll dialog …"
        dryRunOut "Would display the ReEnroll progress dialog"
        return 0
    fi

    notice "Create ReEnroll dialog …"
    "$dialogBinary" "${dialogReEnrollArgs[@]}" &
    dialogPid=$!

    updateDialog "listitem: delete, title: ReEnroll in progress …"
    updateDialog "progresstext: Initializing…"
}

function killProcess() {
    local process="${1:-Dialog}"

    if [[ -n "${dialogPid}" ]] && kill -0 "${dialogPid}" 2>/dev/null; then
        infoOut "Terminating the tracked '${process}' process (PID ${dialogPid}) …"
        kill "${dialogPid}" 2>/dev/null || true
        wait "${dialogPid}" 2>/dev/null || true
    else
        infoOut "The tracked '${process}' process isn't running."
    fi
    dialogPid=""
}

function dialogExit() {

    if [[ "$unattendedExit" == "true" ]]; then
        infoOut "Unattended exit set to 'true', waiting $unattendedExitSeconds seconds then sending kill to Dialog"
        infoOut "Killing the dialog"
        killProcess "Dialog"
    else
        infoOut "Unattended exit set to 'false', leaving dialog on screen"
    fi
}

function completeReEnrollDialog() {

    infoOut "Checking if Dialog is running or closed for another prompt"

    if [[ -n "${dialogPid}" ]] && kill -0 "${dialogPid}" 2>/dev/null; then
        infoOut "Dialog is running."
        infoOut "ReEnroll dialog is still running, proceeding"
        updateDialog "ontop: enabled"
        updateDialog "listitem: delete, title: ReEnroll in progress …,"
        updateDialog "icon: SF=checkmark.circle.fill,weight=bold,colour1=#00ff44,colour2=#075c1e"
        updateDialog "overlayicon: $overlayicon"
        updateDialog "progress: 100"
        updateDialog "progresstext: Done!"
        infoOut "Elapsed Time: $(printf '%dh:%dm:%ds\n' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))"
        sleep 10
    else
        infoOut "Dialog closed at some point. Calling window to show complete"
        "$dialogBinary" "${dialogReEnrollArgs[@]}" &
        dialogPid=$!
        infoOut "Complete ReEnroll dialog"
        updateDialog "icon: SF=checkmark.circle.fill,weight=bold,colour1=#00ff44,colour2=#075c1e"
        updateDialog "listitem: delete, title: ReEnroll in progress …"
        updateDialog "listitem: add, title: ReEnroll Complete, icon: $overlayicon, statustext: Complete, status: success"
        updateDialog "overlayicon: $overlayicon"
        updateDialog "progress: 100"
        updateDialog "progresstext: Done!"
        infoOut "Elapsed Time: $(printf '%dh:%dm:%ds\n' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))"
        sleep 10
    fi
}

function jamfProfileRenew() {
    if isDryRun; then
        dryRunOut "Would display the profiles renew dialog"
        return 0
    fi

    local -a dialogUpdateArgs=(
        --title "Jamf Update Needed"
        --titlefont "name=Arial, size=25"
        --icon "$icon"
        --iconsize 90
        --overlayicon "$overlayicon"
        --message "Hello! Jamf, your Apple management software, needs to be updated. \n\nPlease choose **Options** and **Update** from the drop down menu, or double-click on the **Device Enrollment** notice located in your notifications center."
        --messagefont "name=Arial,size=15"
        --position bottomright
        --height 355
        --width 530
        --button1text "Update Now"
        --infobuttontext "Not Now"
        --helpmessage "$helpMessage"
        --timer 600
        --hidetimerbar
        --ontop
        --moveable
        --messagealignment left
        --commandfile "$updateDialogLog"
    )

    "$dialogBinary" "${dialogUpdateArgs[@]}"
}
# END INLINED MODULE: dialog.zsh
# BEGIN INLINED MODULE: jamf_api.zsh

function seedDryRunApiState() {
    local current_epoch

    current_epoch=$(date +%s)
    client_id="${client_id:-dry-run-client}"
    client_secret="${client_secret:-dry-run-secret}"
    apiBearerToken="${apiBearerToken:-dry-run-token}"
    APIAccess="Success"
    APIResult="Command Sent"
    token_expiration_epoch=$((current_epoch + 3600))
    computerID="${computerID:-0}"
    management_id="${management_id:-dry-run-management-id}"
    computerModel="${computerModel:-${modelName:-Dry Run Model}}"
    computerSite="${computerSite:-$(state_get "ComputerSite")}"
    computerSiteID="${computerSiteID:-$(state_get "ComputerSiteID")}"
}

function get_json_value() {
    JSON="$1" osascript -l 'JavaScript' \
        -e 'const env = $.NSProcessInfo.processInfo.environment.objectForKey("JSON").js' \
        -e "JSON.parse(env).$2"
}

function extract_from_json() {
    echo "$1" | awk -v key="$2" '
    BEGIN {
      RS = "[},]";
      FS = "[:,]";
    }
    {
      for (i = 1; i <= NF; i += 2) {
        if ($i ~ "\"" key "\"") {
          gsub(/["{}]/, "", $(i + 1));
          gsub(/^[\t ]+|[\t ]+$/, "", $(i + 1));
          print $(i + 1);
          exit;
        }
      }
    }
  '
}

function get_json_path() {
    JSON="$1" JSON_PATH="$2" /usr/bin/osascript -l JavaScript \
        -e 'const env = $.NSProcessInfo.processInfo.environment' \
        -e 'let value = JSON.parse(env.objectForKey("JSON").js)' \
        -e 'for (const part of env.objectForKey("JSON_PATH").js.split(".")) { value = value[part.match(/^\d+$/) ? Number(part) : part] }' \
        -e 'if (value === undefined || value === null) { $.exit(1) }' \
        -e 'typeof value === "object" ? JSON.stringify(value) : String(value)'
}

function jamfApiRequest() {
    emulate -L zsh
    local method="$1"
    local url="$2"
    local bodyFile httpStatus curlExit
    local -a curlArgs
    shift 2

    JAMF_HTTP_BODY=""
    JAMF_HTTP_STATUS="000"
    JAMF_HTTP_CURL_EXIT=0
    bodyFile=$(/usr/bin/mktemp /var/tmp/reenroll-http.XXXXXX) || return 1
    curlArgs=(
        --silent
        --show-error
        --location
        --proto '=https'
        --proto-redir '=https'
        --connect-timeout 10
        --max-time 120
        --output "${bodyFile}"
        --write-out '%{http_code}'
        --request "${method}"
    )
    if [[ "${method}" == "GET" || "${method}" == "HEAD" ]]; then
        curlArgs+=(--retry 3 --retry-delay 2)
    fi

    httpStatus=$(/usr/bin/curl "${curlArgs[@]}" "$@" "${url}")
    curlExit=$?
    JAMF_HTTP_BODY="$(<"${bodyFile}")"
    /bin/rm -f -- "${bodyFile}"
    JAMF_HTTP_STATUS="${httpStatus:-000}"
    JAMF_HTTP_CURL_EXIT="${curlExit}"

    (( curlExit == 0 )) || return 1
    [[ "${JAMF_HTTP_STATUS}" == <200-299> ]]
}

function check_token() {
    jamfApiRequest GET "${jssurl}api/v1/auth" \
        --header "Authorization: Bearer ${apiBearerToken}" || true
    apitokenCheck="${JAMF_HTTP_STATUS}"
    infoOut "API Bearer Token Check: ${apitokenCheck}"
    case ${apitokenCheck} in
        200)
            infoOut "API Bearer Token is Valid"
            APIResult="Token Good"
            ;;
        401)
            error "Authentication failed. Verify the credentials and URL being used for the request."
            APIResult="Failure"
            ;;
        403)
            error "Invalid permissions. Verify the account being used has the proper permissions for the resource you are trying to access."
            APIResult="Failure"
            ;;
        404)
            error "The resource you are trying to access could not be found. Check the URL and try again."
            APIResult="Failure"
            ;;
        *)
            error "Unknown error. Status code: ${apitokenCheck}"
            APIResult="Failure"
            ;;
    esac
}

function check_status() {
    local http_status="${1:-${JAMF_HTTP_STATUS:-000}}"
    if [[ "${http_status}" != <200-299> ]]; then
        APIResult="Failure"
    else
        APIResult="Command Sent"
    fi
}

function apiResponse() {
    local version
    local -a versions

    versions=(v3 v2 v1)
    for version in "${versions[@]}"; do
        if jamfApiRequest GET "${jssurl}api/${version}/computers-inventory" \
            --header "Authorization: Bearer ${apiBearerToken}" \
            --header "Accept: application/json" \
            --get \
            --data-urlencode "filter=hardware.serialNumber==\"${serialNumber}\"" \
            --data-urlencode "page-size=1"; then
            response="${JAMF_HTTP_BODY}"
            computerID="$(get_json_path "${response}" "results.0.id" 2>/dev/null || true)"
            if [[ -n "${computerID}" ]]; then
                jamfInventoryApiVersion="${version}"
                infoOut "Using Jamf Pro computer inventory API ${version}."
                return 0
            fi
        fi

        if [[ "${JAMF_HTTP_STATUS}" != "400" && "${JAMF_HTTP_STATUS}" != "404" ]]; then
            break
        fi
    done

    error "Unable to find this computer through a supported Jamf Pro inventory API (HTTP ${JAMF_HTTP_STATUS})."
    return 1
}

function computerIDLookup() {
    if [[ "$debugMode" = "verbose" ]]; then
        debugVerbose "Computer ID: $computerID"
    fi

    if ! jamfApiRequest GET "${jssurl}api/${jamfInventoryApiVersion}/computers-inventory/${computerID}" \
        --header "Authorization: Bearer ${apiBearerToken}" \
        --header "Accept: application/json" \
        --get \
        --data-urlencode "section=GENERAL" \
        --data-urlencode "section=HARDWARE"; then
        APIResult="Failure"
        error "Failed to gather computer inventory (HTTP ${JAMF_HTTP_STATUS})."
        return 1
    fi

    inventoryDetailJson="${JAMF_HTTP_BODY}"
    APIResult="Command Sent"
    infoOut "Successfully gathered computer inventory."
    management_id="$(get_json_path "${inventoryDetailJson}" "general.managementId" 2>/dev/null || true)"
    [[ -n "${management_id}" ]] || management_id="$(get_json_path "${inventoryDetailJson}" "managementId" 2>/dev/null || true)"

    if [[ "$debugMode" = "verbose" ]]; then
        debugVerbose "Management ID: $management_id"
    fi
}

function computerInventoryInfo() {
    computerName="$(get_json_path "${inventoryDetailJson}" "general.name" 2>/dev/null || true)"
    computerSerialNumber="$(get_json_path "${inventoryDetailJson}" "hardware.serialNumber" 2>/dev/null || true)"
    computerModel="$(get_json_path "${inventoryDetailJson}" "hardware.model" 2>/dev/null || true)"
    computerIpAddress="$(get_json_path "${inventoryDetailJson}" "general.lastIpAddress" 2>/dev/null || true)"
    computerIpAddressLastReported="$(get_json_path "${inventoryDetailJson}" "general.lastReportedIp" 2>/dev/null || true)"
    computerSite="$(get_json_path "${inventoryDetailJson}" "general.site.name" 2>/dev/null || true)"
    computerSiteID="$(get_json_path "${inventoryDetailJson}" "general.site.id" 2>/dev/null || true)"

    infoOut "Computer Site ID: $computerSiteID"
    infoOut "Adding computer site ID to ReEnroll Config File"
    state_set "ComputerSiteID" "$computerSiteID"
    infoOut "Computer Site Name: $computerSite"
    infoOut "Adding computer site to ReEnroll Config File"
    state_set "ComputerSite" "$computerSite"
    infoOut "Computer Model: $computerModel"

    if [[ "$debugMode" = "verbose" ]]; then
        debugVerbose "Redeploy Jamf Management Framework for:"
        debugVerbose "• Name: $computerName"
        debugVerbose "• Serial Number: $computerSerialNumber"
        debugVerbose "• Computer Model: $computerModel"
        debugVerbose "• IP Address: $computerIpAddress"
        debugVerbose "• IP Address (LR): $computerIpAddressLastReported"
        debugVerbose "• Computer Site: $computerSite"
        debugVerbose "• Computer Site: $computerSiteID"
        debugVerbose "• Server: ${jssurl}"
        debugVerbose "• Computer ID: ${computerID}"
    fi
}

function clearFailedCommands() {
    if isDryRun; then
        notice "Brute-force clear all failed MDM Commands"
        dryRunOut "Would clear failed MDM commands for computer ID ${computerID}"
        APIResult="Command Sent"
        updateDialog "listitem: title: Gathering Computer Information, icon: SF=pencil.and.list.clipboard,weight=bold, statustext: Complete, status: success"
        return 0
    fi

    notice "Brute-force clear all failed MDM Commands"
    jamfApiRequest DELETE "${jssurl}JSSResource/commandflush/computers/id/${computerID}/status/Failed" \
        --header "Authorization: Bearer ${apiBearerToken}" || true
    clearFailedCommandsResult="${JAMF_HTTP_BODY}"
    check_status "${JAMF_HTTP_STATUS}"

    if [ "$APIResult" = "Failure" ]; then
        errorOut "Failed to clear all failed MDM Commands, error: $APIResult"
    else
        infoOut "Cleared all failed MDM Commands, result: $APIResult"
    fi

    if [ "$APIResult" = "Failure" ]; then
        error "API Command flush could not be cleared, result: $APIAccess"
        updateDialog "listitem: add, title: Gathering Computer Information, icon: SF=pencil.and.list.clipboard,weight=bold, statustext: Error, status: error"
    elif [ "$APIResult" = "Command Sent" ]; then
        infoOut "All Failed MDM Commands have been cleared, result: $APIResult"
        updateDialog "listitem: title: Gathering Computer Information, icon: SF=pencil.and.list.clipboard,weight=bold, statustext: Complete, status: success"
    else
        error "API Command flush could not be cleared, check API credentials and API permissions"
        updateDialog "listitem: add, title: Gathering Computer Information, icon: SF=pencil.and.list.clipboard,weight=bold, statustext: Error, status: error"
    fi
}

function redeployJamfFramework() {
    if isDryRun; then
        notice "Redeploy Jamf binary"
        dryRunOut "Would redeploy the Jamf management framework for computer ID ${computerID}"
        APIResult="Command Sent"
        state_set "ReEnrollMethod" "Redeploy Jamf Framework"
        if [ "$displayReEnrollDialog" = "true" ]; then
            updateDialog "listitem: title: Deploy Jamf Framework, icon: SF=icloud.and.arrow.down.fill,weight=bold, statustext: Complete, status: success"
            updateDialog "progresstext: Jamf Management Framework redeploy simulated"
        fi
        infoOut "Jamf Management Framework redeploy simulated"
        return 0
    fi

    notice "Redeploy Jamf binary"
    jamfApiRequest POST "${jssurl}api/v1/jamf-management-framework/redeploy/${computerID}" \
        --header "Authorization: Bearer ${apiBearerToken}" \
        --header "Accept: application/json" || true
    redeployResult="${JAMF_HTTP_BODY}"
    check_status "${JAMF_HTTP_STATUS}"
    state_set "ReEnrollMethod" "Redeploy Jamf Framework"

    if [ "$displayReEnrollDialog" = "true" ]; then
        if [ "$APIResult" = "Failure" ]; then
            updateDialog "listitem: title: Deploy Jamf Framework, icon: SF=icloud.and.arrow.down.fill,weight=bold, statustext: Error, status: error"
            updateDialog "progresstext: Jamf Management Framework unable to redeploy"
            errorOut "Jamf Management Framework unable to redeploy, error: $APIResult"
        else
            updateDialog "listitem: title: Deploy Jamf Framework, icon: SF=icloud.and.arrow.down.fill,weight=bold, statustext: Complete, status: success"
            updateDialog "progresstext: Jamf Management Framework redeployed"
            infoOut "Jamf Management Framework redeployed, result: $APIResult"
        fi
    else
        infoOut "Display ReEnroll Dialog set to false, skipping dialog"
    fi
}

function getAccessToken() {
    if isDryRun; then
        seedDryRunApiState
        infoOut "Dry run enabled; simulating API bearer token"
        return 0
    fi

    if ! jamfApiRequest POST "${jssurl}api/oauth/token" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=${client_id}" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_secret=${client_secret}"; then
        APIAccess="Failure"
        APIResult="Failure"
        error "Unable to obtain a Jamf API token (HTTP ${JAMF_HTTP_STATUS}, curl ${JAMF_HTTP_CURL_EXIT})."
        return 1
    fi
    tokenResponse="${JAMF_HTTP_BODY}"

    apiBearerToken="$(get_json_path "${tokenResponse}" "access_token" 2>/dev/null || true)"
    if [[ -z "${apiBearerToken}" ]]; then
        APIAccess="Failure"
        APIResult="Failure"
        error "Jamf API token response did not contain an access token."
        return 1
    fi
    check_token "$tokenResponse"
    if [ "$APIResult" = "Failure" ]; then
        APIAccess="Failure"
        error "API Access result: $APIAccess"
    elif [ "$APIResult" = "Token Good" ]; then
        infoOut "API Bearer Token obtained"
        APIAccess="Success"
        infoOut "API Access result: $APIAccess"
        token_expires_in="$(get_json_path "${tokenResponse}" "expires_in" 2>/dev/null || print 0)"
        [[ "${token_expires_in}" == <1-> ]] || token_expires_in=1200
        current_epoch=$(date +%s)
        token_expiration_epoch=$((current_epoch + token_expires_in - 1))
    else
        error "API Bearer Token could not be obtained, check API credentials and API permissions"
        APIAccess="Failure"
    fi
    echo $APIAccess > /dev/null 2>&1
}

function checkTokenExpiration() {
    if isDryRun; then
        seedDryRunApiState
        notice "Dry run token valid until: $(date -r "$token_expiration_epoch" "+%Y-%m-%d %H:%M:%S %Z")"
        return 0
    fi

    current_epoch=$(date +%s)
    if (( token_expiration_epoch >= current_epoch )); then
        token_expiration_date=$(date -r "$token_expiration_epoch" "+%Y-%m-%d %H:%M:%S %Z")
        notice "Token valid until: $token_expiration_date"
    else
        infoOut "No valid token available, getting new token"
        getAccessToken
    fi
}

function jmfrdeploy() {
    if isDryRun; then
        seedDryRunApiState
        infoOut "Dry run enabled; simulating Jamf API inventory and framework redeploy workflow"
        updateDialog "progresstext: Dry run enabled; simulating Jamf API access"
        updateDialog "listitem: add, title: Gathering Computer Information, icon: SF=pencil.and.list.clipboard,weight=bold, statustext: Simulated, status: success"
        state_set "ComputerSiteID" "${computerSiteID:-0}"
        state_set "ComputerSite" "${computerSite:-No Site}"
        clearFailedCommands
        if [ "$redeployFramework" = "true" ]; then
            redeployJamfFramework
        else
            notice "Dry run enabled; Jamf framework redeploy not requested"
        fi
        return 0
    fi

    getAccessToken
    updateDialog "progresstext: Checking token expiration"
    checkTokenExpiration
    updateDialog "progresstext: Getting API access token"
    updateDialog "progresstext: Checking for API credentials"
    if [ -z "$client_id" ] || [ -z "$client_secret" ]; then
        notice "API credentials not set, skipping getting computer inventory"
        updateDialog "progresstext: API credentials are not set"
    elif [ "$APIAccess" = "Failure" ]; then
        error "API access failed, skipping getting computer inventory"
        updateDialog "progresstext: API Access Failure"
        updateDialog "listitem: add, title: Gathering Computer Information, icon: SF=pencil.and.list.clipboard,weight=bold, statustext: Error, status: error"
    elif [ "$APIAccess" = "Success" ]; then
        updateDialog "listitem: add, title: Gathering Computer Information, icon: SF=pencil.and.list.clipboard,weight=bold, statustext: Checking …, status: wait"
        updateDialog "listitem: delete, title: ReEnroll in progress …,"
        infoOut "API credentials set, continuing"
        updateDialog "progresstext: API credentials set, continuing"
        if ! apiResponse || ! computerIDLookup; then
            updateDialog "progresstext: Unable to gather Jamf inventory"
            return 1
        fi
        updateDialog "progresstext: Checking computer inventory"
        computerInventoryInfo
        updateDialog "progresstext: Clearing failed MDM commands"
        clearFailedCommands
        if [ "$displayReEnrollDialog" = "true" ] && [ "$redeployFramework" = "true" ]; then
            infoOut "Display ReEnroll Dialog and 'Redeploy Framework' set to true"
            updateDialog "listitem: title: Gathering Computer Information, icon: SF=pencil.and.list.clipboard,weight=bold, statustext: Complete, status: success"
            updateDialog "listitem: add, title: Deploy Jamf Framework, icon: SF=icloud.and.arrow.down.fill,weight=bold, statustext: Checking…, status: wait"
            updateDialog "listitem: delete, title: ReEnroll in progress …,"
            updateDialog "progresstext: Checking for API credentials"
            updateDialog "progresstext: Jamf Management Framework deploying"
            redeployJamfFramework
        elif [ "$displayReEnrollDialog" = "false" ] && [ "$redeployFramework" = "true" ]; then
            infoOut "Display ReEnroll Dialog set to false and 'Redeploy Framework' set to true, skipping dialog"
            redeployJamfFramework
        else
            notice "Skipping Redeploy of Jamf management framework with displayReEnrollDialog set to false and 'Redeploy Framework' set to false"
        fi
    else
        notice "Skipping Redeploy of Jamf management framework"
    fi
}

function jssConnectionStatus() {
    if isDryRun; then
        scriptResult+="Check for Jamf Pro server connection; "
        jssAvailable="yes"
        infoOut "Dry run enabled; simulating Jamf Pro server connection"
        return 0
    fi

    scriptResult+="Check for Jamf Pro server connection; "

    unset jssStatus
    if [[ -z "${jamfBinary}" || ! -x "${jamfBinary}" ]]; then
        jssAvailable="not installed"
        return 0
    fi
    jssStatus=$("${jamfBinary}" checkJSSConnection 2>&1 | /usr/bin/tr -d '\n')

    case "${jssStatus}" in
        *"The JSS is available." ) jssAvailable="yes" ;;
        *"No such file or directory" ) jssAvailable="not installed" ;;
        * ) jssAvailable="unknown" ;;
    esac
}

function validatePolicy() {
    if isDryRun; then
        policyStatus="yes"
        currentPolicyStatus="Dry run policy validation"
        infoOut "Dry run enabled; simulating Jamf policy validation"
        return 0
    fi

    jamfLogFile="/var/log/jamf.log"
    duplicate_jamfLogFile="$duplicate_log_dir/jamf_position_$timestamp.log"

    if [[ -z "${marker_file}" || ! -f "${marker_file}" ]]; then
        createMarkerFile
    fi

    if [ -f "$marker_file" ]; then
        lastPosition=$(cat "$marker_file")
    else
        lastPosition=0
    fi

    tail -n +$((lastPosition + 1)) "$jamfLogFile" >> "$duplicate_jamfLogFile"
    wc -l "$jamfLogFile" | awk '{print $1}' > "$marker_file"

    lastPosition=$(cat "$marker_file")
    if [[ "$debugMode" = "verbose" ]]; then
        debugVerbose "Last jamf.log position: $lastPosition"
    fi

    policyStatus=$(tail -n1 "$duplicate_jamfLogFile" | awk -F': ' '{print $NF}' | sed -e 's/Removing existing launchd task \/Library\/LaunchDaemons\/com.jamfsoftware.task.bgrecon.plist... //g')
    currentPolicyStatus=$(tail -n1 "$duplicate_jamfLogFile" | awk -F': ' '{print $NF}' | sed -e 's/Removing existing launchd task \/Library\/LaunchDaemons\/com.jamfsoftware.task.bgrecon.plist... //g')

    if [ "$redeployFramework" = "false" ] || [ "$sendEnrollmentInvitation" = "false" ] || [ "$renewProfiles" = "false" ]; then
        case "${policyStatus}" in
            *"No patch policies were found." ) policyStatus="yes" ;;
            *"Removing existing launchd task /Library/LaunchDaemons/com.jamfsoftware.task.bgrecon.plist..." ) policyStatus="yes" ;;
            *"There was an error.

            Unknown Error - An unknown error has occurred" ) policyStatus="connection error" ;;
            * ) policyStatus="unknown" ;;
        esac
    else
        case "${policyStatus}" in
            *"Checking for policies triggered by \"enrollmentComplete\" for user \"${loggedInUser}\"..." ) policyStatus="yes" ;;
            *"Enroll return code:" ) policyStatus="yes" ;;
            *"There was an error.

            Unknown Error - An unknown error has occurred" ) policyStatus="connection error" ;;
            * ) policyStatus="unknown" ;;
        esac
    fi

    if [ "$debugMode" = "verbose" ]; then
        debugVerbose "Current policyStatus: $policyStatus"
        debugVerbose "Current jamf.log status: $currentPolicyStatus"
    fi
}

function validateInventory() {
    if isDryRun; then
        scriptResult+="Check for Jamf Pro inventory connection; "
        inventoryStatus="yes"
        infoOut "Dry run enabled; simulating Jamf inventory validation"
        return 0
    fi

    scriptResult+="Check for Jamf Pro inventory connection; "

    inventoryStatus=$(tail -n1 "$tempInventoryLog" | sed -e 's/verbose: //g' -e 's/Found app: \/System\/Applications\///g' -e 's/Utilities\///g' -e 's/Found app: \/Applications\///g' -e 's/Running script for the extension attribute //g')

    case "${inventoryStatus}" in
        *"Removing existing launchd task /Library/LaunchDaemons/com.jamfsoftware.task.bgrecon.plist..." ) inventoryStatus="yes" ;;
        *"There was an error.

     Unknown Error - An unknown error has occurred" ) inventoryStatus="connection error" ;;
        * ) inventoryStatus="unknown" ;;
    esac
}

function triggerEnrollment() {
    if isDryRun; then
        dryRunOut "Would prompt enrollment renewal for uid ${uid}"
        return 0
    fi

    notice "Displaying enrollment window"
    /bin/launchctl asuser "${uid}" /usr/bin/profiles renew -type enrollment
}
# END INLINED MODULE: jamf_api.zsh
# BEGIN INLINED MODULE: launchd.zsh

function reconLaunchDaemon() {
    if isDryRun; then
        dryRunOut "Would create and bootstrap the recon LaunchDaemon workflow"
        return 0
    fi

    if [[ -z "${jamfBinary:-}" || ! -x "${jamfBinary}" ]]; then
        jamfBinary="$(findJamfBinary || true)"
    fi
    if [[ -z "${jamfBinary}" ]]; then
        errorOut "Unable to create the recon LaunchDaemon because the Jamf binary is unavailable"
        return 1
    fi

    if [[ "$debugMode" = "verbose" ]]; then
        debugVerbose "Creating organization folder if necessary to house the jamf-recon.zsh script"
        debugVerbose "Creating jamf-recon.zsh script"
        debugVerbose "Setting correct ownership and permissions on jamf-recon.zsh script"
        debugVerbose "Creating $organizationReverseDomain.jamf-recon.plist launch daemon"
        debugVerbose "Setting correct ownership and permissions on launch daemon"
        debugVerbose "Setting start launch daemon after policy"
    fi

    /bin/mkdir -p "/Library/$organizationName"

    if [ "$sendEnrollmentInvitation" = "true" ]; then
        rotatePasswordCommand='echo "$(date +"%Y-%m-%d %H:%M:%S") - [RECON DAEMON] Attempting to rotate Management Account Password" >> "'"$scriptLog"'"
    /usr/local/bin/jamf policy -event rotateManagementAccountPassword
    rotateStatus=$?
    if [ $rotateStatus -eq 0 ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - [RECON DAEMON] Successfully sent rotate password command" >> "'"$scriptLog"'"
    else
        echo "$(date +"%Y-%m-%d %H:%M:%S") - [RECON DAEMON] Error sending rotate password command (exit code: $rotateStatus)" >> "'"$scriptLog"'"
    fi'
    else
        rotatePasswordCommand='echo "$(date +"%Y-%m-%d %H:%M:%S") - [RECON DAEMON] Management Account Password will not be rotated" >> "'"$scriptLog"'"'
    fi
    rotatePasswordCommand="${rotatePasswordCommand//\/usr\/local\/bin\/jamf/${jamfBinary}}"

    tee "/Library/$organizationName/jamf-recon.zsh" << EOF
#!/bin/zsh --no-rcs

RECON_LOG="$scriptLog"

log_message() {
    echo "\$(date +"%Y-%m-%d %H:%M:%S") - [RECON DAEMON] \$1" >> "\$RECON_LOG"
}

log_message "=== Recon LaunchDaemon Started ==="

log_message "Running Jamf recon for user: $networkUser"
"${jamfBinary}" recon -endUsername "$networkUser" >> "\$RECON_LOG" 2>&1
reconStatus=\$?
if [ \$reconStatus -eq 0 ]; then
    log_message "Jamf recon completed successfully"
else
    log_message "Jamf recon failed with exit code: \$reconStatus"
fi

log_message "Running Jamf policy"
"${jamfBinary}" policy >> "\$RECON_LOG" 2>&1
policyStatus=\$?
if [ \$policyStatus -eq 0 ]; then
    log_message "Jamf policy completed successfully"
else
    log_message "Jamf policy failed with exit code: \$policyStatus"
fi

$rotatePasswordCommand

log_message "Checking admin status for user: $loggedInUser"
if /usr/sbin/dseditgroup -o checkmember -m "$loggedInUser" admin | /usr/bin/grep -q "is a member"; then
    log_message "$loggedInUser is an admin. Removing from the admin group..."
    /usr/sbin/dseditgroup -o edit -d "$loggedInUser" -t user admin
    if [ \$? -eq 0 ]; then
        log_message "$loggedInUser has been removed from the admin group"
    else
        log_message "Failed to remove $loggedInUser from admin group"
    fi
else
    log_message "$loggedInUser is not an admin"
fi

log_message "Cleaning up LaunchDaemon files"

/bin/rm "/Library/$organizationName/jamf-recon.zsh"
/bin/rmdir "/Library/$organizationName" 2>/dev/null
/bin/rm "/Library/LaunchDaemons/$organizationReverseDomain.jamf-recon.plist"
/bin/launchctl remove "$organizationReverseDomain.jamf-recon"

log_message "=== Recon LaunchDaemon Completed ==="

exit 0
EOF

    /usr/sbin/chown root:wheel "/Library/$organizationName/jamf-recon.zsh" && /bin/chmod +x "/Library/$organizationName/jamf-recon.zsh"

    tee /Library/LaunchDaemons/$organizationReverseDomain.jamf-recon.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>EnvironmentVariables</key>
<dict>
<key>PATH</key>
<string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
</dict>
<key>Label</key>
<string>$organizationReverseDomain.jamf-recon</string>
<key>ProgramArguments</key>
<array>
<string>/bin/zsh</string>
<string>-c</string>
<string>/Library/$organizationName/jamf-recon.zsh</string>
</array>
<key>RunAtLoad</key>
<true/>
<key>StartInterval</key>
<integer>1</integer>
<key>StandardOutPath</key>
<string>/var/log/com.tamu.jamf-recon.stdout.log</string>
<key>StandardErrorPath</key>
<string>/var/log/com.tamu.jamf-recon.stderr.log</string>
</dict>
</plist>
EOF

    /usr/sbin/chown root:wheel /Library/LaunchDaemons/$organizationReverseDomain.jamf-recon.plist && /bin/chmod 644 /Library/LaunchDaemons/$organizationReverseDomain.jamf-recon.plist
    /bin/launchctl bootstrap system "/Library/LaunchDaemons/$organizationReverseDomain.jamf-recon.plist" && \
        /bin/launchctl kickstart -k "system/$organizationReverseDomain.jamf-recon"
}
# END INLINED MODULE: launchd.zsh
# BEGIN INLINED MODULE: webhooks.zsh

function webHookMessage() {
    if isDryRun; then
        dryRunOut "Would send webhook notifications to configured Slack and Teams destinations"
        return 0
    fi

    if [[ -z "$slackURL" ]]; then
        infoOut "No slack URL configured"
    else
        if [[ -z "$supportTeamHyperlink" ]]; then
            supportTeamHyperlink="https://www.slack.com"
        fi

        if [[ -z "$client_id" || -z "$client_secret" ]] || [ "$APIAccess" = "Failure" ]; then
            webhookComputerModel="$modelName"
        else
            webhookComputerModel="$computerModel"
        fi

        infoOut "Sending Slack WebHook"
        if ! /usr/bin/curl --silent --show-error --fail \
            --connect-timeout 10 --max-time 30 \
            --request POST --header 'Content-type: application/json' \
            -d \
            '{
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "'${scriptName}': '"${webhookStatus}"'"
            }
        },
        {
            "type": "divider"
        },
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": ">*Serial Number and Computer Name:*\n>'"$serialNumber"' on '"$computerName"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Computer Model:*\n>'"$webhookComputerModel"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Current User:*\n>'"$loggedInUserFirstname $loggedInUserLastname (User ID: $loggedInUser)"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Notification Status:*\n>'"$webhookStatus"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*ReEnrollment Method:*\n>'"$reEnrollMethod"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Computer Record:*\n>'"$jamfProComputerURL"'"
                }
            ]
        },
        {
        "type": "actions",
            "elements": [
                {
                    "type": "button",
                    "text": {
                        "type": "plain_text",
                        "text": "View computer in Jamf Pro",
                        "emoji": true
                    },
                    "style": "primary",
                    "action_id": "actionId-0",
                    "url": "'"$jamfProComputerURL"'"
                }
            ]
        }
    ]
}' \
            "$slackURL"; then
            warning "Slack webhook delivery failed."
        fi
    fi

    if [[ -z "$teamsURL" ]]; then
        infoOut "No teams Webhook configured"
    else
        if [[ -z "$supportTeamHyperlink" ]]; then
            supportTeamHyperlink="https://www.microsoft.com/en-us/microsoft-teams/"
        fi

        if [[ -z "$client_id" || -z "$client_secret" ]] || [ "$APIAccess" = "Failure" ]; then
            webhookComputerModel="$modelName"
        else
            webhookComputerModel="$computerModel"
        fi

        infoOut "Sending Teams WebHook"
        jsonPayload='{
    "@type": "AdaptiveCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "0076D7",
    "summary": "'${scriptName}': '${webhookStatus}'",
    "sections": [{
        "activityTitle": "'${scriptName}': '${webhookStatus}'",
        "activityImage": "https://raw.githubusercontent.com/AndrewMBarnett/ReEnroll/refs/heads/main/Extras/Images/systemSettings.png",
        "facts": [{
            "name": "Computer Name (Serial Number):",
            "value": "'"$computerName"' ('"$serialNumber"')"
        }, {
            "name": "Computer Model:",
            "value": "'"$webhookComputerModel"'"
        }, {
            "name": "Current User:",
            "value": "'"$loggedInUserFirstname $loggedInUserLastname (User ID: $loggedInUser)"'"
        }, {
            "name": "Notification Status:",
            "value": "'"$webhookStatus"'"
        }, {
            "name": "ReEnrollment Method:",
            "value": "'"$reEnrollMethod"'"
        }, {
            "name": "Computer Record:",
            "value": "'"$jamfProComputerURL"'"
        }],
        "markdown": true
    }],
    "potentialAction": [{
        "@type": "OpenUri",
        "name": "View in Jamf Pro",
        "targets": [{
            "os": "default",
            "uri":
            "'"$jamfProComputerURL"'"
        }]
    }]
}'

        if ! /usr/bin/curl --silent --show-error --fail \
            --connect-timeout 10 --max-time 30 \
            --request POST --header "Content-Type: application/json" \
            --data "$jsonPayload" "$teamsURL"; then
            warning "Teams webhook delivery failed."
        fi
    fi
}
# END INLINED MODULE: webhooks.zsh
# BEGIN INLINED MODULE: laps.zsh

function deleteLAPSAccount() {
    if isDryRun; then
        dryRunOut "Would delete the LAPS account '${lapsAdminAccount}' if present"
        return 0
    fi

    if [ "$skipAccountDeletion" = "false" ]; then
        notice "Skip Account Deletion is set to false, proceeding"
        if [ -n "$lapsAdminAccount" ]; then
            notice "Deleting LAPS account: ${lapsAdminAccount}"
            /usr/bin/dscl . -delete /Users/"$lapsAdminAccount"
        else
            notice "No LAPS account to delete"
        fi
    elif [ "$skipAccountDeletion" = "" ]; then
        infoOut "Skip Account Deletion is set blank, skipping"
    else
        infoOut "Skip Account Deletion is set to true, skipping"
    fi
}

function check_user_exists() {
    local username="$1"
    if id -u "${username}" >/dev/null 2>&1; then
        infoOut "Admin account ${lapsAdminAccount} exist..."
        updateDialog "progresstext: LAPS Admin Account exists..."
        return 0
    else
        infoOut "Admin account ${lapsAdminAccount} does not exist..."
        updateDialog "progresstext: LAPS Admin Account does not exists..."
        return 1
    fi
}

function validate_password() {
    if isDryRun; then
        lapsPassword="dry-run-password"
        authResult=0
        infoOut "Dry run enabled; simulating validation for $lapsAdminAccount"
        updateDialog "progresstext: Dry run enabled; LAPS Admin Account Password validation simulated..."
        return 0
    fi

    checkTokenExpiration

    jamfApiRequest GET "${jssurl}api/v2/local-admin-password/${management_id}/account/${lapsAdminAccount}/password" \
        --header 'Accept: application/json' \
        --header "Authorization: Bearer ${apiBearerToken}" || true
    lapsPasswordInformation="${JAMF_HTTP_BODY}"
    check_status "${JAMF_HTTP_STATUS}"
    if [ "$APIResult" = "Failure" ]; then
        error "Failed to gather the LAPS password (HTTP ${JAMF_HTTP_STATUS})."
        return 1
    else
        infoOut "Successfully gathered LAPS Password, result: $APIResult"
    fi

    lapsPassword=$(get_json_value "$lapsPasswordInformation" 'password')

    infoOut "Authenticating $lapsAdminAccount password..."
    updateDialog "progresstext: Checking LAPS Admin Password credentials..."
    dscl /Local/Default -authonly "$lapsAdminAccount" "$lapsPassword"
    authResult=$?

    if [ $authResult -eq 0 ]; then
        infoOut "$lapsAdminAccount authentication succeeded"
        updateDialog "progresstext: LAPS Admin Account Password are valid..."
    else
        error "$lapsAdminAccount authentication failed"
        updateDialog "progresstext: LAPS Admin Account Password are invalid..."
    fi
}

function checkLAPSAccount() {
    if ! check_user_exists "$lapsAdminAccount"; then
        error "User $lapsAdminAccount does not exist."
        return 1
    fi

    infoOut "Checking password for user $lapsAdminAccount..."
    validate_password
    if [ $authResult -eq 0 ]; then
        notice "Password for user $lapsAdminAccount is correct."
        return 0
    else
        error "Password for user $lapsAdminAccount is incorrect."
        return 1
    fi
}

function updateLAPSPassword() {
    if isDryRun; then
        randomPassword="dry-run-password"
        APIResult="Command Sent"
        dryRunOut "Would update the LAPS password for '${lapsAdminAccount}'"
        return 0
    fi

    randomPassword=$(openssl rand -base64 29 | tr -d '=' | cut -c 1-30)

    checkTokenExpiration
    apiResponse || return 1
    computerIDLookup || return 1

    jamfApiRequest PUT "${jssurl}api/v2/local-admin-password/${management_id}/set-password" \
        --header 'Accept: application/json' \
        --header "Authorization: Bearer ${apiBearerToken}" \
        --header 'Content-Type: application/json' \
        --data "{
    \"lapsUserPasswordList\": [
        {
        \"username\": \"$lapsAdminAccount\",
        \"password\": \"$randomPassword\"
        }
    ]
    }" || true
    setLAPSPassword="${JAMF_HTTP_BODY}"
    check_status "${JAMF_HTTP_STATUS}"
    if [ "$APIResult" = "Failure" ]; then
        error "Failed to set the LAPS password (HTTP ${JAMF_HTTP_STATUS})."
        return 1
    else
        infoOut "Successfully set LAPS Password, result: $APIResult"
    fi
}

function rotateLAPSPassword() {
    if isDryRun; then
        dryRunOut "Would rotate the LAPS password for '${lapsAdminAccount}'"
        verifyLAPSCredentials
        return 0
    fi

    checkTokenExpiration

    notice "Sending rotate Management Account Password command..."
    updateDialog "progresstext: Checking enrollment..."
    updateLAPSPassword

    sleep 10

    infoOut "Sending Rotate Management Account Password Command "
    if [[ -z "${jamfBinary}" || ! -x "${jamfBinary}" ]]; then
        error "The Jamf binary is unavailable; the management account password cannot be rotated locally."
        return 1
    fi
    "${jamfBinary}" rotateManagementAccountPassword

    verifyLAPSCredentials
}

function verifyLAPSCredentials() {
    if isDryRun; then
        scriptResult+="Check for LAPS account and password; "
        lap_Status=0
        infoOut "Dry run enabled; simulating successful LAPS credential verification"
        return 0
    fi

    scriptResult+="Check for LAPS account and password; "

    lap_Status=1
    LAPScounter=1
    until [[ "$lap_Status" -eq 0 ]] || [[ "$LAPScounter" -gt 2 ]]; do
        scriptResult+="Check ${LAPScounter} of 2: LAPS account not valid; waiting to re-check; "
        sleep 60
        checkLAPSAccount "$jssurl" "$management_id" "$apiBearerToken" "$lapsAdminAccount" "$lapsPassword"
        lap_Status=$?

        if [[ "$lap_Status" -ne 0 ]]; then
            notice "Sending enrollment invitation..."
            reEnrollInvitation
        fi

        ((LAPScounter++))
    done
}

function checkLAPSAccountStatus() {
    if isDryRun; then
        verifyLAPSCredentials
        state_set "ReEnrollNotificationStatus" "No Notification"
        webhookStatus="ReEnroll without notification"
        if [[ -z "$reEnrollMethod" ]]; then
            reEnrollMethod="Silent Redeploy of the Jamf Management Framework (Dry Run)"
        fi
        if [ "$skipLaunchDaemon" = "false" ]; then
            reconLaunchDaemon
        fi
        infoOut "Dry run enabled; LAPS account status handling simulated"
        return 0
    fi

    if [ "$displayReEnrollDialog" = "true" ]; then
        notice "Adding 'LAPS Admin Check' dialog"
        updateDialog "listitem: add, title: LAPS Admin Check, icon: SF=person.crop.circle.badge.clock.fill,weight=bold, statustext: Checking …, status: wait"
        updateDialog "listitem: delete, title: ReEnroll in progress …,"
        updateDialog "progresstext: Checking LAPS Admin Account credentials..."
    else
        notice "ReEnroll did not call for 'LAPS Admin Check' dialog"
    fi

    verifyLAPSCredentials

    if [[ "$lap_Status" -eq 0 ]]; then
        infoOut "LAPS account and password are valid"
        updateDialog "listitem: title: LAPS Admin Check, icon: SF=person.crop.circle.fill.badge.checkmark,weight=bold, statustext: Valid Credentials, status: success"
        updateDialog "listitem: title: Sending Enrollment Invitation, icon: SF=person.crop.circle.fill.badge.checkmark,weight=bold, statustext: Invitation Sent, status: success"
        state_set "ReEnrollNotificationStatus" "No Notification"
        webhookStatus="ReEnroll without notification"

        if [[ -z "$reEnrollMethod" ]]; then
            reEnrollMethod="Silent Redeploy of the Jamf Management Framework"
        fi

        if [ $skipLaunchDaemon = "false" ]; then
            infoOut "Skip Launch Daemon is set to false, sending Recon Launch Daemon"
            reconLaunchDaemon
        else
            infoOut "Skip Launch Daemon is set to true, skipping sending Recon Launch Daemon"
        fi
    else
        updateDialog "listitem: title: LAPS Admin Check, icon: SF=person.crop.circle.fill.badge.xmark,weight=bold, statustext: Invalid Credentials …, status: fail"
        updateDialog "listitem: title: Sending Enrollment Invitation, icon: SF=person.crop.circle.fill.badge.xmark,weight=bold, statustext: Invalid Credentials …, status: fail"
        error "LAPS account and password could not be validated"
        infoOut "Sending Profiles Renew Command"
        state_set "ReEnrollNotificationStatus" "ReEnroll with notification"
        webhookStatus="ReEnroll with notification"
        handleRenewProfilesOption
    fi
}
# END INLINED MODULE: laps.zsh
# BEGIN INLINED MODULE: enrollment.zsh

function enrollDeviceReceipt() {
    infoOut "Adding device enrolled receipt"
    state_set "DeviceEnrolledStatus" "Enrolled Device"
}

function handleRenewProfilesOption() {
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
}

function inventoryError() {
    if isDryRun; then
        state_set "ReEnrollNotificationStatus" "ReEnroll with notification"
        state_set "ReEnrollMethod" "Renewing Enrollment"
        webhookStatus="ReEnroll with notification"
        reEnrollMethod="Notification for Renewing Enrollment (Dry Run)"
        dryRunOut "Would present the renew profiles flow and send enrollment renewal instructions"
        quitScript
        return 0
    fi

    if [ "$displayReEnrollDialog" = "true" ]; then
        notice "Adding 'Profiles Renew' dialog"
        updateDialog "listitem: add, title: Jamf Update Needed, icon: SF=exclamationmark.icloud.fill,weight=bold, statustext: Waiting …, status: wait"
        updateDialog "listitem: delete, title: ReEnroll in progress …,"
        updateDialog "progresstext: Waiting for update decision..."
    else
        notice "ReEnroll did not call for 'Profiles Renew' dialog"
    fi

    notice "Sending Profiles Renew Command, deleting LAPS account, and sending notification"
    state_set "ReEnrollNotificationStatus" "ReEnroll with notification"
    state_set "ReEnrollMethod" "Renewing Enrollment"
    webhookStatus="ReEnroll with notification"
    reEnrollMethod="Notification for Renewing Enrollment"

    if [[ "${osMajorVersion}" -ge 12 ]] && [[ -e "/Library/Application Support/Dialog/Dialog.app" ]]; then
        infoOut "Sending Dialog notification for updating profiles"
        jamfProfileRenew

        returncode=$?

        if [ "$debugMode" = "verbose" ]; then
            debugVerbose "Return Code: ${returncode}"
        fi

        case ${returncode} in
            0)
                notice "${loggedInUser} clicked Update Now;"
                state_set "ReEnrollRenewProfilesDialog" "Update Now"
                infoOut "Checking user admin status to renew profiles"
                addAdmin
                sleep 5
                triggerEnrollment
                deleteLAPSAccount
                updateDialog "listitem: title: Jamf Update Needed, icon: SF=arrow.clockwise.icloud.fill,weight=bold, statustext: Update Pending, status: pending"
                updateDialog "progresstext: Update command sent. Waiting for response..."
                updateDialog "progresstext: Check for update notification in your Notifications Center"
                sleep 60
                if [ "$skipCheckIN" = "false" ]; then
                    notice "Skipping check-in option is false, sending check-in command"
                    updateDialog "listitem: title: Jamf Update Needed, icon: SF=arrow.clockwise.icloud.fill,weight=bold, statustext: , status: nothing"
                    checkIn
                else
                    notice "Skipping check-in command"
                    updateDialog "listitem: title: Jamf Update Needed, icon: SF=arrow.clockwise.icloud.fill,weight=bold, statustext: Update Command Sent, status: nothing"
                    sleep 30
                fi
                quitScript
                ;;
            3)
                notice "${loggedInUser} clicked Not Now;"
                state_set "ReEnrollRenewProfilesDialog" "Not Now"
                updateDialog "listitem: title: Jamf Update Needed, icon: SF=arrow.clockwise.icloud.fill,weight=bold, statustext: Deferring Update, status: nothing"
                infoOut "Removing enrollment receipt"
                webhookStatus="ReEnroll with notification"
                reEnrollMethod="Customer Chose: Not Now"
                state_set "DeviceEnrolledStatus" "Not Enrolled"
                quitScript
                ;;
            4)
                notice "${loggedInUser} allowed timer to expire;"
                state_set "ReEnrollRenewProfilesDialog" "Allowed timer to expire"
                updateDialog "listitem: title: Jamf Update Needed, icon: SF=arrow.clockwise.icloud.fill,weight=bold,"
                infoOut "Removing enrollment receipt"
                webhookStatus="ReEnroll with notification"
                reEnrollMethod="Customer allowed timer to expire"
                state_set "DeviceEnrolledStatus" "Not Enrolled"
                quitScript
                ;;
            20)
                notice "${loggedInUser} had Do Not Disturb enabled"
                state_set "ReEnrollRenewProfilesDialog" "Do Not Disturb enabled"
                updateDialog "listitem: title: Jamf Update Needed, icon: SF=arrow.clockwise.icloud.fill,weight=bold,"
                infoOut "Removing enrollment receipt"
                webhookStatus="ReEnroll with notification"
                reEnrollMethod="Customer had Do Not Disturb enabled"
                state_set "DeviceEnrolledStatus" "Not Enrolled"
                quitScript
                ;;
            *)
                notice "Something else happened; Exit code: ${returncode};"
                state_set "ReEnrollRenewProfilesDialog" "Errror: Something else happened"
                updateDialog "listitem: title: Jamf Update Needed, icon: SF=arrow.clockwise.icloud.fill,weight=bold,"
                infoOut "Removing enrollment receipt"
                webhookStatus="ReEnroll with notification"
                reEnrollMethod="Something went wrong, policy will run at next execution"
                state_set "DeviceEnrolledStatus" "Not Enrolled"
                quitScript "${returncode}"
                ;;
        esac
    else
        infoOut "Sending osascript notification for updating profiles"
        state_set "DeviceEnrolledStatus" "Not Enrolled"
        infoOut "Sending Profiles Renew Enrollment Command"
        triggerEnrollment
        webhookStatus="ReEnroll with notification (S/N ${serialNumber})"
        reEnrollMethod="Notification for Renewing Enrollment"
        updateProfilesOSA='display dialog "Hello! Jamf, your Apple management software, needs to be updated. \n\nPlease choose Options and Update from the drop down menu, or double-click on the Device Enrollment notice located in your notifications center." with title "Jamf Update Needed" buttons {"Close"} with icon posix file "/Applications/Self-Service Hub.app/Contents/Resources/AppIcon.icns"'
        if ! runAsLoggedInUser /usr/bin/osascript -e "$updateProfilesOSA"; then
            warning "Unable to display the enrollment renewal dialog for ${loggedInUser:-the console user}."
        fi
    fi

    error "Jamf Pro Inventory or Policy Connection is NOT available; exiting."
    quitScript "1"
}

function reEnrollInvitation() {
    if isDryRun; then
        infoOut "Send Enrollment Invitation is set to true and enrollment invitation is not empty"
        state_set "ReEnrollMethod" "Enrollment Invitation"
        reEnrollMethod="Sending Silent Enrollment Invitation (Dry Run)"
        webhookStatus="ReEnroll without notification"
        dryRunOut "Would send a silent enrollment invitation using invitation '${enrollmentInvitation:-dry-run-invitation}'"
        if [ -n "$lapsAdminAccount" ]; then
            deleteLAPSAccount
        fi
        rotateLAPSPassword
        return 0
    fi

    if [ "$enrollmentInvitation" = "" ] || [ "$sendEnrollmentInvitation" = "false" ]; then
        error "Enrollment invitation is empty, not sending invitation"
        updateDialog "The enrollment invitation is empty or incorrect, unable to send invitation"
    else
        infoOut "Send Enrollment Invitation is set to true and enrollment invitation is not empty"
        updateDialog "listitem: add, title: Sending Enrollment Invitation, icon: SF=paperplane.circle.fill,weight=bold, statustext: Sending …, status: wait"
        updateDialog "listitem: delete, title: ReEnroll in progress …,"
        updateDialog "progresstext: Sending Enrollment Invitation..."

        if [ "$lapsAdminAccount" = "" ]; then
            notice "LAPS Admin Account is empty, not deleting LAPS account"
        else
            infoOut "Deleting ${lapsAdminAccount}"
            deleteLAPSAccount
        fi

        infoOut "Sending Silent Enrollment Invitation"
        if [[ -z "${jamfBinary}" || ! -x "${jamfBinary}" ]]; then
            error "The Jamf binary is unavailable; the enrollment invitation cannot be sent locally."
            return 1
        fi
        "${jamfBinary}" enroll -invitation "$enrollmentInvitation" -noRecon -noPolicy
        updateDialog "listitem: title: Sending Enrollment Invitation, icon: SF=person.crop.circle.fill.badge.checkmark,weight=bold, statustext: Invitation Sent, status: success"
        updateDialog "progresstext: Enrollment Invitation Sent"
        state_set "ReEnrollMethod" "Enrollment Invitation"

        reEnrollMethod="Sending Silent Enrollment Invitation"
        webhookStatus="ReEnroll without notification"

        rotateLAPSPassword
    fi
}

function checkIn() {
    if isDryRun; then
        jssAvailable="yes"
        policyStatus="yes"
        inventoryStatus="yes"
        infoOut "Dry run enabled; simulating Jamf check-in, policy, and inventory validation"
        if [[ "$skipLAPSAdminCheck" = "false" ]]; then
            checkLAPSAccountStatus
        fi
        return 0
    fi

    jssConnectionStatus
    if [ "$displayReEnrollDialog" = "true" ]; then
        notice "Adding 'Jamf Connection Status' dialog"
        updateDialog "listitem: add, title: Jamf Connection Status, icon: SF=icloud.and.arrow.up.fill,weight=bold, statustext: Check 1 of 3, status: wait"
        updateDialog "listitem: delete, title: ReEnroll in progress …,"
        updateDialog "listitem: add, title: • JSS Connection, statustext: Checking …, status: wait"
        updateDialog "listitem: add, title: • Policy Status, statustext: Pending …"
        updateDialog "listitem: add, title: • Inventory Status, statustext: Pending …"
        updateDialog "progresstext: Checking Jamf Software Server (JSS)"
    else
        notice "ReEnroll did not call for 'LAPS Admin Check' dialog"
    fi

    counter=1
    until [[ "${jssAvailable}" = "yes" ]] || [[ "${counter}" -gt "10" ]]; do
        scriptResult+="Check ${counter} of 10: Jamf Pro server NOT reachable; waiting to re-check; "
        sleep "30"
        jssConnectionStatus
        ((counter++))
    done

    if [[ "${jssAvailable}" = "yes" ]]; then
        infoOut "Jamf Pro server is available, proceeding"
        infoOut "Reading Jamf log for Policy Status"
        updateDialog "listitem: title: Jamf Connection Status, icon: SF=icloud.and.arrow.up.fill,weight=bold, statustext: Check 2 of 3, status: wait"
        updateDialog "listitem: title: • JSS Connection, icon: SF=icloud.and.arrow.up.fill,weight=bold, statustext: Connected, status: success"
        updateDialog "listitem: title: • Policy Status, statustext: Checking …, status: wait"
        updateDialog "progresstext: Policies allow you to remotely automate common management tasks on managed computers."

        validatePolicy
        counterPolicy=1
        until [[ "${policyStatus}" = "yes" ]] || [[ "${counterPolicy}" -gt "120" ]]; do
            scriptResult+="Check ${counterPolicy} of 120: Jamf Pro Policy Connection Error; "
            if [[ "$debugMode" = "verbose" ]]; then
                debugVerbose "Check Policy count ${counterPolicy} of 120"
            fi
            sleep "2"
            validatePolicy
            ((counterPolicy++))
        done

        if [[ "${policyStatus}" = "yes" ]]; then
            infoOut "Jamf Pro Policy Connection is stable, proceeding"
            updateDialog "listitem: title: • Policy Status, icon: SF=icloud.and.arrow.up.fill,weight=bold, statustext: Connected, status: success"
        else
            error "Unable to verify Jamf Pro Policy Check In, proceeding"
            updateDialog "listitem: title: • Policy Status, icon: SF=exclamationmark.icloud.fill, statustext: Unable to Verify, status: error"
        fi

        infoOut "Terminating Jamf Check-In"
        pkill jamf

        sleep 5
        updateDialog "listitem: title: Jamf Connection Status, icon: SF=icloud.and.arrow.up.fill,weight=bold, statustext: Check 3 of 3, status: wait"
        updateDialog "listitem: title: • Inventory Status, statustext: Checking …, status: wait"
        updateDialog "progresstext: Jamf Pro stores detailed inventory information for each computer."

        infoOut "Forcing computer to submit inventory"
        if [[ -z "${jamfBinary}" || ! -x "${jamfBinary}" ]]; then
            error "The Jamf binary is unavailable; inventory submission cannot run."
            inventoryStatus="not installed"
            return 1
        fi
        "${jamfBinary}" recon -endUsername "${networkUser}" --verbose >> "${tempInventoryLog}"

        validateInventory
        counterInventory=1
        until [[ "${inventoryStatus}" = "yes" ]] || [[ "${counterInventory}" -gt "4" ]]; do
            scriptResult+="Check ${counterInventory} of 4: Jamf Pro Inventory Connection Error; "
            if [[ "$debugMode" = "verbose" ]]; then
                debugVerbose "Check Inventory count ${counterInventory} of 4"
            fi
            sleep "30"
            validateInventory
            ((counterInventory++))
        done

        if [[ "${inventoryStatus}" = "yes" ]]; then
            infoOut "Jamf Pro Inventory Connection is stable, proceeding"
            updateDialog "listitem: title: • Inventory Status, icon: SF=icloud.and.arrow.up.fill,weight=bold, statustext: Connected, status: success"
            updateDialog "listitem: title: Jamf Connection Status, icon: SF=icloud.and.arrow.up.fill,weight=bold, statustext: Success, status: success"
        else
            error "Jamf Pro Inventory Connection status error"
            updateDialog "listitem: title: • Inventory Status, icon: SF=exclamationmark.icloud.fill, statustext: Connection Error, status: error"
            updateDialog "listitem: title: Jamf Connection Status, icon: SF=icloud.and.arrow.up.fill,weight=bold, statustext: Connection Error, status: error"
            handleRenewProfilesOption
        fi

        if [[ "$skipLAPSAdminCheck" = "false" ]]; then
            notice "Skip LAPS admin Account verification is set to false, proceeding"
            checkLAPSAccountStatus
        else
            notice "Skip LAPS admin Account verification is set to true, skipping"
        fi
    else
        updateDialog "listitem: title: Jamf Connection Status, icon: SF=icloud.and.arrow.up.fill,weight=bold, statustext: Connection Error …, status: error"
        updateDialog "listitem: title: • JSS Connection, icon: SF=exclamationmark.icloud.fill, statustext: Connection Error …, status: error"
        updateDialog "progresstext: No connection could be established"
        handleRenewProfilesOption
    fi
}

function computerSiteUpdate() {
    if isDryRun; then
        dryRunOut "Would update the computer back to its original Jamf site ID '${computerSiteID}'"
        return 0
    fi

    infoOut "Computer has an original Site: ($originalComputerSite), site ID: ($originalComputerSiteID)"
    if ! jamfApiRequest PATCH "${jssurl}api/${jamfInventoryApiVersion}/computers-inventory-detail/${computerID}" \
        --header "Authorization: Bearer $apiBearerToken" \
        --header 'accept: application/json' \
        --header 'Content-Type: application/json' \
        --data "{
        \"general\": {
            \"siteId\": \"$computerSiteID\"
        }
        }"; then
        error "Unable to restore the original Jamf site (HTTP ${JAMF_HTTP_STATUS})."
        return 1
    fi
}

function newComputerSiteUpdate() {
    if isDryRun; then
        dryRunOut "Would update the computer to the new Jamf site ID '${newComputerSiteID}'"
        return 0
    fi

    infoOut "Computer has an original Site: ($computerSite)"
    if ! jamfApiRequest PATCH "${jssurl}api/${jamfInventoryApiVersion}/computers-inventory-detail/${computerID}" \
        --header "Authorization: Bearer $apiBearerToken" \
        --header 'accept: application/json' \
        --header 'Content-Type: application/json' \
        --data "{
        \"general\": {
            \"siteId\": \"$newComputerSiteID\"
        }
        }"; then
        error "Unable to update the Jamf site (HTTP ${JAMF_HTTP_STATUS})."
        return 1
    fi
}

function updatedComputerInventoryInfo() {
    if isDryRun; then
        originalComputerSite=$(state_get "ComputerSite")
        originalComputerSiteID=$(state_get "ComputerSiteID")
        infoOut "Dry run enabled; simulating post-enrollment computer site update"
        if [ -n "$newComputerSiteID" ]; then
            newComputerSiteUpdate
        else
            computerSiteUpdate
        fi
        quitScript
        return 0
    fi

    originalComputerSite=$(state_get "ComputerSite")
    originalComputerSiteID=$(state_get "ComputerSiteID")

    if [ "$updateComputerSite" = "true" ]; then
        infoOut "Update computer site is set to true, verifying and updating computer Site"
        getAccessToken
        checkTokenExpiration
        apiResponse
        computerIDLookup
        computerInventoryInfo
        if [ ! "$newComputerSiteID" = "" ]; then
            newComputerSiteUpdate
            notice "New Computer Site ID: $newComputerSiteID"
        elif [ "$originalComputerSiteID" -gt "1" ]; then
            computerSiteUpdate
            notice "The computer ($serialNumber) was updated to the original site ($originalComputerSite)."
        elif [ "$originalComputerSiteID" -lt "0" ]; then
            notice "The computer ($serialNumber) Site was set to none."
        else
            error "The computer was not updated to the original site"
        fi
    else
        infoOut "Update computer site is set to false, skipping verifying and updating computer Site"
    fi

    quitScript
}
# END INLINED MODULE: enrollment.zsh

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

    # Find the last position marker or start from the beginning if not found
    if [[ -f "$marker_file" && -f $jamfLogFile ]]; then
        lastPosition=$(cat "$marker_file")
    else 
        preFlight "Creating jamf log file and setting error position as zero"
        touch "$jamfLogFile"
        chmod 755 "$jamfLogFile"
        lastPosition=0
    fi

    # Copy new entries from jamf.log to the duplicate log file
    if [ -f "$jamfLogFile" ]; then
        tail -n +$((lastPosition + 1)) "$jamfLogFile" > "$duplicate_jamfLogFile"
        preFlight "jamf log file exists. Tailing new entries from log file to duplicate log file" 
    else 
        error "jamf log file not found"
    fi

    # Update the marker file with the new position
    wc -l "$jamfLogFile" | awk '{print $1}' > "$marker_file"
    preFlight "Updating marker file"

    # Echo out the last position on the marker file
    lastPosition=$(cat "$marker_file")
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

function dockCheck() {

    preFlight "Checking if Finder & Dock are running"

    DockFinderCounter="1"

    until [[ "${DockFinderCounter}" -gt "10" ]] || (pgrep -q -x "Finder" && pgrep -q -x "Dock"); do
    preFlight "Finder & Dock are NOT running; pausing for 1 second"
        sleep 2
        ((DockFinderCounter++))

        if [[ "${DockFinderCounter}" -gt "10" ]] || ! pgrep -q -x "Finder" || ! pgrep -q -x "Dock"; then
            error "Finder or Dock not found or timeout reached; exiting"
            quitScript 1
        else
            preFlight "Finder & Dock are running; proceeding"
        fi
    done
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

function cleanupPrivileges() {
    if [ "$renewProfiles" = "true" ]; then
        infoOut "Removing admin access from computer"
        removeAdmin
    else
        infoOut "Renew Profiles was set to $renewProfiles, skipping removing admin access from computer"
    fi
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

    if dseditgroup -o checkmember -m "$loggedInUser" admin | grep -q "not a member"; then
        infoOut "${loggedInUser} is not an admin. Adding to the admin group..."
        updateDialog "progresstext: Adding ${loggedInUser} to the admin group..."
        /usr/sbin/dseditgroup -o edit -a "$loggedInUser" -t user admin
        infoOut "${loggedInUser} has been added to the admin group."
        updateDialog "progresstext: ${loggedInUser} has been added to the admin group."
    else
        infoOut "${loggedInUser} is already an admin."
        updateDialog "progresstext: ${loggedInUser} is already an admin."
    fi
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

    if dseditgroup -o checkmember -m "$loggedInUser" admin | grep -q "is a member"; then
        quitOut "$loggedInUser is an admin. Removing from the admin group..."
        /usr/sbin/dseditgroup -o edit -d "$loggedInUser" -t user admin
        quitOut "$loggedInUser has been removed from the admin group."
    else
        quitOut "$loggedInUser is not an admin."
    fi
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Find User Accounts and Remove
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

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

    # Demote LAPS admin account to be removed
    infoOut "Demoting $lapsAdminAccount account"

/usr/sbin/dseditgroup -o edit -d "$lapsAdminAccount" -t user admin

RESULT=()

# Read the list of users with UniqueID greater than 500
while read -r user; do
    userHome=$(dscl . read /Users/"$user" NFSHomeDirectory | awk '{print $NF}')

    found_in_exempt_list=false

    for exempt_user in "${exempt_users[@]}"; do
        if [[ "$user" == "$exempt_user" ]]; then
            RESULT+=("$(infoOut "Found user $user in exempt list, ignoring...\n")")
            found_in_exempt_list=true
            break
        fi
    done

     # Check if user is a local admin
    if ! $found_in_exempt_list; then
        RESULT+=("$(infoOut "User $user not found in exempt list, checking admin status...\n")")
        if dseditgroup -o checkmember -u "$user" admin 1 >/dev/null; then
            RESULT+=("$(infoOut "User $user was found to be a Local Admin, ignoring...\n")")
        else
            # Check if user is in targeted list
            for targeted_user in "${targeted_users[@]}"; do
                if [[ "$user" == "$targeted_user" ]]; then
                    RESULT+=("$(infoOut "Found user $user in targeted list, $userHome will be deleted...\n")")
                    dscl . delete /Users/"$user"
                    rm -rf "$userHome"
                    break
                fi
            done
        fi
    fi
    done < <(dscl . list /Users UniqueID | awk '$2 > 500 {print $1}')

    echo -e "${RESULT[@]}"

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
    enrollDeviceReceipt

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

trap 'cleanupResources' EXIT
trap 'handleTerminationSignal "INT"' INT
trap 'handleTerminationSignal "TERM"' TERM

main "$@"
