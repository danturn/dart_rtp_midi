import 'package:rtp_midi/src/rtp/journal/sequence_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('SequenceTracker', () {
    test('first packet signals gap for late-join journal recovery', () {
      final (tracker, gap) = SequenceTracker.process(
        SequenceTracker.initial,
        100,
      );
      expect(gap, isTrue);
      expect(tracker, isNotNull);
    });

    test('consecutive sequence numbers are not a gap after journal processed',
        () {
      var tracker = SequenceTracker.initial;
      bool gap;

      (tracker, gap) = SequenceTracker.process(tracker, 100);
      expect(gap, isTrue); // first packet — late-join gap
      tracker = tracker.withJournalProcessed();

      (tracker, gap) = SequenceTracker.process(tracker, 101);
      expect(gap, isFalse);

      (tracker, gap) = SequenceTracker.process(tracker, 102);
      expect(gap, isFalse);
    });

    test('signals gap until journal is processed', () {
      var tracker = SequenceTracker.initial;
      bool gap;

      (tracker, gap) = SequenceTracker.process(tracker, 100);
      expect(gap, isTrue); // first packet

      // Still signals gap because journal hasn't been processed yet
      (tracker, gap) = SequenceTracker.process(tracker, 101);
      expect(gap, isTrue);

      tracker = tracker.withJournalProcessed();

      (tracker, gap) = SequenceTracker.process(tracker, 102);
      expect(gap, isFalse);
    });

    test('skipped sequence number is a gap', () {
      var tracker = SequenceTracker.initial;
      bool gap;

      (tracker, gap) = SequenceTracker.process(tracker, 100);
      tracker = tracker.withJournalProcessed();

      // Skip 101
      (tracker, gap) = SequenceTracker.process(tracker, 102);
      expect(gap, isTrue);
    });

    test('multiple skipped sequence numbers is a gap', () {
      var tracker = SequenceTracker.initial;
      bool gap;

      (tracker, gap) = SequenceTracker.process(tracker, 100);
      tracker = tracker.withJournalProcessed();

      // Skip 101-109
      (tracker, gap) = SequenceTracker.process(tracker, 110);
      expect(gap, isTrue);
    });

    test('uint16 wrapping 65535 to 0 is not a gap', () {
      var tracker = SequenceTracker.initial;
      bool gap;

      (tracker, gap) = SequenceTracker.process(tracker, 65535);
      tracker = tracker.withJournalProcessed();

      (tracker, gap) = SequenceTracker.process(tracker, 0);
      expect(gap, isFalse);
    });

    test('uint16 wrapping with gap across boundary', () {
      var tracker = SequenceTracker.initial;
      bool gap;

      (tracker, gap) = SequenceTracker.process(tracker, 65535);
      tracker = tracker.withJournalProcessed();

      // Skip 0, receive 1
      (tracker, gap) = SequenceTracker.process(tracker, 1);
      expect(gap, isTrue);
    });

    test('recovery after gap continues normally', () {
      var tracker = SequenceTracker.initial;
      bool gap;

      (tracker, gap) = SequenceTracker.process(tracker, 100);
      tracker = tracker.withJournalProcessed();

      (tracker, gap) = SequenceTracker.process(tracker, 105); // gap
      expect(gap, isTrue);

      // Next in sequence after gap
      (tracker, gap) = SequenceTracker.process(tracker, 106);
      expect(gap, isFalse);
    });

    test('first packet with seqnum 0 signals late-join gap', () {
      final (tracker, gap) = SequenceTracker.process(
        SequenceTracker.initial,
        0,
      );
      expect(gap, isTrue);

      final processed = tracker.withJournalProcessed();
      final (_, gap2) = SequenceTracker.process(processed, 1);
      expect(gap2, isFalse);
    });

    test('duplicate sequence number is a gap (treated as out-of-order)', () {
      var tracker = SequenceTracker.initial;
      bool gap;

      (tracker, gap) = SequenceTracker.process(tracker, 100);
      tracker = tracker.withJournalProcessed();

      (tracker, gap) = SequenceTracker.process(tracker, 100); // duplicate
      expect(gap, isTrue);
    });
  });
}
