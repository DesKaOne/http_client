import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http_client/ext/bytes_ext.dart';

import '../core/proxy_config.dart';
import '../exc/socks5_handler_exception.dart';
import '../stream/stream_reader.dart';

class Socks5Handler {
  // true: resolve di client, false: biarkan proxy resolve (domain)
  final bool useLookup;
  final Socket rawSocket;
  final StreamReader reader;
  final ProxyConfig proxy;

  bool isConnected = false;

  Socks5Handler({
    required this.useLookup,
    required this.rawSocket,
    required this.reader,
    required this.proxy,
  });

  // ---------------- internals: buffer untuk readExact ----------------
  List<int> _stash = const [];

  Future<Uint8List> _readExactDeadline(
    int n,
    Stopwatch sw,
    Duration total,
  ) async {
    while (_stash.length < n) {
      final left = total - Duration(milliseconds: sw.elapsedMilliseconds);
      if (left.isNegative) {
        throw TimeoutException(
          'SOCKS5 read timed out after ${total.inMilliseconds}ms',
        );
      }
      final chunk = await reader.first.timeout(left);
      if (_stash.isEmpty) {
        _stash = chunk;
      } else {
        final tmp = Uint8List(_stash.length + chunk.length);
        tmp.setRange(0, _stash.length, _stash);
        tmp.setRange(_stash.length, tmp.length, chunk);
        _stash = tmp;
      }
    }
    final out = _stash.sublist(0, n).asUint8View;
    _stash = _stash.sublist(n);
    return out;
  }

  // ---------------- handshake ----------------
  Future<void> handshake({
    required Duration greetingTimeout,
    required Duration authTimeout,
  }) async {
    // Greeting
    final methods = <int>[0x00]; // NOAUTH
    if (proxy.username != null && proxy.password != null) methods.add(0x02);

    rawSocket.add([0x05, methods.length, ...methods]);
    await rawSocket.flush();

    final sw = Stopwatch()..start();
    final resp = await _readExactDeadline(2, sw, greetingTimeout);
    if (resp[0] != 0x05) {
      throw Socks5HandlerException(
        '❌ SOCKS version mismatch (got: 0x${resp[0].toRadixString(16)})',
      );
    }
    if (resp[1] == 0xFF) {
      throw Socks5HandlerException('❌ No acceptable auth methods');
    }

    // USER/PASS (RFC1929)
    if (resp[1] == 0x02) {
      final u = proxy.username!;
      final p = proxy.password!;
      final ub = u.codeUnits.asUint8View;
      final pb = p.codeUnits.asUint8View;
      if (ub.length > 255 || pb.length > 255) {
        throw Socks5HandlerException(
          '❌ Username/password too long for RFC1929',
        );
      }
      rawSocket.add([0x01, ub.length, ...ub, pb.length, ...pb]);
      await rawSocket.flush();

      final sw2 = Stopwatch()..start();
      final up = await _readExactDeadline(2, sw2, authTimeout);
      if (up[0] != 0x01 || up[1] != 0x00) {
        throw Socks5HandlerException('❌ SOCKS5 auth failed');
      }
    }
  }

  // ---------------- CONNECT request ----------------
  Future<void> connect(
    String host,
    int port, {
    required Duration timeout,
  }) async {
    final req = BytesBuilder()..add([0x05, 0x01, 0x00]); // VER,CMD,RSV

    if (useLookup) {
      final addrs = await InternetAddress.lookup(host);
      final addr = addrs.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => addrs.first,
      );
      if (addr.type == InternetAddressType.IPv4) {
        req.add([0x01]);
        req.add(addr.rawAddress);
      } else {
        req.add([0x04]);
        req.add(addr.rawAddress);
      }
    } else {
      final name = host.toUtf8Bytes;
      if (name.length > 255) {
        throw Socks5HandlerException('❌ Domain too long for ATYP=DOMAIN');
      }
      req.add([0x03, name.length]);
      req.add(name);
    }
    req.add([(port >> 8) & 0xFF, port & 0xFF]);

    rawSocket.add(req.takeBytes());
    await rawSocket.flush();

    final sw = Stopwatch()..start();
    final head = await _readExactDeadline(4, sw, timeout);
    if (head[0] != 0x05) {
      throw Socks5HandlerException('❌ SOCKS version mismatch in reply');
    }

    final rep = head[1];
    if (rep != 0x00) {
      throw Socks5HandlerException(
        '❌ SOCKS CONNECT failed: ${_repMessage(rep)}',
      );
    }

    final atyp = head[3];
    if (atyp == 0x01) {
      await _readExactDeadline(4, sw, timeout);
    } else if (atyp == 0x04) {
      await _readExactDeadline(16, sw, timeout);
    } else if (atyp == 0x03) {
      final l = (await _readExactDeadline(1, sw, timeout))[0];
      await _readExactDeadline(l, sw, timeout);
    } else {
      throw Socks5HandlerException(
        '❌ Unknown ATYP in reply: 0x${atyp.toRadixString(16)}',
      );
    }
    await _readExactDeadline(2, sw, timeout); // BND.PORT
  }

  String _repMessage(int rep) {
    switch (rep) {
      case 0x01:
        return 'General SOCKS server failure';
      case 0x02:
        return 'Connection not allowed by ruleset';
      case 0x03:
        return 'Network unreachable';
      case 0x04:
        return 'Host unreachable';
      case 0x05:
        return 'Connection refused';
      case 0x06:
        return 'TTL expired';
      case 0x07:
        return 'Command not supported';
      case 0x08:
        return 'Address type not supported';
      default:
        return 'Unknown error (0x${rep.toRadixString(16)})';
    }
  }
}
