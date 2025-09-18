class HttpHandlerException implements Exception {
  final String message;

  HttpHandlerException(this.message);

  @override
  String toString() => 'HttpHandlerException: $message';
}
