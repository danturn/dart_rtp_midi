/// Configuration for an RTP-MIDI endpoint.
///
/// All fields have sensible defaults. The [port] must be either 0 (for
/// automatic assignment) or a positive even number, since RTP-MIDI uses
/// a pair of consecutive ports: an even-numbered control port and the
/// next odd-numbered data port.
class RtpMidiConfig {
  /// Human-readable name advertised during session invitation.
  final String name;

  /// The control port number to bind to.
  ///
  /// Use 0 for automatic port assignment by the OS. If specified, must be
  /// a positive even number (the data port will be `port + 1`).
  final int port;

  /// Interval between periodic clock synchronization exchanges.
  final Duration clockSyncInterval;

  /// Maximum number of invitation retries before giving up.
  final int maxInvitationRetries;

  /// Base interval for invitation retry exponential backoff.
  final Duration invitationRetryBaseInterval;

  /// Duration after which an idle session is considered timed out.
  final Duration sessionTimeout;

  const RtpMidiConfig({
    this.name = 'Dart RTP-MIDI',
    this.port = 0,
    this.clockSyncInterval = const Duration(seconds: 10),
    this.maxInvitationRetries = 12,
    this.invitationRetryBaseInterval = const Duration(milliseconds: 1500),
    this.sessionTimeout = const Duration(seconds: 60),
  }) : assert(
          port == 0 || port > 0 && port % 2 == 0,
          'Port must be 0 (auto) or a positive even number',
        );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RtpMidiConfig &&
          name == other.name &&
          port == other.port &&
          clockSyncInterval == other.clockSyncInterval &&
          maxInvitationRetries == other.maxInvitationRetries &&
          invitationRetryBaseInterval == other.invitationRetryBaseInterval &&
          sessionTimeout == other.sessionTimeout;

  @override
  int get hashCode => Object.hash(
        name,
        port,
        clockSyncInterval,
        maxInvitationRetries,
        invitationRetryBaseInterval,
        sessionTimeout,
      );

  @override
  String toString() =>
      'RtpMidiConfig(name: "$name", port: $port, '
      'clockSyncInterval: $clockSyncInterval, '
      'maxInvitationRetries: $maxInvitationRetries, '
      'retryBase: $invitationRetryBaseInterval, '
      'sessionTimeout: $sessionTimeout)';
}
