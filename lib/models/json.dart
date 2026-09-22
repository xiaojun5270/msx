// Flexible JSON decoding helpers — mirrors FlexID / FlexString / Envelope / AnyJSON
// / JSONBox from the Swift Models.swift.

/// Coerce any JSON scalar id (String / int / double) into a String.
/// Mirrors Swift `FlexID`.
String flexId(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is int) return value.toString();
  if (value is double) return value.toInt().toString();
  if (value is bool) return value.toString();
  return value.toString();
}

/// Optional variant — returns null when absent instead of empty string.
String? flexIdOrNull(dynamic value) {
  if (value == null) return null;
  final s = flexId(value);
  return s.isEmpty ? null : s;
}

/// Coerce a JSON value that may be a list of strings or a single string into
/// a `List<String>`. Mirrors Swift `FlexString`.
List<String> flexStringList(dynamic value) {
  if (value == null) return const [];
  if (value is List) {
    return value.map((e) => e == null ? '' : e.toString()).toList();
  }
  if (value is String) {
    return value.isEmpty ? const [] : [value];
  }
  return const [];
}

// Safe typed accessors -------------------------------------------------------

String? asString(dynamic v) => v is String ? v : (v == null ? null : v.toString());

String asStringOr(dynamic v, String fallback) => v is String ? v : (v?.toString() ?? fallback);

int? asInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? asDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool? asBool(dynamic v) {
  if (v is bool) return v;
  if (v is String) {
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
  }
  if (v is num) return v != 0;
  return null;
}

Map<String, dynamic>? asMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : null;

List<dynamic> asList(dynamic v) => v is List ? v : const [];

/// Decode a list of objects with a factory.
List<T> decodeList<T>(dynamic v, T Function(Map<String, dynamic>) factory) {
  if (v is! List) return <T>[];
  final out = <T>[];
  for (final e in v) {
    if (e is Map) out.add(factory(e.cast<String, dynamic>()));
  }
  return out;
}

/// A thrown API error mirroring Swift `APIError`.
class ApiError implements Exception {
  final String message;
  final int status;
  const ApiError(this.message, {this.status = 0});
  @override
  String toString() => message;
}

/// Unwrap the server envelope `{result:{status,data,error}}`.
/// Mirrors Swift `JSONBox.unwrap` / `Envelope`.
dynamic unwrapEnvelope(dynamic root) {
  if (root is! Map) {
    throw const ApiError('空响应');
  }
  final result = root['result'];
  if (result is! Map) {
    throw const ApiError('空响应');
  }
  final status = result['status'];
  if (status == 'error') {
    final err = result['error'];
    final msg = (err is Map ? err['message'] : null) as String?;
    throw ApiError(msg ?? '请求失败');
  }
  return result['data'];
}
