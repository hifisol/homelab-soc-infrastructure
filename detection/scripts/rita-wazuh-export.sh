#!/bin/bash
# RITA to Wazuh Export Script
# Runs RITA analysis and outputs findings to /var/log/rita/alerts.log
# Wazuh monitors this log file and triggers rules based on content
# Schedule via cron: 30 * * * * /opt/rita-wazuh-export.sh

LOG_FILE="/var/log/rita/alerts.log"
DB="${RITA_DB:-localhost-rolling}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Minimum beacon score to alert (0.92 = 92% confidence)
MIN_BEACON_SCORE=0.92

# Safelist for beacons (cloud services that naturally beacon)
# Add IP prefixes to safelist (pipe-delimited regex). Example: "142.251|74.125|172.217"
BEACON_SAFELIST="${BEACON_SAFELIST:-}"

# Safelist for long connections (Tailscale, cloud services, etc.)
# Example: "142.250|172.217|13.107"
LONG_CONN_SAFELIST="${LONG_CONN_SAFELIST:-}"

# Function to log JSON alert
log_alert() {
    local type="$1"
    local src_ip="$2"
    local dst_ip="$3"
    local score="$4"
    local details="$5"

    echo "{\"timestamp\":\"$TIMESTAMP\",\"type\":\"$type\",\"src_ip\":\"$src_ip\",\"dst_ip\":\"$dst_ip\",\"score\":\"$score\",\"details\":\"$details\",\"database\":\"$DB\"}" >> "$LOG_FILE"
}

# Check for beacons (C2 activity) - only high confidence, exclude safelisted
rita show-beacons "$DB" 2>/dev/null | tail -n +2 | while IFS=, read -r score src dst conns avgbytes totalbytes tsscore dsscore durscore histscore topint; do
    if [[ -n "$score" && "$score" != "Score" ]]; then
        # Skip if destination is safelisted
        if [[ -n "$BEACON_SAFELIST" ]] && echo "$dst" | grep -qE "$BEACON_SAFELIST"; then
            continue
        fi
        # Compare score using bc for floating point
        if (( $(echo "$score >= $MIN_BEACON_SCORE" | bc -l) )); then
            log_alert "beacon" "$src" "$dst" "$score" "connections:$conns"
        fi
    fi
done

# Check for long connections > 1 hour (3600 seconds) - exclude safelisted IPs
rita show-long-connections "$DB" 2>/dev/null | tail -n +2 | head -20 | while IFS=, read -r src dst port duration state; do
    if [[ -n "$src" && "$src" != "Source IP" ]]; then
        dur_int=${duration%.*}
        # Skip if destination is safelisted
        if [[ -n "$LONG_CONN_SAFELIST" ]] && echo "$dst" | grep -qE "$LONG_CONN_SAFELIST"; then
            continue
        fi
        if [[ "$dur_int" -gt 3600 ]]; then
            log_alert "long_connection" "$src" "$dst" "$dur_int" "port:$port,state:$state"
        fi
    fi
done

# Check for blacklisted IPs (source) - always alert
rita show-bl-source-ips "$DB" 2>/dev/null | tail -n +2 | while IFS=, read -r ip conns total_bytes lists; do
    if [[ -n "$ip" && "$ip" != "IP" ]]; then
        log_alert "blacklist_src" "$ip" "-" "100" "connections:$conns,lists:$lists"
    fi
done

# Check for blacklisted IPs (destination) - always alert
rita show-bl-dest-ips "$DB" 2>/dev/null | tail -n +2 | while IFS=, read -r ip conns total_bytes lists; do
    if [[ -n "$ip" && "$ip" != "IP" ]]; then
        log_alert "blacklist_dst" "-" "$ip" "100" "connections:$conns,lists:$lists"
    fi
done

# Check for strobes (port scans) - only top 5 most aggressive
rita show-strobes "$DB" 2>/dev/null | tail -n +2 | head -5 | while IFS=, read -r src dst conns; do
    if [[ -n "$src" && "$src" != "Source" ]]; then
        log_alert "strobe" "$src" "$dst" "75" "connections:$conns"
    fi
done
