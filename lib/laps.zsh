[[ -n "${REENROLL_LAPS_MODULE_LOADED:-}" ]] && return
REENROLL_LAPS_MODULE_LOADED="true"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Local account safety checks
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Account names reach dscl as /Users/<name>, so only plain short names are
# accepted; a name such as "../Groups/admin" must never reach a delete.
reenrollLocalAccountNamePattern='^[A-Za-z0-9_][A-Za-z0-9._-]*$'

# Prints the first value of a local user record attribute. Reading the plist
# form keeps values that contain spaces (such as a home folder path) intact.
function localAccountAttribute() {
    /usr/bin/dscl -plist . -read "/Users/${1}" "${2}" 2>/dev/null \
        | /usr/bin/plutil -extract "dsAttrTypeStandard:${2}.0" raw -o - - 2>/dev/null
}

# Decides whether ReEnroll may delete or demote a local account. Returns 0
# when it may, 2 when no such account exists and 1 when it must not:
# an invalid name, a system account (UID below 500), the console user or an
# account in exempt_users. Sets removableAccountUID and accountRemovalReason.
# A mistyped Jamf parameter $6 or targeted_users entry is refused here.
function localAccountRemovable() {
    local account="$1"
    local consoleUser exemptUser

    removableAccountUID=""
    accountRemovalReason=""

    if [[ ! "${account}" =~ ${reenrollLocalAccountNamePattern} ]]; then
        accountRemovalReason="'${account}' is not a valid local account name"
        return 1
    fi

    removableAccountUID="$(localAccountAttribute "${account}" UniqueID)" || removableAccountUID=""
    if [[ -z "${removableAccountUID}" ]]; then
        accountRemovalReason="no local account named ${account} exists"
        return 2
    fi
    if [[ "${removableAccountUID}" != <-> ]]; then
        accountRemovalReason="${account} has an unreadable UID (${removableAccountUID})"
        return 1
    fi
    if (( removableAccountUID < 500 )); then
        accountRemovalReason="${account} has UID ${removableAccountUID}; accounts below UID 500 are system accounts"
        return 1
    fi

    consoleUser="$(liveConsoleUser)" || consoleUser=""
    if [[ "${account}" == "${loggedInUser:-}" || "${account}" == "${consoleUser}" ]]; then
        accountRemovalReason="${account} is the console user"
        return 1
    fi

    for exemptUser in "${exempt_users[@]}"; do
        if [[ -n "${exemptUser}" && "${account}" == "${exemptUser}" ]]; then
            accountRemovalReason="${account} is in exempt_users"
            return 1
        fi
    done

    return 0
}

# Returns 0 when the account is in the admin group, 1 when dseditgroup reports
# it is not, and 2 when membership cannot be determined. Callers treat 2 as
# "leave the account alone".
function localAccountIsAdmin() {
    local membership

    membership="$(/usr/sbin/dseditgroup -o checkmember -m "${1}" admin 2>&1)" || true
    case "${membership}" in
        "yes "*) return 0 ;;
        "no "*) return 1 ;;
        *) return 2 ;;
    esac
}

# Deletes the Jamf-managed LAPS account named by Jamf parameter $6 so the
# enrollment that follows recreates it. The account must pass
# localAccountRemovable; the home folder is left in place.
function deleteLAPSAccount() {
    if isDryRun; then
        dryRunOut "Would delete the LAPS account '${lapsAdminAccount}' if present"
        return 0
    fi

    if [ "$skipAccountDeletion" = "false" ]; then
        notice "Skip Account Deletion is set to false, proceeding"
        if [ -z "$lapsAdminAccount" ]; then
            notice "No LAPS account to delete"
            return 0
        fi

        local removable=0
        localAccountRemovable "${lapsAdminAccount}" || removable=$?
        case ${removable} in
            0) ;;
            2)
                notice "LAPS account ${lapsAdminAccount} does not exist; nothing to delete"
                return 0
                ;;
            *)
                error "Not deleting LAPS account ${lapsAdminAccount}: ${accountRemovalReason}"
                return 1
                ;;
        esac

        notice "Deleting LAPS account: ${lapsAdminAccount} (UID ${removableAccountUID})"
        if ! /usr/bin/dscl . -delete "/Users/${lapsAdminAccount}"; then
            error "Unable to delete LAPS account ${lapsAdminAccount}"
            return 1
        fi
        infoOut "Deleted LAPS account ${lapsAdminAccount}"
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

