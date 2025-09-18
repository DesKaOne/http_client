import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:http/http.dart';
import 'package:http/io_client.dart';

import 'proxy_config.dart';
import 'proxy_mode.dart';
import 'proxy_settings.dart';
import 'proxy_type.dart';
import 'socks5_connector.dart';

class _NotImplementedSocks5Connector implements Socks5Connector {
  @override
  Future<Socket> connect({
    required String proxyHost,
    required int proxyPort,
    required String destinationHost,
    required int destinationPort,
    String? username,
    String? password,
    Duration? timeout,
  }) {
    throw UnimplementedError(
      'Socks5Connector belum di-set. Inject implementasi dari paket/handler SOCKS5.',
    );
  }
}

class HttpClientCore implements Client {
  final ProxySettings _defaultProxy;
  final Socks5Connector _socks5; // injectable
  late final IOClient _base;

  final Map<String, String> _addHeaders = {};

  HttpClientCore({
    ProxySettings defaultProxy = const ProxySettings.none(),
    Socks5Connector? socks5Connector,
    List<String> publicIP = const [],
  }) : _defaultProxy = defaultProxy,
       _socks5 = socks5Connector ?? _NotImplementedSocks5Connector() {
    _base = IOClient(_buildHttpClient(_defaultProxy, _socks5));
    if (publicIP.isNotEmpty) {
      final chain = publicIP.join(',');
      _addHeaders.addAll({
        'X-Real-IP': chain,
        'X-Forwarded-For': chain,
        'X-Remote-Addr': chain,
      });
    }
  }

  HttpClientCore withProxy(
    ProxySettings proxy, {
    Socks5Connector? socks5Connector,
  }) {
    return HttpClientCore(
      defaultProxy: proxy,
      socks5Connector: socks5Connector ?? _socks5,
    );
  }

  static HttpClient _buildHttpClient(
    ProxySettings proxy,
    Socks5Connector socks5,
  ) {
    final httpClient = HttpClient();

    // Proxy HTTP: native
    if (proxy.type == ProxyType.HTTP) {
      httpClient.findProxy = (uri) => "PROXY ${proxy.host}:${proxy.port}";
      if (proxy.hasAuth) {
        httpClient.addProxyCredentials(
          proxy.host,
          proxy.port,
          '',
          HttpClientBasicCredentials(proxy.username!, proxy.password!),
        );
      }
    }

    // SOCKS5: gunakan connectionFactory (untuk http & https).
    if (proxy.type == ProxyType.SOCKS5) {
      httpClient.findProxy = (_) => "DIRECT"; // kita yang urus via SOCKS

      httpClient.connectionFactory =
          (Uri uri, String? proxyHost, int? proxyPort) async {
            final int targetPort = uri.port == 0
                ? (uri.scheme == 'https' ? 443 : 80)
                : uri.port;

            // 1) Future<Socket>: tunnel SOCKS5 + TLS jika https
            final Future<Socket> socketFuture = () async {
              final raw = await socks5.connect(
                proxyHost: proxy.host,
                proxyPort: proxy.port,
                destinationHost: uri.host,
                destinationPort: targetPort,
                username: proxy.username,
                password: proxy.password,
                timeout: const Duration(seconds: 30),
              );

              if (uri.scheme == 'https') {
                return await SecureSocket.secure(
                  raw,
                  host: uri.host,
                  // onBadCertificate: (_) => true, // hanya untuk debug
                );
              }
              return raw;
            }();

            // 2) bungkus dengan ConnectionTask.fromSocket
            return ConnectionTask.fromSocket(socketFuture, () async {
              // Best-effort cancel: tutup socket jika sudah ada
              try {
                final s = await socketFuture;
                await s.close();
              } catch (_) {
                // kalau future belum selesai / error, abaikan
              }
            });
          };
    }

    httpClient.idleTimeout = const Duration(seconds: 30);
    return httpClient;
  }

  // ===================== Delegasi Client =====================

  @override
  void close() => _base.close();

  @override
  Future<Response> get(Uri url, {Map<String, String>? headers}) async {
    if (headers != null) _addHeaders.addAll(headers);
    return await _base.get(url, headers: _addHeaders);
  }

  @override
  Future<Response> head(Uri url, {Map<String, String>? headers}) async {
    if (headers != null) _addHeaders.addAll(headers);
    return await _base.head(url, headers: _addHeaders);
  }

