import 'midi_message.dart';
import '../session/session_controller.dart';
import '../session/session_state.dart';

/// An active RTP-MIDI session with a remote peer.
///
/// Provides connection state, session metadata, and MIDI send/receive.
class RtpMidiSession {
  final SessionController _controller;

  /// Creates a session wrapper around a [SessionController].
  ///
  /// This is intended to be created by [RtpMidiHost] and [RtpMidiClient],
  /// not directly by application code.
  RtpMidiSession(this._controller);

  /// The human-readable name of the remote peer.
  String get remoteName => _controller.remoteName;

  /// The network address of the remote peer.
  String get remoteAddress => _controller.remoteAddress;

  /// The remote peer's control port.
  int get remoteControlPort => _controller.remoteControlPort;

  /// The remote peer's data port.
  int get remoteDataPort => _controller.remoteDataPort;

  /// The current session state.
  SessionState get state => _controller.state;

  /// Stream of session state changes.
  Stream<SessionState> get onStateChanged => _controller.onStateChanged;

  /// Stream of incoming MIDI messages from the remote peer.
  Stream<MidiMessage> get onMidiMessage => _controller.onMidiMessage;

  /// Send a MIDI message to the remote peer.
  void send(MidiMessage message) => _controller.sendMidi(message);

  /// Disconnect from the remote peer.
  Future<void> disconnect() => _controller.disconnect();

  @override
  String toString() =>
      'RtpMidiSession(remote: "$remoteName" @ $remoteAddress, state: $state)';
}
