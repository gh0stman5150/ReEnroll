[[ -n "${REENROLL_LAPS_MODULE_LOADED:-}" ]] && return
REENROLL_LAPS_MODULE_LOADED="true"

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

    lapsPasswordInformation=$(curl -X 'GET' \
        "${jssurl}"api/v2/local-admin-password/"${management_id}"/account/"${lapsAdminAccount}"/password \
        -H 'accept: application/json' \
        -H "Authorization: Bearer ${apiBearerToken}"
        )
    check_status "$lapsPasswordInformation"
    if [ "$APIResult" = "Failure" ]; then
        errorOut "Failed to gather LAPS Password, error: $APIResult"
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
    apiResponse
    computerIDLookup

    setLAPSPassword=$(/usr/bin/curl -X 'PUT' \
        --url "${jssurl}api/v2/local-admin-password/$management_id/set-password" \
        -H 'accept: application/json' \
        -H "Authorization: Bearer $apiBearerToken" \
        -H 'Content-Type: application/json' \
        -d "{
    \"lapsUserPasswordList\": [
        {
        \"username\": \"$lapsAdminAccount\",
        \"password\": \"$randomPassword\"
        }
    ]
    }"
    )
    check_status "$setLAPSPassword"
    if [ "$APIResult" = "Failure" ]; then
        errorOut "Failed to set LAPS Password, error: $APIResult"
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
    /usr/local/bin/jamf rotateManagementAccountPassword

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
