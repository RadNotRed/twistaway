#!/usr/bin/env bash

set -euo pipefail

avd_name="${TWISTAWAY_AVD:-Twistaway_Pixel_7_API_36}"
sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${HOME:?}/Android/Sdk}}"
emulator_bin="$sdk_root/emulator/emulator"
adb_bin="$sdk_root/platform-tools/adb"
log_file="${TMPDIR:-/tmp}/twistaway-android-emulator.log"

if [[ ! -x "$emulator_bin" ]]; then
  echo "Android Emulator was not found at $emulator_bin." >&2
  echo "Set ANDROID_SDK_ROOT to your Android SDK directory." >&2
  exit 1
fi

if [[ ! -x "$adb_bin" ]]; then
  echo "adb was not found at $adb_bin." >&2
  exit 1
fi

find_running_emulator() {
  local serial

  while read -r serial state; do
    [[ "$serial" == emulator-* && "$state" == "device" ]] || continue
    if "$adb_bin" -s "$serial" emu avd name 2>/dev/null | tr -d '\r' | head -n 1 | grep -Fxq "$avd_name"; then
      printf '%s\n' "$serial"
      return 0
    fi
  done < <("$adb_bin" devices | tail -n +2)

  return 1
}

avd_process_is_running() {
  pgrep -af 'qemu-system|emulator' 2>/dev/null | grep -F -- "-avd $avd_name" >/dev/null
}

serial="$(find_running_emulator || true)"

if [[ -z "$serial" ]]; then
  if ! "$emulator_bin" -list-avds | grep -Fxq "$avd_name"; then
    echo "Android virtual device '$avd_name' does not exist." >&2
    echo "Create it in Android Studio's Device Manager or set TWISTAWAY_AVD." >&2
    exit 1
  fi

  if avd_process_is_running; then
    echo "$avd_name is already starting."
  else
    echo "Starting $avd_name..."
    nohup "$emulator_bin" -avd "$avd_name" >"$log_file" 2>&1 &
  fi

  for _ in {1..120}; do
    serial="$(find_running_emulator || true)"
    [[ -n "$serial" ]] && break
    sleep 1
  done

  if [[ -z "$serial" ]]; then
    echo "The emulator did not connect. See $log_file." >&2
    exit 1
  fi
else
  echo "$avd_name is already running as $serial."
fi

echo "Waiting for Android to finish booting..."
for _ in {1..180}; do
  if [[ "$("$adb_bin" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    echo "$avd_name is ready as $serial."
    exit 0
  fi
  sleep 1
done

echo "Android did not finish booting. See $log_file." >&2
exit 1
