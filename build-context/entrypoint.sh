#!/usr/bin/env bash
set -euo pipefail

# Configuration
HOST="${UNOSERVER_HOST:-0.0.0.0}"
PORT="${UNOSERVER_PORT:-2003}"
CONVERSION_TIMEOUT="${CONVERSION_TIMEOUT:-10}"

# Watchdog settings
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"
MAX_CONSECUTIVE_FAILURES="${MAX_CONSECUTIVE_FAILURES:-3}"

RESTART_BACKOFF_SECONDS="${RESTART_BACKOFF_SECONDS:-2}"
UNOSERVER_PID=""
STOP_REQUESTED="0"

log() { echo "[$(date -Is)] $*" >&2; }

# --- Process Management ---

kill_soffice() {
  # Kill only soffice.bin processes belonging to this user
  # This avoids killing system-wide processes if running on a shared host
  local pids
  pids="$(pgrep -u "$(id -u)" -f 'soffice\.bin' || true)"
  if [[ -n "${pids}" ]]; then
    log "Cleaning up leftover LibreOffice PIDs: ${pids}"
    kill -TERM ${pids} 2>/dev/null || true
    sleep 1
    kill -KILL ${pids} 2>/dev/null || true
  fi
}

stop_unoserver() {
  if [[ -n "${UNOSERVER_PID}" ]]; then
    log "Stopping unoserver (PID ${UNOSERVER_PID})..."
    kill -TERM "${UNOSERVER_PID}" 2>/dev/null || true
    wait "${UNOSERVER_PID}" 2>/dev/null || true
  fi
  kill_soffice
}

start_unoserver() {
  log "Starting unoserver on ${HOST}:${PORT}..."
  unoserver --interface "${HOST}" --port "${PORT}" --conversion-timeout "${CONVERSION_TIMEOUT}" &
  UNOSERVER_PID="$!"

  # Wait for port to open
  for i in {1..20}; do
    if timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${PORT}" 2>/dev/null; then
      log "unoserver is listening."
      return 0
    fi
    sleep 1
  done

  log "Timed out waiting for unoserver start."
  return 1
}

restart_stack() {
  log "Restarting stack..."
  stop_unoserver
  sleep "${RESTART_BACKOFF_SECONDS}"
  start_unoserver
}

# --- Functional Healthcheck ---

check_health() {
  local test_file="/tmp/healthcheck_${PORT}.txt"
  local pdf_file="/tmp/healthcheck_${PORT}.pdf"
  echo "healthcheck" > "${test_file}"

  # Run a tiny conversion to prove the system works
  # We use the 'unoconvert' client which is installed alongside the server
  if timeout "${HEALTH_CHECK_TIMEOUT}" unoconvert \
      --host "127.0.0.1" \
      --port "${PORT}" \
      --convert-to pdf \
      "${test_file}" \
      "${pdf_file}" >/dev/null 2>&1; then

    rm -f "${test_file}" "${pdf_file}"
    return 0 # Success
  fi

  rm -f "${test_file}" "${pdf_file}"
  return 1 # Failure
}

# --- Main Loop ---

cleanup_and_exit() {
  STOP_REQUESTED="1"
  trap - EXIT
  log "Shutdown signal received."
  stop_unoserver
  exit 0
}

trap cleanup_and_exit TERM INT EXIT

start_unoserver

failures=0

while [[ "${STOP_REQUESTED}" == "0" ]]; do
  sleep "${HEALTH_CHECK_INTERVAL}"

  # 1. Check if process is alive
  if ! kill -0 "${UNOSERVER_PID}" 2>/dev/null; then
    log "CRITICAL: unoserver process died."
    restart_stack
    failures=0
    continue
  fi

  # 2. Functional Check (Synthetic Transaction)
  if check_health; then
    # Reset failure counter on success
    if [[ "${failures}" -gt 0 ]]; then
      log "Healthcheck recovered."
      failures=0
    fi
  else
    failures=$((failures + 1))
    log "Healthcheck failed (${failures}/${MAX_CONSECUTIVE_FAILURES})."

    if [[ "${failures}" -ge "${MAX_CONSECUTIVE_FAILURES}" ]]; then
      log "CRITICAL: Max failures reached. Assuming stuck. Restarting..."
      restart_stack
      failures=0
    fi
  fi
done