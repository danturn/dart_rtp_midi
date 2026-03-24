import 'dart:async';
import 'dart:typed_data';

import 'package:dart_rtp_midi/src/session/exchange_packet.dart';
import 'package:dart_rtp_midi/src/session/invitation_protocol.dart';
import 'package:dart_rtp_midi/src/session/clock_sync.dart';
import 'package:dart_rtp_midi/src/session/session_state.dart';
import 'package:dart_rtp_midi/src/transport/transport.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Manual mock transport for integration tests.
// Records all sent messages and allows injecting received messages.
// ---------------------------------------------------------------------------
class MockTransport implements Transport {
  final int _controlPort;
  final int _dataPort;

  MockTransport({int controlPort = 5004, int dataPort = 5005})
      : _controlPort = controlPort,
        _dataPort = dataPort;

  @override
  int get controlPort => _controlPort;

  @override
  int get dataPort => _dataPort;

  // Recorded sends
  final List<SentDatagram> controlSends = [];
  final List<SentDatagram> dataSends = [];

  // Inject received messages via these controllers
  final _controlController = StreamController<Datagram>.broadcast();
  final _dataController = StreamController<Datagram>.broadcast();

  @override
  Stream<Datagram> get onControlMessage => _controlController.stream;

  @override
  Stream<Datagram> get onDataMessage => _dataController.stream;

  @override
  void sendControl(Uint8List data, String address, int port) {
    controlSends.add(SentDatagram(data, address, port));
  }

  @override
  void sendData(Uint8List data, String address, int port) {
    dataSends.add(SentDatagram(data, address, port));
  }

  @override
  Future<void> bind() async {
    // No-op for mock
  }

  @override
  Future<void> close() async {
    await _controlController.close();
    await _dataController.close();
  }

  /// Simulate receiving a message on the control port.
  void injectControlMessage(Uint8List data,
      {String address = '192.168.1.100', int port = 5004}) {
    _controlController.add(Datagram(data, address, port));
  }

  /// Simulate receiving a message on the data port.
  void injectDataMessage(Uint8List data,
      {String address = '192.168.1.100', int port = 5005}) {
    _dataController.add(Datagram(data, address, port));
  }
}

class SentDatagram {
  final Uint8List data;
  final String address;
  final int port;

  SentDatagram(this.data, this.address, this.port);
}

// ---------------------------------------------------------------------------
// A lightweight session driver that wires together the pure functions
// with a Transport, processing events through the state machine.
//
// This is the "integration glue" we test at the middle of the testing
// triangle. Since there is no SessionController class yet, this driver
// exercises the composition of pure session functions + transport.
// ---------------------------------------------------------------------------
class _SessionDriver {
  final MockTransport transport;
  final String localName = 'TestLocal';
  final int localSsrc = 0x11111111;
  final int initiatorToken = 0xDEADBEEF;
  final String remoteAddress = '192.168.1.100';
  final int remoteControlPort = 5004;
  final int remoteDataPort = 5005;

  SessionState state = SessionState.idle;
  final List<SessionEffect> executedEffects = [];

  _SessionDriver({required this.transport});

  /// Apply an event and execute the resulting effects.
  void handleEvent(SessionEvent event) {
    final result = transition(state, event);
    state = result.newState;
    for (final effect in result.effects) {
      executedEffects.add(effect);
      _executeEffect(effect);
    }
  }

  void _executeEffect(SessionEffect effect) {
    switch (effect) {
      case SessionEffect.sendControlInvitation:
        final packet = createInvitation(
          initiatorToken: initiatorToken,
          ssrc: localSsrc,
          name: localName,
        );
        transport.sendControl(
            packet.encode(), remoteAddress, remoteControlPort);
        break;
      case SessionEffect.sendDataInvitation:
        final packet = createInvitation(
          initiatorToken: initiatorToken,
          ssrc: localSsrc,
          name: localName,
        );
        transport.sendData(packet.encode(), remoteAddress, remoteDataPort);
        break;
      case SessionEffect.sendBye:
        final packet = createBye(
          initiatorToken: initiatorToken,
          ssrc: localSsrc,
          name: localName,
        );
        transport.sendControl(
            packet.encode(), remoteAddress, remoteControlPort);
        transport.sendData(packet.encode(), remoteAddress, remoteDataPort);
        break;
      case SessionEffect.sendClockSync:
        final ck0 = createCk0(ssrc: localSsrc, timestamp1: 1000);
        transport.sendData(ck0.encode(), remoteAddress, remoteDataPort);
        break;
      default:
        // Other effects (scheduling, emitting) are no-ops in this test driver
        break;
    }
  }
}

