// ignore_for_file: constant_identifier_names

enum ProxyMode {
  CHAIN('CHAIN'),
  ROTATOR('ROTATOR'),
  NONE('NONE');

  final String value;

  const ProxyMode(this.value);

  static ProxyMode fromValue(String value) {
    return ProxyMode.values.firstWhere(
      (type) => type.value.toUpperCase() == value.toUpperCase(),
      orElse: () => ProxyMode.NONE, // Nilai default jika tidak ditemukan
    );
  }
}
