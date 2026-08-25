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
