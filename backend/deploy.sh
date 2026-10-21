#!/bin/bash
# Deploys the backend code to the droplet: rsyncs app/ and requirements.txt
# to /opt/igdl/backend/, restarts igdl-backend, and confirms it came up and
# which Instagram session it's configured to load (SESSION_USERNAME lives in app/config.py,
# so a deploy is what actually switches accounts — update_session.sh only
# replaces the session file, not the code).
#
# Deliberately leaves .env and .venv on the server alone. If requirements.txt
# changed, install the new deps by hand:
#   ssh root@159.223.135.92 'sudo -u igdl /opt/igdl/backend/.venv/bin/pip install -r /opt/igdl/backend/requirements.txt'
#
# Usage:
#   ./deploy.sh [--dry-run]   # --dry-run only lists what would be copied
set -euo pipefail

SERVER_HOST="root@159.223.135.92"
REMOTE_DIR="/opt/igdl/backend"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RSYNC_FLAGS=(-rlptv --exclude '__pycache__/' --exclude 'test_*.py')
if [[ "${1:-}" == "--dry-run" ]]; then
    RSYNC_FLAGS+=(--dry-run)
fi

echo "Syncing app/ to ${SERVER_HOST}:${REMOTE_DIR}/app/ ..."
# --delete scoped to app/ only, so a file removed locally is removed on the
# server too; nothing outside app/ is ever touched by it.
rsync "${RSYNC_FLAGS[@]}" --delete "${SCRIPT_DIR}/app/" "${SERVER_HOST}:${REMOTE_DIR}/app/"
rsync "${RSYNC_FLAGS[@]}" "${SCRIPT_DIR}/requirements.txt" "${SERVER_HOST}:${REMOTE_DIR}/requirements.txt"

if [[ "${1:-}" == "--dry-run" ]]; then
    echo "Dry run — nothing copied, service not restarted."
    exit 0
fi

# macOS's bundled rsync predates --chown, so fix ownership afterwards.
ssh "$SERVER_HOST" "chown -R igdl:igdl ${REMOTE_DIR}/app ${REMOTE_DIR}/requirements.txt"

echo "Restarting igdl-backend..."
ssh "$SERVER_HOST" "systemctl restart igdl-backend"
sleep 3
STATE="$(ssh "$SERVER_HOST" "systemctl is-active igdl-backend" || true)"
if [[ "$STATE" != "active" ]]; then
    echo "error: igdl-backend is '${STATE}' after restart — check: ssh ${SERVER_HOST} journalctl -u igdl-backend -n 50" >&2
    exit 1
fi

# Reads the deployed config rather than grepping the journal for "Loaded
# session": that line is a buffered print() that doesn't reach the journal
# until the first request, so it's absent right after a restart.
echo "Deployed config: $(ssh "$SERVER_HOST" "grep SESSION_USERNAME ${REMOTE_DIR}/app/config.py")"
echo "Deployed."
