import 'dart:io';

import '../handler/socks5_handler.dart';
import '../stream/stream_reader.dart';
import 'proxy_config.dart';
import 'proxy_type.dart';

abstract class Socks5Connector {
  Future<Socket> connect({
    required String proxyHost,
    required int proxyPort,
    required String destinationHost,
    required int destinationPort,
    String? username,
    String? password,
    Duration? timeout,
  });
}

/// Menggunakan Socks5Handler buatanmu sebagai “mesin”-nya.
class Socks5HandlerConnector implements Socks5Connector {
  /// Jika true → resolve DNS di sisi klien (kirim ATYP=IP).
  /// Jika false → biarkan proxy yang resolve DNS (ATYP=DOMAIN). Biasanya ini yang paling kompatibel.
  final bool useLookup;

  /// Timeout default kalau caller tidak mengisi.
  final Duration defaultTimeout;

  /// Timeout greeting & auth (bagian handshake).
  final Duration greetingTimeout;
  final Duration authTimeout;

  const Socks5HandlerConnector({
    this.useLookup = false,
    this.defaultTimeout = const Duration(seconds: 30),
    this.greetingTimeout = const Duration(seconds: 10),
    this.authTimeout = const Duration(seconds: 10),
  });

  @override
  Future<Socket> connect({
    required String proxyHost,
    required int proxyPort,
    required String destinationHost,
    required int destinationPort,
    String? username,
    String? password,
    Duration? timeout,
    ProxyType type = ProxyType.NONE,
  }) async {
    final total = timeout ?? defaultTimeout;

    // 1) Koneksikan socket mentah ke proxy
    final raw = await Socket.connect(proxyHost, proxyPort, timeout: total);

    // (opsional) performa kecil-kecilan
    raw.setOption(SocketOption.tcpNoDelay, true);

    // 2) Siapkan reader & config buat handler
    final reader = StreamReader.fromStream(raw);

    // NOTE: Sesuaikan constructor ProxyConfig dengan punyamu.
    // Di bawah ini contoh umum. Kalau berbeda, ganti sesuai definisi class-mu.
    final proxyCfg = ProxyConfig(
      host: proxyHost,
      port: proxyPort,
      username: username,
      password: password,
      type: type,
    );

    final handler = Socks5Handler(
      useLookup: useLookup,
      rawSocket: raw,
      reader: reader,
      proxy: proxyCfg,
    );

    // 3) Handshake (greeting + optional auth)
    await handler.handshake(
      greetingTimeout: greetingTimeout,
      authTimeout: authTimeout,
    );

    // 4) CONNECT ke tujuan
    await handler.connect(destinationHost, destinationPort, timeout: total);

    // Sampai sini, `raw` sudah menjadi tunnel ke (destinationHost:destinationPort)
    // HTTP → langsung dipakai.
    // HTTPS → RequestsCustom akan bungkus pakai SecureSocket.secure(...)
    return raw;
  }
}
