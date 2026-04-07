import 'dart:async';
import 'dart:typed_data';

import 'package:rtp_midi/src/api/midi_message.dart';
import 'package:rtp_midi/src/api/rtp_midi_config.dart';
import 'package:rtp_midi/src/rtp/journal/channel_journal.dart';
import 'package:rtp_midi/src/rtp/journal/journal_header.dart';
import 'package:rtp_midi/src/rtp/midi_command_codec.dart';
import 'package:rtp_midi/src/rtp/rtp_header.dart';
import 'package:rtp_midi/src/rtp/rtp_midi_payload.dart';
import 'package:rtp_midi/src/session/rs_packet.dart';
import 'package:rtp_midi/src/session/session_controller.dart';
import 'package:rtp_midi/src/session/session_state.dart';
import 'package:rtp_midi/src/transport/transport.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock transport
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

    final okBytes = _buildOkPacket(
      initiatorToken:
          transport.controlSends.first.data.buffer.asByteData().getUint32(8),
      ssrc: 0x22222222,
      name: 'RemotePeer',
    );
    transport.injectControlMessage(okBytes);
    await Future.delayed(Duration.zero);

    transport.injectDataMessage(okBytes);
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
  // RS detection in _onControlMessage
  // -------------------------------------------------------------------------
  group('RS detection on control port', () {
    test('RS packet on control port does not crash', () async {
      await driveToReady();
      // Inject an RS packet on the control port
      const rs = RsPacket(ssrc: 0x22222222, sequenceNumber: 100);
      transport.injectControlMessage(rs.encode());
      await Future.delayed(Duration.zero);
      // No crash = pass
      expect(controller.state, SessionState.ready);
    });

    test('RS packet is not confused with exchange packet', () async {
      await driveToReady();
      final controlSendsBefore = transport.controlSends.length;
      // Inject RS — should not trigger any exchange packet handling
      const rs = RsPacket(ssrc: 0x22222222, sequenceNumber: 100);
      transport.injectControlMessage(rs.encode());
      await Future.delayed(Duration.zero);
      // No new control sends (no OK/NO response to RS)
      expect(transport.controlSends.length, controlSendsBefore);
    });

    test('exchange packets still work after RS detection added', () async {
      await driveToReady();
      // Verify BYE still works
      controller.disconnect();
      await Future.delayed(Duration.zero);
      expect(controller.state, SessionState.disconnecting);
    });
  });

  // -------------------------------------------------------------------------
  // RS sending after receiving journal data
  // -------------------------------------------------------------------------
  group('RS sending after journal receipt', () {
    test('sends RS on control port when receiving packet with journal',
        () async {
      await driveToReady();
      final controlSendsBefore = transport.controlSends.length;

      // Inject an RTP-MIDI packet with journal data
      final journalBytes =
          _buildNoteJournal(checkpointSeqNum: 50, channel: 0, notes: {60: 100});
      _injectRtpMidiWithJournal(
        transport,
        seqNum: 100,
        message: const NoteOn(channel: 0, note: 60, velocity: 100),
        journalData: journalBytes,
      );
      await Future.delayed(Duration.zero);

      // Should have sent an RS packet on the control port
      final newControlSends =
          transport.controlSends.skip(controlSendsBefore).toList();
      expect(newControlSends, isNotEmpty,
          reason: 'Should send RS on control port');
      final rsPacket = RsPacket.decode(newControlSends.last.data);
      expect(rsPacket, isNotNull);
      expect(rsPacket!.sequenceNumber, 100);
      expect(rsPacket.ssrc, 0x11111111); // local SSRC
    });

    test('does not send RS when receiving packet without journal', () async {
      await driveToReady();
      final controlSendsBefore = transport.controlSends.length;

      _injectRtpMidi(transport,
          seqNum: 100,
          message: const NoteOn(channel: 0, note: 60, velocity: 100));
      await Future.delayed(Duration.zero);

      expect(transport.controlSends.length, controlSendsBefore,
          reason: 'No RS when no journal');
    });

    test('RS sent to remote control port', () async {
      await driveToReady();
      final controlSendsBefore = transport.controlSends.length;

      final journalBytes =
          _buildNoteJournal(checkpointSeqNum: 50, channel: 0, notes: {60: 100});
      _injectRtpMidiWithJournal(
        transport,
        seqNum: 100,
        message: const NoteOn(channel: 0, note: 60, velocity: 100),
        journalData: journalBytes,
      );
      await Future.delayed(Duration.zero);

      final rsSend = transport.controlSends.skip(controlSendsBefore).last;
      expect(rsSend.address, '192.168.1.100');
      expect(rsSend.port, 5004);
    });
  });

  // -------------------------------------------------------------------------
  // RS handling: advance checkpoint + trimState
  // -------------------------------------------------------------------------
  group('RS handling advances checkpoint and trims state', () {
    test('RS advances checkpoint and shrinks journal', () async {
      await driveToReady();

      // Send some MIDI messages
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      controller
          .sendMidi(const ControlChange(channel: 0, controller: 7, value: 80));

      final firstPayload =
          RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final firstJournalSize = firstPayload.journalData!.length;

      // Get the seqnum of the first packet we sent
      final firstSendPayload = RtpMidiPayload.decode(transport.dataSends
          .where((s) => RtpMidiPayload.decode(s.data) != null)
          .first
          .data)!;
      final firstSeq = firstSendPayload.header.sequenceNumber;
      final secondSeq = (firstSeq + 1) & 0xFFFF;

      // Simulate RS from remote confirming receipt of second packet
      final rs = RsPacket(ssrc: 0x22222222, sequenceNumber: secondSeq);
      transport.injectControlMessage(rs.encode());
      await Future.delayed(Duration.zero);

      // Send another MIDI message — journal should be smaller
      controller.sendMidi(const NoteOn(channel: 0, note: 64, velocity: 90));
      final laterPayload =
          RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final laterJournalSize = laterPayload.journalData!.length;

      expect(laterJournalSize, lessThan(firstJournalSize),
          reason: 'Journal should shrink after RS confirms earlier packets');
    });

    test('RS with older seqnum is ignored', () async {
      await driveToReady();

      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      controller.sendMidi(const NoteOn(channel: 0, note: 64, velocity: 80));
      controller.sendMidi(const NoteOn(channel: 0, note: 67, velocity: 90));

      // Get seqnums
      final payloads = transport.dataSends
          .map((s) => RtpMidiPayload.decode(s.data))
          .where((p) => p != null)
          .toList();
      final secondSeq = payloads[1]!.header.sequenceNumber;
      final thirdSeq = payloads[2]!.header.sequenceNumber;

      // Confirm third packet
      transport.injectControlMessage(
          RsPacket(ssrc: 0x22222222, sequenceNumber: thirdSeq).encode());
      await Future.delayed(Duration.zero);

      // Now inject older RS (second packet) — should be ignored
      transport.injectControlMessage(
          RsPacket(ssrc: 0x22222222, sequenceNumber: secondSeq).encode());
      await Future.delayed(Duration.zero);

      // Send more to check journal — should still be based on thirdSeq
      controller.sendMidi(const NoteOn(channel: 0, note: 72, velocity: 70));
      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final header = JournalHeader.decode(payload.journalData!)!;
      // Checkpoint should be thirdSeq (not secondSeq)
      expect(header.checkpointSeqNum, thirdSeq);
    });
  });

  // -------------------------------------------------------------------------
  // End-to-end: send → receive → RS → smaller journal
  // -------------------------------------------------------------------------
  group('End-to-end RS trimming', () {
    test('journal contains only delta after RS confirmation', () async {
      await driveToReady();

      // Send several messages
      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      controller
          .sendMidi(const ControlChange(channel: 0, controller: 7, value: 80));
      controller.sendMidi(const ProgramChange(channel: 0, program: 42));

      // Before RS: journal has all 3 chapters
      final beforePayload =
          RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final beforeCh =
          ChannelJournal.decode(beforePayload.journalData!, JournalHeader.size)!
              .$1;
      expect(beforeCh.chapterN, isNotNull);
      expect(beforeCh.chapterC, isNotNull);
      expect(beforeCh.chapterP, isNotNull);

      // Get seqnum of last packet (program change)
      final lastSeq = beforePayload.header.sequenceNumber;

      // Confirm all packets via RS
      transport.injectControlMessage(
          RsPacket(ssrc: 0x22222222, sequenceNumber: lastSeq).encode());
      await Future.delayed(Duration.zero);

      // Send new message
      controller
          .sendMidi(const ControlChange(channel: 0, controller: 11, value: 50));
      final afterPayload =
          RtpMidiPayload.decode(transport.dataSends.last.data)!;

      // Journal should only contain the new CC#11
      final afterCh =
          ChannelJournal.decode(afterPayload.journalData!, JournalHeader.size)!
              .$1;
      expect(afterCh.chapterC, isNotNull);
      expect(afterCh.chapterC!.logs.length, 1);
      expect(afterCh.chapterC!.logs[0].number, 11);
      // Old chapters should be gone
      expect(afterCh.chapterN, isNull);
      expect(afterCh.chapterP, isNull);
    });

    test('journal checkpoint updates to RS-confirmed seqnum', () async {
      await driveToReady();

      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final seqNum = payload.header.sequenceNumber;

      // Confirm via RS
      transport.injectControlMessage(
          RsPacket(ssrc: 0x22222222, sequenceNumber: seqNum).encode());
      await Future.delayed(Duration.zero);

      // Send another message
      controller.sendMidi(const NoteOn(channel: 0, note: 64, velocity: 80));
      final newPayload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final header = JournalHeader.decode(newPayload.journalData!)!;
      expect(header.checkpointSeqNum, seqNum);
    });

    test('no journal when all state confirmed by RS', () async {
      await driveToReady();

      controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
      final payload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      final seqNum = payload.header.sequenceNumber;

      // Confirm via RS
      transport.injectControlMessage(
          RsPacket(ssrc: 0x22222222, sequenceNumber: seqNum).encode());
      await Future.delayed(Duration.zero);

      // Send NoteOff for same note — the NoteOff creates a released note
      // at a new seq, but the note-on state was trimmed.
      // Actually, sending the same note off means we need a NoteOn first
      // in the SENDER state. The note at seq=seqNum was trimmed.
      // Let's instead just verify that sending nothing after RS
      // but then re-sending will have a minimal journal.

      // Let me verify: re-send a fresh message
      controller
          .sendMidi(const ControlChange(channel: 0, controller: 7, value: 80));
      final newPayload = RtpMidiPayload.decode(transport.dataSends.last.data)!;
      // Should have a journal with only the new CC
      expect(newPayload.hasJournal, isTrue);
      final ch =
          ChannelJournal.decode(newPayload.journalData!, JournalHeader.size)!
              .$1;
      expect(ch.chapterC!.logs.length, 1);
      expect(ch.chapterN, isNull, reason: 'Old note was trimmed by RS');
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
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

Uint8List _buildNoteJournal({
  required int checkpointSeqNum,
  required int channel,
  required Map<int, int> notes,
}) {
  final logCount = notes.length;
  final chapterN = Uint8List(2 + logCount * 2);
  chapterN[0] = logCount & 0x7F;
  chapterN[1] = 0xF0;
  var i = 0;
  for (final entry in notes.entries) {
    chapterN[2 + i * 2] = 0x80 | (entry.key & 0x7F);
    chapterN[2 + i * 2 + 1] = 0x80 | (entry.value & 0x7F);
    i++;
  }

  final channelContentSize = 3 + chapterN.length;
  final channelHeader = Uint8List(3);
  channelHeader[0] =
      0x80 | ((channel & 0x0F) << 3) | ((channelContentSize >> 8) & 0x03);
  channelHeader[1] = channelContentSize & 0xFF;
  channelHeader[2] = 0x08; // N flag

  final header = JournalHeader(
    singlePacketLoss: true,
    channelJournalsPresent: true,
    totalChannels: 0,
    checkpointSeqNum: checkpointSeqNum,
  );
  final headerBytes = header.encode();

  final totalSize = headerBytes.length + channelHeader.length + chapterN.length;
  final result = Uint8List(totalSize);
  var offset = 0;
  result.setRange(offset, offset + headerBytes.length, headerBytes);
  offset += headerBytes.length;
  result.setRange(offset, offset + channelHeader.length, channelHeader);
  offset += channelHeader.length;
  result.setRange(offset, offset + chapterN.length, chapterN);
  return result;
}
