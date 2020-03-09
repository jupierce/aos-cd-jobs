import groovy.json.JsonOutput

def notifySlack(channel, text, attachments=[], thread_ts=null) {
    // https://www.christopherrung.com/2017/05/04/slack-build-notifications/

     withCredentials([string(credentialsId: 'art-bot-slack-token', variable: 'SLACK_BOT_TOKEN')]) {

        base = [   channel: channel,
                   icon_emoji: ":robot_face:",
                   username: "art-release-bot",
                   attachments: attachments,
                   link_names: 1,
                   // icon_url
        ]

        if ( text ) {
            base['text'] = text
        }

        if ( thread_ts ) {
            base['thread_ts'] = thread_ts
        }

        def payload = JsonOutput.toJson(base)
        // echo "Sending slack notification: ${payload}\n"
        response = httpRequest(
                        // consoleLogResponseBody: true, // Great for debug, but noisy otherwise
                        httpMode: 'POST',
                        quiet: true,
                        contentType: 'APPLICATION_JSON',
                        customHeaders: [
                            [   maskValue: true,
                                name: 'Authorization',
                                value: "Bearer $SLACK_BOT_TOKEN"
                            ]
                        ],
                        ignoreSslErrors: true,
                        requestBody: "${payload}",
                        url: 'https://slack.com/api/chat.postMessage'
        )

         //print "Received slack response: ${response}\n\n"
         return readJSON(text: response.content)
    }
}

class SlackTrack {

}

def newSlackThread(channel, text, attachments=[]) {
    json = notifySlack(channel, text, attachments)
    return json.message.ts
}

// Default channel for art slack notifications
art_channel = '#art-release'

def art_slack_thread_channel(channel) {
    art_channel = channel
}

// Global notification attachments for slack notifications.
art_notification_attachments = []

art_current_thread_ts = null

def art_slack_notification(text, additional_attachments = [], with_callouts=false, thread_ts=null) {
    try {
        if (with_callouts) {
            attachments = additional_attachments + art_notification_attachments
        } else {
            attachments = additional_attachments
        }
        slack_lib.notifySlack(art_channel, text, attachments, thread_ts)
    } catch ( e ) {
        echo "Error sending slack notification: ${e}"
    }
}

def art_slack_thread_append(text, additional_attachments=[], with_callouts=false) {
    art_slack_notification(text, additional_attachments, with_callouts, art_current_thread_ts)
}

def art_slack_thread(title, color='#439FE0', attachments=[]) {
    owner = ''

    wrap([$class: 'BuildUser']) {
        if ( env.BUILD_USER_EMAIL ) { //null if triggered by timer
            owner = env.BUILD_USER_EMAIL
        } else {
            owner = 'Timer'
        }
    }

    attachments << [
            title: "${title}\nJob: <${env.BUILD_URL}console|#${currentBuild.number}> by ${owner}",
            color: color,
    ]
    art_current_thread_ts = slack_lib.newSlackThread(art_channel, null, attachments)
}

return this