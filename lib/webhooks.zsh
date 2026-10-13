[[ -n "${REENROLL_WEBHOOKS_MODULE_LOADED:-}" ]] && return
REENROLL_WEBHOOKS_MODULE_LOADED="true"

# Escapes a value for use inside a JSON string literal: backslash, double
# quote and every control character. Computer names and the full name from
# "id -F" are end-user controlled, so a raw value could break the payload or
# inject extra Slack blocks or Teams card actions.
function jsonEscape() {
    emulate -L zsh
    local value="$1" char escapedChar
    local -i code

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\f'/\\f}"
    for code in {1..31}; do
        char="${(#)code}"
        [[ "${value}" == *"${char}"* ]] || continue
        printf -v escapedChar '\\u%04x' "${code}"
        value="${value//${char}/${escapedChar}}"
    done
    print -r -- "${value}"
}

# Slack mrkdwn treats &, < and > as control characters (<!channel>, links).
function slackEscape() {
    local value="$1"
    value="${value//"&"/&amp;}"
    value="${value//"<"/&lt;}"
    value="${value//">"/&gt;}"
    print -r -- "${value}"
}

# A value for a Slack mrkdwn field inside the JSON payload.
function slackField() {
    jsonEscape "$(slackEscape "$1")"
}

function webHookMessage() {
    if isDryRun; then
        dryRunOut "Would send webhook notifications to configured Slack and Teams destinations"
        return 0
    fi

    local webhookUser slackPayload jsonPayload

    if [[ -z "$client_id" || -z "$client_secret" ]] || [ "$APIAccess" = "Failure" ]; then
        webhookComputerModel="$modelName"
    else
        webhookComputerModel="$computerModel"
    fi
    webhookUser="$loggedInUserFirstname $loggedInUserLastname (User ID: $loggedInUser)"

    if [[ -z "$slackURL" ]]; then
        infoOut "No slack URL configured"
    else
        if [[ -z "$supportTeamHyperlink" ]]; then
            supportTeamHyperlink="https://www.slack.com"
        fi

        infoOut "Sending Slack WebHook"
        slackPayload='{
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "'"$(jsonEscape "${scriptName}: ${webhookStatus}")"'"
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
                    "text": ">*Serial Number and Computer Name:*\n>'"$(slackField "$serialNumber on $computerName")"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Computer Model:*\n>'"$(slackField "$webhookComputerModel")"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Current User:*\n>'"$(slackField "$webhookUser")"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Notification Status:*\n>'"$(slackField "$webhookStatus")"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*ReEnrollment Method:*\n>'"$(slackField "$reEnrollMethod")"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Computer Record:*\n>'"$(slackField "$jamfProComputerURL")"'"
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
                    "url": "'"$(jsonEscape "$jamfProComputerURL")"'"
                }
            ]
        }
    ]
}'

        if ! /usr/bin/curl --silent --show-error --fail \
            --connect-timeout 10 --max-time 30 \
            --request POST --header 'Content-type: application/json' \
            -d "$slackPayload" \
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

        infoOut "Sending Teams WebHook"
        jsonPayload='{
    "@type": "AdaptiveCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "0076D7",
    "summary": "'"$(jsonEscape "${scriptName}: ${webhookStatus}")"'",
    "sections": [{
        "activityTitle": "'"$(jsonEscape "${scriptName}: ${webhookStatus}")"'",
        "activityImage": "https://raw.githubusercontent.com/AndrewMBarnett/ReEnroll/refs/heads/main/Extras/Images/systemSettings.png",
        "facts": [{
            "name": "Computer Name (Serial Number):",
            "value": "'"$(jsonEscape "$computerName ($serialNumber)")"'"
        }, {
            "name": "Computer Model:",
            "value": "'"$(jsonEscape "$webhookComputerModel")"'"
        }, {
            "name": "Current User:",
            "value": "'"$(jsonEscape "$webhookUser")"'"
        }, {
            "name": "Notification Status:",
            "value": "'"$(jsonEscape "$webhookStatus")"'"
        }, {
            "name": "ReEnrollment Method:",
            "value": "'"$(jsonEscape "$reEnrollMethod")"'"
        }, {
            "name": "Computer Record:",
            "value": "'"$(jsonEscape "$jamfProComputerURL")"'"
        }],
        "markdown": true
    }],
    "potentialAction": [{
        "@type": "OpenUri",
        "name": "View in Jamf Pro",
        "targets": [{
            "os": "default",
            "uri":
            "'"$(jsonEscape "$jamfProComputerURL")"'"
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
