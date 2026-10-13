[[ -n "${REENROLL_LAUNCHD_MODULE_LOADED:-}" ]] && return
REENROLL_LAUNCHD_MODULE_LOADED="true"

# Directory for the admin guard LaunchDaemon property list.
reenrollLaunchDaemonDirectory="/Library/LaunchDaemons"

# Prints the jamf-recon.zsh script that the recon LaunchDaemon runs. Values
# that come from the account (the network user) are shell-quoted so they stay
# literal arguments in the generated root script.
function printReconDaemonScript() {
    local rotatePasswordCommand reconUser reconCommand reconLogMessage

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

    # Never pass an empty -endUsername: it can blank the User and Location
    # username on the Jamf computer record.
    reconUser="$(reconEndUsername)"
    if [[ -n "${reconUser}" ]]; then
        reconCommand="${(qq)jamfBinary} recon -endUsername ${(qq)reconUser}"
        reconLogMessage="Running Jamf recon for user: ${reconUser}"
    else
        reconCommand="${(qq)jamfBinary} recon"
        reconLogMessage="Running Jamf recon without -endUsername (no network user)"
    fi

    cat << EOF
#!/bin/zsh --no-rcs

RECON_LOG="$scriptLog"

log_message() {
    echo "\$(date +"%Y-%m-%d %H:%M:%S") - [RECON DAEMON] \$1" >> "\$RECON_LOG"
}

clear_admin_grant() {
    for key in ReEnrollPromotedUser ReEnrollPromotedPID ReEnrollPromotedAt; do
        /usr/bin/defaults delete "$reEnrollConfigFile" "\$key" >/dev/null 2>&1
    done
}

log_message "=== Recon LaunchDaemon Started ==="

log_message ${(qq)reconLogMessage}
${reconCommand} >> "\$RECON_LOG" 2>&1
reconStatus=\$?
if [ \$reconStatus -eq 0 ]; then
    log_message "Jamf recon completed successfully"
else
    log_message "Jamf recon failed with exit code: \$reconStatus"
fi

log_message "Running Jamf policy"
${(qq)jamfBinary} policy >> "\$RECON_LOG" 2>&1
policyStatus=\$?
if [ \$policyStatus -eq 0 ]; then
    log_message "Jamf policy completed successfully"
else
    log_message "Jamf policy failed with exit code: \$policyStatus"
fi

$rotatePasswordCommand

log_message "Checking admin status for user: $loggedInUser"
# Only demote an account that ReEnroll itself promoted (recorded by addAdmin);
# a user who was already an administrator keeps their rights.
promotedUser="\$(/usr/bin/defaults read "$reEnrollConfigFile" ReEnrollPromotedUser 2>/dev/null)"
if [ -z "$loggedInUser" ] || [ "\$promotedUser" != "$loggedInUser" ]; then
    log_message "ReEnroll did not promote $loggedInUser; leaving admin membership unchanged"
elif /usr/sbin/dseditgroup -o checkmember -m "$loggedInUser" admin | /usr/bin/grep -q "is a member"; then
    log_message "$loggedInUser was promoted by ReEnroll. Removing from the admin group..."
    /usr/sbin/dseditgroup -o edit -d "$loggedInUser" -t user admin
    if [ \$? -eq 0 ]; then
        log_message "$loggedInUser has been removed from the admin group"
        clear_admin_grant
    else
        log_message "Failed to remove $loggedInUser from admin group"
    fi
else
    log_message "$loggedInUser is not an admin"
    clear_admin_grant
fi

log_message "Cleaning up LaunchDaemon files"

/bin/rm "/Library/$organizationName/jamf-recon.zsh"
/bin/rmdir "/Library/$organizationName" 2>/dev/null
/bin/rm "/Library/LaunchDaemons/$organizationReverseDomain.jamf-recon.plist"
/bin/launchctl remove "$organizationReverseDomain.jamf-recon"

log_message "=== Recon LaunchDaemon Completed ==="

exit 0
EOF
}

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

    printReconDaemonScript | tee "/Library/$organizationName/jamf-recon.zsh"

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

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Admin guard LaunchDaemon
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# addAdmin records a temporary admin grant (ReEnrollPromotedUser, ...PID and
# ...At in the ReEnroll plist) and arms this guard before promoting the console
# user. The guard runs at load, at every boot and every minute. While the run
# that made the grant is still running (same boot, process alive, younger than
# adminGrantMaxSeconds) it does nothing. Once that run has ended without
# revoking the grant (killed, timed out or a restart), it demotes the recorded
# user, clears the record and removes itself. Only recorded users are demoted,
# so an account that was already an administrator is never touched.

function adminGuardLabel() {
    print -r -- "${organizationReverseDomain}.reenroll-admin-guard"
}

function adminGuardScriptPath() {
    print -r -- "${folder_path}/ReEnrollAdminGuard.zsh"
}

function xmlEscape() {
    local value="$1"
    value="${value//"&"/&amp;}"
    value="${value//"<"/&lt;}"
    value="${value//">"/&gt;}"
    print -r -- "${value}"
}

