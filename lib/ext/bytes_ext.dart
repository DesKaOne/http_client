import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart' as conv;

import '../stream/stream_reader.dart';

extension BytesExt on Uint8List {
  String hex({bool lowerCase = true}) => (lowerCase
      ? conv.hex.encode(this).toLowerCase()
      : conv.hex.encode(this).toUpperCase());

  String hex0x({bool lowerCase = true}) => '0x${hex(lowerCase: lowerCase)}';

  String get b64Encode {
    return base64Encode(this);
  }

  String get toUtf8String {
    return utf8.decode(this);
  }

  String get decode => toUtf8String;

  static Uint8List get zero => Uint8List(0);

  static Uint8List fromInt(int input) => Uint8List(input);

  static String _sanitizeHex(String hex) => hex.replaceAll(RegExp(r'\s+'), '');

  static Uint8List fromHex(
    String hex, {
    bool allow0x = true,
    bool allowSpaces = false,
  }) {
    if (allowSpaces) hex = _sanitizeHex(hex);
    if (allow0x && hex.startsWith('0x')) hex = hex.substring(2);
    if (hex.length % 2 != 0) {
      throw ArgumentError('String hex harus genap. Panjang=${hex.length}.');
    }
    return Uint8List.fromList(conv.hex.decode(hex));
  }

  static Uint8List? tryFromHex(String hex, {bool allow0x = true}) {
    try {
      return fromHex(hex, allow0x: allow0x);
    } catch (_) {
      return null;
    }
  }

  static int decodeHexInto(
    String hex,
    Uint8List out, {
    int outOffset = 0,
    bool allow0x = true,
  }) {
    if (allow0x && hex.startsWith('0x')) hex = hex.substring(2);
    final n = hex.length;
    if (n % 2 != 0) {
      throw ArgumentError('String hex harus genap. Panjang=$n.');
    }
    final need = n >> 1;
    if (outOffset < 0 || outOffset + need > out.length) {
      throw RangeError(
        'Buffer tidak cukup: butuh $need byte pada offset $outOffset, '
        'kapasitas=${out.length}.',
      );
    }
    for (int i = 0, j = outOffset; i < n; i += 2, j++) {
      final hi = _hexNibble(hex.codeUnitAt(i));
      final lo = _hexNibble(hex.codeUnitAt(i + 1));
      if (hi < 0 || lo < 0) {
        throw FormatException(
          'Karakter hex tidak valid pada index $i: "${hex[i]}${hex[i + 1]}"',
        );
      }
      out[j] = (hi << 4) | lo;
    }
    return need;
  }

  static int _hexNibble(int cc) {
    if (cc >= 0x30 && cc <= 0x39) return cc - 0x30; // '0'..'9'
    if (cc >= 0x41 && cc <= 0x46) return cc - 0x41 + 10; // 'A'..'F'
    if (cc >= 0x61 && cc <= 0x66) return cc - 0x61 + 10; // 'a'..'f'
    return -1;
  }

  /// Berapa byte yang dibutuhkan untuk menampung hasil decode hex (panjang/2).
  static int hexLength(String hex, {bool allow0x = true}) {
    if (allow0x && hex.startsWith('0x')) hex = hex.substring(2);
    if (hex.length % 2 != 0) {
      throw ArgumentError('String hex harus genap. Panjang=${hex.length}.');
    }
    return hex.length >> 1;
  }

  /// Versi aman dari decodeHexInto: return false jika gagal.
  static bool tryDecodeHexInto(
    String hex,
    Uint8List out, {
    int outOffset = 0,
    bool allow0x = true,
  }) {
    try {
      decodeHexInto(hex, out, outOffset: outOffset, allow0x: allow0x);
      return true;
    } catch (_) {
      return false;
    }
  }
}

extension BytesListExt on List<int> {
  String hex({bool lowerCase = true, bool with0x = false}) {
    final sb = StringBuffer();
    writeHexTo(sb, lowerCase: lowerCase, with0x: with0x);
    return sb.toString();
  }

  /// Tulis hex langsung ke StringBuffer (tanpa alokasi String sementara).
  /// Bisa pilih case, prefix 0x, dan subset byte (start..end).
  void writeHexTo(
    StringBuffer out, {
    bool lowerCase = true,
    bool with0x = false,
    int start = 0,
    int? end,
  }) {
    final list = this;
    final end0 = end ?? list.length;
    if (start < 0 || end0 < start || end0 > list.length) {
      throw RangeError(
        'Range tidak valid: start=$start, end=$end0, len=${list.length}',
      );
    }
    if (with0x) out.write('0x');

    final digits = lowerCase ? _hexDigitsLower : _hexDigitsUpper;
    for (var i = start; i < end0; i++) {
      final b = list[i] & 0xFF;
      out.writeCharCode(digits[b >> 4]);
      out.writeCharCode(digits[b & 0x0F]);
    }
  }

  /// Dapatkan view Uint8List tanpa copy jika sudah Uint8List.
  Uint8List get asUint8View {
    final self = this;
    if (self is Uint8List) return self;
    if (self is TypedData) {
      final td = self as TypedData;
      // view ke keseluruhan buffer
      return td.buffer.asUint8List(td.offsetInBytes, td.lengthInBytes);
    }
    // fallback: copy
    return Uint8List.fromList(self);
  }
}

extension Str on String {
  Uint8List get b64Decode => base64Decode(this);

  Uint8List get toUtf8Bytes => Uint8List.fromList(utf8.encode(this));

  Uint8List get encode => toUtf8Bytes;

  String get toCapitalizeEachWord =>
      split(' ').map((word) => word.toCapitalize).join(' ');

  String get toCapitalize {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}

/// Precomputed digit tables (char codes) biar kenceng saat writeHexTo
const List<int> _hexDigitsLower = <int>[
  0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, // 0..9
  0x61, 0x62, 0x63, 0x64, 0x65, 0x66, // a..f
];

const List<int> _hexDigitsUpper = <int>[
  0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, // 0..9
  0x41, 0x42, 0x43, 0x44, 0x45, 0x46, // A..F
];

extension NumFmt on num {
  // 8 desimal maksimal, lalu buang .0 / nol belakang
  String toTrimmed([int maxDecimals = 8]) {
    var s = toStringAsFixed(maxDecimals);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

/// Quality-of-life: konversi cepat dari Stream ke StreamReader
extension StreamUint8ToReader on Stream<Uint8List> {
  StreamReader toStreamReader({
    bool sync = false,
    bool bufferUntilListen = true,
    bool copyOnForward = false,
    bool closeOnSourceDone = false,
  }) => StreamReader.fromStream(
    this,
    sync: sync,
    bufferUntilListen: bufferUntilListen,
    copyOnForward: copyOnForward,
    closeOnSourceDone: closeOnSourceDone,
  );
}
