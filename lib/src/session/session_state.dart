/// Session lifecycle states for an RTP-MIDI session.
///
/// A session progresses through these states during the invitation handshake,
/// clock synchronization, normal operation, and teardown.
enum SessionState {
  /// No session activity. Initial state.
  idle,

  /// Invitation sent on the control port, awaiting OK or NO.
  invitingControl,

  /// Control port invitation accepted. Invitation sent on the data port,
  /// awaiting OK or NO.
  invitingData,

  /// Both ports connected. Awaiting first clock sync exchange.
  connected,

  /// Clock sync in progress (CK0 sent, awaiting CK1/CK2 completion).
  synchronizing,

  /// Session fully established and synchronized. Ready for MIDI traffic.
  ready,

  /// Bye sent, awaiting confirmation or timeout before cleanup.
  disconnecting,

  /// Session has ended. Terminal state.
  disconnected,
}

/// Events that drive session state transitions.
enum SessionEvent {
  /// The local side initiates an invitation.
  sendInvitation,

  /// An OK response was received on the control port.
  controlOkReceived,

  /// A NO (rejection) was received on the control port.
  controlNoReceived,

  /// An OK response was received on the data port.
  dataOkReceived,

  /// A NO (rejection) was received on the data port.
  dataNoReceived,

  /// Clock synchronization exchange completed successfully.
  clockSyncComplete,

  /// Clock synchronization timed out without completing.
  clockSyncTimeout,

  /// A BYE packet was received from the remote peer.
  byeReceived,

  /// The local side sent a BYE packet.
  byeSent,

  /// A timeout occurred (e.g., invitation retry exhausted, session idle).
  timeout,

  /// An unrecoverable error occurred.
  error,
}

/// Side effects produced by a state transition.
///
/// These are pure descriptions of actions to perform — the shell layer
/// is responsible for interpreting and executing them.
enum SessionEffect {
  /// Send an invitation on the control port.
  sendControlInvitation,

  /// Send an invitation on the data port.
  sendDataInvitation,

  /// Initiate a clock sync exchange (send CK0).
  sendClockSync,

  /// Send a BYE packet on both ports.
  sendBye,

  /// Emit a "connected" notification to the application.
  emitConnected,

  /// Emit a "synchronized" notification to the application.
  emitSynchronized,

  /// Emit a "disconnected" notification to the application.
  emitDisconnected,

  /// Schedule an invitation retry timeout.
  scheduleInvitationRetry,

  /// Schedule a clock sync timeout.
  scheduleClockSyncTimeout,

  /// Schedule a periodic clock sync.
  schedulePeriodicClockSync,

  /// Cancel all pending timers.
  cancelTimers,

  /// Emit an error notification to the application.
  emitError,
}

/// The result of a state transition: a new state and a list of effects
/// to execute.
class SessionTransition {
  /// The state to move to.
  final SessionState newState;

  /// Side effects that the shell should execute in order.
  final List<SessionEffect> effects;

  const SessionTransition(this.newState, [this.effects = const []]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionTransition &&
          newState == other.newState &&
          _listEquals(effects, other.effects);

  @override
  int get hashCode => Object.hash(newState, Object.hashAll(effects));

  @override
  String toString() => 'SessionTransition($newState, $effects)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Pure state transition function for the RTP-MIDI session state machine.
///
/// Given the [current] state and an incoming [event], returns a
/// [SessionTransition] containing the new state and a list of
/// [SessionEffect]s for the shell to execute.
///
/// Events that are not valid for the current state return a transition
/// to the same state with no effects (no-op).
SessionTransition transition(SessionState current, SessionEvent event) {
  switch (current) {
    case SessionState.idle:
      return _fromIdle(event);
    case SessionState.invitingControl:
      return _fromInvitingControl(event);
    case SessionState.invitingData:
      return _fromInvitingData(event);
    case SessionState.connected:
      return _fromConnected(event);
    case SessionState.synchronizing:
      return _fromSynchronizing(event);
    case SessionState.ready:
      return _fromReady(event);
    case SessionState.disconnecting:
      return _fromDisconnecting(event);
    case SessionState.disconnected:
      return const SessionTransition(SessionState.disconnected);
  }
}

SessionTransition _fromIdle(SessionEvent event) {
  switch (event) {
    case SessionEvent.sendInvitation:
      return const SessionTransition(SessionState.invitingControl, [
        SessionEffect.sendControlInvitation,
        SessionEffect.scheduleInvitationRetry,
      ]);
    default:
      return const SessionTransition(SessionState.idle);
  }
}

SessionTransition _fromInvitingControl(SessionEvent event) {
  switch (event) {
    case SessionEvent.controlOkReceived:
      return const SessionTransition(SessionState.invitingData, [
        SessionEffect.sendDataInvitation,
        SessionEffect.scheduleInvitationRetry,
      ]);
    case SessionEvent.controlNoReceived:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.timeout:
      // Retry exhausted — give up.
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.byeReceived:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.error:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitError,
      ]);
    default:
      return const SessionTransition(SessionState.invitingControl);
  }
}

