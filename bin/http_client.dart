import 'package:http_client/http_client.dart';

Future<void> main(List<String> arguments) async {
  final direct = HttpClientCore.build();
  final resp1 = await direct.get(Uri.parse('https://httpbin.org/ip'));
  print('Direct: ${resp1.body}');
  direct.close();

  final socksPx = HttpClientCore.build(
    proxies: [
      ProxyConfig(host: '127.0.0.1', port: 1080, type: ProxyType.SOCKS5),
    ],
  );
  final resp2 = await socksPx.get(Uri.parse('https://httpbin.org/ip'));
  print('Socks5 Proxy: ${resp2.body}');
  socksPx.close();

  final httpPx = HttpClientCore.build(
    proxies: [ProxyConfig(host: '127.0.0.1', port: 8080, type: ProxyType.HTTP)],
  );
  final resp3 = await httpPx.get(Uri.parse('https://httpbin.org/ip'));
  print('Http Proxy: ${resp3.body}');
  httpPx.close();
}