function writeAdminGuardScript() {
    local scriptPath="$1" label="$2" plistPath="$3"
    local maxSeconds="${adminGrantMaxSeconds:-3600}"
    [[ "${maxSeconds}" == <1-> ]] || maxSeconds=3600

    {
        print -r -- '#!/bin/zsh --no-rcs'
        print -r -- '# Generated by ReEnroll (lib/launchd.zsh): revokes the admin rights ReEnroll'
        print -r -- '# granted once the run that granted them has ended, then removes itself.'
        print -r -- "configFile=${(qq)reEnrollConfigFile}"
        print -r -- "logFile=${(qq)scriptLog}"
        print -r -- "guardLabel=${(qq)label}"
        print -r -- "guardPlist=${(qq)plistPath}"
        print -r -- "guardScript=${(qq)scriptPath}"
        print -r -- "maxGrantSeconds=${maxSeconds}"
        cat << 'EOF'

function log_message() {
    print -r -- "$(/bin/date +"%Y-%m-%d %H:%M:%S") - [ADMIN GUARD] $1" >> "${logFile}"
}

function remove_guard() {
    /bin/rm -f -- "${guardPlist}" "${guardScript}"
    /bin/launchctl bootout "system/${guardLabel}" >/dev/null 2>&1
}

function clear_grant() {
    local key
    for key in ReEnrollPromotedUser ReEnrollPromotedPID ReEnrollPromotedAt; do
        /usr/bin/defaults delete "${configFile}" "${key}" >/dev/null 2>&1
    done
}

promotedUser="$(/usr/bin/defaults read "${configFile}" ReEnrollPromotedUser 2>/dev/null)"
if [[ -z "${promotedUser}" ]]; then
    log_message "No temporary admin grant is recorded; removing the admin guard"
    remove_guard
    exit 0
fi

# The granting run is still active when this boot began before the grant,
# its process is alive and the grant is younger than the limit.
promotedPID="$(/usr/bin/defaults read "${configFile}" ReEnrollPromotedPID 2>/dev/null)"
promotedAt="$(/usr/bin/defaults read "${configFile}" ReEnrollPromotedAt 2>/dev/null)"
bootTime="$(/usr/sbin/sysctl -n kern.boottime 2>/dev/null)"
bootTime="${${bootTime#*sec = }%%,*}"
now="$(/bin/date +%s)"
if [[ "${promotedPID}" == <2-> && "${promotedAt}" == <1-> && "${bootTime}" == <1-> && "${now}" == <1-> ]] \
    && (( bootTime <= promotedAt && now - promotedAt < maxGrantSeconds )) \
    && kill -0 "${promotedPID}" 2>/dev/null; then
    exit 0
fi

if /usr/sbin/dseditgroup -o checkmember -m "${promotedUser}" admin 2>/dev/null | /usr/bin/grep -q "is a member"; then
    if ! /usr/sbin/dseditgroup -o edit -d "${promotedUser}" -t user admin >/dev/null 2>&1; then
        log_message "Failed to remove ${promotedUser} from the admin group; retrying in a minute"
        exit 1
    fi
    log_message "Removed ${promotedUser} from the admin group; the ReEnroll run that granted it has ended"
else
    log_message "${promotedUser} is no longer an administrator"
fi
clear_grant
remove_guard
exit 0
EOF
    } > "${scriptPath}"
}

function installAdminGuardDaemon() {
    if isDryRun; then
        dryRunOut "Would install and bootstrap the admin guard LaunchDaemon"
        return 0
    fi

    local label scriptPath plistPath
    label="$(adminGuardLabel)"
    scriptPath="$(adminGuardScriptPath)"
    plistPath="${reenrollLaunchDaemonDirectory}/${label}.plist"

    # Replace a guard left by an earlier run; the script reads the current record.
    /bin/launchctl bootout "system/${label}" >/dev/null 2>&1 || true

    writeAdminGuardScript "${scriptPath}" "${label}" "${plistPath}" || return 1
    /usr/sbin/chown root:wheel "${scriptPath}" && /bin/chmod 700 "${scriptPath}" || return 1

    cat > "${plistPath}" << EOF || return 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>Label</key>
<string>$(xmlEscape "${label}")</string>
<key>ProgramArguments</key>
<array>
<string>/bin/zsh</string>
<string>--no-rcs</string>
<string>$(xmlEscape "${scriptPath}")</string>
</array>
<key>RunAtLoad</key>
<true/>
<key>StartInterval</key>
<integer>60</integer>
</dict>
</plist>
EOF

    /usr/sbin/chown root:wheel "${plistPath}" && /bin/chmod 644 "${plistPath}" || return 1
    /bin/launchctl bootstrap system "${plistPath}" || return 1
    infoOut "Armed the admin guard LaunchDaemon (${label})"
}

function removeAdminGuardDaemon() {
    if isDryRun; then
        dryRunOut "Would remove the admin guard LaunchDaemon"
        return 0
    fi

    local label
    label="$(adminGuardLabel)"
    /bin/rm -f -- "${reenrollLaunchDaemonDirectory}/${label}.plist" "$(adminGuardScriptPath)"
    /bin/launchctl bootout "system/${label}" >/dev/null 2>&1 || true
}
