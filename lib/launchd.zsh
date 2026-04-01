[[ -n "${REENROLL_LAUNCHD_MODULE_LOADED:-}" ]] && return
REENROLL_LAUNCHD_MODULE_LOADED="true"

function reconLaunchDaemon() {
    if isDryRun; then
        dryRunOut "Would create and bootstrap the recon LaunchDaemon workflow"
        return 0
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

    tee "/Library/$organizationName/jamf-recon.zsh" << EOF
#!/bin/zsh

RECON_LOG="$scriptLog"

log_message() {
    echo "\$(date +"%Y-%m-%d %H:%M:%S") - [RECON DAEMON] \$1" >> "\$RECON_LOG"
}

log_message "=== Recon LaunchDaemon Started ==="

log_message "Running Jamf recon for user: $networkUser"
/usr/local/bin/jamf recon -endUsername "$networkUser" >> "\$RECON_LOG" 2>&1
reconStatus=\$?
if [ \$reconStatus -eq 0 ]; then
    log_message "Jamf recon completed successfully"
else
    log_message "Jamf recon failed with exit code: \$reconStatus"
fi

log_message "Running Jamf policy"
/usr/local/bin/jamf policy >> "\$RECON_LOG" 2>&1
policyStatus=\$?
if [ \$policyStatus -eq 0 ]; then
    log_message "Jamf policy completed successfully"
else
    log_message "Jamf policy failed with exit code: \$policyStatus"
fi

$rotatePasswordCommand

log_message "Checking admin status for user: $loggedInUser"
if dseditgroup -o checkmember -m $loggedInUser admin | grep -q "is a member"; then
    log_message "$loggedInUser is an admin. Removing from the admin group..."
    /usr/bin/sudo dseditgroup -o edit -d $loggedInUser -t user admin
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
<string>"/Library/$organizationName/jamf-recon.zsh"</string>
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
    /bin/launchctl bootstrap system /Library/LaunchDaemons/$organizationReverseDomain.jamf-recon.plist && /bin/launchctl start /Library/LaunchDaemons/$organizationReverseDomain.jamf-recon.plist
}
