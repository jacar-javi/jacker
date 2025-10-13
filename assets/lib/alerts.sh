#!/usr/bin/env bash
#
# alerts.sh - Alert management functions for Jacker
#

# Source common functions
source "${JACKER_DIR}/assets/lib/common.sh"

# Test Telegram alerts
test_telegram_alerts() {
    log_info "Testing Telegram alerts..."

    # Check if Telegram is configured
    if [[ -z "${TELEGRAM_BOT_TOKEN}" ]] || [[ -z "${TELEGRAM_CHAT_ID}" ]]; then
        log_error "Telegram is not configured. Please run 'jacker config alerts' first."
        return 1
    fi

    # Send test message
    local test_message="🚀 *Jacker Alert Test*

✅ Telegram integration is working!
📊 System: $(hostname)
📅 Time: $(date '+%Y-%m-%d %H:%M:%S')
🏠 Domain: ${DOMAINNAME:-localhost}

This is a test message from your Jacker monitoring system."

    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${test_message}" \
        -d "parse_mode=Markdown" > /dev/null; then
        log_success "Test message sent to Telegram successfully!"
        return 0
    else
        log_error "Failed to send test message to Telegram"
        log_error "Please check your bot token and chat ID"
        return 1
    fi
}

# Test email alerts
test_email_alerts() {
    log_info "Testing email alerts..."

    # Check if email is configured
    if [[ -z "${SMTP_HOST}" ]] || [[ -z "${SMTP_USERNAME}" ]] || [[ -z "${ALERT_EMAIL_TO}" ]]; then
        log_error "Email is not configured. Please run 'jacker config alerts' first."
        return 1
    fi

    # Create test email
    local subject="[Jacker] Alert Test - ${HOSTNAME}"
    local body="This is a test email from your Jacker monitoring system.

System: ${HOSTNAME}
Domain: ${DOMAINNAME:-localhost}
Time: $(date '+%Y-%m-%d %H:%M:%S')

If you received this email, your email alerts are working correctly!"

    # Use Python to send email (more reliable than mail command)
    python3 - <<EOF
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

smtp_host = "${SMTP_HOST}"
smtp_port = ${SMTP_PORT:-587}
smtp_user = "${SMTP_USERNAME}"
smtp_pass = "${SMTP_PASSWORD}"
from_addr = "${SMTP_FROM:-${SMTP_USERNAME}}"
to_addr = "${ALERT_EMAIL_TO}"

msg = MIMEMultipart()
msg['From'] = from_addr
msg['To'] = to_addr
msg['Subject'] = "${subject}"

msg.attach(MIMEText("""${body}""", 'plain'))

try:
    server = smtplib.SMTP(smtp_host, smtp_port)
    server.starttls()
    server.login(smtp_user, smtp_pass)
    server.send_message(msg)
    server.quit()
    print("SUCCESS")
except Exception as e:
    print(f"ERROR: {e}")
EOF

    local result=$?
    if [[ $result -eq 0 ]]; then
        log_success "Test email sent successfully!"
        return 0
    else
        log_error "Failed to send test email"
        return 1
    fi
}

# Test Slack alerts
test_slack_alerts() {
    log_info "Testing Slack alerts..."

    # Check if Slack is configured
    if [[ -z "${SLACK_WEBHOOK_URL}" ]]; then
        log_error "Slack is not configured. Please run 'jacker config alerts' first."
        return 1
    fi

    # Send test message
    local test_message='{
        "text": "🚀 Jacker Alert Test",
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": "Jacker Monitoring System Test"
                }
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": "*Status:* ✅ Working"},
                    {"type": "mrkdwn", "text": "*System:* '$(hostname)'"},
                    {"type": "mrkdwn", "text": "*Domain:* '${DOMAINNAME:-localhost}'"},
                    {"type": "mrkdwn", "text": "*Time:* '$(date '+%Y-%m-%d %H:%M:%S')'"}
                ]
            }
        ]
    }'

    if curl -s -X POST "${SLACK_WEBHOOK_URL}" \
        -H 'Content-Type: application/json' \
        -d "${test_message}" | grep -q "ok"; then
        log_success "Test message sent to Slack successfully!"
        return 0
    else
        log_error "Failed to send test message to Slack"
        return 1
    fi
}

# Test all configured alert channels
test_all_alerts() {
    log_section "Testing All Alert Channels"

    local success_count=0
    local total_count=0

    # Test Telegram
    if [[ -n "${TELEGRAM_BOT_TOKEN}" ]]; then
        ((total_count++))
        if test_telegram_alerts; then
            ((success_count++))
        fi
    fi

    # Test Email
    if [[ -n "${SMTP_HOST}" ]]; then
        ((total_count++))
        if test_email_alerts; then
            ((success_count++))
        fi
    fi

    # Test Slack
    if [[ -n "${SLACK_WEBHOOK_URL}" ]]; then
        ((total_count++))
        if test_slack_alerts; then
            ((success_count++))
        fi
    fi

    if [[ $total_count -eq 0 ]]; then
        log_warn "No alert channels are configured"
        log_info "Run 'jacker config alerts' to set up alert notifications"
        return 1
    fi

    echo
    log_info "Test Results: ${success_count}/${total_count} channels working"

    if [[ $success_count -eq $total_count ]]; then
        log_success "All alert channels are working correctly!"
        return 0
    else
        log_warn "Some alert channels failed. Please check the configuration."
        return 1
    fi
}

# Show current alert configuration
show_alert_config() {
    log_section "Alert Configuration"

    echo "Email Alerts:"
    if [[ -n "${SMTP_HOST}" ]]; then
        echo "  SMTP Host: ${SMTP_HOST}:${SMTP_PORT}"
        echo "  SMTP User: ${SMTP_USERNAME}"
        echo "  Recipients: ${ALERT_EMAIL_TO}"
        success "  Status: Configured"
    else
        echo "  Status: Not configured"
    fi

    echo
    echo "Telegram Alerts:"
    if [[ -n "${TELEGRAM_BOT_TOKEN}" ]]; then
        echo "  Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}..."
        echo "  Chat ID: ${TELEGRAM_CHAT_ID}"
        success "  Status: Configured"
    else
        echo "  Status: Not configured"
    fi

    echo
    echo "Slack Alerts:"
    if [[ -n "${SLACK_WEBHOOK_URL}" ]]; then
        echo "  Webhook: ${SLACK_WEBHOOK_URL:0:50}..."
        echo "  Default Channel: ${SLACK_CHANNEL_INFO:-#monitoring}"
        success "  Status: Configured"
    else
        echo "  Status: Not configured"
    fi

    echo
    echo "Alert Routing:"
    echo "  Critical: ${ALERT_EMAIL_CRITICAL:-${ALERT_EMAIL_TO:-Not set}}"
    echo "  Security: ${ALERT_EMAIL_SECURITY:-${ALERT_EMAIL_TO:-Not set}}"
    echo "  Database: ${ALERT_EMAIL_DATABASE:-${ALERT_EMAIL_TO:-Not set}}"
    echo "  Warning: ${ALERT_EMAIL_WARNING:-${ALERT_EMAIL_TO:-Not set}}"
}

# Export functions
export -f test_telegram_alerts test_email_alerts test_slack_alerts
export -f test_all_alerts show_alert_config