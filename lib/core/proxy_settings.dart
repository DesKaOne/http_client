import 'proxy_type.dart';

class ProxySettings {
  final ProxyType type;
  final String host;
  final int port;
  final String? username;
  final String? password;

  const ProxySettings.none()
    : type = ProxyType.NONE,
      host = '',
      port = 0,
      username = null,
      password = null;

  const ProxySettings.http({
    required this.host,
    required this.port,
    this.username,
    this.password,
  }) : type = ProxyType.HTTP;

  const ProxySettings.socks5({
    required this.host,
    required this.port,
    this.username,
    this.password,
  }) : type = ProxyType.SOCKS5;

  bool get hasAuth => username != null && password != null;
}
