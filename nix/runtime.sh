#!/usr/bin/env bash
set -euo pipefail

source "${VOICE_CHANGER_ENV_SCRIPT:-$(dirname "${BASH_SOURCE[0]}")/environment.sh}"
action="${1:-start}"
shift || true

root="$(voice_changer_root)"
# Lock regeneration is a development operation on an explicit checkout.
if [[ "$action" == lock ]]; then
  root="${VOICE_CHANGER_ROOT:-$PWD}"
elif [[ "$action" == setup && -z "${VOICE_CHANGER_ROOT:-}" ]]; then
  if [[ -z "${VOICE_CHANGER_SOURCE:-}" ]]; then
    printf 'Application source missing. Use voice-changer-setup or nix run .#setup.\n' >&2
    exit 1
  fi
  mkdir -p "$root/server" "$root/client/demo" "$root/nix"
  # Only packaged application files are replaced; user settings/models are not
  # part of the source and are retained. Do not copy the store's read-only modes.
  cp -R --no-preserve=mode "$VOICE_CHANGER_SOURCE/server/." "$root/server/"
  cp -R --no-preserve=mode "$VOICE_CHANGER_SOURCE/client/demo/dist" "$root/client/demo/"
  cp -R --no-preserve=mode "$VOICE_CHANGER_SOURCE/nix/." "$root/nix/"
fi

if [[ ! -f "$root/server/MMVCServerSIO.py" || ! -f "$root/nix/requirements.in" ]]; then
  printf 'Application missing in %s. Run voice-changer-setup (nix run .#setup), or set VOICE_CHANGER_ROOT to a checkout.\n' "$root" >&2
  exit 1
fi
root="$(realpath "$root")"
venv="$root/.venv"

require_python310() {
  if ! "$venv/bin/python" -c 'import sys; sys.exit(sys.version_info[:2] != (3, 10))'; then
    printf 'Expected Python 3.10 in %s. Move the existing .venv aside and rerun voice-changer-setup (nix run .#setup).\n' "$venv" >&2
    exit 1
  fi
}

prepare_audio() {
  if ! pactl info >/dev/null; then
    printf 'Cannot connect to the audio server. Start PipeWire with pipewire-pulse (or PulseAudio) in your desktop session.\n' >&2
    exit 1
  fi

  if ! pactl get-sink-volume voicechanger >/dev/null 2>&1; then
    if ! pactl load-module module-null-sink sink_name=voicechanger \
      sink_properties=device.description=VoiceChanger >/dev/null; then
      printf 'Failed to create the VoiceChanger virtual audio output.\n' >&2
      exit 1
    fi
  fi

  if ! pactl get-source-volume voicechanger.monitor >/dev/null; then
    printf 'The voicechanger output exists, but its monitor input is unavailable. Check the audio server configuration.\n' >&2
    exit 1
  fi

  # WebRTC clients filter out sink monitors. Expose it as a regular microphone.
  if ! pactl get-source-volume voicechanger_input >/dev/null 2>&1; then
    if ! pactl load-module module-remap-source master=voicechanger.monitor \
      source_name=voicechanger_input \
      "source_properties='device.description=\"Monitor of VoiceChanger\"'" >/dev/null; then
      printf 'Failed to create the Monitor of VoiceChanger microphone input.\n' >&2
      exit 1
    fi
  fi

  if ! pactl get-source-volume voicechanger_input >/dev/null; then
    printf 'The Monitor of VoiceChanger microphone input is unavailable.\n' >&2
    exit 1
  fi

  printf 'Audio ready: select VoiceChanger as the voice-changer output, and Monitor of VoiceChanger as the call app input.\n'
}

case "$action" in
  lock)
    cd "$root"
    for requirements in build-requirements requirements; do
      uv pip compile --quiet --python /usr/bin/python3 --generate-hashes \
        --index-url https://pypi.org/simple --custom-compile-command 'nix run .#lock' \
        "nix/$requirements.in" -o "nix/$requirements.lock"
    done
    exit
    ;;
  setup)
    if [[ ! -x "$venv/bin/python" ]]; then
      uv venv --python /usr/bin/python3 "$venv"
    fi
    require_python310
    uv pip install --python "$venv/bin/python" --require-hashes --index-url https://pypi.org/simple \
      -r "$root/nix/build-requirements.lock"
    uv pip sync --python "$venv/bin/python" --require-hashes --no-build-isolation --index-url https://pypi.org/simple \
      "$root/nix/requirements.lock"
    printf '\nSetup complete in %s. Run voice-changer-doctor (nix run .#doctor).\n' "$root"
    exit
    ;;
esac

if [[ ! -x "$venv/bin/python" ]]; then
  printf 'Python environment missing. Run voice-changer-setup (nix run .#setup).\n' >&2
  exit 1
fi
require_python310
voice_changer_activate "$root"

case "$action" in
  doctor)
    exec "$venv/bin/python" "$root/nix/doctor.py" "$@"
    ;;
  start)
    prepare_audio
    cd "$root/server"
    exec "$venv/bin/python" MMVCServerSIO.py --host 127.0.0.1 -p 18888 "$@"
    ;;
  *)
    printf 'Unknown action: %s\n' "$action" >&2
    exit 1
    ;;
esac
