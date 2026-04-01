[[ -n "${REENROLL_DIALOG_MODULE_LOADED:-}" ]] && return
REENROLL_DIALOG_MODULE_LOADED="true"

function prepareOverlayIcon() {
    if [[ "$useOverlayIcon" == "true" ]]; then
        xxd -p -s 260 "$(defaults read /Library/Preferences/com.jamfsoftware.jamf self_service_app_path)"/Icon$'\r'/..namedfork/rsrc | xxd -r -p > /var/tmp/overlayicon.icns
        overlayicon="/var/tmp/overlayicon.icns"
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

function dialogInstall() {
    if isDryRun; then
        dialogVersion="${swiftDialogMinimumRequiredVersion}"
        dryRunOut "Would install or update swiftDialog to at least version ${swiftDialogMinimumRequiredVersion}"
        return 0
    fi

    # Get the URL of the latest PKG From the Dialog GitHub repo
    dialogURL=$(curl -L --silent --fail "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")

    # Expected Team ID of the downloaded PKG
    expectedDialogTeamID="PWA5E9TQ59"

    preFlight "Installing swiftDialog..."

    # Create temporary working directory
    workDirectory=$(/usr/bin/basename "$0")
    tempDirectory=$(/usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX")

    # Download the installer package
    /usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"

    # Verify the download
    teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')

    # Install the package if Team ID validates
    if [[ "$expectedDialogTeamID" == "$teamID" ]]; then
        /usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
        sleep 2
        dialogVersion=$(/usr/local/bin/dialog --version)
        preFlight "swiftDialog version ${dialogVersion} installed; proceeding..."
    else
        infoOut "Unable to verify swift dialog team ID. Not installing or udpating"
    fi

    /bin/rm -Rf "$tempDirectory"
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
        if [[ "${dialogVersion}" < "${swiftDialogMinimumRequiredVersion}" ]]; then
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

    dialogReEnroll="$dialogBinary \
--title \"$title\" \
--titlefont \"name=Arial, size=25\" \
--icon \"$icon\" \
--message \"\" \
--overlayicon \"$overlayicon\" \
--helpmessage \"$helpMessage\" \
--height 450 \
--width 725 \
--windowbuttons min \
--position center \
--ontop \
--button1text \"Close\" \
--moveable \
--listitem \"ReEnroll in progress …\" \
--progress \
--titlefont size=20 \
--messagefont size=14 \
--infobox \"**Computer Name:**  \n\n • $computerName  \n\n **macOS Version:**  \n\n • $osVersionFull\" \
--progresstext \"$inventoryProgressText\" \
--infotext \"$infoTextScriptVersion\" \
--quitkey K \
--commandfile \"$dialogLog\" "
}

function evalReEnrollDialog() {
    if isDryRun; then
        notice "Create ReEnroll dialog …"
        dryRunOut "Would display the ReEnroll progress dialog"
        return 0
    fi

    notice "Create ReEnroll dialog …"
    eval "$dialogReEnroll" &

    updateDialog "listitem: delete, title: ReEnroll in progress …"
    updateDialog "progresstext: Initializing…"
}

function killProcess() {

    process="$1"
    if process_pid=$(pgrep -a "${process}" 2>/dev/null); then
        infoOut "Attempting to terminate the '$process' process …"
        infoOut "(Termination message indicates success.)"
        kill "$process_pid" 2> /dev/null
        if pgrep -a "$process" >/dev/null; then
            errorOut "'$process' could not be terminated."
        fi
    else
        infoOut "The '$process' process isn't running."
    fi
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

    if pgrep -x "Dialog" >/dev/null; then
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
        eval "$dialogReEnroll" &
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

    dialogUpdateReEnroll="$dialogBinary \
    --title \"Jamf Update Needed\" \
    --titlefont \"name=Arial, size=25\" \
    --icon \"$icon\" \
    --iconsize 90 \
    --overlayicon \"$overlayicon\" \
    --message \"Hello! Jamf, your Apple management software, needs to be updated. \n\nPlease choose **Options** and **Update** from the drop down menu, or double-click on the **Device Enrollment** notice located in your notifications center.\" \
    --messagefont \"name=Arial,size=15\" \
    --position bottomright \
    --height 355 \
    --width 530 \
    --button1text \"Update Now\" \
    --infobuttontext \"Not Now\" \
    --helpmessage \"$helpMessage\" \
    --timer 600 \
    --hidetimerbar \
    --ontop \
    --moveable \
    --messagealignment left \
    --commandfile \"$updateDialogLog\" "

    eval "$dialogUpdateReEnroll"
}
