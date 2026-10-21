#!/usr/bin/env bash
set -euo pipefail

# Run from the checkout, not the immutable copy of the flake in /nix/store.
root="${VOICE_CHANGER_ROOT:-$PWD}"
if [[ ! -f "$root/server/MMVCServerSIO.py" || ! -f "$root/nix/requirements.in" ]]; then
  printf 'Run from the repository root, or set VOICE_CHANGER_ROOT to the checkout.\n' >&2
  exit 1
fi
root="$(realpath "$root")"
venv="$root/.venv"
action="${1:-start}"
shift || true

require_python310() {
  if ! "$venv/bin/python" -c 'import sys; sys.exit(sys.version_info[:2] != (3, 10))'; then
    printf 'Expected Python 3.10 in %s. Move the existing .venv aside and rerun nix run .#setup.\n' "$venv" >&2
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
    printf '\nSetup complete. Run: nix run .#doctor\n'
    exit
    ;;
esac

if [[ ! -x "$venv/bin/python" ]]; then
  printf 'Python environment missing. Run: nix run .#setup\n' >&2
  exit 1
fi
require_python310
source "${VOICE_CHANGER_ENV_SCRIPT:-$root/nix/environment.sh}"
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
