// ignore_for_file: constant_identifier_names

enum ProxyType {
  HTTP('HTTP'),
  SOCKS5('SOCKS5'),
  SOCKS4('SOCKS4'),
  NONE('NONE');

  final String value;

  const ProxyType(this.value);

  static ProxyType fromValue(String value) {
    return ProxyType.values.firstWhere(
      (type) => type.value.toUpperCase() == value.toUpperCase(),
      orElse: () => ProxyType.NONE, // Nilai default jika tidak ditemukan
    );
  }
}
