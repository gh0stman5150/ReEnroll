[[ -n "${REENROLL_JAMF_API_MODULE_LOADED:-}" ]] && return
REENROLL_JAMF_API_MODULE_LOADED="true"

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

function check_token() {

    apitokenCheck=$(/usr/bin/curl --write-out "%{http_code}" --silent --output /dev/null "${jssurl}api/v1/auth" --request GET --header "Authorization: Bearer ${apiBearerToken}")
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
    if [[ $1 == *"Bad Request"* || $1 == *"httpStatus"* || $1 == *"Access Denied"* || $1 == *"Status page"* ]]; then
        APIResult="Failure"
    else
        APIResult="Command Sent"
    fi
}

function apiResponse() {
    response=$(/usr/bin/curl -s -X GET \
        -H "Authorization: Bearer $apiBearerToken" \
        -H "Accept: application/xml" \
        "${jssurl}JSSResource/computers/serialnumber/$serialNumber")
}

function computerIDLookup() {

    computerID=$(echo "$response" | xmllint --xpath 'string(/computer/general/id)' - | sed 's/[^0-9]*//g')

    if [[ "$debugMode" = "verbose" ]]; then
        debugVerbose "Computer ID: $computerID"
    fi

    managmentIDAPI=$(/usr/bin/curl -s -X GET \
        -H "Authorization: Bearer $apiBearerToken" \
        -H "accept: application/json" \
        "${jssurl}api/v1/computers-inventory-detail/$computerID")
    check_status "$managmentIDAPI"
    if [ "$APIResult" = "Failure" ]; then
        errorOut "Failed to gather computer inventory, error: $APIResult"
    else
        infoOut "Successfully gathered computer inventory, result: $APIResult"
    fi

    management_id=$(extract_from_json "$managmentIDAPI" "managementId")

    if [ -z "$management_id" ]; then
        management_id=$(extract_from_json "$managmentIDAPI" "general:managementId")
    fi

    if [[ "$debugMode" = "verbose" ]]; then
        debugVerbose "Management ID: $management_id"
    fi
}

function computerInventoryInfo() {

    generalComputerInfo=$(/usr/bin/curl -H "Authorization: Bearer ${apiBearerToken}" -H "Accept: text/xml" -sfk "${jssurl}JSSResource/computers/id/${computerID}/subset/General" -X GET)
    check_status "$generalComputerInfo"
    if [ "$APIResult" = "Failure" ]; then
        errorOut "Failed to get general computer info, error: $APIResult"
    else
        infoOut "Successfully gathered general computer info, result: $APIResult"
    fi

    hardwareComputerInfo=$(/usr/bin/curl -H "Authorization: Bearer ${apiBearerToken}" -H "Accept: text/xml" -sfk "${jssurl}JSSResource/computers/id/${computerID}/subset/Hardware" -X GET)
    check_status "$hardwareComputerInfo"
    if [ "$APIResult" = "Failure" ]; then
        errorOut "Failed to get hardware computer info, error: $APIResult"
    else
        infoOut "Successfully gathered hardware computer info, result: $APIResult"
    fi

    computerName=$(echo "${generalComputerInfo}" | xpath -q -e "/computer/general/name/text()")
    computerSerialNumber=$(echo "${generalComputerInfo}" | xpath -q -e "/computer/general/serial_number/text()")
    computerModel=$(echo "${hardwareComputerInfo}" | xpath -q -e "/computer/hardware/model/text()")
    computerIpAddress=$(echo "${generalComputerInfo}" | xpath -q -e "/computer/general/ip_address/text()")
    computerIpAddressLastReported=$(echo "${generalComputerInfo}" | xpath -q -e "/computer/general/last_reported_ip/text()")
    computerSite=$(echo "${generalComputerInfo}" | xpath -q -e "/computer/general/site/name/text()")
    computerSiteID=$(echo "${generalComputerInfo}" | xpath -q -e "/computer/general/site/id/text()")

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
    clearFailedCommandsResult=$(/usr/bin/curl -H "Authorization: Bearer ${apiBearerToken}" "${jssurl}JSSResource/commandflush/computers/id/${computerID}/status/Failed" -X DELETE)
    check_status "$clearFailedCommandsResult"

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
    redeployResult=$(/usr/bin/curl -H "Authorization: Bearer ${apiBearerToken}" -H "accept: application/json" --progress-bar --fail-with-body "${jssurl}api/v1/jamf-management-framework/redeploy/${computerID}" -X POST)
    check_status "$redeployResult"
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

    tokenResponse=$(curl --silent --location --request POST "${jssurl}api/oauth/token" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=${client_id}" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_secret=${client_secret}")

    if [[ "${osMajorVersion}" -lt 12 ]]; then
        apiBearerToken=$(/usr/bin/awk -F \" 'NR==2{print $4}' <<< "$tokenResponse" | /usr/bin/xargs)
    else
        apiBearerToken=$(echo "$tokenResponse" | plutil -extract access_token raw -)
    fi
    check_token "$tokenResponse"
    if [ "$APIResult" = "Failure" ]; then
        APIAccess="Failure"
        error "API Access result: $APIAccess"
    elif [ "$APIResult" = "Token Good" ]; then
        infoOut "API Bearer Token obtained"
        APIAccess="Success"
        infoOut "API Access result: $APIAccess"
        token_expires_in=$(echo "$tokenResponse" | plutil -extract expires_in raw -)
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
        apiResponse
        computerIDLookup
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
    jssStatus=$(/usr/local/bin/jamf checkJSSConnection 2>&1 | /usr/bin/tr -d '\n')

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

    marker_file="/var/tmp/jamfTempMarker.txt"
    jamfLogFile="/var/log/jamf.log"
    duplicate_jamfLogFile="$duplicate_log_dir/jamf_position_$timestamp.log"

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
