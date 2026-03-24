import 'dart:async';
import 'dart:typed_data';

import 'package:dart_rtp_midi/src/api/midi_message.dart';
import 'package:dart_rtp_midi/src/api/rtp_midi_config.dart';
import 'package:dart_rtp_midi/src/rtp/journal/journal_header.dart';
import 'package:dart_rtp_midi/src/rtp/journal/channel_journal.dart';
import 'package:dart_rtp_midi/src/rtp/midi_command_codec.dart';
import 'package:dart_rtp_midi/src/rtp/rtp_header.dart';
import 'package:dart_rtp_midi/src/rtp/rtp_midi_payload.dart';
import 'package:dart_rtp_midi/src/session/session_controller.dart';
import 'package:dart_rtp_midi/src/session/session_state.dart';
import 'package:dart_rtp_midi/src/transport/transport.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock transport (same pattern as midi_roundtrip_test.dart)
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

Uint8List _buildOkPacket({
  required int initiatorToken,
  required int ssrc,
  required String name,
}) {
  final nameBytes = name.codeUnits;
  final length = 16 + nameBytes.length + 1;
  final data = Uint8List(length);
  final view = ByteData.sublistView(data);
  view.setUint16(0, 0xFFFF);
  view.setUint16(2, 0x4F4B);
  view.setUint32(4, 2);
  view.setUint32(8, initiatorToken);
  view.setUint32(12, ssrc);
  data.setRange(16, 16 + nameBytes.length, nameBytes);
  data[16 + nameBytes.length] = 0;
  return data;
}

