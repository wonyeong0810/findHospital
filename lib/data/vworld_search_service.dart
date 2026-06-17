import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class VWorldSearchService {
  const VWorldSearchService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<VWorldPlace?> searchPlace(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !AppConfig.hasVworldKey) {
      return null;
    }

    final client = _client ?? http.Client();
    final closeClient = _client == null;

    try {
      for (final attempt in _attempts) {
        try {
          final result = await _search(client, trimmed, attempt);
          if (result != null) {
            return result;
          }
        } catch (_) {
          // A timeout or transient error on one attempt should not abort the
          // remaining fallback attempts (place -> road -> parcel).
        }
      }
      return null;
    } finally {
      if (closeClient) {
        client.close();
      }
    }
  }

  Future<VWorldPlace?> _search(
    http.Client client,
    String query,
    _VWorldSearchAttempt attempt,
  ) async {
    final params = <String, String>{
      'service': 'search',
      'request': 'search',
      'version': '2.0',
      'crs': 'EPSG:4326',
      'size': '1',
      'page': '1',
      'query': query,
      'type': attempt.type,
      'format': 'json',
      'errorformat': 'json',
      'key': AppConfig.vworldApiKey,
      if (attempt.category != null) 'category': attempt.category!,
    };

    final response = await client
        .get(Uri.https('api.vworld.kr', '/req/search', params))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final responseObject = decoded['response'];
    if (responseObject is! Map<String, dynamic> ||
        responseObject['status'] != 'OK') {
      return null;
    }

    final resultObject = responseObject['result'];
    if (resultObject is! Map<String, dynamic>) {
      return null;
    }

    final items = resultObject['items'];
    if (items is! List || items.isEmpty || items.first is! Map) {
      return null;
    }

    final item = Map<String, dynamic>.from(items.first as Map);
    final point = item['point'];
    if (point is! Map) {
      return null;
    }

    final longitude = double.tryParse('${point['x']}');
    final latitude = double.tryParse('${point['y']}');
    if (latitude == null || longitude == null) {
      return null;
    }

    return VWorldPlace(
      title: _stripHtml('${item['title'] ?? query}'),
      address: _addressFrom(item),
      latitude: latitude,
      longitude: longitude,
      category: '${item['category'] ?? attempt.type}',
    );
  }

  static String _addressFrom(Map<String, dynamic> item) {
    final address = item['address'];
    if (address is Map) {
      final road = '${address['road'] ?? ''}'.trim();
      if (road.isNotEmpty) {
        return road;
      }

      final parcel = '${address['parcel'] ?? ''}'.trim();
      if (parcel.isNotEmpty) {
        return parcel;
      }
    }

    return '${item['title'] ?? ''}'.trim();
  }

  static String _stripHtml(String value) {
    return value.replaceAll(RegExp('<[^>]+>'), '').trim();
  }

  static const _attempts = [
    _VWorldSearchAttempt(type: 'place'),
    _VWorldSearchAttempt(type: 'address', category: 'road'),
    _VWorldSearchAttempt(type: 'address', category: 'parcel'),
  ];
}

class VWorldPlace {
  const VWorldPlace({
    required this.title,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.category,
  });

  final String title;
  final String address;
  final double latitude;
  final double longitude;
  final String category;
}

class _VWorldSearchAttempt {
  const _VWorldSearchAttempt({required this.type, this.category});

  final String type;
  final String? category;
}
