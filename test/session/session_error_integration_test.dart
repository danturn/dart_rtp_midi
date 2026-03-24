import 'dart:async';
import 'dart:typed_data';

import 'package:dart_rtp_midi/src/api/midi_message.dart';
import 'package:dart_rtp_midi/src/api/rtp_midi_config.dart';
import 'package:dart_rtp_midi/src/api/session_error.dart';
import 'package:dart_rtp_midi/src/rtp/midi_command_codec.dart';
import 'package:dart_rtp_midi/src/rtp/rtp_header.dart';
import 'package:dart_rtp_midi/src/rtp/rtp_midi_payload.dart';
import 'package:dart_rtp_midi/src/session/clock_sync.dart';
import 'package:dart_rtp_midi/src/session/exchange_packet.dart';
import 'package:dart_rtp_midi/src/session/invitation_protocol.dart';
import 'package:dart_rtp_midi/src/session/session_controller.dart';
import 'package:dart_rtp_midi/src/session/session_state.dart';
import 'package:dart_rtp_midi/src/transport/transport.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock transport (same pattern as session_controller_test.dart)
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

  final List<Sent> controlSends = [];
  final List<Sent> dataSends = [];

  final _controlController = StreamController<Datagram>.broadcast();
  final _dataController = StreamController<Datagram>.broadcast();

  @override
  Stream<Datagram> get onControlMessage => _controlController.stream;
  @override
  Stream<Datagram> get onDataMessage => _dataController.stream;

  @override
  void sendControl(Uint8List data, String address, int port) {
    controlSends.add(Sent(data, address, port));
  }

  @override
  void sendData(Uint8List data, String address, int port) {
    dataSends.add(Sent(data, address, port));
  }

  @override
  Future<void> bind() async {}

  @override
  Future<void> close() async {
    await _controlController.close();
    await _dataController.close();
  }

  void injectControl(Uint8List data,
      {String address = '192.168.1.100', int port = 5004}) {
    _controlController.add(Datagram(data, address, port));
  }

  void injectData(Uint8List data,
      {String address = '192.168.1.100', int port = 5005}) {
    _dataController.add(Datagram(data, address, port));
  }
}

