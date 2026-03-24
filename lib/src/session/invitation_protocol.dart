import 'exchange_packet.dart';

/// Create an invitation (`IN`) exchange packet.
///
/// The [initiatorToken] is an opaque value chosen by the inviting side and
/// echoed in the response. The [ssrc] identifies the sender. The [name] is
/// the human-readable session endpoint name.
ExchangePacket createInvitation({
  required int initiatorToken,
  required int ssrc,
  required String name,
}) {
  return ExchangePacket(
    command: ExchangeCommand.invitation,
    initiatorToken: initiatorToken,
    ssrc: ssrc,
    name: name,
  );
}

/// Create an invitation-accepted (`OK`) exchange packet.
///
/// The [initiatorToken] must match the token from the received invitation.
ExchangePacket createOk({
  required int initiatorToken,
  required int ssrc,
  required String name,
}) {
  return ExchangePacket(
    command: ExchangeCommand.ok,
    initiatorToken: initiatorToken,
    ssrc: ssrc,
    name: name,
  );
}

/// Create an invitation-rejected (`NO`) exchange packet.
///
/// The [initiatorToken] must match the token from the received invitation.
ExchangePacket createNo({
  required int initiatorToken,
  required int ssrc,
  required String name,
}) {
  return ExchangePacket(
    command: ExchangeCommand.no,
    initiatorToken: initiatorToken,
    ssrc: ssrc,
    name: name,
  );
}

/// Create a session teardown (`BY`) exchange packet.
///
/// Sent on both the control and data ports when ending a session.
ExchangePacket createBye({
  required int initiatorToken,
  required int ssrc,
  required String name,
}) {
  return ExchangePacket(
    command: ExchangeCommand.bye,
    initiatorToken: initiatorToken,
    ssrc: ssrc,
    name: name,
  );
}

/// Compute the delay before the next invitation retry.
///
/// Uses exponential backoff: each successive [attempt] doubles the
/// [baseInterval]. Returns `null` if [attempt] is greater than or equal
/// to [maxRetries], meaning no further retries should be made.
///
/// Attempt numbering starts at 0 (the first retry after the initial send).
///
/// Examples with default parameters (baseInterval = 1500ms, maxRetries = 12):
/// - attempt 0 → 1500ms
/// - attempt 1 → 3000ms
/// - attempt 2 → 6000ms
/// - attempt 11 → 3072000ms (~51 minutes)
/// - attempt 12 → null (max retries exceeded)
Duration? nextRetryDelay({
  required int attempt,
  Duration baseInterval = const Duration(milliseconds: 1500),
  int maxRetries = 12,
}) {
  if (attempt < 0 || attempt >= maxRetries) return null;

  final multiplier = 1 << attempt; // 2^attempt
  return baseInterval * multiplier;
}
