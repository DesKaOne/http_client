import 'proxy_type.dart';

class ProxyConfig {
  final String host;
  final int port;
  final ProxyType type;
  final String? username;
  final String? password;

  const ProxyConfig({
    required this.host,
    required this.port,
    required this.type,
    this.username,
    this.password,
  });

  @override
  String toString() =>
      'Host: $host,'
      ' Port: $port,'
      ' Username: $username,'
      ' Password: $password';
}
