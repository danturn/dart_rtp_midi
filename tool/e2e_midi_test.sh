#!/usr/bin/env bash
#
# End-to-end MIDI message test against macOS Network MIDI.
#
# Self-contained: installs tools, enables Network MIDI, runs tests.
#
# Sends every MIDI message type from Dart, captures what the Mac receives
# via receivemidi (independent CoreMIDI decoder), and diffs against expected.
# Then sends from sendmidi on the Mac and verifies Dart decodes correctly.
#
# Usage:
#   ./tool/e2e_midi_test.sh [remote-ip] [port] [midi-device-name]
#
# All arguments are optional. Defaults to local loopback on port 5004.
#
# Examples:
#   ./tool/e2e_midi_test.sh                          # loopback on this Mac
#   ./tool/e2e_midi_test.sh 192.168.1.89 5004        # remote Mac

set -euo pipefail

# Default to this machine's LAN IP for loopback testing.
DEFAULT_IP="$(ipconfig getifaddr en0 2>/dev/null || echo "127.0.0.1")"
REMOTE_IP="${1:-$DEFAULT_IP}"
PORT="${2:-5004}"
MIDI_DEV="${3:-Network Session 1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- Tool checks and auto-install ---

RECEIVEMIDI_URL="https://github.com/gbevin/ReceiveMIDI/releases/download/1.4.4/receivemidi-macOS-1.4.4.zip"
SENDMIDI_URL="https://github.com/gbevin/SendMIDI/releases/download/1.3.1/sendmidi-macOS-1.3.1.zip"

install_tool() {
  local name="$1"
  local url="$2"
  local zip_name="${url##*/}"
  local pkg_name

  echo "$name not found. Installing..."
  echo ""

  cd /tmp
  curl -LO "$url"
  unzip -o "$zip_name"

  # The pkg name uses lowercase and may differ from the zip name.
  pkg_name="$(ls -1 ${name}*.pkg 2>/dev/null | head -1 || ls -1 ${name,,}*.pkg 2>/dev/null | head -1)"

  if [[ -z "$pkg_name" ]]; then
    echo "ERROR: Could not find .pkg file after unzipping $zip_name"
    exit 1
  fi

  echo ""
  echo "Installing $pkg_name (requires sudo)..."
  sudo installer -pkg "$pkg_name" -target /

  cd - >/dev/null

  if ! command -v "$name" &>/dev/null; then
    echo "ERROR: $name still not found after install."
    exit 1
  fi
  echo "$name installed successfully."
  echo ""
}

if ! command -v receivemidi &>/dev/null; then
  install_tool receivemidi "$RECEIVEMIDI_URL"
fi

if ! command -v sendmidi &>/dev/null; then
  install_tool sendmidi "$SENDMIDI_URL"
fi

# --- Check / auto-detect Network MIDI device ---

AVAILABLE_DEVICES="$(receivemidi list 2>/dev/null || true)"
DEVICE_COUNT="$(echo "$AVAILABLE_DEVICES" | grep -c . || true)"

if echo "$AVAILABLE_DEVICES" | grep -q "$MIDI_DEV"; then
  echo "Found MIDI device: $MIDI_DEV"
elif [[ "$DEVICE_COUNT" -eq 1 ]] && [[ -n "$AVAILABLE_DEVICES" ]]; then
  MIDI_DEV="$(echo "$AVAILABLE_DEVICES" | head -1)"
  echo "Auto-detected MIDI device: $MIDI_DEV"
elif [[ "$DEVICE_COUNT" -gt 1 ]]; then
  echo "MIDI device '$MIDI_DEV' not found. Available devices:"
  echo "$AVAILABLE_DEVICES"
  echo ""
  echo "Re-run with the correct device name:"
  echo "  $0 $REMOTE_IP $PORT \"<device-name>\""
  exit 1
else
  echo "No MIDI devices found."
  echo ""
  echo "One-time setup required:"
  echo "  1. Open Audio MIDI Setup > Window > Show MIDI Studio > double-click Network"
  echo "  2. Click '+' under 'My Sessions' to create a session"
  echo "  3. Tick the checkbox next to it to enable"
  exit 1
fi
echo ""

echo "=== E2E MIDI Message Test ==="
echo "Remote: $REMOTE_IP:$PORT"
echo "MIDI device: $MIDI_DEV"
echo ""

# --- Part 1: Test SEND (Dart → Mac) ---

echo "--- Part 1: Dart sends, Mac receives (via receivemidi) ---"

RECV_LOG="$TMP_DIR/received.txt"
EXPECTED_SEND="$PROJECT_DIR/tool/expected_send_output.txt"

# Start receivemidi in background, capturing output.
receivemidi dev "$MIDI_DEV" ts > "$RECV_LOG" 2>/dev/null &
RECV_PID=$!

# Give it a moment to start listening.
sleep 1

# Run the Dart test sender (--exit flag makes it exit after sending).
echo "Running Dart MIDI sender..."
dart run "$PROJECT_DIR/example/midi_message_test.dart" "$REMOTE_IP" "$PORT" --exit 2>&1

# Give receivemidi time to flush.
sleep 2

# Stop receivemidi.
kill "$RECV_PID" 2>/dev/null || true
wait "$RECV_PID" 2>/dev/null || true

