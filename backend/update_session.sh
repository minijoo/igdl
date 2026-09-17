#!/bin/bash
# Uploads a freshly-generated instaloader session file for SESSION_USERNAME
# to the backend droplet, replacing the one currently deployed there, then
# restarts igdl-backend so it actually picks it up — instagram.py loads the
# session once at process startup (see docs/plan.md), so just replacing the
# file on disk isn't enough on its own. Finishes with a real resolve call
# against the live backend to confirm the new session actually works,
# rather than just trusting the file copy succeeded.
#
# Usage:
#   ./update_session.sh [short_code_to_verify_with]
#
# Generate a fresh session first if you haven't already, e.g.:
#   instaloader -b chrome --login=imjustaswe
set -euo pipefail

SESSION_USERNAME="imjustaswe"
LOCAL_SESSION_FILE="$HOME/.config/instaloader/session-${SESSION_USERNAME}"
SERVER_HOST="root@159.223.135.92"
REMOTE_SESSION_DIR="/home/igdl/.config/instaloader"
VERIFY_SHORT_CODE="${1:-DbvVH3RTq9w}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SCRIPT_DIR}/../ios/IGDL/IGDL/Networking/Secrets.swift"

if [[ ! -f "$LOCAL_SESSION_FILE" ]]; then
    echo "error: no local session file found at $LOCAL_SESSION_FILE" >&2
    echo "generate one first, e.g.: instaloader -b chrome --login=${SESSION_USERNAME}" >&2
    exit 1
fi

echo "Uploading $LOCAL_SESSION_FILE to ${SERVER_HOST}..."
scp "$LOCAL_SESSION_FILE" "${SERVER_HOST}:${REMOTE_SESSION_DIR}/session-${SESSION_USERNAME}.new"

echo "Backing up the current session and swapping in the new one..."
ssh "$SERVER_HOST" bash -s <<REMOTE
set -euo pipefail
cd "$REMOTE_SESSION_DIR"
if [[ -f "session-${SESSION_USERNAME}" ]]; then
    cp "session-${SESSION_USERNAME}" "session-${SESSION_USERNAME}.bak"
fi
mv "session-${SESSION_USERNAME}.new" "session-${SESSION_USERNAME}"
chown igdl:igdl "session-${SESSION_USERNAME}" "session-${SESSION_USERNAME}.bak"
chmod 600 "session-${SESSION_USERNAME}" "session-${SESSION_USERNAME}.bak"
REMOTE

echo "Restarting igdl-backend..."
ssh "$SERVER_HOST" "systemctl restart igdl-backend"
sleep 2
ssh "$SERVER_HOST" "systemctl is-active igdl-backend"

echo "Verifying the new session against short_code=${VERIFY_SHORT_CODE}..."
if [[ -z "${IGDL_API_KEY:-}" ]]; then
    if [[ -f "$SECRETS_FILE" ]]; then
        IGDL_API_KEY="$(sed -n 's/.*backendAPIKey = "\(.*\)"/\1/p' "$SECRETS_FILE")"
    fi
fi
if [[ -z "${IGDL_API_KEY:-}" ]]; then
    echo "warning: couldn't find the API key (no Secrets.swift and IGDL_API_KEY unset) — skipping verification" >&2
    exit 0
fi

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: ${IGDL_API_KEY}" "https://igdl.jordys.site/downloads/resolve?short_code=${VERIFY_SHORT_CODE}")
if [[ "$STATUS" == "200" ]]; then
    echo "Success: new session resolved short_code=${VERIFY_SHORT_CODE} (200 OK)."
else
    echo "warning: verification resolve returned HTTP ${STATUS} — check: ssh ${SERVER_HOST} journalctl -u igdl-backend -n 20" >&2
    exit 1
fi