SessionTransition _fromInvitingData(SessionEvent event) {
  switch (event) {
    case SessionEvent.dataOkReceived:
      return const SessionTransition(SessionState.connected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitConnected,
        SessionEffect.sendClockSync,
        SessionEffect.scheduleClockSyncTimeout,
      ]);
    case SessionEvent.dataNoReceived:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.sendBye,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.timeout:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.sendBye,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.byeReceived:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.error:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitError,
      ]);
    default:
      return const SessionTransition(SessionState.invitingData);
  }
}

SessionTransition _fromConnected(SessionEvent event) {
  switch (event) {
    case SessionEvent.clockSyncComplete:
      return const SessionTransition(SessionState.ready, [
        SessionEffect.cancelTimers,
        SessionEffect.emitSynchronized,
        SessionEffect.schedulePeriodicClockSync,
      ]);
    case SessionEvent.clockSyncTimeout:
      // First sync failed — stay connected and retry.
      return const SessionTransition(SessionState.connected, [
        SessionEffect.sendClockSync,
        SessionEffect.scheduleClockSyncTimeout,
      ]);
    case SessionEvent.byeReceived:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.byeSent:
      return const SessionTransition(SessionState.disconnecting, [
        SessionEffect.sendBye,
        SessionEffect.cancelTimers,
      ]);
    case SessionEvent.error:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.sendBye,
        SessionEffect.emitError,
      ]);
    default:
      return const SessionTransition(SessionState.connected);
  }
}

SessionTransition _fromSynchronizing(SessionEvent event) {
  switch (event) {
    case SessionEvent.clockSyncComplete:
      return const SessionTransition(SessionState.ready, [
        SessionEffect.emitSynchronized,
        SessionEffect.schedulePeriodicClockSync,
      ]);
    case SessionEvent.clockSyncTimeout:
      // Sync timed out — fall back to ready (still usable, just not freshly synced).
      return const SessionTransition(SessionState.ready, [
        SessionEffect.schedulePeriodicClockSync,
      ]);
    case SessionEvent.byeReceived:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.byeSent:
      return const SessionTransition(SessionState.disconnecting, [
        SessionEffect.sendBye,
        SessionEffect.cancelTimers,
      ]);
    case SessionEvent.error:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.sendBye,
        SessionEffect.emitError,
      ]);
    default:
      return const SessionTransition(SessionState.synchronizing);
  }
}

SessionTransition _fromReady(SessionEvent event) {
  switch (event) {
    case SessionEvent.sendInvitation:
      // Periodic clock sync triggered.
      return const SessionTransition(SessionState.synchronizing, [
        SessionEffect.sendClockSync,
        SessionEffect.scheduleClockSyncTimeout,
      ]);
    case SessionEvent.clockSyncComplete:
      // Received a sync while already ready (periodic sync completed).
      return const SessionTransition(SessionState.ready, [
        SessionEffect.emitSynchronized,
        SessionEffect.schedulePeriodicClockSync,
      ]);
    case SessionEvent.byeReceived:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.byeSent:
      return const SessionTransition(SessionState.disconnecting, [
        SessionEffect.sendBye,
        SessionEffect.cancelTimers,
      ]);
    case SessionEvent.timeout:
      // Session idle timeout.
      return const SessionTransition(SessionState.disconnecting, [
        SessionEffect.sendBye,
        SessionEffect.cancelTimers,
      ]);
    case SessionEvent.error:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.sendBye,
        SessionEffect.emitError,
      ]);
    default:
      return const SessionTransition(SessionState.ready);
  }
}

SessionTransition _fromDisconnecting(SessionEvent event) {
  switch (event) {
    case SessionEvent.byeReceived:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.timeout:
      // No BYE confirmation received — disconnect anyway.
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitDisconnected,
      ]);
    case SessionEvent.error:
      return const SessionTransition(SessionState.disconnected, [
        SessionEffect.cancelTimers,
        SessionEffect.emitError,
      ]);
    default:
      return const SessionTransition(SessionState.disconnecting);
  }
}