void main() {
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

  Future<void> driveToReady() async {
    final readyCompleter = Completer<void>();
    controller.onStateChanged.listen((state) {
      if (state == SessionState.ready && !readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
    });

    await controller.invite('192.168.1.100', 5004);

    final okControlBytes = _buildOkPacket(
      initiatorToken:
          transport.controlSends.first.data.buffer.asByteData().getUint32(8),
      ssrc: 0x22222222,
      name: 'RemotePeer',
    );
    transport.injectControlMessage(okControlBytes);
    await Future.delayed(Duration.zero);

    transport.injectDataMessage(okControlBytes);
    await Future.delayed(Duration.zero);

    final ck0Send = transport.dataSends.firstWhere(
      (s) => s.data.length >= 36 && s.data[2] == 0x43 && s.data[3] == 0x4B,
    );
    final ck0View = ByteData.sublistView(ck0Send.data);
    final t1Hi = ck0View.getUint32(12);
    final t1Lo = ck0View.getUint32(16);

    final ck1 = Uint8List(36);
    final ck1View = ByteData.sublistView(ck1);
    ck1View.setUint16(0, 0xFFFF);
    ck1View.setUint16(2, 0x434B);
    ck1View.setUint32(4, 0x22222222);
    ck1[8] = 1;
    ck1View.setUint32(12, t1Hi);
    ck1View.setUint32(16, t1Lo);
    final now = DateTime.now().microsecondsSinceEpoch ~/ 100;
    ck1View.setUint32(20, (now >> 32) & 0xFFFFFFFF);
    ck1View.setUint32(24, now & 0xFFFFFFFF);

    transport.injectDataMessage(ck1);
    await readyCompleter.future.timeout(const Duration(seconds: 2));
  }

  // -------------------------------------------------------------------------
  // Step 6: Send-side journal integration
  // -------------------------------------------------------------------------
  group('Send-side journal', () {
    test('sendMidi sets J=1 flag in outgoing packets', () async {
      await driveToReady();
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));

      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      expect(payload.hasJournal, isTrue);
    });

    test('outgoing packet contains valid journal bytes', () async {
      await driveToReady();
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));

      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      expect(payload.journalData, isNotNull);

      // Decode the journal header.
      final header = JournalHeader.decode(payload.journalData!);
      expect(header, isNotNull);
      expect(header!.channelJournalsPresent, isTrue);
      expect(header.singlePacketLoss, isTrue);
      expect(header.systemJournalPresent, isFalse);
    });

    test('journal checkpoint seqnum matches first packet sent', () async {
      await driveToReady();

      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      final firstPayload =
          RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final firstSeq = firstPayload.header.sequenceNumber;
      final firstJournalHeader =
          JournalHeader.decode(firstPayload.journalData!)!;
      expect(firstJournalHeader.checkpointSeqNum, firstSeq);

      // Second packet should have same checkpoint.
      controller.sendMidi(const NoteOn(channel: 0, note: 64, velocity: 80));
      final secondPayload =
          RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final secondJournalHeader =
          JournalHeader.decode(secondPayload.journalData!)!;
      expect(secondJournalHeader.checkpointSeqNum, firstSeq);
    });

    test('journal accumulates state across messages', () async {
      await driveToReady();

      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      controller.sendMidi(const NoteOn(channel: 0, note: 64, velocity: 80));

      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final header = JournalHeader.decode(payload.journalData!)!;
      expect(header.totalChannels, 0); // 1 channel

      final ch =
          ChannelJournal.decode(payload.journalData!, JournalHeader.size)!.$1;
      expect(ch.channel, 0);
      expect(ch.chapterN, isNotNull);
      expect(ch.chapterN!.logs.length, 2); // both notes active
    });

    test('journal includes chapters P, C, W, N, T, A as needed', () async {
      await driveToReady();

      controller.sendMidi(const ProgramChange(channel: 0, program: 42));
      controller
          .sendMidi(const ControlChange(channel: 0, controller: 7, value: 100));
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      controller.sendMidi(const PitchBend(channel: 0, value: 8192));
      controller.sendMidi(const ChannelAftertouch(channel: 0, pressure: 50));
      controller
          .sendMidi(const PolyAftertouch(channel: 0, note: 60, pressure: 40));

      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final ch =
          ChannelJournal.decode(payload.journalData!, JournalHeader.size)!.$1;
      expect(ch.chapterP, isNotNull);
      expect(ch.chapterC, isNotNull);
      expect(ch.chapterN, isNotNull);
      expect(ch.chapterW, isNotNull);
      expect(ch.chapterT, isNotNull);
      expect(ch.chapterA, isNotNull);
    });

    test('NoteOff moves note from log to offbit bitmap', () async {
      await driveToReady();

      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      controller
          .sendMidi(const ControlChange(channel: 0, controller: 7, value: 80));
      controller.sendMidi(const NoteOff(channel: 0, note: 60, velocity: 0));

      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final ch =
          ChannelJournal.decode(payload.journalData!, JournalHeader.size)!.$1;
      // Note 60 should be in offbit bitmap, not in note logs.
      expect(ch.chapterN, isNotNull);
      expect(ch.chapterN!.logs, isEmpty);
      expect(ch.chapterN!.b, isTrue);
      expect(ch.chapterN!.offBits, isNotNull);
      expect(ch.chapterC, isNotNull);
    });

    test('multiple channels appear in journal', () async {
      await driveToReady();

      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      controller.sendMidi(const NoteOn(channel: 9, note: 36, velocity: 127));

      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final header = JournalHeader.decode(payload.journalData!)!;
      expect(header.totalChannels, 1); // 2 channels - 1
    });

    test('journal Y=0 (no system journal), A=1 (channel journals)', () async {
      await driveToReady();
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));

      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final header = JournalHeader.decode(payload.journalData!)!;
      expect(header.systemJournalPresent, isFalse);
      expect(header.channelJournalsPresent, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Step 7: Receive-side journal recovery
  // -------------------------------------------------------------------------
  group('Receive-side journal recovery', () {
    test('no recovery on sequential packets', () async {
      await driveToReady();

      final messages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(messages.add);

      // Send two sequential packets
      _injectRtpMidi(transport,
          seqNum: 100,
          message: const NoteOn(channel: 0, note: 60, velocity: 100));
      await Future.delayed(Duration.zero);

      _injectRtpMidi(transport,
          seqNum: 101,
          message: const NoteOn(channel: 0, note: 64, velocity: 80));
      await Future.delayed(Duration.zero);

      // Should get exactly 2 messages, no extra recovery
      expect(messages.length, 2);
      expect(messages[0], const NoteOn(channel: 0, note: 60, velocity: 100));
      expect(messages[1], const NoteOn(channel: 0, note: 64, velocity: 80));

      await sub.cancel();
    });

    test('gap without journal does not crash', () async {
      await driveToReady();

      final messages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(messages.add);

      _injectRtpMidi(transport,
          seqNum: 100,
          message: const NoteOn(channel: 0, note: 60, velocity: 100));
      await Future.delayed(Duration.zero);

      // Skip seqNum 101, inject 102 without journal
      _injectRtpMidi(transport,
          seqNum: 102,
          message: const NoteOn(channel: 0, note: 64, velocity: 80));
      await Future.delayed(Duration.zero);

      expect(messages.length, 2);
      await sub.cancel();
    });

    test('gap with journal emits corrective NoteOn for stuck note', () async {
      await driveToReady();

      final messages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(messages.add);

      // First packet: seqNum=100, NoteOn 60
      _injectRtpMidi(transport,
          seqNum: 100,
          message: const NoteOn(channel: 0, note: 60, velocity: 100));
      await Future.delayed(Duration.zero);

      // Simulate: sender also sent NoteOn 64 in packet 101 (lost) and
      // NoteOn 67 in packet 102. Journal reflects notes 60, 64, 67 active.
      // Build a journal that knows about notes 60, 64, 67 from sender perspective.
      final journalBytes = _buildNoteJournal(
        checkpointSeqNum: 100,
        channel: 0,
        notes: {60: 100, 64: 80, 67: 90},
      );

      // Inject packet 102 (gap: 101 missing) with journal
      _injectRtpMidiWithJournal(
        transport,
        seqNum: 102,
        message: const NoteOn(channel: 0, note: 67, velocity: 90),
        journalData: journalBytes,
      );
      await Future.delayed(Duration.zero);

      // messages[0] = NoteOn 60 (from packet 100)
      // messages[1] = corrective NoteOn 64 (recovery, since receiver didn't have it)
      // messages[2] = NoteOn 67 (from packet 102, regular command)
      // Note: corrective NoteOn 60 is a no-op since receiver already has it,
      //       but corrective NoteOn 67 velocity matches what will be set, so
      //       it may or may not appear before the regular command.
      // Let's check that note 64 was recovered:
      expect(
        messages.any((m) =>
            m is NoteOn && m.channel == 0 && m.note == 64 && m.velocity == 80),
        isTrue,
        reason: 'Should have recovered NoteOn for note 64',
      );

      await sub.cancel();
    });

    test('gap with journal emits corrective NoteOff for orphan note', () async {
      await driveToReady();

      final messages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(messages.add);

      // Receiver gets NoteOn 60 (packet 100)
      _injectRtpMidi(transport,
          seqNum: 100,
          message: const NoteOn(channel: 0, note: 60, velocity: 100));
      await Future.delayed(Duration.zero);

      // Sender sent NoteOff 60 in lost packet 101, then CC in packet 102.
      // Journal shows no active notes, just CC7=80.
      final journalBytes = _buildCcJournal(
        checkpointSeqNum: 100,
        channel: 0,
        controllers: {7: 80},
      );

      _injectRtpMidiWithJournal(
        transport,
        seqNum: 102,
        message: const ControlChange(channel: 0, controller: 7, value: 80),
        journalData: journalBytes,
      );
      await Future.delayed(Duration.zero);

      // The journal has no Chapter N — the sender has no active notes.
      // Recovery should emit NoteOff for the orphan note 60.
      expect(
          messages.any((m) => m is NoteOff && m.channel == 0 && m.note == 60),
          isTrue,
          reason: 'Should emit NoteOff for orphan note 60');
      expect(
          messages.any((m) => m is ControlChange && m.controller == 7), isTrue);

      await sub.cancel();
    });

    test('gap with journal emits corrective CC', () async {
      await driveToReady();

      final messages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(messages.add);

      // Packet 100: initial state
      _injectRtpMidi(transport,
          seqNum: 100,
          message: const NoteOn(channel: 0, note: 60, velocity: 100));
      await Future.delayed(Duration.zero);

      // Packet 101 lost (had CC7=80). Packet 102 has CC11=50, journal has
      // both CC7=80 and CC11=50 and note 60.
      final journalBytes = _buildMixedJournal(
        checkpointSeqNum: 100,
        channel: 0,
        notes: {60: 100},
        controllers: {7: 80, 11: 50},
      );

      _injectRtpMidiWithJournal(
        transport,
        seqNum: 102,
        message: const ControlChange(channel: 0, controller: 11, value: 50),
        journalData: journalBytes,
      );
      await Future.delayed(Duration.zero);

      // Should have recovered CC7=80 from journal
      expect(
        messages.any(
            (m) => m is ControlChange && m.controller == 7 && m.value == 80),
        isTrue,
        reason: 'Should have recovered CC7=80',
      );

      await sub.cancel();
    });

    test('recovery messages come before regular commands', () async {
      await driveToReady();

      final messages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(messages.add);

      _injectRtpMidi(transport,
          seqNum: 100,
          message: const NoteOn(channel: 0, note: 60, velocity: 100));
      await Future.delayed(Duration.zero);

      // Build journal with CC7=80, inject with regular CC11=50
      final journalBytes = _buildMixedJournal(
        checkpointSeqNum: 100,
        channel: 0,
        notes: {60: 100},
        controllers: {7: 80},
      );

      _injectRtpMidiWithJournal(
        transport,
        seqNum: 102, // gap: 101 missing
        message: const ControlChange(channel: 0, controller: 11, value: 50),
        journalData: journalBytes,
      );
      await Future.delayed(Duration.zero);

      // Find the CC7 (recovery) and CC11 (regular) messages
      final cc7Idx =
          messages.indexWhere((m) => m is ControlChange && m.controller == 7);
      final cc11Idx =
          messages.indexWhere((m) => m is ControlChange && m.controller == 11);
      expect(cc7Idx, greaterThanOrEqualTo(0));
      expect(cc11Idx, greaterThan(cc7Idx),
          reason: 'Recovery CC7 should come before regular CC11');

      await sub.cancel();
    });
  });

  // -------------------------------------------------------------------------
  // Step 8: End-to-end scenario tests
  // -------------------------------------------------------------------------
  group('End-to-end recovery scenarios', () {
    test('stuck note recovery: NoteOn lost, journal fixes it', () async {
      await driveToReady();

      final messages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(messages.add);

      // Receiver gets nothing initially (packet 100 with NoteOn lost).
      // Packet 101 arrives with CC7=100, journal shows note 60 active + CC7.
      final journalBytes = _buildMixedJournal(
        checkpointSeqNum: 100,
        channel: 0,
        notes: {60: 100},
        controllers: {7: 100},
      );

      // First packet the receiver sees is 101 (no gap for first packet)
      _injectRtpMidiWithJournal(
        transport,
        seqNum: 101,
        message: const ControlChange(channel: 0, controller: 7, value: 100),
        journalData: journalBytes,
      );
      await Future.delayed(Duration.zero);

      // First packet is never a gap, so no recovery. Just the CC.
      expect(messages.length, 1);
      expect(messages[0],
          const ControlChange(channel: 0, controller: 7, value: 100));

      // Now packet 103 arrives (102 lost), journal still has note 60 + CC7
      _injectRtpMidiWithJournal(
        transport,
        seqNum: 103,
        message: const ControlChange(channel: 0, controller: 11, value: 50),
        journalData: journalBytes,
      );
      await Future.delayed(Duration.zero);

      // Gap detected (102 missing). Recovery should emit NoteOn 60.
      expect(
        messages.any((m) => m is NoteOn && m.note == 60 && m.velocity == 100),
        isTrue,
        reason: 'Should recover stuck NoteOn 60',
      );

      await sub.cancel();
    });

    test('controller value recovery across loss event', () async {
      await driveToReady();

      final messages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(messages.add);

      // Packet 100: CC7=50
      _injectRtpMidi(transport,
          seqNum: 100,
          message: const ControlChange(channel: 0, controller: 7, value: 50));
      await Future.delayed(Duration.zero);

      // Packet 101 (lost): CC7=100
      // Packet 102 arrives with CC11=80, journal has CC7=100 + CC11=80
      final journalBytes = _buildCcJournal(
        checkpointSeqNum: 100,
        channel: 0,
        controllers: {7: 100, 11: 80},
      );

      _injectRtpMidiWithJournal(
        transport,
        seqNum: 102,
        message: const ControlChange(channel: 0, controller: 11, value: 80),
        journalData: journalBytes,
      );
      await Future.delayed(Duration.zero);

      // Recovery should fix CC7 from 50 to 100
      expect(
        messages.any(
            (m) => m is ControlChange && m.controller == 7 && m.value == 100),
        isTrue,
        reason: 'Should recover CC7=100',
      );

      await sub.cancel();
    });

    test('send-side journal is decodable by Wireshark-compatible parser',
        () async {
      await driveToReady();

      // Send a mix of messages
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      controller
          .sendMidi(const ControlChange(channel: 0, controller: 7, value: 80));
      controller.sendMidi(const ProgramChange(channel: 0, program: 42));

      // Get the last packet
      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      expect(payload.hasJournal, isTrue);

      final journalData = payload.journalData!;
      // Verify full decode through standard codec path
      final header = JournalHeader.decode(journalData)!;
      expect(header.channelJournalsPresent, isTrue);
      expect(header.totalChannels, 0); // 1 channel

      const offset = JournalHeader.size;
      final (ch0, _) = ChannelJournal.decode(journalData, offset)!;
      expect(ch0.channel, 0);
      expect(ch0.chapterP!.program, 42);
      expect(ch0.chapterC, isNotNull);
      expect(ch0.chapterN!.logs.length, 1);
      expect(ch0.chapterN!.logs[0].noteNum, 60);
    });

    test('full packet byte-level Wireshark dissector walkthrough', () async {
      await driveToReady();

      // Send NoteOn, CC, ProgramChange — covers chapters N, C, P.
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      controller
          .sendMidi(const ControlChange(channel: 0, controller: 7, value: 80));
      controller.sendMidi(const ProgramChange(channel: 0, program: 42));

      // Get the raw bytes that went on the wire.
      final wireBytes = transport.dataSends.last.data;

      // === RTP Header (12 bytes) ===
      // Wireshark RTP dissector parses this before handing to RTP-MIDI.
      // Byte 0: V=2(2b) P=0(1b) X=0(1b) CC=0(4b) → 0x80
      expect(wireBytes[0], 0x80);
      // Byte 1: M=0(1b) PT=97(7b) → 0x61
      expect(wireBytes[1], 0x61);
      // Bytes 2-3: sequence number (uint16, varies)
      // Bytes 4-7: timestamp (uint32, varies)
      // Bytes 8-11: SSRC = 0x11111111
      final ssrc = ByteData.sublistView(wireBytes).getUint32(8);
      expect(ssrc, 0x11111111);

      // === MIDI Command Section Header (offset 12) ===
      // Wireshark dissect_rtp_midi starts here (after RTP header is stripped).
      final midiFlags = wireBytes[12];
      // B flag: check if short or long header
      final bFlag = (midiFlags & 0x80) != 0;
      // J flag: journal present
      expect(midiFlags & 0x40, 0x40, reason: 'J flag must be set');
      // Z flag: 0 (first command has no delta time)
      expect(midiFlags & 0x20, 0, reason: 'Z flag should be 0');
      // P flag: 0 (no phantom/running status)
      expect(midiFlags & 0x10, 0, reason: 'P flag should be 0');

      int cmdLen;
      int journalOffset;
      if (bFlag) {
        // Long header: cmd_len = tvb_get_ntohs(tvb, offset) & 0x0fff
        cmdLen = (ByteData.sublistView(wireBytes).getUint16(12)) & 0x0FFF;
        journalOffset = 14 + cmdLen;
      } else {
        // Short header: cmd_len = flags & 0x0f
        cmdLen = midiFlags & 0x0F;
        journalOffset = 13 + cmdLen;
      }

      // Command data should contain a ProgramChange (last sent message).
      // (The packet only contains the single command from sendMidi.)
      expect(cmdLen, greaterThan(0), reason: 'Should have MIDI command data');

      // === Journal Section ===
      // Wireshark: if (flags & RTP_MIDI_CS_FLAG_J) → parse journal
      final journalBytes = wireBytes.sublist(journalOffset);

      // Journal header (3 bytes):
      // flags = tvb_get_uint8(tvb, offset)
      final jFlags = journalBytes[0];
      // S flag (0x80): should be set
      expect(jFlags & 0x80, 0x80, reason: 'Journal S flag must be set');
      // Y flag (0x40): no system journal
      expect(jFlags & 0x40, 0, reason: 'Y flag must be 0 (no system journal)');
      // A flag (0x20): channel journals present
      expect(jFlags & 0x20, 0x20, reason: 'A flag must be set');
      // H flag (0x10): no enhanced chapter C
      expect(jFlags & 0x10, 0, reason: 'H flag should be 0');
      // TOTCHAN (0x0F): 0 (one channel journal)
      final totchan = jFlags & 0x0F;
      expect(totchan, 0, reason: 'TOTCHAN should be 0 (one channel)');

      // Checkpoint seqnum (2 bytes)
      final checkpointSeq = ByteData.sublistView(journalBytes).getUint16(1);
      expect(checkpointSeq, greaterThan(0));

      // Wireshark: for (i = 0; i <= totchan; i++) { decode_channel_journal }
      // Channel journal header (3 bytes, offset 3 in journal)
      final cjByte0 = journalBytes[3];
      final cjChannel = (cjByte0 >> 3) & 0x0F;
      expect(cjChannel, 0, reason: 'Channel should be 0');

      final cjLength = ((cjByte0 & 0x03) << 8) | journalBytes[4];
      expect(cjLength, greaterThan(3),
          reason: 'Channel journal must have content');

      // Chapter presence flags
      final chapterFlags = journalBytes[5];
      expect(chapterFlags & 0x80, 0x80, reason: 'P flag (program) set');
      expect(chapterFlags & 0x40, 0x40, reason: 'C flag (controller) set');
      expect(chapterFlags & 0x08, 0x08, reason: 'N flag (notes) set');

      // Verify the total journal bytes don't exceed the packet.
      expect(journalOffset + journalBytes.length, wireBytes.length,
          reason: 'Journal should extend to end of packet');

      // Verify our codec can roundtrip the journal section.
      final header = JournalHeader.decode(Uint8List.fromList(journalBytes))!;
      expect(header.totalChannels, totchan);
      final (ch, _) = ChannelJournal.decode(
          Uint8List.fromList(journalBytes), JournalHeader.size)!;
      expect(ch.chapterP!.program, 42);
      expect(ch.chapterN!.logs.length, 1);
      expect(ch.chapterN!.logs[0].noteNum, 60);
    });

    test('no recovery on first packet (even with journal)', () async {
      await driveToReady();

      final messages = <MidiMessage>[];
      final sub = controller.onMidiMessage.listen(messages.add);

      // First packet with journal — should NOT trigger recovery
      final journalBytes = _buildNoteJournal(
        checkpointSeqNum: 50,
        channel: 0,
        notes: {60: 100, 64: 80},
      );

      _injectRtpMidiWithJournal(
        transport,
        seqNum: 100,
        message: const NoteOn(channel: 0, note: 67, velocity: 90),
        journalData: journalBytes,
      );
      await Future.delayed(Duration.zero);

      // Only the regular command, no recovery
      expect(messages.length, 1);
      expect(messages[0], const NoteOn(channel: 0, note: 67, velocity: 90));

      await sub.cancel();
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers to build and inject RTP-MIDI packets
// ---------------------------------------------------------------------------

void _injectRtpMidi(
  MockTransport transport, {
  required int seqNum,
  required MidiMessage message,
}) {
  final payload = RtpMidiPayload(
    header: RtpHeader(
      sequenceNumber: seqNum,
      timestamp: seqNum * 100,
      ssrc: 0x22222222,
    ),
    commands: [TimestampedMidiCommand(0, message)],
  );
  transport.injectDataMessage(payload.encode(), address: '192.168.1.100');
}

void _injectRtpMidiWithJournal(
  MockTransport transport, {
  required int seqNum,
  required MidiMessage message,
  required Uint8List journalData,
}) {
  final payload = RtpMidiPayload(
    header: RtpHeader(
      sequenceNumber: seqNum,
      timestamp: seqNum * 100,
      ssrc: 0x22222222,
    ),
    commands: [TimestampedMidiCommand(0, message)],
    hasJournal: true,
    journalData: journalData,
  );
  transport.injectDataMessage(payload.encode(), address: '192.168.1.100');
}

/// Build journal bytes containing only Chapter N (active notes) for one channel.
Uint8List _buildNoteJournal({
  required int checkpointSeqNum,
  required int channel,
  required Map<int, int> notes,
}) {
  final chapterN = _encodeChapterN(notes);
  return _buildSingleChannelJournal(
    checkpointSeqNum: checkpointSeqNum,
    channel: channel,
    chapterN: chapterN,
  );
}

/// Build journal bytes containing only Chapter C (controllers) for one channel.
Uint8List _buildCcJournal({
  required int checkpointSeqNum,
  required int channel,
  required Map<int, int> controllers,
}) {
  final chapterC = _encodeChapterC(controllers);
  return _buildSingleChannelJournal(
    checkpointSeqNum: checkpointSeqNum,
    channel: channel,
    chapterC: chapterC,
  );
}

/// Build journal with both notes and controllers for one channel.
Uint8List _buildMixedJournal({
  required int checkpointSeqNum,
  required int channel,
  Map<int, int>? notes,
  Map<int, int>? controllers,
}) {
  final chapterN = notes != null ? _encodeChapterN(notes) : null;
  final chapterC = controllers != null ? _encodeChapterC(controllers) : null;
  return _buildSingleChannelJournal(
    checkpointSeqNum: checkpointSeqNum,
    channel: channel,
    chapterC: chapterC,
    chapterN: chapterN,
  );
}

Uint8List _buildSingleChannelJournal({
  required int checkpointSeqNum,
  required int channel,
  Uint8List? chapterC,
  Uint8List? chapterN,
}) {
  // Channel journal header: 3 bytes
  // S=1, CHAN, H=0, LENGTH, chapter flags
  final channelContentSize =
      3 + (chapterC?.length ?? 0) + (chapterN?.length ?? 0);

  final channelHeader = Uint8List(3);
  // Byte 0: S(1) CHAN(4) H(1) LENGTH[9:8](2)
  channelHeader[0] = 0x80 | // S=1
      ((channel & 0x0F) << 3) | // CHAN
      ((channelContentSize >> 8) & 0x03); // LENGTH high bits
  // Byte 1: LENGTH[7:0]
  channelHeader[1] = channelContentSize & 0xFF;
  // Byte 2: P C M W N E T A flags
  int flags = 0;
  if (chapterC != null) flags |= 0x40; // C bit
  if (chapterN != null) flags |= 0x08; // N bit
  channelHeader[2] = flags;

  // Journal header: 3 bytes
  final header = JournalHeader(
    singlePacketLoss: true,
    channelJournalsPresent: true,
    totalChannels: 0,
    checkpointSeqNum: checkpointSeqNum,
  );
  final headerBytes = header.encode();

  // Assemble
  final totalSize = headerBytes.length +
      channelHeader.length +
      (chapterC?.length ?? 0) +
      (chapterN?.length ?? 0);
  final result = Uint8List(totalSize);
  var offset = 0;
  result.setRange(offset, offset + headerBytes.length, headerBytes);
  offset += headerBytes.length;
  result.setRange(offset, offset + channelHeader.length, channelHeader);
  offset += channelHeader.length;
  if (chapterC != null) {
    result.setRange(offset, offset + chapterC.length, chapterC);
    offset += chapterC.length;
  }
  if (chapterN != null) {
    result.setRange(offset, offset + chapterN.length, chapterN);
    offset += chapterN.length;
  }
  return result;
}

/// Encode Chapter N: header (2 bytes) + note logs.
Uint8List _encodeChapterN(Map<int, int> notes) {
  final logCount = notes.length;
  final data = Uint8List(2 + logCount * 2);
  // Header: B=0, LEN=logCount
  data[0] = logCount & 0x7F;
  // LOW=15, HIGH=0 (no offbits)
  data[1] = 0xF0;
  var i = 0;
  for (final entry in notes.entries) {
    // S=1, noteNum
    data[2 + i * 2] = 0x80 | (entry.key & 0x7F);
    // Y=1 (active), velocity
    data[2 + i * 2 + 1] = 0x80 | (entry.value & 0x7F);
    i++;
  }
  return data;
}

/// Encode Chapter C: header (1 byte) + controller logs.
Uint8List _encodeChapterC(Map<int, int> controllers) {
  final logCount = controllers.length;
  final data = Uint8List(1 + logCount * 2);
  // Header: S=1, LEN=logCount-1
  data[0] = 0x80 | ((logCount - 1) & 0x7F);
  var i = 0;
  for (final entry in controllers.entries) {
    data[1 + i * 2] = 0x80 | (entry.key & 0x7F);
    data[1 + i * 2 + 1] = entry.value & 0x7F;
    i++;
  }
  return data;
}
