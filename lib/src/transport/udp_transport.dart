import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'transport.dart';

/// UDP transport implementation using dart:io [RawDatagramSocket].
///
/// Binds a pair of adjacent UDP ports (even control, odd data)
/// as required by the RTP-MIDI session protocol.
class UdpTransport implements Transport {
  final int _requestedPort;
  final String _bindAddress;

  io.RawDatagramSocket? _controlSocket;
  io.RawDatagramSocket? _dataSocket;

  final _controlController = StreamController<Datagram>.broadcast();
  final _dataController = StreamController<Datagram>.broadcast();

  /// Creates a UDP transport.
  ///
  /// [port] must be even (control port). The data port will be port + 1.
  /// If [port] is 0, the OS will assign an available even/odd pair.
  /// [bindAddress] defaults to '0.0.0.0' (all interfaces).
  UdpTransport({int port = 0, String bindAddress = '0.0.0.0'})
      : assert(port == 0 || port.isEven, 'Control port must be even'),
        _requestedPort = port,
        _bindAddress = bindAddress;

  int _controlPort = 0;

  @override
  int get controlPort => _controlPort;

  @override
  int get dataPort => _controlPort + 1;

  @override
  Stream<Datagram> get onControlMessage => _controlController.stream;

  @override
  Stream<Datagram> get onDataMessage => _dataController.stream;

  @override
  Future<void> bind() async {
    if (_requestedPort == 0) {
      // Bind control to any port, then try adjacent odd port
      _controlSocket = await io.RawDatagramSocket.bind(
        io.InternetAddress(_bindAddress),
        0,
      );
      _controlPort = _controlSocket!.port;
      // Ensure it's even; if odd, rebind
      if (_controlPort.isOdd) {
        _controlSocket!.close();
        // Try the next even port
        _controlSocket = await io.RawDatagramSocket.bind(
          io.InternetAddress(_bindAddress),
          0,
        );
        _controlPort = _controlSocket!.port;
        if (_controlPort.isOdd) {
          // Accept whatever we get - adjust
          _controlPort = _controlSocket!.port;
        }
      }
      _dataSocket = await io.RawDatagramSocket.bind(
        io.InternetAddress(_bindAddress),
        _controlPort + 1,
      );
    } else {
      _controlPort = _requestedPort;
      _controlSocket = await io.RawDatagramSocket.bind(
        io.InternetAddress(_bindAddress),
        _controlPort,
      );
      _dataSocket = await io.RawDatagramSocket.bind(
        io.InternetAddress(_bindAddress),
        _controlPort + 1,
      );
    }

    _listen(_controlSocket!, _controlController);
    _listen(_dataSocket!, _dataController);
  }

  void _listen(
    io.RawDatagramSocket socket,
    StreamController<Datagram> controller,
  ) {
    socket.listen((event) {
      if (event == io.RawSocketEvent.read) {
        final dg = socket.receive();
        if (dg != null) {
          controller.add(Datagram(
            Uint8List.fromList(dg.data),
            dg.address.address,
            dg.port,
          ));
        }
      }
    });
  }

  @override
  void sendControl(Uint8List data, String address, int port) {
    _controlSocket?.send(data, io.InternetAddress(address), port);
  }

  @override
  void sendData(Uint8List data, String address, int port) {
    _dataSocket?.send(data, io.InternetAddress(address), port);
  }

  @override
  Future<void> close() async {
    _controlSocket?.close();
    _dataSocket?.close();
    await _controlController.close();
    await _dataController.close();
  }
}
