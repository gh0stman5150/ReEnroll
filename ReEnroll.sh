#!/bin/zsh --no-rcs

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
client_id="$4"
client_secret="$5"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Skip Check-In, LAPS Admin Account Username and User to Exempt/Target for Deletion Options
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Skip Jamf connection verification after enrollment
skipCheckIN="false"                                                 # [ false (default) | true ]
# Skip LAPS admin account verification after enrollment
skipLAPSAdminCheck="false"                                          # [ false (default) | true ]
# LAPS admin account username (add the Jamf managed local admin account username here)
lapsAdminAccount="$6"                                                 # [ add the LAPS admin account username here ]
# Skip User Exemption/Targeted Deletion
skipAccountDeletion="false"                                         # [ false (default) | true ]
# Define the exempt user list from being deleted (Add the username in quotes, with a space in between each)
exempt_users=("Shared" "Guest" "$loggedInUser")                     # [ add the exempt user list here ]
# Define the targeted user list to be deleted (Add the username in quotes, with a space in between each) 
targeted_users=("$lapsAdminAccount" "anotherAccount" )              # [ add the targeted user list here ]
# Jamf Enrollment Invitation ID (https:/company.jamfcloud.com/enroll?invitation=1542270881__;!!KwNVnq) (Invitation ID in this example would be: 1542270881)
enrollmentInvitation="$7"                                             # [ add the Invitation ID here ]

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
displayReEnrollDialog="$8"                                    # Display ReEnroll Dialog [ true | false (default) ]
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
# Dialog temporary command files
dialogLog=$( mktemp -u /var/tmp/dialogLog.XXX )
updateDialogLog=$( mktemp -u /var/tmp/updateDialogLog.XXX )

# Set icon based on whether the Mac is a desktop or laptop
if system_profiler SPPowerDataType | grep -q "Battery Power"; then
    icon="SF=arrow.triangle.2.circlepath.icloud.fill,weight=regular,colour1=black,colour2=white"
else
    icon="SF=arrow.triangle.2.circlepath.icloud.fill,weight=regular,colour1=black,colour2=white"
fi

### Overlay Icon ###
useOverlayIcon="true"								# Toggles swiftDialog to use an overlay icon [ true (default) | false ]
overlayicon=""

### Webhook Options ###

webhookEnabled="false"                                                          # Enables the webhook feature [ all | failures | false (default) ]
teamsURL=""                                                                     # Teams webhook URL                         
slackURL=""                                                                     # Slack webhook URL

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Operating System Variables and Jamf URL
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Current JSS address
jssurl=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)
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
    (( errorCount++ )) || true
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

function sourceModule() {
    local modulePath="${scriptDirectory}/lib/${1}"
    if [[ ! -r "${modulePath}" ]]; then
        echo "Missing required module: ${modulePath}" >&2
        exit 1
    fi

    source "${modulePath}"
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
    mkdir -p "$(sed 's/\(.*\)\/.*/\1/' <<< $1)"
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
    chmod 655 "$duplicate_log_dir"

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
marker_file="/var/tmp/jamfTempMarker.txt"

# Get the PID of the current script for caffeinate
reEnrollPID="$$"

# Create a marker file if it doesn't exist
function createMarkerFile(){

# 
if [ ! -f "$marker_file" ]; then
        preFlight "Marker file not found, creating temp marker file"
        touch "$marker_file"
        else
        preFlight "marker file exist, continuing"
     fi
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

     # Create a directory for duplicate log files if it doesn't exist
     if [ ! -f "$marker_file" ]; then
        preFlight "Marker file not found, creating temp marker file"
        touch "$marker_file"
        else
        preFlight "marker file exist, continuing"
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
        if [[ ! -f "{$jamfLogFile}" ]] || [[ "${lastPosition}" -le 0 ]]; then
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
        caffeinate -dimsu -w $reEnrollPID &
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

    infoOut "De-caffeinate $reEnrollPID..."
    killProcess "caffeinate"

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

    responseCode=$(/usr/bin/curl -w "%{http_code}" -H "Authorization: Bearer ${apiBearerToken}" "${jssurl}api/v1/auth/invalidate-token" -X POST -s -o /dev/null)
    if [[ ${responseCode} == 204 ]]; then
        quitOut "Token successfully invalidated"
        access_token=""
        token_expiration_epoch="0"
    elif [[ ${responseCode} == 401 ]]; then
        quitOut "Token already invalid"
    else
        quitOut "An unknown error occurred invalidating the token"
        apiBearerToken=$(/usr/bin/curl "${jssurl}api/v1/auth/invalidate-token" --silent --header "Authorization: Bearer ${apiBearerToken}" -X POST)
        apiBearerToken=""
    fi
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
    local exitCode="${1:-0}"

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
        sudo /usr/sbin/dseditgroup -o edit -a "$loggedInUser" -t user admin
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
        sudo /usr/sbin/dseditgroup -o edit -d "$loggedInUser" -t user admin
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

sudo dseditgroup -o edit -d "$lapsAdminAccount" -t user admin

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
        quitScript "0"
    else
        updatedComputerInventoryInfo
    fi

    quitScript "1"
}

trap 'cleanupResources' EXIT
trap 'handleTerminationSignal "INT"' INT
trap 'handleTerminationSignal "TERM"' TERM

main "$@"
