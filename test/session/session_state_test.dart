import 'package:dart_rtp_midi/src/session/session_state.dart';
import 'package:test/test.dart';

void main() {
  group('SessionTransition equality', () {
    test('transitions with same state and effects are equal', () {
      const a = SessionTransition(SessionState.idle, [SessionEffect.sendBye]);
      const b = SessionTransition(SessionState.idle, [SessionEffect.sendBye]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('transitions with different states are not equal', () {
      const a = SessionTransition(SessionState.idle);
      const b = SessionTransition(SessionState.connected);
      expect(a, isNot(equals(b)));
    });

    test('transitions with different effects are not equal', () {
      const a = SessionTransition(SessionState.idle, [SessionEffect.sendBye]);
      const b =
          SessionTransition(SessionState.idle, [SessionEffect.emitConnected]);
      expect(a, isNot(equals(b)));
    });

    test('transitions with different effect counts are not equal', () {
      const a = SessionTransition(SessionState.idle, [SessionEffect.sendBye]);
      const b = SessionTransition(SessionState.idle,
          [SessionEffect.sendBye, SessionEffect.cancelTimers]);
      expect(a, isNot(equals(b)));
    });

    test('transitions with empty effects are equal', () {
      const a = SessionTransition(SessionState.idle);
      const b = SessionTransition(SessionState.idle, []);
      expect(a, equals(b));
    });

    test('toString produces readable output', () {
      const t = SessionTransition(SessionState.ready, [SessionEffect.sendBye]);
      expect(t.toString(), contains('ready'));
      expect(t.toString(), contains('sendBye'));
    });
  });

  group('transition from idle', () {
    test('sendInvitation -> invitingControl with sendControlInvitation', () {
      final result = transition(SessionState.idle, SessionEvent.sendInvitation);
      expect(result.newState, SessionState.invitingControl);
      expect(result.effects, contains(SessionEffect.sendControlInvitation));
      expect(result.effects, contains(SessionEffect.scheduleInvitationRetry));
      expect(result.effects.length, 2);
    });

    test('irrelevant events return idle with no effects', () {
      final irrelevant = [
        SessionEvent.controlOkReceived,
        SessionEvent.controlNoReceived,
        SessionEvent.dataOkReceived,
        SessionEvent.dataNoReceived,
        SessionEvent.clockSyncComplete,
        SessionEvent.clockSyncTimeout,
        SessionEvent.byeReceived,
        SessionEvent.byeSent,
        SessionEvent.timeout,
        SessionEvent.error,
      ];
      for (final event in irrelevant) {
        final result = transition(SessionState.idle, event);
        expect(result.newState, SessionState.idle,
            reason: 'idle + $event should stay idle');
        expect(result.effects, isEmpty,
            reason: 'idle + $event should have no effects');
      }
    });
  });

  group('transition from invitingControl', () {
    test('controlOkReceived -> invitingData with sendDataInvitation', () {
      final result = transition(
          SessionState.invitingControl, SessionEvent.controlOkReceived);
      expect(result.newState, SessionState.invitingData);
      expect(result.effects, contains(SessionEffect.sendDataInvitation));
      expect(result.effects, contains(SessionEffect.scheduleInvitationRetry));
      expect(result.effects.length, 2);
    });

    test('controlNoReceived -> disconnected with cancel and emit', () {
      final result = transition(
          SessionState.invitingControl, SessionEvent.controlNoReceived);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('timeout -> disconnected with cancel and emit', () {
      final result =
          transition(SessionState.invitingControl, SessionEvent.timeout);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('byeReceived -> disconnected with cancel and emit', () {
      final result =
          transition(SessionState.invitingControl, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('error -> disconnected with cancel and emitError', () {
      final result =
          transition(SessionState.invitingControl, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('irrelevant events stay in invitingControl', () {
      final irrelevant = [
        SessionEvent.sendInvitation,
        SessionEvent.dataOkReceived,
        SessionEvent.dataNoReceived,
        SessionEvent.clockSyncComplete,
        SessionEvent.clockSyncTimeout,
        SessionEvent.byeSent,
      ];
      for (final event in irrelevant) {
        final result = transition(SessionState.invitingControl, event);
        expect(result.newState, SessionState.invitingControl,
            reason: 'invitingControl + $event should stay invitingControl');
        expect(result.effects, isEmpty,
            reason: 'invitingControl + $event should have no effects');
      }
    });
  });

  group('transition from invitingData', () {
    test('dataOkReceived -> connected with emitConnected and sendClockSync',
        () {
      final result =
          transition(SessionState.invitingData, SessionEvent.dataOkReceived);
      expect(result.newState, SessionState.connected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitConnected));
      expect(result.effects, contains(SessionEffect.sendClockSync));
      expect(result.effects, contains(SessionEffect.scheduleClockSyncTimeout));
      expect(result.effects.length, 4);
    });

    test('dataNoReceived -> disconnected with sendBye', () {
      final result =
          transition(SessionState.invitingData, SessionEvent.dataNoReceived);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.sendBye));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('timeout -> disconnected with sendBye', () {
      final result =
          transition(SessionState.invitingData, SessionEvent.timeout);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.sendBye));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('byeReceived -> disconnected', () {
      final result =
          transition(SessionState.invitingData, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('error -> disconnected with emitError', () {
      final result = transition(SessionState.invitingData, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('irrelevant events stay in invitingData', () {
      final irrelevant = [
        SessionEvent.sendInvitation,
        SessionEvent.controlOkReceived,
        SessionEvent.controlNoReceived,
        SessionEvent.clockSyncComplete,
        SessionEvent.clockSyncTimeout,
        SessionEvent.byeSent,
      ];
      for (final event in irrelevant) {
        final result = transition(SessionState.invitingData, event);
        expect(result.newState, SessionState.invitingData,
            reason: 'invitingData + $event should stay invitingData');
        expect(result.effects, isEmpty);
      }
    });
  });

  group('transition from connected', () {
    test('clockSyncComplete -> ready with emitSynchronized', () {
      final result =
          transition(SessionState.connected, SessionEvent.clockSyncComplete);
      expect(result.newState, SessionState.ready);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitSynchronized));
      expect(result.effects, contains(SessionEffect.schedulePeriodicClockSync));
      expect(result.effects.length, 3);
    });

    test('clockSyncTimeout -> connected (retry sync)', () {
      final result =
          transition(SessionState.connected, SessionEvent.clockSyncTimeout);
      expect(result.newState, SessionState.connected);
      expect(result.effects, contains(SessionEffect.sendClockSync));
      expect(result.effects, contains(SessionEffect.scheduleClockSyncTimeout));
      expect(result.effects.length, 2);
    });

    test('byeReceived -> disconnected', () {
      final result =
          transition(SessionState.connected, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('byeSent -> disconnecting with sendBye', () {
      final result = transition(SessionState.connected, SessionEvent.byeSent);
      expect(result.newState, SessionState.disconnecting);
      expect(result.effects, contains(SessionEffect.sendBye));
      expect(result.effects, contains(SessionEffect.cancelTimers));
    });

    test('error -> disconnected with sendBye and emitError', () {
      final result = transition(SessionState.connected, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.sendBye));
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('irrelevant events stay in connected', () {
      final irrelevant = [
        SessionEvent.sendInvitation,
        SessionEvent.controlOkReceived,
        SessionEvent.controlNoReceived,
        SessionEvent.dataOkReceived,
        SessionEvent.dataNoReceived,
        SessionEvent.timeout,
      ];
      for (final event in irrelevant) {
        final result = transition(SessionState.connected, event);
        expect(result.newState, SessionState.connected,
            reason: 'connected + $event should stay connected');
        expect(result.effects, isEmpty);
      }
    });
  });

  group('transition from synchronizing', () {
    test('clockSyncComplete -> ready with emitSynchronized', () {
      final result = transition(
          SessionState.synchronizing, SessionEvent.clockSyncComplete);
      expect(result.newState, SessionState.ready);
      expect(result.effects, contains(SessionEffect.emitSynchronized));
      expect(result.effects, contains(SessionEffect.schedulePeriodicClockSync));
      expect(result.effects.length, 2);
    });

    test('clockSyncTimeout -> ready (fallback, schedule periodic)', () {
      final result =
          transition(SessionState.synchronizing, SessionEvent.clockSyncTimeout);
      expect(result.newState, SessionState.ready);
      expect(result.effects, contains(SessionEffect.schedulePeriodicClockSync));
      expect(result.effects.length, 1);
    });

    test('byeReceived -> disconnected', () {
      final result =
          transition(SessionState.synchronizing, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('byeSent -> disconnecting', () {
      final result =
          transition(SessionState.synchronizing, SessionEvent.byeSent);
      expect(result.newState, SessionState.disconnecting);
      expect(result.effects, contains(SessionEffect.sendBye));
      expect(result.effects, contains(SessionEffect.cancelTimers));
    });

    test('error -> disconnected with sendBye and emitError', () {
      final result = transition(SessionState.synchronizing, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.sendBye));
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('irrelevant events stay in synchronizing', () {
      final irrelevant = [
        SessionEvent.sendInvitation,
        SessionEvent.controlOkReceived,
        SessionEvent.controlNoReceived,
        SessionEvent.dataOkReceived,
        SessionEvent.dataNoReceived,
        SessionEvent.timeout,
      ];
      for (final event in irrelevant) {
        final result = transition(SessionState.synchronizing, event);
        expect(result.newState, SessionState.synchronizing,
            reason: 'synchronizing + $event should stay synchronizing');
        expect(result.effects, isEmpty);
      }
    });
  });

  group('transition from ready', () {
    test('sendInvitation -> synchronizing (periodic clock sync)', () {
      final result =
          transition(SessionState.ready, SessionEvent.sendInvitation);
      expect(result.newState, SessionState.synchronizing);
      expect(result.effects, contains(SessionEffect.sendClockSync));
      expect(result.effects, contains(SessionEffect.scheduleClockSyncTimeout));
      expect(result.effects.length, 2);
    });

    test('clockSyncComplete -> ready (stay ready, reschedule)', () {
      final result =
          transition(SessionState.ready, SessionEvent.clockSyncComplete);
      expect(result.newState, SessionState.ready);
      expect(result.effects, contains(SessionEffect.emitSynchronized));
      expect(result.effects, contains(SessionEffect.schedulePeriodicClockSync));
      expect(result.effects.length, 2);
    });

    test('byeReceived -> disconnected', () {
      final result = transition(SessionState.ready, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('byeSent -> disconnecting', () {
      final result = transition(SessionState.ready, SessionEvent.byeSent);
      expect(result.newState, SessionState.disconnecting);
      expect(result.effects, contains(SessionEffect.sendBye));
      expect(result.effects, contains(SessionEffect.cancelTimers));
    });

    test('timeout -> disconnecting (idle timeout)', () {
      final result = transition(SessionState.ready, SessionEvent.timeout);
      expect(result.newState, SessionState.disconnecting);
      expect(result.effects, contains(SessionEffect.sendBye));
      expect(result.effects, contains(SessionEffect.cancelTimers));
    });

    test('error -> disconnected with sendBye and emitError', () {
      final result = transition(SessionState.ready, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.sendBye));
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('irrelevant events stay in ready', () {
      final irrelevant = [
        SessionEvent.controlOkReceived,
        SessionEvent.controlNoReceived,
        SessionEvent.dataOkReceived,
        SessionEvent.dataNoReceived,
        SessionEvent.clockSyncTimeout,
      ];
      for (final event in irrelevant) {
        final result = transition(SessionState.ready, event);
        expect(result.newState, SessionState.ready,
            reason: 'ready + $event should stay ready');
        expect(result.effects, isEmpty);
      }
    });
  });

  group('transition from disconnecting', () {
    test('byeReceived -> disconnected (graceful close)', () {
      final result =
          transition(SessionState.disconnecting, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('timeout -> disconnected (no bye confirmation)', () {
      final result =
          transition(SessionState.disconnecting, SessionEvent.timeout);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitDisconnected));
    });

    test('error -> disconnected with emitError', () {
      final result = transition(SessionState.disconnecting, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.cancelTimers));
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('irrelevant events stay in disconnecting', () {
      final irrelevant = [
        SessionEvent.sendInvitation,
        SessionEvent.controlOkReceived,
        SessionEvent.controlNoReceived,
        SessionEvent.dataOkReceived,
        SessionEvent.dataNoReceived,
        SessionEvent.clockSyncComplete,
        SessionEvent.clockSyncTimeout,
        SessionEvent.byeSent,
      ];
      for (final event in irrelevant) {
        final result = transition(SessionState.disconnecting, event);
        expect(result.newState, SessionState.disconnecting,
            reason: 'disconnecting + $event should stay disconnecting');
        expect(result.effects, isEmpty);
      }
    });
  });

  group('transition from disconnected (terminal)', () {
    test('all events return disconnected with no effects', () {
      for (final event in SessionEvent.values) {
        final result = transition(SessionState.disconnected, event);
        expect(result.newState, SessionState.disconnected,
            reason: 'disconnected + $event should stay disconnected');
        expect(result.effects, isEmpty,
            reason: 'disconnected + $event should have no effects');
      }
    });
  });

  group('full outbound invitation flow', () {
    test('idle -> invitingControl -> invitingData -> connected -> ready', () {
      // Step 1: Start invitation
      var result = transition(SessionState.idle, SessionEvent.sendInvitation);
      expect(result.newState, SessionState.invitingControl);

      // Step 2: Control port accepted
      result = transition(result.newState, SessionEvent.controlOkReceived);
      expect(result.newState, SessionState.invitingData);

      // Step 3: Data port accepted
      result = transition(result.newState, SessionEvent.dataOkReceived);
      expect(result.newState, SessionState.connected);

      // Step 4: Clock sync completes
      result = transition(result.newState, SessionEvent.clockSyncComplete);
      expect(result.newState, SessionState.ready);
    });
  });

  group('rejection flows', () {
    test('control port rejection leads to disconnected', () {
      var result = transition(SessionState.idle, SessionEvent.sendInvitation);
      expect(result.newState, SessionState.invitingControl);

      result = transition(result.newState, SessionEvent.controlNoReceived);
      expect(result.newState, SessionState.disconnected);
    });

    test('data port rejection leads to disconnected with bye', () {
      var result = transition(SessionState.idle, SessionEvent.sendInvitation);
      result = transition(result.newState, SessionEvent.controlOkReceived);
      expect(result.newState, SessionState.invitingData);

      result = transition(result.newState, SessionEvent.dataNoReceived);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.sendBye));
    });
  });

  group('bye flow from various states', () {
    test(
        'connected -> disconnecting -> disconnected on byeSent then byeReceived',
        () {
      var result = transition(SessionState.connected, SessionEvent.byeSent);
      expect(result.newState, SessionState.disconnecting);
      expect(result.effects, contains(SessionEffect.sendBye));

      result = transition(result.newState, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
    });

    test('ready -> disconnecting -> disconnected on byeSent then timeout', () {
      var result = transition(SessionState.ready, SessionEvent.byeSent);
      expect(result.newState, SessionState.disconnecting);

      result = transition(result.newState, SessionEvent.timeout);
      expect(result.newState, SessionState.disconnected);
    });

    test('synchronizing -> disconnecting on byeSent', () {
      final result =
          transition(SessionState.synchronizing, SessionEvent.byeSent);
      expect(result.newState, SessionState.disconnecting);
      expect(result.effects, contains(SessionEffect.sendBye));
      expect(result.effects, contains(SessionEffect.cancelTimers));
    });
  });

  group('byeReceived from any active state leads to disconnected', () {
    test('from invitingControl', () {
      final result =
          transition(SessionState.invitingControl, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
    });

    test('from invitingData', () {
      final result =
          transition(SessionState.invitingData, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
    });

    test('from connected', () {
      final result =
          transition(SessionState.connected, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
    });

    test('from synchronizing', () {
      final result =
          transition(SessionState.synchronizing, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
    });

    test('from ready', () {
      final result = transition(SessionState.ready, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
    });

    test('from disconnecting', () {
      final result =
          transition(SessionState.disconnecting, SessionEvent.byeReceived);
      expect(result.newState, SessionState.disconnected);
    });
  });

  group('error from any active state leads to disconnected', () {
    test('from invitingControl', () {
      final result =
          transition(SessionState.invitingControl, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('from invitingData', () {
      final result = transition(SessionState.invitingData, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('from connected', () {
      final result = transition(SessionState.connected, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('from synchronizing', () {
      final result = transition(SessionState.synchronizing, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('from ready', () {
      final result = transition(SessionState.ready, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.emitError));
    });

    test('from disconnecting', () {
      final result = transition(SessionState.disconnecting, SessionEvent.error);
      expect(result.newState, SessionState.disconnected);
      expect(result.effects, contains(SessionEffect.emitError));
    });
  });

  group('periodic clock sync re-entry', () {
    test('ready -> synchronizing -> ready cycle', () {
      // Periodic sync triggers
      var result = transition(SessionState.ready, SessionEvent.sendInvitation);
      expect(result.newState, SessionState.synchronizing);
      expect(result.effects, contains(SessionEffect.sendClockSync));

      // Sync completes
      result = transition(result.newState, SessionEvent.clockSyncComplete);
      expect(result.newState, SessionState.ready);
      expect(result.effects, contains(SessionEffect.emitSynchronized));
      expect(result.effects, contains(SessionEffect.schedulePeriodicClockSync));
    });
  });

  group('clock sync retry on timeout during connection', () {
    test('connected retries sync on clockSyncTimeout', () {
      final result =
          transition(SessionState.connected, SessionEvent.clockSyncTimeout);
      expect(result.newState, SessionState.connected);
      expect(result.effects, contains(SessionEffect.sendClockSync));
      expect(result.effects, contains(SessionEffect.scheduleClockSyncTimeout));
    });
  });

  group('effect ordering is preserved', () {
    test('dataOkReceived effects are in correct order', () {
      final result =
          transition(SessionState.invitingData, SessionEvent.dataOkReceived);
      // Verify the specific order: cancelTimers, emitConnected, sendClockSync, scheduleClockSyncTimeout
      expect(result.effects[0], SessionEffect.cancelTimers);
      expect(result.effects[1], SessionEffect.emitConnected);
      expect(result.effects[2], SessionEffect.sendClockSync);
      expect(result.effects[3], SessionEffect.scheduleClockSyncTimeout);
    });

    test('controlNoReceived effects are in correct order', () {
      final result = transition(
          SessionState.invitingControl, SessionEvent.controlNoReceived);
      expect(result.effects[0], SessionEffect.cancelTimers);
      expect(result.effects[1], SessionEffect.emitDisconnected);
    });
  });
}
