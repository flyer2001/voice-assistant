#!/usr/bin/env bash
# Pre-grant TCC permissions to a simulator app via direct sqlite INSERT.
# Workaround: `xcrun simctl privacy <udid> grant <service> <bundle>` fails with
# "Operation not permitted" on macOS Tahoe 26+ even when shell has nominal access
# (TCC layer wraps the simctl call). The simulator's own TCC.db is plain sqlite
# and writable. App must NOT be running when grants are applied — relaunch after.
#
# Usage:
#   scripts/sim-grant.sh <device-udid-or-name> <bundle-id> [service ...]
#
# Devices: full UDID OR substring match against `xcrun simctl list devices available`.
# Services default to "microphone speech-recognition". Known: microphone,
# speech-recognition, camera, photos, contacts, location, calendar, reminders.
# Pass raw kTCCService* string for anything else.
#
# Exit codes: 0 ok / 1 device not found / 2 TCC.db missing (boot simulator first).
set -euo pipefail

DEVICE_INPUT="${1:?device udid or name (e.g. \"iPhone 13 mini\" or UDID)}"
BUNDLE="${2:?bundle id (e.g. com.example.app)}"
shift 2
SERVICES=("$@")
[ ${#SERVICES[@]} -eq 0 ] && SERVICES=(microphone speech-recognition)

# Resolve device UDID
if [[ "$DEVICE_INPUT" =~ ^[A-F0-9-]{36}$ ]]; then
  DEVICE="$DEVICE_INPUT"
else
  DEVICE=$(xcrun simctl list devices available \
    | grep -E "$DEVICE_INPUT.*\(([A-F0-9-]{36})\) \((Booted|Shutdown)\)" \
    | head -1 \
    | sed -nE 's/.*\(([A-F0-9-]{36})\).*/\1/p')
fi
if [ -z "${DEVICE:-}" ]; then
  echo "error: no simulator matching '$DEVICE_INPUT'" >&2
  exit 1
fi

TCC_DB="$HOME/Library/Developer/CoreSimulator/Devices/$DEVICE/data/Library/TCC/TCC.db"
if [ ! -f "$TCC_DB" ]; then
  echo "error: TCC.db missing at $TCC_DB" >&2
  echo "       boot the simulator first: xcrun simctl boot $DEVICE" >&2
  exit 2
fi

resolve_service() {
  # Maps a friendly name to kTCCService* identifier. Falls through to raw input
  # so `scripts/sim-grant.sh ... kTCCServiceCustom` works for unmapped services.
  case "$1" in
    microphone)         echo kTCCServiceMicrophone ;;
    speech-recognition) echo kTCCServiceSpeechRecognition ;;
    camera)             echo kTCCServiceCamera ;;
    photos)             echo kTCCServicePhotos ;;
    photos-add)         echo kTCCServicePhotosAdd ;;
    contacts)           echo kTCCServiceAddressBook ;;
    location)           echo kTCCServiceLocation ;;
    calendar)           echo kTCCServiceCalendar ;;
    reminders)          echo kTCCServiceReminders ;;
    motion)             echo kTCCServiceMotion ;;
    bluetooth)          echo kTCCServiceBluetoothAlways ;;
    *)                  echo "$1" ;;
  esac
}

echo "device: $DEVICE"
echo "bundle: $BUNDLE"
for svc in "${SERVICES[@]}"; do
  tcc_name=$(resolve_service "$svc")
  sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('$tcc_name', '$BUNDLE', 0, 2, 4, 1);"
  echo "  granted: $svc ($tcc_name)"
done
