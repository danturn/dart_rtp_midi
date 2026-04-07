import 'dart:async';
import 'dart:typed_data';

import 'package:rtp_midi/src/api/midi_message.dart';
import 'package:rtp_midi/src/api/rtp_midi_config.dart';
import 'package:rtp_midi/src/rtp/midi_command_codec.dart';
import 'package:rtp_midi/src/rtp/rtp_header.dart';
import 'package:rtp_midi/src/rtp/rtp_midi_payload.dart';
import 'package:rtp_midi/src/session/session_controller.dart';
import 'package:rtp_midi/src/session/session_state.dart';
import 'package:rtp_midi/src/transport/transport.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock transport that records sent datagrams and allows injection.
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

  final List<SentDatagram> controlSends = [];
  final List<SentDatagram> dataSends = [];

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
  Future<void> bind() async {}

  @override
  Future<void> close() async {
    await _controlController.close();
    await _dataController.close();
  }

  void injectControlMessage(Uint8List data,
      {String address = '192.168.1.100', int port = 5004}) {
    _controlController.add(Datagram(data, address, port));
  }

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

void main() {
  group('MIDI roundtrip integration', () {
    late MockTransport transport;
    late SessionController controller;

    setUp(() {
      transport = MockTransport();
      controller = SessionController(
        transport: transport,
        config: const RtpMidiConfig(name: 'TestLocal'),
        localSsrc: 0x11111111,
      );
    });

    tearDown(() async {
      await controller.dispose();
      await transport.close();
    });

    /// Helper: drive the controller to the 'ready' state.
    Future<void> driveToReady() async {
      // Initiate outbound connection.
      await controller.invite('192.168.1.100', 5004);

      // Simulate receiving OK on control port (via control stream).
      // We need the controller to process this — but the controller
      // only listens on the transport streams. We'll inject via the
      // transport's internal controllers.

      // Instead, let's manually set up by accepting an invitation.
      // Reset by creating a new controller.
      await controller.dispose();

      transport = MockTransport();
      controller = SessionController(
        transport: transport,
        config: const RtpMidiConfig(name: 'TestLocal'),
        localSsrc: 0x11111111,
      );

      // Use a Completer to wait for the ready state.
      final readyCompleter = Completer<void>();
      controller.onStateChanged.listen((state) {
        if (state == SessionState.ready && !readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
      });

      // Start an outbound invitation.
      await controller.invite('192.168.1.100', 5004);

      // Simulate OK on control port.
      final okControlBytes = _buildOkPacket(
        initiatorToken:
            transport.controlSends.first.data.buffer.asByteData().getUint32(8),
        ssrc: 0x22222222,
        name: 'RemotePeer',
      );
      transport.injectControlMessage(okControlBytes);
      await Future.delayed(Duration.zero);

      // Simulate OK on data port.
      transport.injectDataMessage(okControlBytes);
      await Future.delayed(Duration.zero);

      // Simulate CK1 response to complete clock sync.
      // Find the CK0 that was sent.
      final ck0Send = transport.dataSends.firstWhere(
        (s) => s.data.length >= 36 && s.data[2] == 0x43 && s.data[3] == 0x4B,
      );
      final ck0View = ByteData.sublistView(ck0Send.data);
      final t1Hi = ck0View.getUint32(12);
      final t1Lo = ck0View.getUint32(16);

      // Build CK1 response.
      final ck1 = Uint8List(36);
      final ck1View = ByteData.sublistView(ck1);
      ck1View.setUint16(0, 0xFFFF);
      ck1View.setUint16(2, 0x434B);
      ck1View.setUint32(4, 0x22222222);
      ck1[8] = 1; // count = 1
      ck1View.setUint32(12, t1Hi);
      ck1View.setUint32(16, t1Lo);
      // t2 = current time (arbitrary for test)
      final now = DateTime.now().microsecondsSinceEpoch ~/ 100;
      ck1View.setUint32(20, (now >> 32) & 0xFFFFFFFF);
      ck1View.setUint32(24, now & 0xFFFFFFFF);

      transport.injectDataMessage(ck1);

      await readyCompleter.future.timeout(const Duration(seconds: 2));
      expect(controller.state, equals(SessionState.ready));
    }

    test('sendMidi produces valid RTP-MIDI bytes on transport', () async {
      await driveToReady();

      final initialDataSends = transport.dataSends.length;
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));

      // Should have one more data send.
      expect(transport.dataSends.length, equals(initialDataSends + 1));

      final sent = transport.dataSends.last;
      // The sent bytes should be a valid RTP-MIDI payload.
      final payload = RtpMidiPayload.decode(sent.data);
      expect(payload, isNotNull);
      expect(payload!.header.ssrc, equals(0x11111111));
      expect(payload.commands.length, equals(1));
      expect(payload.commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
    });

    test('injected RTP-MIDI bytes produce MIDI on stream', () async {
      await driveToReady();

      // Build an RTP-MIDI packet containing a CC message.
      const payload = RtpMidiPayload(
        header: RtpHeader(
          sequenceNumber: 99,
          timestamp: 5000,
          ssrc: 0x22222222,
        ),
        commands: [
          TimestampedMidiCommand(
              0, ControlChange(channel: 0, controller: 7, value: 100)),
        ],
      );

      final midiMessages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(midiMessages.add);

      transport.injectDataMessage(
        payload.encode(),
        address: '192.168.1.100',
      );
      await Future.delayed(Duration.zero);

      expect(midiMessages.length, equals(1));
      expect(midiMessages[0],
          equals(const ControlChange(channel: 0, controller: 7, value: 100)));

      await sub.cancel();
    });

    test('full send→receive roundtrip via transport', () async {
      await driveToReady();

      // Send a MIDI message.
      controller.sendMidi(const ProgramChange(channel: 9, program: 42));

      // The sent bytes on the wire.
      final sentBytes = transport.dataSends.last.data;

      // Now inject those same bytes back as if received from the remote peer.
      final midiMessages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(midiMessages.add);

      transport.injectDataMessage(sentBytes, address: '192.168.1.100');
      await Future.delayed(Duration.zero);

      // First received packet triggers late-join journal recovery (RFC 4695 §4).
      // The journal contains ProgramChange state, so recovery emits it before
      // the regular command. The last message is always the regular command.
      expect(midiMessages.last,
          equals(const ProgramChange(channel: 9, program: 42)));

      await sub.cancel();
    });

    test('sendMidi does nothing when not in active state', () {
      // Controller is in idle state.
      final initialSends = transport.dataSends.length;
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      expect(transport.dataSends.length, equals(initialSends));
    });

    test('sequence numbers increment', () async {
      await driveToReady();

      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      controller.sendMidi(const NoteOn(channel: 0, note: 72, velocity: 80));

      final sent1 = transport.dataSends[transport.dataSends.length - 2];
      final sent2 = transport.dataSends.last;

      final payload1 = RtpMidiPayload.decode(sent1.data)!;
      final payload2 = RtpMidiPayload.decode(sent2.data)!;

      expect(payload2.header.sequenceNumber,
          equals(payload1.header.sequenceNumber + 1));
    });
  });
}

/// Build a minimal OK exchange packet for testing.
Uint8List _buildOkPacket({
  required int initiatorToken,
  required int ssrc,
  required String name,
}) {
  final nameBytes = name.codeUnits;
  final length = 16 + nameBytes.length + 1;
  final data = Uint8List(length);
  final view = ByteData.sublistView(data);
  view.setUint16(0, 0xFFFF); // signature
  view.setUint16(2, 0x4F4B); // OK
  view.setUint32(4, 2); // protocol version
  view.setUint32(8, initiatorToken);
  view.setUint32(12, ssrc);
  data.setRange(16, 16 + nameBytes.length, nameBytes);
  data[16 + nameBytes.length] = 0; // NUL
  return data;
}
