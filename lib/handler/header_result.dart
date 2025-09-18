import 'dart:async';
import 'dart:typed_data';

import 'package:http_client/ext/bytes_ext.dart';

import '../stream/stream_reader.dart';

class HeaderResult {
  final String headers;
  final Uint8List leftover;
  HeaderResult(this.headers, this.leftover);

  static int _indexOf(Uint8List data, Uint8List pattern) {
    if (pattern.isEmpty || data.length < pattern.length) return -1;
    final first = pattern[0];
    final max = data.length - pattern.length;
    for (var i = 0; i <= max; i++) {
      if (data[i] != first) continue;
      var j = 1;
      while (j < pattern.length && data[i + j] == pattern[j]) {
        j++;
      }
      if (j == pattern.length) return i;
    }
    return -1;
  }

  static Duration _remaining(Stopwatch sw, Duration total) {
    final spent = Duration(milliseconds: sw.elapsedMilliseconds);
    final left = total - spent;
    if (left.isNegative) {
      throw TimeoutException('HTTP CONNECT header read timed out', total);
    }
    return left;
  }

  static Future<HeaderResult> readHeaders({
    required StreamReader reader,
    required int cr,
    required int lf,
    Duration? timeout,
  }) async {
    final stash = BytesBuilder(copy: false);
    final delimiter = [cr, lf, cr, lf].asUint8View;
    final sw = timeout != null ? (Stopwatch()..start()) : null;

    while (true) {
      final data = stash.toBytes();
      final idx = _indexOf(data, delimiter);
      if (idx >= 0) {
        final headerBytes = Uint8List.sublistView(data, 0, idx + 4);
        final leftover = Uint8List.sublistView(data, idx + 4);
        final text = headerBytes.toUtf8String; // header = ASCII/UTF-8 aman
        return HeaderResult(text, leftover);
      }

      final fut = reader.first;
      final chunk = (timeout != null)
          ? await fut.timeout(_remaining(sw!, timeout))
          : await fut;
      stash.add(chunk);
    }
  }
}
