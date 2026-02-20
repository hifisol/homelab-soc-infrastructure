#!/bin/bash
# RITA Daily Summary Report Generator
# Generates downloadable CSV/JSON reports and posts summary to Discord
# Schedule via cron: 0 6 * * * /opt/rita-daily-report.sh

REPORT_DIR="/var/log/rita/reports"
DB="${RITA_DB:-localhost-rolling}"
DATE=$(date +"%Y-%m-%d")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"

mkdir -p "$REPORT_DIR"

CSV_FILE="${REPORT_DIR}/rita-report-${DATE}.csv"
JSON_FILE="${REPORT_DIR}/rita-report-${DATE}.json"
SUMMARY_FILE="${REPORT_DIR}/rita-summary-${DATE}.txt"

# Initialize summary
cat > "$SUMMARY_FILE" << EOF
================================================================================
                        RITA Daily Threat Analysis Report
================================================================================
Date: ${DATE}
Generated: ${TIMESTAMP}
Database: ${DB}
================================================================================
EOF

echo "type,src_ip,dst_ip,score,connections,details,timestamp" > "$CSV_FILE"
echo "[" > "$JSON_FILE"

# ===== BEACONS =====
echo "" >> "$SUMMARY_FILE"
echo "=== BEACONS (Potential C2 Activity) ===" >> "$SUMMARY_FILE"

BEACON_DATA=""
BEACON_COUNT=0
while IFS=, read -r score src dst conns rest; do
    if [[ -n "$score" && "$score" != "Score" ]]; then
        echo "beacon,$src,$dst,$score,$conns,\"beacon\",${TIMESTAMP}" >> "$CSV_FILE"
        printf "%s | %s | %s | %s\n" "$score" "$src" "$dst" "$conns" >> "$SUMMARY_FILE"
        if [ $BEACON_COUNT -lt 8 ]; then
            BEACON_DATA="${BEACON_DATA}${score} | ${src} -> ${dst}\n"
        fi
        ((BEACON_COUNT++))
    fi
done < <(rita show-beacons "$DB" 2>/dev/null | tail -n +2 | head -50)

# ===== LONG CONNECTIONS =====
echo "" >> "$SUMMARY_FILE"
echo "=== LONG CONNECTIONS (>1 hour) ===" >> "$SUMMARY_FILE"

LONG_DATA=""
LONG_COUNT=0
while IFS=, read -r src dst port duration state; do
    if [[ -n "$src" && "$src" != "Source IP" ]]; then
        dur_int=${duration%.*}
        if [ "$dur_int" -gt 3600 ] 2>/dev/null; then
            hours=$((dur_int / 3600))
            echo "long_conn,$src,$dst,$duration,1,\"port:$port\",${TIMESTAMP}" >> "$CSV_FILE"
            printf "%sh | %s | %s | %s\n" "$hours" "$src" "$dst" "$port" >> "$SUMMARY_FILE"
            if [ $LONG_COUNT -lt 8 ]; then
                LONG_DATA="${LONG_DATA}${hours}h | ${src} -> ${dst}\n"
            fi
            ((LONG_COUNT++))
        fi
    fi
done < <(rita show-long-connections "$DB" 2>/dev/null | tail -n +2 | head -50)

# ===== STROBES =====
echo "" >> "$SUMMARY_FILE"
echo "=== STROBES (Port Scan Activity) ===" >> "$SUMMARY_FILE"

STROBE_DATA=""
STROBE_COUNT=0
while IFS=, read -r src dst conns; do
    if [[ -n "$src" && "$src" != "Source" ]]; then
        echo "strobe,$src,$dst,$conns,$conns,\"portscan\",${TIMESTAMP}" >> "$CSV_FILE"
        printf "%s | %s | %s\n" "$src" "$dst" "$conns" >> "$SUMMARY_FILE"
        if [ $STROBE_COUNT -lt 5 ]; then
            STROBE_DATA="${STROBE_DATA}${src} -> ${dst} (${conns})\n"
        fi
        ((STROBE_COUNT++))
    fi
done < <(rita show-strobes "$DB" 2>/dev/null | tail -n +2 | head -20)

echo "]" >> "$JSON_FILE"

cat >> "$SUMMARY_FILE" << EOF

================================================================================
Reports: $CSV_FILE
================================================================================
EOF

chmod 644 "$CSV_FILE" "$JSON_FILE" "$SUMMARY_FILE"
find "$REPORT_DIR" -name "rita-*" -mtime +30 -delete 2>/dev/null

# ===== POST TO DISCORD =====
[ -z "$BEACON_DATA" ] && BEACON_DATA="None detected"
[ -z "$LONG_DATA" ] && LONG_DATA="None detected"
[ -z "$STROBE_DATA" ] && STROBE_DATA="None detected"

python3 << PYEOF
import json
import requests

webhook = "$DISCORD_WEBHOOK"
date = "$DATE"
timestamp = "$TIMESTAMP"
beacon_count = $BEACON_COUNT
long_count = $LONG_COUNT
strobe_count = $STROBE_COUNT

beacon_data = """$(echo -e "$BEACON_DATA")""".strip() or "None detected"
long_data = """$(echo -e "$LONG_DATA")""".strip() or "None detected"
strobe_data = """$(echo -e "$STROBE_DATA")""".strip() or "None detected"

payload = {
    "embeds": [{
        "title": f"RITA Daily Summary - {date}",
        "color": 3447003,
        "fields": [
            {"name": f"Top Beacons ({beacon_count} total)", "value": f"\`\`\`{beacon_data[:500]}\`\`\`", "inline": False},
            {"name": f"Long Connections ({long_count} total)", "value": f"\`\`\`{long_data[:500]}\`\`\`", "inline": False},
            {"name": f"Port Scans ({strobe_count} total)", "value": f"\`\`\`{strobe_data[:300]}\`\`\`", "inline": False},
        ],
        "footer": {"text": f"RITA Network Threat Analysis | {timestamp}"}
    }]
}

try:
    r = requests.post(webhook, json=payload, timeout=10)
    print(f"Discord: {r.status_code}")
except Exception as e:
    print(f"Discord error: {e}")
PYEOF

echo "RITA daily report generated: $SUMMARY_FILE"