class Sent {
  final Uint8List data;
  final String address;
  final int port;
  Sent(this.data, this.address, this.port);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _remoteAddress = '192.168.1.100';
const _remoteSsrc = 0x22222222;
const _localSsrc = 0x11111111;

SessionController _makeController(MockTransport transport) {
  return SessionController(
    transport: transport,
    config: const RtpMidiConfig(
      name: 'TestLocal',
      maxInvitationRetries: 3,
      invitationRetryBaseInterval: Duration(milliseconds: 50),
    ),
    localSsrc: _localSsrc,
  );
}

/// Drive the controller to the ready state via outbound invitation flow.
Future<void> _driveToReady(
    SessionController controller, MockTransport transport) async {
  await controller.invite(_remoteAddress, 5004);
  // Allow the invite to send
  await Future<void>.delayed(Duration.zero);

  // Inject control OK
  final controlOk = createOk(
    initiatorToken: _extractToken(transport.controlSends.last.data),
    ssrc: _remoteSsrc,
    name: 'RemotePeer',
  );
  transport.injectControl(controlOk.encode());
  await Future<void>.delayed(Duration.zero);

  // Inject data OK
  final dataOk = createOk(
    initiatorToken: _extractToken(transport.dataSends.first.data),
    ssrc: _remoteSsrc,
    name: 'RemotePeer',
  );
  transport.injectData(dataOk.encode());
  await Future<void>.delayed(Duration.zero);

  // Complete clock sync: inject CK1 response to our CK0
  final ck0Sends = transport.dataSends.where((s) {
    return isClockSyncPacket(s.data) == true;
  }).toList();
  if (ck0Sends.isNotEmpty) {
    final ck0 = ClockSyncPacket.decode(ck0Sends.last.data)!;
    final ck1 = createCk1(
      ssrc: _remoteSsrc,
      timestamp1: ck0.timestamp1,
      timestamp2: ck0.timestamp1 + 100,
    );
    transport.injectData(ck1.encode());
    await Future<void>.delayed(Duration.zero);
  }
}

int _extractToken(Uint8List data) {
  final packet = ExchangePacket.decode(data);
  return packet!.initiatorToken;
}

/// Build a valid RTP-MIDI payload with a NoteOn message.
Uint8List _validRtpMidiPayload({int seqNum = 1}) {
  final payload = RtpMidiPayload(
    header: RtpHeader(
      sequenceNumber: seqNum,
      timestamp: 1000,
      ssrc: _remoteSsrc,
      marker: false,
    ),
    commands: [
      const TimestampedMidiCommand(
          0, NoteOn(channel: 0, note: 60, velocity: 100))
    ],
    hasJournal: false,
  );
  return payload.encode();
}

void main() {
  group('Error stream plumbing', () {
    late MockTransport transport;
    late SessionController controller;

    setUp(() {
      transport = MockTransport();
      controller = _makeController(transport);
    });

    tearDown(() async {
      await controller.dispose();
      await transport.close();
    });

    test('onError stream exists and is broadcast', () {
      // Should be able to listen multiple times.
      controller.onError.listen((_) {});
      controller.onError.listen((_) {});
    });

    test('onError stream closes on dispose', () async {
      final done = Completer<void>();
      controller.onError.listen(
        (_) {},
        onDone: done.complete,
      );
      await controller.dispose();
      await done.future;
    });
  });

  group('MalformedPacket errors (A1-A5)', () {
    late MockTransport transport;
    late SessionController controller;

    setUp(() async {
      transport = MockTransport();
      controller = _makeController(transport);
      await _driveToReady(controller, transport);
    });

    tearDown(() async {
      await controller.dispose();
      await transport.close();
    });

    test('A1: malformed exchange packet on control port emits MalformedPacket',
        () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      // 0xFFFF signature + garbage (not CK, not valid exchange)
      final bad = Uint8List.fromList([
        0xFF, 0xFF, 0x49, 0x4E, // signature + IN
        0x00, 0x00, 0x00, // too short to decode
      ]);
      transport.injectControl(bad);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<MalformedPacket>());
      final mp = errors[0] as MalformedPacket;
      expect(mp.packetType, PacketType.exchange);
      expect(mp.address, _remoteAddress);
    });

    test('A2: malformed exchange packet on data port emits MalformedPacket',
        () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      // Has 0xFFFF signature but invalid (not CK, too short for exchange)
      final bad = Uint8List.fromList([
        0xFF, 0xFF, 0x49, 0x4E, // signature + IN command
        0x00, 0x00, // too short
      ]);
      transport.injectData(bad);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<MalformedPacket>());
      final mp = errors[0] as MalformedPacket;
      expect(mp.packetType, PacketType.exchange);
    });

    test('A3: malformed clock sync packet emits MalformedPacket', () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      // CK header but too short
      final bad = Uint8List.fromList([
        0xFF, 0xFF, 0x43, 0x4B, // signature + CK
        0x00, 0x00, 0x00, 0x01, // ssrc
        // Missing rest of CK packet (need 36 bytes total)
      ]);
      transport.injectData(bad);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<MalformedPacket>());
      final mp = errors[0] as MalformedPacket;
      expect(mp.packetType, PacketType.clockSync);
    });

    test('A4: malformed RTP-MIDI packet emits MalformedPacket', () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      // Looks like RTP (version 2) but B flag set with too-short body.
      // Byte 0: 0x80 (version 2), Byte 12: 0x8F (B flag + length high nibble)
      // B flag means 2-byte MIDI header, but only 1 byte available at offset 12.
      final bad = Uint8List(13);
      bad[0] = 0x80; // RTP version 2
      bad[12] = 0x8F; // B flag set, needs 2-byte header but only 1 byte left
      transport.injectData(bad);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<MalformedPacket>());
      final mp = errors[0] as MalformedPacket;
      expect(mp.packetType, PacketType.rtpMidi);
    });

    // A5 (RS packet) not tested: isRsPacket() and RsPacket.decode() share
    // identical guards, so decode can never return null once isRsPacket passes.
  });

  group('UTF-8 crash fix (A6)', () {
    late MockTransport transport;
    late SessionController controller;

    setUp(() {
      transport = MockTransport();
      controller = _makeController(transport);
    });

    tearDown(() async {
      await controller.dispose();
      await transport.close();
    });

    test('invalid UTF-8 in exchange packet emits MalformedPacket, no crash',
        () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      // Craft an exchange packet with invalid UTF-8 in the name field.
      // Wire format: sig(2) + cmd(2) + ver(4) + token(4) + ssrc(4) + name + NUL
      final bad = Uint8List(18);
      final view = ByteData.sublistView(bad);
      view.setUint16(0, 0xFFFF); // signature
      view.setUint16(2, 0x494E); // IN command
      view.setUint32(4, 2); // version
      view.setUint32(8, 0xDEADBEEF); // token
      view.setUint32(12, 0xCAFE); // ssrc
      bad[16] = 0xFE; // invalid UTF-8 byte
      bad[17] = 0x00; // NUL terminator

      transport.injectControl(bad);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<MalformedPacket>());
      final mp = errors[0] as MalformedPacket;
      expect(mp.packetType, PacketType.exchange);
      expect(mp.message, contains('UTF-8'));
    });

    test('invalid UTF-8 on data port also caught', () async {
      // First drive to invitingData so data port handler processes exchanges
      await controller.invite(_remoteAddress, 5004);
      await Future<void>.delayed(Duration.zero);

      // Inject control OK to advance to invitingData
      final token = _extractToken(transport.controlSends.last.data);
      final controlOk = createOk(
        initiatorToken: token,
        ssrc: _remoteSsrc,
        name: 'Remote',
      );
      transport.injectControl(controlOk.encode());
      await Future<void>.delayed(Duration.zero);

      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      // Now inject bad UTF-8 exchange on data port
      final bad = Uint8List(18);
      final view = ByteData.sublistView(bad);
      view.setUint16(0, 0xFFFF);
      view.setUint16(2, 0x494E); // IN
      view.setUint32(4, 2);
      view.setUint32(8, 0xBEEF);
      view.setUint32(12, 0xFACE);
      bad[16] = 0xFF; // invalid UTF-8
      bad[17] = 0x00;

      transport.injectData(bad);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<MalformedPacket>());
    });
  });

  group('ConnectionFailed errors (B1-B3)', () {
    late MockTransport transport;
    late SessionController controller;

    setUp(() {
      transport = MockTransport();
      controller = _makeController(transport);
    });

    tearDown(() async {
      await controller.dispose();
      await transport.close();
    });

    test('B1: max retries exhausted emits ConnectionFailed timeout', () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      await controller.invite(_remoteAddress, 5004);
      // Wait for retries to exhaust (3 retries at 50ms base, exponential)
      // 50 + 100 + 200 = 350ms, then timeout fires
      await Future<void>.delayed(const Duration(milliseconds: 800));

      expect(errors.whereType<ConnectionFailed>(), isNotEmpty);
      final cf = errors.whereType<ConnectionFailed>().first;
      expect(cf.reason, ConnectionFailedReason.timeout);
      expect(cf.address, _remoteAddress);
      expect(cf.port, 5004);
    });

    test('B2: control port NO emits ConnectionFailed rejected', () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      await controller.invite(_remoteAddress, 5004);
      await Future<void>.delayed(Duration.zero);

      final token = _extractToken(transport.controlSends.last.data);
      final no = createNo(
        initiatorToken: token,
        ssrc: _remoteSsrc,
        name: 'Remote',
      );
      transport.injectControl(no.encode());
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<ConnectionFailed>());
      final cf = errors[0] as ConnectionFailed;
      expect(cf.reason, ConnectionFailedReason.rejected);
    });

    test('B3: data port NO emits ConnectionFailed dataHandshakeFailed',
        () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      await controller.invite(_remoteAddress, 5004);
      await Future<void>.delayed(Duration.zero);

      // Control OK
      final token = _extractToken(transport.controlSends.last.data);
      transport.injectControl(createOk(
        initiatorToken: token,
        ssrc: _remoteSsrc,
        name: 'Remote',
      ).encode());
      await Future<void>.delayed(Duration.zero);

      // Data NO
      transport.injectData(createNo(
        initiatorToken: token,
        ssrc: _remoteSsrc,
        name: 'Remote',
      ).encode());
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<ConnectionFailed>());
      final cf = errors[0] as ConnectionFailed;
      expect(cf.reason, ConnectionFailedReason.dataHandshakeFailed);
    });
  });

  group('ProtocolViolation errors (C1-C3)', () {
    late MockTransport transport;
    late SessionController controller;

    setUp(() {
      transport = MockTransport();
      controller = _makeController(transport);
    });

    tearDown(() async {
      await controller.dispose();
      await transport.close();
    });

    test('C1: token mismatch on OK emits ProtocolViolation', () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      await controller.invite(_remoteAddress, 5004);
      await Future<void>.delayed(Duration.zero);

      // Send OK with wrong token
      final wrongOk = createOk(
        initiatorToken: 0x00000000, // wrong token
        ssrc: _remoteSsrc,
        name: 'Remote',
      );
      transport.injectControl(wrongOk.encode());
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<ProtocolViolation>());
      final pv = errors[0] as ProtocolViolation;
      expect(pv.reason, ProtocolViolationReason.tokenMismatch);
    });

    test('C2: sendMidi before ready emits ProtocolViolation', () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      // Controller is in idle state — sendMidi should emit error
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<ProtocolViolation>());
      final pv = errors[0] as ProtocolViolation;
      expect(pv.reason, ProtocolViolationReason.sendBeforeReady);
    });

    test('C3: clock sync timeout emits ProtocolViolation', () async {
      // Use a controller with a very short clock sync timeout.
      await controller.dispose();
      controller = SessionController(
        transport: transport,
        config: const RtpMidiConfig(
          name: 'TestLocal',
          maxInvitationRetries: 3,
          invitationRetryBaseInterval: Duration(milliseconds: 50),
          clockSyncTimeout: Duration(milliseconds: 50),
        ),
        localSsrc: _localSsrc,
      );

      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      await controller.invite(_remoteAddress, 5004);
      await Future<void>.delayed(Duration.zero);

      // Control OK
      final token = _extractToken(transport.controlSends.last.data);
      transport.injectControl(createOk(
        initiatorToken: token,
        ssrc: _remoteSsrc,
        name: 'Remote',
      ).encode());
      await Future<void>.delayed(Duration.zero);

      // Data OK (moves to connected, starts clock sync with 50ms timeout)
      transport.injectData(createOk(
        initiatorToken: token,
        ssrc: _remoteSsrc,
        name: 'Remote',
      ).encode());
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, SessionState.connected);

      // Wait for the 50ms clock sync timeout to fire.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final violations = errors.whereType<ProtocolViolation>().toList();
      expect(violations, isNotEmpty);
      expect(violations.first.reason, ProtocolViolationReason.clockSyncTimeout);
    });
  });

  group('PeerDisconnected (D1)', () {
    late MockTransport transport;
    late SessionController controller;

    setUp(() async {
      transport = MockTransport();
      controller = _makeController(transport);
      await _driveToReady(controller, transport);
    });

    tearDown(() async {
      await controller.dispose();
      await transport.close();
    });

    test('BYE received emits PeerDisconnected', () async {
      final errors = <SessionError>[];
      controller.onError.listen(errors.add);

      final bye = createBye(
        initiatorToken: 0,
        ssrc: _remoteSsrc,
        name: 'Remote',
      );
      transport.injectControl(bye.encode());
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<PeerDisconnected>());
      final pd = errors[0] as PeerDisconnected;
      expect(pd.reason, PeerDisconnectedReason.byeReceived);
      expect(pd.address, _remoteAddress);
    });
  });

  group('Errors do not interrupt normal flow', () {
    late MockTransport transport;
    late SessionController controller;

    setUp(() async {
      transport = MockTransport();
      controller = _makeController(transport);
      await _driveToReady(controller, transport);
    });

    tearDown(() async {
      await controller.dispose();
      await transport.close();
    });

    test('malformed packet followed by valid MIDI still delivers MIDI',
        () async {
      final errors = <SessionError>[];
      final midi = <MidiMessage>[];
      controller.onError.listen(errors.add);
      controller.onMidiMessage.listen(midi.add);

      // Inject malformed RTP (B flag set, too short)
      final bad = Uint8List(13);
      bad[0] = 0x80;
      bad[12] = 0x8F; // B flag, needs 2-byte header
      transport.injectData(bad);
      await Future<void>.delayed(Duration.zero);

      // Inject valid MIDI
      transport.injectData(_validRtpMidiPayload());
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors[0], isA<MalformedPacket>());
      expect(midi, hasLength(1));
      expect(midi[0], isA<NoteOn>());
    });

    test('session remains in ready state after malformed packet', () async {
      // Inject malformed RTP (B flag set, too short)
      final bad = Uint8List(13);
      bad[0] = 0x80;
      bad[12] = 0x8F;
      transport.injectData(bad);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, SessionState.ready);
    });
  });
}
