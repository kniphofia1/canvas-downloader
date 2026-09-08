#!/bin/sh

# Cron entrypoint for NAS scheduled runs.
# It refreshes the Canvas token through the existing Compose command, then runs
# canvas-downloader only after the wrapper has stored the fresh token.

set -u
umask 077

PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

PROJECT_DIR="${FUDAN_CANVAS_PROJECT_DIR:-/vol1/1000/Docker/Fudan_canvasdownloader}"
LOG_FILE="${FUDAN_CANVAS_CRON_LOG:-$PROJECT_DIR/sync-cron.log}"
LOCK_FILE="${FUDAN_CANVAS_LOCK_FILE:-/tmp/fudan-canvasdownloader.lock}"
RUN_RETRIES="${CANVAS_RUN_RETRIES:-3}"
RETRY_DELAY="${CANVAS_RETRY_DELAY_SECONDS:-60}"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S %z'
}

run_compose_once() {
    cd "$PROJECT_DIR" || return 1

    echo "[$(timestamp)] Starting Fudan Canvas token refresh and sync."

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        docker compose run --rm fudan-canvasdownloader
        code=$?
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose run --rm fudan-canvasdownloader
        code=$?
    else
        echo "[$(timestamp)] ERROR: neither 'docker compose' nor 'docker-compose' is available." >&2
        code=127
    fi

    echo "[$(timestamp)] Finished Fudan Canvas sync with exit code $code."
    return "$code"
}

run_compose_sync() {
    attempt=1
    while :; do
        run_compose_once
        code=$?
        if [ "$code" -eq 0 ] || [ "$attempt" -ge "$RUN_RETRIES" ]; then
            return "$code"
        fi
        echo "[$(timestamp)] Attempt $attempt/$RUN_RETRIES failed; retrying in ${RETRY_DELAY}s."
        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done
}

mkdir -p "$(dirname "$LOG_FILE")"

if command -v flock >/dev/null 2>&1; then
    (
        if ! flock -n 9; then
            echo "[$(timestamp)] Previous Fudan Canvas sync is still running; skipping this schedule."
            exit 0
        fi
        run_compose_sync
    ) 9>"$LOCK_FILE" >>"$LOG_FILE" 2>&1
else
    run_compose_sync >>"$LOG_FILE" 2>&1
fi
