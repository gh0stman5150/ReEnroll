[[ -n "${REENROLL_ENROLLMENT_MODULE_LOADED:-}" ]] && return
REENROLL_ENROLLMENT_MODULE_LOADED="true"

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
        quitScript "0"
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
                quitScript "0"
                ;;
            3)
                notice "${loggedInUser} clicked Not Now;"
                state_set "ReEnrollRenewProfilesDialog" "Not Now"
                updateDialog "listitem: title: Jamf Update Needed, icon: SF=arrow.clockwise.icloud.fill,weight=bold, statustext: Deferring Update, status: nothing"
                infoOut "Removing enrollment receipt"
                webhookStatus="ReEnroll with notification"
                reEnrollMethod="Customer Chose: Not Now"
                state_set "DeviceEnrolledStatus" "Not Enrolled"
                quitScript "0"
                ;;
            4)
                notice "${loggedInUser} allowed timer to expire;"
                state_set "ReEnrollRenewProfilesDialog" "Allowed timer to expire"
                updateDialog "listitem: title: Jamf Update Needed, icon: SF=arrow.clockwise.icloud.fill,weight=bold,"
                infoOut "Removing enrollment receipt"
                webhookStatus="ReEnroll with notification"
                reEnrollMethod="Customer allowed timer to expire"
                state_set "DeviceEnrolledStatus" "Not Enrolled"
                quitScript "0"
                ;;
            20)
                notice "${loggedInUser} had Do Not Disturb enabled"
                state_set "ReEnrollRenewProfilesDialog" "Do Not Disturb enabled"
                updateDialog "listitem: title: Jamf Update Needed, icon: SF=arrow.clockwise.icloud.fill,weight=bold,"
                infoOut "Removing enrollment receipt"
                webhookStatus="ReEnroll with notification"
                reEnrollMethod="Customer had Do Not Disturb enabled"
                state_set "DeviceEnrolledStatus" "Not Enrolled"
                quitScript "0"
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
        /usr/bin/osascript -e "$updateProfilesOSA"
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
        /usr/local/bin/jamf enroll -invitation "$enrollmentInvitation" -noRecon -noPolicy
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

    errorCount=0

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
        /usr/local/bin/jamf recon -endUsername "${networkUser}" --verbose >> $tempInventoryLog

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
    /usr/bin/curl --silent --output /dev/null --request PATCH \
        -sf "${jssurl}api/v1/computers-inventory-detail/$computerID" \
        --header "Authorization: Bearer $apiBearerToken" \
        --header 'accept: application/json' \
        --header 'Content-Type: application/json' \
        --data "{
        \"general\": {
            \"siteId\": \"$computerSiteID\"
        }
        }"
}

function newComputerSiteUpdate() {
    if isDryRun; then
        dryRunOut "Would update the computer to the new Jamf site ID '${newComputerSiteID}'"
        return 0
    fi

    infoOut "Computer has an original Site: ($computerSite)"
    /usr/bin/curl --silent --output /dev/null --request PATCH \
        -sf "${jssurl}api/v1/computers-inventory-detail/$computerID" \
        --header "Authorization: Bearer $apiBearerToken" \
        --header 'accept: application/json' \
        --header 'Content-Type: application/json' \
        --data "{
        \"general\": {
            \"siteId\": \"$newComputerSiteID\"
        }
        }"
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
        quitScript "0"
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

    quitScript "0"
}
