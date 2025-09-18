import 'dart:async';
import 'dart:io';

import 'package:http_client/ext/bytes_ext.dart';

import '../exc/http_handler_exception.dart';
import '../stream/stream_reader.dart';
import '../utils/custom_user_agent.dart';
import 'header_result.dart';

class HttpHandler {
  final Socket rawSocket;
  final StreamReader reader;
  final String? username;
  final String? password;

  bool isConnected = false;

  HttpHandler({
    required this.rawSocket,
    required this.reader,
    this.username,
    this.password,
  });

  Future<void> connect(
    String host,
    int port, {
    Duration? timeout,
    String connection = 'keep-alive',
  }) async {
    final hostPort = _formatHostPort(host, port);
    final buf = StringBuffer()
      ..writeln('CONNECT $hostPort HTTP/1.1')
      ..writeln('Host: $hostPort');

    if (username != null && password != null) {
      final auth = '${username!}:${password!}'.toUtf8Bytes.b64Encode;
      buf.writeln('Proxy-Authorization: Basic $auth');
    }

    // (opsional) minimal header tambahan; beberapa proxy suka ini:
    buf.writeln('Proxy-Connection: $connection');
    buf.writeln('Connection: $connection');
    buf.writeln('User-Agent: ${CustomUserAgent.userAgent}');

    buf.writeln(); // CRLF CRLF
    rawSocket.write(buf.toString());
    await rawSocket.flush();

    // Baca sampai CRLFCRLF, aman untuk paket yang terpecah
    final res = await HeaderResult.readHeaders(
      timeout: timeout,
      reader: reader,
      cr: _cr,
      lf: _lf,
    );
    final headersText = res.headers;

    final code = _parseStatusCode(headersText);
    if (code != 200) {
      // coba tarik alasan / header autentikasi jika ada
      final authHdr = _findHeader(headersText, 'Proxy-Authenticate');
      throw HttpHandlerException(
        'HTTP proxy CONNECT failed: $code'
        '${authHdr != null ? ' | $authHdr' : ''}\n$headersText',
      );
    }

    // Ada kemungkinan setelah \r\n\r\n sudah ada payload TLS.
    if (res.leftover.isNotEmpty) {
      // dorong kembali ke reader, biar consumer berikutnya (TLS) dapat
      reader.add(res.leftover, copy: true);
    }

    isConnected = true;
  }

  // -------------------- Helpers --------------------

  String _formatHostPort(String host, int port) {
    // bracket IPv6
    if (host.contains(':') && !host.startsWith('[')) {
      return '[$host]:$port';
    }
    return '$host:$port';
  }

  int _parseStatusCode(String headers) {
    // Contoh: HTTP/1.1 200 Connection Established
    final m = RegExp(
      r'^HTTP/\d\.\d\s+(\d{3})',
      multiLine: true,
    ).firstMatch(headers);
    if (m == null) return -1;
    return int.tryParse(m.group(1)!) ?? -1;
  }

  String? _findHeader(String headers, String name) {
    // Case-insensitive match, ambil baris header apa adanya
    final re = RegExp(
      '^${RegExp.escape(name)}\\s*:\\s*(.*)\$',
      multiLine: true,
      caseSensitive: false,
    );
    final m = re.firstMatch(headers);
    return m?.group(0);
  }

  // -------------------- Header reader --------------------

  static const _cr = 13; // \r
  static const _lf = 10; // \n
}
