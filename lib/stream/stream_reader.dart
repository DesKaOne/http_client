// stream_reader.dart
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:http_client/ext/bytes_ext.dart';

class StreamReader extends Stream<Uint8List> {
  final bool broadcast;
  final bool bufferUntilListen; // berguna untuk broadcast
  final bool sync;

  late final StreamController<Uint8List> _controller;
  final Queue<Uint8List> _preListen = Queue<Uint8List>();

  StreamReader({
    this.broadcast = false,
    this.bufferUntilListen = true,
    this.sync = false,
  }) {
    void onFirstListen() {
      if (!bufferUntilListen || _preListen.isEmpty) return;
      while (_preListen.isNotEmpty) {
        _controller.add(_preListen.removeFirst());
      }
    }

    _controller = broadcast
        ? StreamController<Uint8List>.broadcast(
            sync: sync,
            onListen: onFirstListen,
          )
        : StreamController<Uint8List>(sync: sync, onListen: onFirstListen);
  }

  /// Factory: bungkus Stream sumber (boleh hasil asBroadcastStream) jadi StreamReader.
  factory StreamReader.fromStream(
    Stream<Uint8List> source, {
    bool sync = false,
    bool bufferUntilListen = true,
    bool copyOnForward = false,
    bool closeOnSourceDone = false,
  }) {
    final sr = StreamReader(
      broadcast: true, // karena sumbernya biasanya broadcast
      bufferUntilListen: bufferUntilListen,
      sync: sync,
    );

    // Bridge manual: hormati bufferUntilListen, jangan pakai addStream.
    source.listen(
      (data) {
        final chunk = copyOnForward ? data.asUint8View : data;
        if (sr.broadcast &&
            sr.bufferUntilListen &&
            !sr._controller.hasListener) {
          sr._preListen.add(chunk);
        } else {
          sr._controller.add(chunk);
        }
      },
      onError: (e, st) => sr._controller.addError(e, st),
      onDone: () async {
        if (closeOnSourceDone && !sr._controller.isClosed) {
          await sr._controller.close();
        }
      },
      cancelOnError: false,
    );

    return sr;
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  // API utilitas (tetap ada, kalau kamu mau push manual juga)
  void add(Uint8List data, {bool copy = false}) {
    if (_controller.isClosed) return;
    final chunk = copy ? data.asUint8View : data;
    if (broadcast && bufferUntilListen && !_controller.hasListener) {
      _preListen.add(chunk);
    } else {
      _controller.add(chunk);
    }
  }

  void addError(Object error, [StackTrace? st]) {
    if (_controller.isClosed) return;
    _controller.addError(error, st);
  }

  Future<void> close() => _controller.close();
  Future<void> get done => _controller.done;
  StreamSink<Uint8List> get sink => _controller.sink;
  bool get isClosed => _controller.isClosed;
  bool get hasListener => _controller.hasListener;
}

void example(Socket rawSocket) {
  // 1) Kalau mau broadcast dari socket:
  final src = rawSocket.asBroadcastStream(); // Stream<Uint8List>
  // ignore: unused_local_variable
  final reader = src.toStreamReader(bufferUntilListen: true);

  // 2) Atau langsung dari socket (single-subscription) juga boleh:
  // ignore: unused_local_variable
  final reader2 = StreamReader.fromStream(rawSocket, bufferUntilListen: true);
}