  @override
  Future<Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    if (headers != null) _addHeaders.addAll(headers);
    return await _base.post(
      url,
      headers: _addHeaders,
      body: body,
      encoding: encoding,
    );
  }

  @override
  Future<Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    if (headers != null) _addHeaders.addAll(headers);
    return await _base.put(
      url,
      headers: _addHeaders,
      body: body,
      encoding: encoding,
    );
  }

  @override
  Future<Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    if (headers != null) _addHeaders.addAll(headers);
    return await _base.patch(
      url,
      headers: _addHeaders,
      body: body,
      encoding: encoding,
    );
  }

  @override
  Future<Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    if (headers != null) _addHeaders.addAll(headers);
    return await _base.delete(
      url,
      headers: _addHeaders,
      body: body,
      encoding: encoding,
    );
  }

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    if (headers != null) _addHeaders.addAll(headers);
    return await _base.read(url, headers: _addHeaders);
  }

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) async {
    if (headers != null) _addHeaders.addAll(headers);
    return await _base.readBytes(url, headers: _addHeaders);
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) => _base.send(request);

  factory HttpClientCore.build({
    List<ProxyConfig> proxies = const [],
    ProxyMode proxyMode = ProxyMode.NONE,
    List<String> publicIP = const [],
  }) {
    if (proxies.isEmpty) {
      return HttpClientCore(publicIP: publicIP);
    } else {
      switch (proxyMode) {
        case ProxyMode.CHAIN:
          throw UnimplementedError(
            'ProxyMode.CHAIN belum didukung. Perlu tunneling berlapis.',
          );
        case ProxyMode.ROTATOR:
          final clients = <HttpClientCore>[];
          proxies.shuffle();
          for (final p in proxies) {
            final ps = HttpClientCore._proxyConfigToSettings(p);
            clients.add(
              HttpClientCore(
                defaultProxy: ps,
                socks5Connector: HttpClientCore._makeDefaultSocksConnector(),
                publicIP: publicIP,
              ),
            );
          }
          return RotatingClient(clients); // lihat catatan opsional di bawah
        case ProxyMode.NONE:
          proxies.shuffle();
          final first = proxies.first;
          final ps = HttpClientCore._proxyConfigToSettings(first);
          return HttpClientCore(
            defaultProxy: ps,
            socks5Connector: HttpClientCore._makeDefaultSocksConnector(),
            publicIP: publicIP,
          );
      }
    }
  }

  /// Buat connector default: gunakan Socks5HandlerConnector tanpa lookup.
  /// Jika kamu mau injeksi berbeda, panggil HttpClientCore(...) manual.
  static Socks5Connector _makeDefaultSocksConnector() {
    return const Socks5HandlerConnector(useLookup: false);
  }

  static ProxySettings _proxyConfigToSettings(ProxyConfig cfg) {
    switch (cfg.type) {
      case ProxyType.HTTP:
        return ProxySettings.http(
          host: cfg.host,
          port: cfg.port,
          username: cfg.username,
          password: cfg.password,
        );
      case ProxyType.SOCKS5:
        return ProxySettings.socks5(
          host: cfg.host,
          port: cfg.port,
          username: cfg.username,
          password: cfg.password,
        );
      default:
        return const ProxySettings.none();
    }
  }
}

final class RotatingClient extends HttpClientCore {
  final List<HttpClientCore> _clients;
  int _idx = 0;

  RotatingClient(this._clients) : super() {
    // super ini hanya untuk membentuk tipe; jangan gunakan _base dari parent.
    // Kita override semua method untuk delegasi ke salah satu _clients.
  }

  HttpClientCore _pickClient() {
    // Round-robin (thread-safety sederhana — kira-kira cukup untuk kebanyakan kasus)
    final c = _clients[_idx % _clients.length];
    _idx = (_idx + 1) % _clients.length;
    return c;
  }

  // Override semua metode Client untuk delegasi
  @override
  void close() {
    for (final c in _clients) {
      c.close();
    }
  }

  @override
  Future<Response> get(Uri url, {Map<String, String>? headers}) =>
      _pickClient().get(url, headers: headers);

  @override
  Future<Response> head(Uri url, {Map<String, String>? headers}) =>
      _pickClient().head(url, headers: headers);

  @override
  Future<Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) =>
      _pickClient().post(url, headers: headers, body: body, encoding: encoding);

  @override
  Future<Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) =>
      _pickClient().put(url, headers: headers, body: body, encoding: encoding);

  @override
  Future<Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _pickClient().patch(
    url,
    headers: headers,
    body: body,
    encoding: encoding,
  );

  @override
  Future<Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _pickClient().delete(
    url,
    headers: headers,
    body: body,
    encoding: encoding,
  );

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) =>
      _pickClient().read(url, headers: headers);

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) =>
      _pickClient().readBytes(url, headers: headers);

  @override
  Future<StreamedResponse> send(BaseRequest request) =>
      _pickClient().send(request);
}
