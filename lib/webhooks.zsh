[[ -n "${REENROLL_WEBHOOKS_MODULE_LOADED:-}" ]] && return
REENROLL_WEBHOOKS_MODULE_LOADED="true"

function webHookMessage() {
    if isDryRun; then
        dryRunOut "Would send webhook notifications to configured Slack and Teams destinations"
        return 0
    fi

    if [[ -z "$slackURL" ]]; then
        infoOut "No slack URL configured"
    else
        if [[ -z "$supportTeamHyperlink" ]]; then
            supportTeamHyperlink="https://www.slack.com"
        fi

        if [[ -z "$client_id" || -z "$client_secret" ]] || [ "$APIAccess" = "Failure" ]; then
            webhookComputerModel="$modelName"
        else
            webhookComputerModel="$computerModel"
        fi

        infoOut "Sending Slack WebHook"
        curl -s -X POST -H 'Content-type: application/json' \
            -d \
            '{
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "'${scriptName}': '"${webhookStatus}"'"
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
                    "text": ">*Serial Number and Computer Name:*\n>'"$serialNumber"' on '"$computerName"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Computer Model:*\n>'"$webhookComputerModel"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Current User:*\n>'"$loggedInUserFirstname $loggedInUserLastname (User ID: $loggedInUser)"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Notification Status:*\n>'"$webhookStatus"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*ReEnrollment Method:*\n>'"$reEnrollMethod"'"
                },
                {
                    "type": "mrkdwn",
                    "text": ">*Computer Record:*\n>'"$jamfProComputerURL"'"
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
                    "url": "'"$jamfProComputerURL"'"
                }
            ]
        }
    ]
}' \
            "$slackURL"
    fi

    if [[ -z "$teamsURL" ]]; then
        infoOut "No teams Webhook configured"
    else
        if [[ -z "$supportTeamHyperlink" ]]; then
            supportTeamHyperlink="https://www.microsoft.com/en-us/microsoft-teams/"
        fi

        if [[ -z "$client_id" || -z "$client_secret" ]] || [ "$APIAccess" = "Failure" ]; then
            webhookComputerModel="$modelName"
        else
            webhookComputerModel="$computerModel"
        fi

        infoOut "Sending Teams WebHook"
        jsonPayload='{
    "@type": "AdaptiveCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "0076D7",
    "summary": "'${scriptName}': '${webhookStatus}'",
    "sections": [{
        "activityTitle": "'${scriptName}': '${webhookStatus}'",
        "activityImage": "https://raw.githubusercontent.com/AndrewMBarnett/ReEnroll/refs/heads/main/Extras/Images/systemSettings.png",
        "facts": [{
            "name": "Computer Name (Serial Number):",
            "value": "'"$computerName"' ('"$serialNumber"')"
        }, {
            "name": "Computer Model:",
            "value": "'"$webhookComputerModel"'"
        }, {
            "name": "Current User:",
            "value": "'"$loggedInUserFirstname $loggedInUserLastname (User ID: $loggedInUser)"'"
        }, {
            "name": "Notification Status:",
            "value": "'"$webhookStatus"'"
        }, {
            "name": "ReEnrollment Method:",
            "value": "'"$reEnrollMethod"'"
        }, {
            "name": "Computer Record:",
            "value": "'"$jamfProComputerURL"'"
        }],
        "markdown": true
    }],
    "potentialAction": [{
        "@type": "OpenUri",
        "name": "View in Jamf Pro",
        "targets": [{
            "os": "default",
            "uri":
            "'"$jamfProComputerURL"'"
        }]
    }]
}'

        curl -s -X POST -H "Content-Type: application/json" -d "$jsonPayload" "$teamsURL"
    fi
}
