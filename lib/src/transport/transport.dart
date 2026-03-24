import 'dart:typed_data';
import 'dart:async';

/// A received datagram with its source address information.
class Datagram {
  final Uint8List data;
  final String address;
  final int port;

  const Datagram(this.data, this.address, this.port);
}

/// Abstract transport interface for sending and receiving UDP datagrams.
///
/// RTP-MIDI uses a pair of UDP ports: an even-numbered control port
/// and the next odd-numbered data port.
abstract class Transport {
  /// The local control port (even).
  int get controlPort;

  /// The local data port (control port + 1, odd).
  int get dataPort;

  /// Stream of datagrams received on the control port.
  Stream<Datagram> get onControlMessage;

  /// Stream of datagrams received on the data port.
  Stream<Datagram> get onDataMessage;

  /// Send a datagram to the specified address and port via the control socket.
  void sendControl(Uint8List data, String address, int port);

  /// Send a datagram to the specified address and port via the data socket.
  void sendData(Uint8List data, String address, int port);

  /// Bind both sockets and start listening.
  Future<void> bind();

  /// Close both sockets and release resources.
  Future<void> close();
}
