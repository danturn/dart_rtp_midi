import 'dart:async';

/// A discovered mDNS service.
class MdnsServiceInfo {
  /// The advertised service name.
  final String name;

  /// The host address of the service.
  final String address;

  /// The port number of the service.
  final int port;

  /// Creates an mDNS service info entry.
  const MdnsServiceInfo({
    required this.name,
    required this.address,
    required this.port,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MdnsServiceInfo &&
          name == other.name &&
          address == other.address &&
          port == other.port;

  @override
  int get hashCode => Object.hash(name, address, port);

  @override
  String toString() => 'MdnsServiceInfo(name: "$name", $address:$port)';
}

/// Abstract interface for mDNS service registration (broadcasting).
///
/// Implementations can use bonsoir (Flutter), multicast_dns (pure Dart),
/// or any other mDNS library.
abstract class MdnsBroadcaster {
  /// Register a service with the given [name], [type], and [port].
  ///
  /// The service will be advertised on the local network until [stop]
  /// is called.
  Future<void> start({
    required String name,
    required String type,
    required int port,
  });

  /// Stop advertising the service.
  Future<void> stop();
}

/// Abstract interface for mDNS service discovery.
///
/// Implementations can use bonsoir (Flutter), multicast_dns (pure Dart),
/// or any other mDNS library.
abstract class MdnsDiscoverer {
  /// Start discovering services of the given [type].
  ///
  /// Returns a stream of resolved services. The stream stays open until
  /// [stop] is called.
  Stream<MdnsServiceInfo> discover(String type);

  /// Stop the active discovery.
  Future<void> stop();
}

/// A no-op mDNS broadcaster that does nothing.
///
/// Use this when mDNS registration is not needed (e.g., direct connections
/// only, or in tests).
class NoOpMdnsBroadcaster implements MdnsBroadcaster {
  @override
  Future<void> start({
    required String name,
    required String type,
    required int port,
  }) async {}

  @override
  Future<void> stop() async {}
}

/// A no-op mDNS discoverer that never finds anything.
///
/// Use this in tests or when discovery is not needed.
class NoOpMdnsDiscoverer implements MdnsDiscoverer {
  @override
  Stream<MdnsServiceInfo> discover(String type) => const Stream.empty();

  @override
  Future<void> stop() async {}
}