# Strip timestamps from receivemidi output for comparison.
# receivemidi with 'ts' outputs: "HH:MM:SS.mmm  channel ..." — strip the timestamp prefix.
sed 's/^[0-9:.]*[[:space:]]*//' "$RECV_LOG" > "$TMP_DIR/received_stripped.txt"

echo ""
echo "Received $(wc -l < "$TMP_DIR/received_stripped.txt" | tr -d ' ') MIDI messages."
echo ""

if [[ -f "$EXPECTED_SEND" ]]; then
  echo "Comparing against expected output..."
  if diff -u "$EXPECTED_SEND" "$TMP_DIR/received_stripped.txt" > "$TMP_DIR/send_diff.txt" 2>&1; then
    echo "PASS: All sent messages received correctly."
  else
    echo "FAIL: Output differs from expected."
    cat "$TMP_DIR/send_diff.txt"
    echo ""
    echo "To update expected output after verifying correctness:"
    echo "  cp $TMP_DIR/received_stripped.txt $EXPECTED_SEND"
    SEND_RESULT=1
  fi
else
  echo "No expected output file yet. Saving captured output as baseline."
  echo "Review the output below, and if correct, it will be saved as the expected baseline."
  echo ""
  cat "$TMP_DIR/received_stripped.txt"
  echo ""
  read -p "Does this look correct? (y/n) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    cp "$TMP_DIR/received_stripped.txt" "$EXPECTED_SEND"
    echo "Saved to $EXPECTED_SEND"
  else
    echo "Not saved. Fix the issues and re-run."
    exit 1
  fi
fi

# --- Part 2: Test RECEIVE (Mac → Dart) ---

echo ""
echo "--- Part 2: Mac sends (via sendmidi), Dart receives ---"

DART_LOG="$TMP_DIR/dart_received.txt"
EXPECTED_RECV="$PROJECT_DIR/tool/expected_recv_output.txt"

# Start a Dart listener that prints received MIDI and exits after a timeout.
dart run "$PROJECT_DIR/tool/midi_listener.dart" "$REMOTE_IP" "$PORT" > "$DART_LOG" 2>&1 &
DART_PID=$!

# Give the Dart session time to connect and reach ready state.
sleep 4

echo "Sending MIDI from Mac via sendmidi..."

# Channel voice messages
sendmidi dev "$MIDI_DEV" on 60 100
sleep 0.1
sendmidi dev "$MIDI_DEV" off 60 0
sleep 0.1
sendmidi dev "$MIDI_DEV" cc 7 100
sleep 0.1
sendmidi dev "$MIDI_DEV" cc 64 127
sleep 0.1
sendmidi dev "$MIDI_DEV" cc 64 0
sleep 0.1
sendmidi dev "$MIDI_DEV" pc 42
sleep 0.1
sendmidi dev "$MIDI_DEV" pb 8192
sleep 0.1
sendmidi dev "$MIDI_DEV" at 80
sleep 0.1
sendmidi dev "$MIDI_DEV" pp 60 90
sleep 0.1

# System messages
sendmidi dev "$MIDI_DEV" start
sleep 0.1
sendmidi dev "$MIDI_DEV" clock
sleep 0.1
sendmidi dev "$MIDI_DEV" continue
sleep 0.1
sendmidi dev "$MIDI_DEV" stop
sleep 0.1
sendmidi dev "$MIDI_DEV" as
sleep 0.1

# SysEx (GM System On)
sendmidi dev "$MIDI_DEV" hex syx 7e 7f 09 01
sleep 0.1

# Give Dart time to receive everything.
sleep 2

# Stop the Dart listener.
kill "$DART_PID" 2>/dev/null || true
wait "$DART_PID" 2>/dev/null || true

echo ""
echo "Dart received $(wc -l < "$DART_LOG" | tr -d ' ') MIDI messages."
echo ""

if [[ -f "$EXPECTED_RECV" ]]; then
  echo "Comparing against expected output..."
  if diff -u "$EXPECTED_RECV" "$DART_LOG" > "$TMP_DIR/recv_diff.txt" 2>&1; then
    echo "PASS: All received messages decoded correctly."
  else
    echo "FAIL: Output differs from expected."
    cat "$TMP_DIR/recv_diff.txt"
    echo ""
    echo "To update expected output after verifying correctness:"
    echo "  cp $DART_LOG $EXPECTED_RECV"
    RECV_RESULT=1
  fi
else
  echo "No expected output file yet. Saving captured output as baseline."
  echo "Review the output below, and if correct, it will be saved as the expected baseline."
  echo ""
  cat "$DART_LOG"
  echo ""
  read -p "Does this look correct? (y/n) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    cp "$DART_LOG" "$EXPECTED_RECV"
    echo "Saved to $EXPECTED_RECV"
  else
    echo "Not saved. Fix the issues and re-run."
    exit 1
  fi
fi

# --- Summary ---

echo ""
echo "=== Summary ==="
SEND_RESULT="${SEND_RESULT:-0}"
RECV_RESULT="${RECV_RESULT:-0}"

if [[ "$SEND_RESULT" == "0" ]] && [[ "$RECV_RESULT" == "0" ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
