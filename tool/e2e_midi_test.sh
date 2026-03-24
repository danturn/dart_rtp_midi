#!/usr/bin/env bash
#
# End-to-end MIDI message test against macOS Network MIDI.
#
# Sends every MIDI message type from Dart, captures what the Mac receives
# via receivemidi (independent CoreMIDI decoder), and diffs against expected.
# Then sends from sendmidi on the Mac and verifies Dart decodes correctly.
#
# Prerequisites:
#   - macOS with Network MIDI session enabled (Audio MIDI Setup)
#   - receivemidi and sendmidi installed (this script offers to install them)
#
# Usage:
#   ./tool/e2e_midi_test.sh <remote-ip> [port] [midi-device-name]
#
# Example:
#   ./tool/e2e_midi_test.sh 192.168.1.89 5004 "Network Session 1"

set -euo pipefail

REMOTE_IP="${1:-}"
PORT="${2:-5004}"
MIDI_DEV="${3:-Network Session 1}"

if [[ -z "$REMOTE_IP" ]]; then
  echo "Usage: $0 <remote-ip> [port] [midi-device-name]"
  echo ""
  echo "Example: $0 192.168.1.89 5004 \"Network Session 1\""
  echo ""
  echo "Setup:"
  echo "  1. On the Mac: Audio MIDI Setup > Network > create/enable a session"
  echo "  2. Note the session name (default: 'Network Session 1')"
  echo "  3. Run this script from the dart_rtp_midi directory"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- Tool checks ---

check_tool() {
  local tool="$1"
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: '$tool' not found."
    echo ""
    echo "Install via pre-built packages:"
    echo "  # Download from GitHub releases:"
    echo "  curl -LO https://github.com/gbevin/ReceiveMIDI/releases/download/1.4.4/receivemidi-macOS-1.4.4.zip"
    echo "  curl -LO https://github.com/gbevin/SendMIDI/releases/download/1.3.1/sendmidi-macOS-1.3.1.zip"
    echo "  unzip receivemidi-macOS-1.4.4.zip && sudo installer -pkg receivemidi-macos-1.4.4.pkg -target /"
    echo "  unzip sendmidi-macOS-1.3.1.zip && sudo installer -pkg sendmidi-macos-1.3.1.pkg -target /"
    echo ""
    echo "Or with full Xcode installed:"
    echo "  brew install gbevin/tools/receivemidi gbevin/tools/sendmidi"
    exit 1
  fi
}

check_tool receivemidi
check_tool sendmidi

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

# Run the Dart test sender.
echo "Running Dart MIDI sender..."
dart run "$PROJECT_DIR/example/midi_message_test.dart" "$REMOTE_IP" "$PORT" 2>&1 | \
  grep -E '^\s*(>>|---|\-\-\- Test)' || true

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
