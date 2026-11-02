import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/api_client.dart';

/// Turns an exception into something worth showing a player.
///
/// The backend reports failures as `{"detail": "..."}` (or FastAPI's
/// validation shape), which would otherwise reach the UI as raw JSON.
String friendlyError(Object error) {
  if (error is ApiException) {
    // The one failure a player can fix themselves, so it says how.
    if (error.statusCode == 404) {
      return 'No game with that code. Check it and try again.';
    }
    final detail = _detailFrom(error.message);
    if (detail == null) return 'Something went wrong (${error.statusCode})';
    // The backend's messages are lower-case fragments.
    return detail[0].toUpperCase() + detail.substring(1);
  }
  if (error is TimeoutException) {
    return 'The server took too long to respond. Check your connection.';
  }
  if (error is SocketException) {
    return "Can't reach the server. Check your connection.";
  }
  return 'Something went wrong.';
}

String? _detailFrom(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final detail = decoded['detail'];
    if (detail is String) return detail;
    // FastAPI validation errors: [{"loc": [...], "msg": "..."}]
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] is String) return first['msg'] as String;
    }
  } on FormatException {
    return null;
  }
  return null;
}
