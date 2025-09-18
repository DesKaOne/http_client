class Socks5HandlerException implements Exception {
  final String message;

  Socks5HandlerException(this.message);

  @override
  String toString() => 'Socks5HandlerException: $message';
}