void main() {
  group('MockTransport', () {
    test('records control sends', () {
      final transport = MockTransport();
      final data = Uint8List.fromList([1, 2, 3]);
      transport.sendControl(data, '10.0.0.1', 5004);
      expect(transport.controlSends.length, 1);
      expect(transport.controlSends[0].address, '10.0.0.1');
      expect(transport.controlSends[0].port, 5004);
      expect(transport.controlSends[0].data, data);
    });

    test('records data sends', () {
      final transport = MockTransport();
      final data = Uint8List.fromList([4, 5, 6]);
      transport.sendData(data, '10.0.0.2', 5005);
      expect(transport.dataSends.length, 1);
    });

    test('injects control messages', () async {
      final transport = MockTransport();
      final completer = Completer<Datagram>();
      transport.onControlMessage.listen(completer.complete);

      final data = Uint8List.fromList([7, 8, 9]);
      transport.injectControlMessage(data);

      final received = await completer.future;
      expect(received.data, data);
    });

    test('injects data messages', () async {
      final transport = MockTransport();
      final completer = Completer<Datagram>();
      transport.onDataMessage.listen(completer.complete);

      final data = Uint8List.fromList([10, 11, 12]);
      transport.injectDataMessage(data);

      final received = await completer.future;
      expect(received.data, data);
    });
  });

  group('Outbound invitation flow', () {
    late MockTransport transport;
    late _SessionDriver driver;

    setUp(() {
      transport = MockTransport();
      driver = _SessionDriver(transport: transport);
    });

    test(
        'send IN -> receive OK on control -> send IN on data -> receive OK on data -> connected',
        () {
      // Start invitation
      driver.handleEvent(SessionEvent.sendInvitation);
      expect(driver.state, SessionState.invitingControl);

      // Verify IN was sent on control port
      expect(transport.controlSends.length, 1);
      final sentInvitation =
          ExchangePacket.decode(transport.controlSends[0].data);
      expect(sentInvitation, isNotNull);
      expect(sentInvitation!.command, ExchangeCommand.invitation);
      expect(sentInvitation.initiatorToken, 0xDEADBEEF);
      expect(sentInvitation.name, 'TestLocal');

      // Simulate OK response on control port
      driver.handleEvent(SessionEvent.controlOkReceived);
      expect(driver.state, SessionState.invitingData);

      // Verify IN was sent on data port
      expect(transport.dataSends.length, 1);
      final dataInvitation = ExchangePacket.decode(transport.dataSends[0].data);
      expect(dataInvitation, isNotNull);
      expect(dataInvitation!.command, ExchangeCommand.invitation);

      // Simulate OK response on data port
      driver.handleEvent(SessionEvent.dataOkReceived);
      expect(driver.state, SessionState.connected);

      // Verify CK0 was sent on data port for clock sync
      expect(transport.dataSends.length, 2); // invitation + CK0
      final ck0 = ClockSyncPacket.decode(transport.dataSends[1].data);
      expect(ck0, isNotNull);
      expect(ck0!.count, 0);
    });

    test('effects are recorded in correct order through full flow', () {
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlOkReceived);
      driver.handleEvent(SessionEvent.dataOkReceived);
      driver.handleEvent(SessionEvent.clockSyncComplete);

      expect(
          driver.executedEffects,
          containsAllInOrder([
            SessionEffect.sendControlInvitation,
            SessionEffect.scheduleInvitationRetry,
            SessionEffect.sendDataInvitation,
            SessionEffect.scheduleInvitationRetry,
            SessionEffect.cancelTimers,
            SessionEffect.emitConnected,
            SessionEffect.sendClockSync,
            SessionEffect.scheduleClockSyncTimeout,
            SessionEffect.cancelTimers,
            SessionEffect.emitSynchronized,
            SessionEffect.schedulePeriodicClockSync,
          ]));
    });
  });

  group('Incoming invitation flow', () {
    late MockTransport transport;

    setUp(() {
      transport = MockTransport();
    });

    test(
        'receive IN on control -> send OK -> receive IN on data -> send OK -> connected',
        () {
      // This flow is driven by the responder side. We test that the
      // correct OK packets are created and can be decoded.
      const remoteSsrc = 0x22222222;
      const remoteToken = 0xCAFEBABE;
      const localSsrc = 0x11111111;

      // Simulate receiving an invitation on the control port
      final incomingInvitation = createInvitation(
        initiatorToken: remoteToken,
        ssrc: remoteSsrc,
        name: 'RemoteDevice',
      );

      // Decode it as the responder would
      final decoded = ExchangePacket.decode(incomingInvitation.encode());
      expect(decoded, isNotNull);
      expect(decoded!.command, ExchangeCommand.invitation);

      // Create OK response echoing the token
      final okResponse = createOk(
        initiatorToken: decoded.initiatorToken,
        ssrc: localSsrc,
        name: 'LocalDevice',
      );
      expect(okResponse.command, ExchangeCommand.ok);
      expect(okResponse.initiatorToken, remoteToken);

      // Send OK on control port
      transport.sendControl(okResponse.encode(), '192.168.1.100', 5004);
      expect(transport.controlSends.length, 1);
      final sentOk = ExchangePacket.decode(transport.controlSends[0].data);
      expect(sentOk!.command, ExchangeCommand.ok);
      expect(sentOk.initiatorToken, remoteToken);

      // Now receive IN on data port
      final dataInvitation = createInvitation(
        initiatorToken: remoteToken,
        ssrc: remoteSsrc,
        name: 'RemoteDevice',
      );
      final decodedData = ExchangePacket.decode(dataInvitation.encode());
      expect(decodedData!.command, ExchangeCommand.invitation);

      // Create OK for data port
      final dataOk = createOk(
        initiatorToken: decodedData.initiatorToken,
        ssrc: localSsrc,
        name: 'LocalDevice',
      );
      transport.sendData(dataOk.encode(), '192.168.1.100', 5005);
      expect(transport.dataSends.length, 1);
      final sentDataOk = ExchangePacket.decode(transport.dataSends[0].data);
      expect(sentDataOk!.command, ExchangeCommand.ok);
      expect(sentDataOk.initiatorToken, remoteToken);
    });
  });

  group('Rejection flow', () {
    late MockTransport transport;
    late _SessionDriver driver;

    setUp(() {
      transport = MockTransport();
      driver = _SessionDriver(transport: transport);
    });

    test('send IN -> receive NO -> disconnected', () {
      driver.handleEvent(SessionEvent.sendInvitation);
      expect(driver.state, SessionState.invitingControl);

      driver.handleEvent(SessionEvent.controlNoReceived);
      expect(driver.state, SessionState.disconnected);

      // No data sends should have happened
      expect(transport.dataSends, isEmpty);

      // Effects should include cancelTimers and emitDisconnected
      expect(driver.executedEffects, contains(SessionEffect.emitDisconnected));
      expect(driver.executedEffects, contains(SessionEffect.cancelTimers));
    });

    test('control OK then data NO -> disconnected with bye sent', () {
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlOkReceived);
      expect(driver.state, SessionState.invitingData);

      driver.handleEvent(SessionEvent.dataNoReceived);
      expect(driver.state, SessionState.disconnected);

      // Should have sent bye on both ports
      expect(driver.executedEffects, contains(SessionEffect.sendBye));

      // Check that bye packets were actually sent
      // Control: 1 invitation + 1 bye = 2
      expect(transport.controlSends.length, 2);
      final byeOnControl =
          ExchangePacket.decode(transport.controlSends[1].data);
      expect(byeOnControl!.command, ExchangeCommand.bye);

      // Data: 1 invitation + 1 bye = 2
      expect(transport.dataSends.length, 2);
      final byeOnData = ExchangePacket.decode(transport.dataSends[1].data);
      expect(byeOnData!.command, ExchangeCommand.bye);
    });

    test('send NO to incoming invitation', () {
      const remoteToken = 0xBEEF;
      const localSsrc = 0x1111;

      final noPacket = createNo(
        initiatorToken: remoteToken,
        ssrc: localSsrc,
        name: 'Local',
      );

      // Verify NO packet is well-formed
      expect(noPacket.command, ExchangeCommand.no);
      expect(noPacket.initiatorToken, remoteToken);

      final bytes = noPacket.encode();
      final decoded = ExchangePacket.decode(bytes);
      expect(decoded!.command, ExchangeCommand.no);
    });
  });

  group('Bye flow', () {
    late MockTransport transport;
    late _SessionDriver driver;

    setUp(() {
      transport = MockTransport();
      driver = _SessionDriver(transport: transport);
      // Get to connected state
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlOkReceived);
      driver.handleEvent(SessionEvent.dataOkReceived);
      driver.handleEvent(SessionEvent.clockSyncComplete);
      expect(driver.state, SessionState.ready);
    });

    test(
        'connected -> bye sent -> disconnecting -> bye received -> disconnected',
        () {
      final controlSendsBeforeBye = transport.controlSends.length;
      final dataSendsBeforeBye = transport.dataSends.length;

      driver.handleEvent(SessionEvent.byeSent);
      expect(driver.state, SessionState.disconnecting);

      // Check BYE was sent on both ports
      expect(transport.controlSends.length, controlSendsBeforeBye + 1);
      expect(transport.dataSends.length, dataSendsBeforeBye + 1);

      final controlBye =
          ExchangePacket.decode(transport.controlSends.last.data);
      expect(controlBye!.command, ExchangeCommand.bye);

      final dataBye = ExchangePacket.decode(transport.dataSends.last.data);
      expect(dataBye!.command, ExchangeCommand.bye);

      // Remote acknowledges
      driver.handleEvent(SessionEvent.byeReceived);
      expect(driver.state, SessionState.disconnected);
    });

    test('disconnecting times out to disconnected', () {
      driver.handleEvent(SessionEvent.byeSent);
      expect(driver.state, SessionState.disconnecting);

      driver.handleEvent(SessionEvent.timeout);
      expect(driver.state, SessionState.disconnected);
    });
  });

  group('Clock sync exchange after connection', () {
    late MockTransport transport;
    late _SessionDriver driver;

    setUp(() {
      transport = MockTransport();
      driver = _SessionDriver(transport: transport);
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlOkReceived);
      driver.handleEvent(SessionEvent.dataOkReceived);
      // Now in connected state, CK0 has been sent
    });

    test('CK0 is sent when entering connected state', () {
      // The last data send should be a CK0
      final lastDataSend = transport.dataSends.last;
      final ck0 = ClockSyncPacket.decode(lastDataSend.data);
      expect(ck0, isNotNull);
      expect(ck0!.count, 0);
      expect(ck0.ssrc, driver.localSsrc);
    });

    test('CK1 response can be created from CK0', () {
      final ck0Data = transport.dataSends.last.data;
      final ck0 = ClockSyncPacket.decode(ck0Data)!;

      // Responder creates CK1
      const responderSsrc = 0x22222222;
      final ck1 = createCk1(
        ssrc: responderSsrc,
        timestamp1: ck0.timestamp1,
        timestamp2: 2000,
      );

      expect(ck1.count, 1);
      expect(ck1.timestamp1, ck0.timestamp1);
      expect(ck1.timestamp2, 2000);

      // Verify it roundtrips
      final decoded = ClockSyncPacket.decode(ck1.encode());
      expect(decoded, equals(ck1));
    });

    test('full CK0/CK1/CK2 exchange produces correct sync result', () {
      final ck0Data = transport.dataSends.last.data;
      final ck0 = ClockSyncPacket.decode(ck0Data)!;

      // Responder sends CK1
      final ck1 = createCk1(
        ssrc: 0x22222222,
        timestamp1: ck0.timestamp1,
        timestamp2: 1050,
      );

      // Initiator creates CK2
      final ck2 = createCk2(
        ssrc: driver.localSsrc,
        timestamp1: ck1.timestamp1,
        timestamp2: ck1.timestamp2,
        timestamp3: 1100,
      );

      // Compute offset
      final result = computeOffset(ck2);
      // offset = ((1000+1100) - 2*1050) / 2 = 0 ticks -> 0 us
      // latency = (1100-1000) / 2 = 50 ticks -> 5000 us
      expect(result.offsetMicroseconds, 0);
      expect(result.latencyMicroseconds, 5000);

      // After computing, signal clockSyncComplete
      driver.handleEvent(SessionEvent.clockSyncComplete);
      expect(driver.state, SessionState.ready);
    });
  });

  group('Timeout handling', () {
    late MockTransport transport;
    late _SessionDriver driver;

    setUp(() {
      transport = MockTransport();
      driver = _SessionDriver(transport: transport);
    });

    test('timeout during invitingControl -> disconnected', () {
      driver.handleEvent(SessionEvent.sendInvitation);
      expect(driver.state, SessionState.invitingControl);

      driver.handleEvent(SessionEvent.timeout);
      expect(driver.state, SessionState.disconnected);
    });

    test('timeout during invitingData -> disconnected with bye', () {
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlOkReceived);
      expect(driver.state, SessionState.invitingData);

      driver.handleEvent(SessionEvent.timeout);
      expect(driver.state, SessionState.disconnected);
      expect(driver.executedEffects, contains(SessionEffect.sendBye));
    });

    test('clock sync timeout in connected state -> retries sync', () {
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlOkReceived);
      driver.handleEvent(SessionEvent.dataOkReceived);
      expect(driver.state, SessionState.connected);

      final dataSendsBefore = transport.dataSends.length;

      driver.handleEvent(SessionEvent.clockSyncTimeout);
      expect(driver.state, SessionState.connected); // stays connected
      expect(transport.dataSends.length, dataSendsBefore + 1); // new CK0

      final retryCk0 = ClockSyncPacket.decode(transport.dataSends.last.data);
      expect(retryCk0!.count, 0);
    });

    test('idle timeout in ready state -> disconnecting', () {
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlOkReceived);
      driver.handleEvent(SessionEvent.dataOkReceived);
      driver.handleEvent(SessionEvent.clockSyncComplete);
      expect(driver.state, SessionState.ready);

      driver.handleEvent(SessionEvent.timeout);
      expect(driver.state, SessionState.disconnecting);
      expect(driver.executedEffects, contains(SessionEffect.sendBye));
    });
  });

  group('Packet wire format validation through transport', () {
    late MockTransport transport;

    setUp(() {
      transport = MockTransport();
    });

    test('invitation packet sent through transport is valid on the wire', () {
      final packet = createInvitation(
        initiatorToken: 0xABCD,
        ssrc: 0x1234,
        name: 'WireTest',
      );
      transport.sendControl(packet.encode(), '10.0.0.1', 5004);

      final sentBytes = transport.controlSends[0].data;

      // Verify raw wire format
      final view = ByteData.sublistView(sentBytes);
      expect(view.getUint16(0), 0xFFFF); // signature
      expect(view.getUint16(2), 0x494E); // 'IN'
      expect(view.getUint32(4), 2); // version

      // Also verify it decodes back
      final decoded = ExchangePacket.decode(sentBytes);
      expect(decoded, equals(packet));
    });

    test('clock sync packet sent through transport is valid on the wire', () {
      final ck0 = createCk0(ssrc: 0x5678, timestamp1: 42);
      transport.sendData(ck0.encode(), '10.0.0.1', 5005);

      final sentBytes = transport.dataSends[0].data;
      expect(sentBytes.length, ClockSyncPacket.size);

      // Check it is identified correctly
      expect(isClockSyncPacket(sentBytes), isTrue);

      // Verify decode
      final decoded = ClockSyncPacket.decode(sentBytes);
      expect(decoded, equals(ck0));
    });

    test('isClockSyncPacket correctly differentiates exchange and clock sync',
        () {
      final invitation = createInvitation(
        initiatorToken: 1,
        ssrc: 2,
        name: 'T',
      ).encode();
      final ck0 = createCk0(ssrc: 1, timestamp1: 100).encode();

      expect(isClockSyncPacket(invitation), isFalse);
      expect(isClockSyncPacket(ck0), isTrue);
    });
  });

  group('Clock sync uses data port', () {
    late MockTransport transport;
    late _SessionDriver driver;

    setUp(() {
      transport = MockTransport();
      driver = _SessionDriver(transport: transport);
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlOkReceived);
      driver.handleEvent(SessionEvent.dataOkReceived);
    });

    test('CK0 is sent on the data port, not the control port', () {
      // After connection, CK0 should appear in dataSends (not controlSends)
      final controlCkPackets = transport.controlSends
          .where((s) => isClockSyncPacket(s.data) == true)
          .toList();
      final dataCkPackets = transport.dataSends
          .where((s) => isClockSyncPacket(s.data) == true)
          .toList();

      expect(controlCkPackets, isEmpty,
          reason: 'CK packets should not be sent on control port');
      expect(dataCkPackets, hasLength(1),
          reason: 'CK0 should be sent on data port');
      expect(ClockSyncPacket.decode(dataCkPackets[0].data)!.count, 0);
    });

    test('CK0 is sent to the remote data port', () {
      final ckSend = transport.dataSends
          .where((s) => isClockSyncPacket(s.data) == true)
          .first;
      expect(ckSend.port, driver.remoteDataPort);
      expect(ckSend.address, driver.remoteAddress);
    });

    test('clock sync retry also uses data port', () {
      final dataSendsBefore = transport.dataSends.length;

      driver.handleEvent(SessionEvent.clockSyncTimeout);

      final newDataCk = transport.dataSends
          .skip(dataSendsBefore)
          .where((s) => isClockSyncPacket(s.data) == true)
          .toList();
      expect(newDataCk, hasLength(1));
      expect(ClockSyncPacket.decode(newDataCk[0].data)!.count, 0);
    });
  });

  group('Retry delay integration', () {
    test('retry delays follow exponential backoff pattern', () {
      final delays = <Duration>[];
      for (var i = 0; i < 12; i++) {
        delays.add(nextRetryDelay(attempt: i)!);
      }

      // Verify first delay
      expect(delays[0], const Duration(milliseconds: 1500));

      // Verify each is double the previous
      for (var i = 1; i < delays.length; i++) {
        expect(delays[i], delays[i - 1] * 2,
            reason: 'delay[$i] should be 2x delay[${i - 1}]');
      }

      // Verify 13th attempt is null
      expect(nextRetryDelay(attempt: 12), isNull);
    });
  });

  group('Error recovery', () {
    late MockTransport transport;
    late _SessionDriver driver;

    setUp(() {
      transport = MockTransport();
      driver = _SessionDriver(transport: transport);
    });

    test('error during connection sends bye and disconnects', () {
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlOkReceived);
      driver.handleEvent(SessionEvent.dataOkReceived);
      expect(driver.state, SessionState.connected);

      driver.handleEvent(SessionEvent.error);
      expect(driver.state, SessionState.disconnected);
      expect(driver.executedEffects, contains(SessionEffect.sendBye));
      expect(driver.executedEffects, contains(SessionEffect.emitError));
    });

    test('error during ready sends bye and disconnects', () {
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlOkReceived);
      driver.handleEvent(SessionEvent.dataOkReceived);
      driver.handleEvent(SessionEvent.clockSyncComplete);
      expect(driver.state, SessionState.ready);

      driver.handleEvent(SessionEvent.error);
      expect(driver.state, SessionState.disconnected);
      expect(driver.executedEffects, contains(SessionEffect.sendBye));
      expect(driver.executedEffects, contains(SessionEffect.emitError));
    });

    test('disconnected state is terminal - no further transitions', () {
      driver.handleEvent(SessionEvent.sendInvitation);
      driver.handleEvent(SessionEvent.controlNoReceived);
      expect(driver.state, SessionState.disconnected);

      final effectCountBefore = driver.executedEffects.length;

      // Try all events - none should produce effects
      for (final event in SessionEvent.values) {
        driver.handleEvent(event);
        expect(driver.state, SessionState.disconnected);
      }

      expect(driver.executedEffects.length, effectCountBefore);
    });
  });
}