# Checks a local account password through OpenDirectory. The account name and
# password reach osascript through its environment, which other local users
# cannot read, instead of argv, which any user can read with ps. dscl -authonly
# would expose the LAPS password on its command line.
function verifyLocalAccountPassword() {
    REENROLL_AUTH_USER="$1" REENROLL_AUTH_PASSWORD="$2" /usr/bin/osascript -l JavaScript \
        -e 'ObjC.import("OpenDirectory")' \
        -e 'ObjC.import("stdlib")' \
        -e 'const env = $.NSProcessInfo.processInfo.environment' \
        -e 'const node = $.ODNode.nodeWithSessionTypeError($.ODSession.defaultSession, $.kODNodeTypeLocalNodes, null)' \
        -e 'const record = node.recordWithRecordTypeNameAttributesError($.kODRecordTypeUsers, env.objectForKey("REENROLL_AUTH_USER"), $(), null)' \
        -e 'if (record.isNil()) { $.exit(2) }' \
        -e 'if (!record.verifyPasswordError(env.objectForKey("REENROLL_AUTH_PASSWORD"), null)) { $.exit(1) }' \
        -e '""' >/dev/null 2>&1
}

function validate_password() {
    # Start from failure so an early return can never leave a stale success
    # from an earlier check in the global that checkLAPSAccount reads.
    authResult=1
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
    verifyLocalAccountPassword "$lapsAdminAccount" "$lapsPassword"
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

    # Jamf Pro needs time to escrow the new password before a check can pass.
    # This is the only up-front wait; verifyLAPSCredentials checks at once.
    infoOut "Waiting 60 seconds for Jamf Pro to escrow the rotated LAPS password"
    sleep 60

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

    # The counter is local so a nested verification (reEnrollInvitation ->
    # rotateLAPSPassword -> verifyLAPSCredentials) cannot reset the outer
    # loop's bound, and the enrollment invitation is sent at most once per
    # run: each invitation deletes the LAPS account, re-enrolls and rotates
    # the password, so repeating it on every failed check looped forever.
    # The first check runs at once, so a valid account costs no wait; the 60
    # second pause is only between a failed check and the next one (at most
    # two checks per call). rotateLAPSPassword waits for escrow itself.
    local LAPScounter=1
    checkLAPSAccount "$jssurl" "$management_id" "$apiBearerToken" "$lapsAdminAccount" "$lapsPassword"
    lap_Status=$?

    while [[ "$lap_Status" -ne 0 ]]; do
        if [[ "${lapsReEnrollInvitationSent:-false}" == "true" ]]; then
            warning "LAPS credentials are still invalid after the enrollment invitation; not sending another"
        else
            lapsReEnrollInvitationSent="true"
            notice "Sending enrollment invitation..."
            reEnrollInvitation
            # The invitation's own verification sets lap_Status; stop if it
            # already confirmed the new credentials.
            [[ "$lap_Status" -eq 0 ]] && break
        fi

        (( LAPScounter >= 2 )) && break
        scriptResult+="Check ${LAPScounter} of 2: LAPS account not valid; waiting to re-check; "
        sleep 60
        (( LAPScounter++ ))
        checkLAPSAccount "$jssurl" "$management_id" "$apiBearerToken" "$lapsAdminAccount" "$lapsPassword"
        lap_Status=$?
    done
}

function checkLAPSAccountStatus() {
    # checkIn already runs this on its success path and main calls it again;
    # the second run repeated the 60s verification wait and rewrote the recon
    # LaunchDaemon while the first instance could already be executing.
    # The latch is set only after a successful check, so a re-check after a
    # profile renewal still runs.
    if [[ "${lapsAccountStatusChecked:-false}" == "true" ]]; then
        infoOut "LAPS admin account status was already verified this run; skipping repeat"
        return 0
    fi

    if isDryRun; then
        verifyLAPSCredentials
        [[ "$lap_Status" -eq 0 ]] && lapsAccountStatusChecked="true"
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
    [[ "$lap_Status" -eq 0 ]] && lapsAccountStatusChecked="true"

    if [[ "$lap_Status" -eq 0 ]]; then
        infoOut "LAPS account and password are valid"
        updateDialog "listitem: title: LAPS Admin Check, icon: SF=person.crop.circle.fill.badge.checkmark,weight=bold, statustext: Valid Credentials, status: success"
        updateDialog "listitem: title: Sending Enrollment Invitation, icon: SF=person.crop.circle.fill.badge.checkmark,weight=bold, statustext: Invitation Sent, status: success"
        state_set "ReEnrollNotificationStatus" "No Notification"
        webhookStatus="ReEnroll without notification"
        enrollDeviceReceipt "the Jamf-managed LAPS credentials were verified"

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
