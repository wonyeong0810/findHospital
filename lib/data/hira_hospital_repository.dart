import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../config/app_config.dart';
import '../domain/hospital.dart';
import '../domain/medical_specialty.dart';
import 'sample_hospitals.dart';

class HybridHospitalRepository implements HospitalRepository {
  const HybridHospitalRepository({
    this.hira = const HiraHospitalRepository(),
    this.sample = const SampleHospitalRepository(),
  });

  final HiraHospitalRepository hira;
  final SampleHospitalRepository sample;

  @override
  Future<List<Hospital>> search(HospitalSearchQuery query) async {
    if (!AppConfig.hasDataGoKrKey) {
      return sample.search(query);
    }

    try {
      return await hira.search(query);
    } catch (error) {
      // Keep the app explorable while API approval or key setup is unfinished.
      debugPrint('FINDHOSPITAL_DIAG HIRA search failed: $error');
    }

    return sample.search(query);
  }

  @override
  Stream<List<Hospital>> searchStreaming(HospitalSearchQuery query) async* {
    if (!AppConfig.hasDataGoKrKey) {
      yield* sample.searchStreaming(query);
      return;
    }

    try {
      // Hira only throws before the first emission (list fetch). Once the list
      // is out, specialist failures are swallowed per-hospital, so a mid-stream
      // error here means the list itself failed -> fall back to sample.
      yield* hira.searchStreaming(query);
    } catch (error) {
      debugPrint('FINDHOSPITAL_DIAG HIRA stream failed: $error');
      yield* sample.searchStreaming(query);
    }
  }
}

class HiraHospitalRepository implements HospitalRepository {
  const HiraHospitalRepository({http.Client? client}) : _client = client;

  final http.Client? _client;

  // data.go.kr is frequently slow on mobile networks, so the list request (the
  // one that gates whether real data shows at all) gets a generous timeout and
  // more retries. The per-hospital detail calls stay shorter since they fail
  // gracefully and run many at once.
  static const _listTimeout = Duration(seconds: 18);
  static const _detailTimeout = Duration(seconds: 10);
  static const _listMaxRetries = 1;
  static const _maxEnrich = 24;
  static const _enrichBatchSize = 6;

  @override
  Future<List<Hospital>> search(HospitalSearchQuery query) async {
    final client = _client ?? http.Client();
    final closeClient = _client == null;

    try {
      final hospitals = await _fetchHospitalsWithRetry(client, query);
      var anySpecialistLookupFailed = false;
      final enriched = await Future.wait(
        hospitals.take(24).map((hospital) async {
          var specialists = const <SpecialistCount>[];
          var specialistLookupFailed = false;
          try {
            specialists = await _fetchSpecialists(client, hospital.id);
          } catch (_) {
            anySpecialistLookupFailed = true;
            specialistLookupFailed = true;
          }

          return Hospital(
            id: hospital.id,
            name: hospital.name,
            category: hospital.category,
            address: hospital.address,
            phone: hospital.phone,
            latitude: hospital.latitude,
            longitude: hospital.longitude,
            specialists: specialists,
            source: specialistLookupFailed
                ? '건강보험심사평가원 (전문의 정보 확인 실패)'
                : '건강보험심사평가원',
          );
        }),
      );

      if (anySpecialistLookupFailed &&
          enriched.every((hospital) => hospital.specialists.isEmpty)) {
        return enriched;
      }

      return enriched.where((hospital) {
        if (!query.onlyWithSpecialists) {
          return query.specialty.id == MedicalSpecialty.all.id ||
              hospital.hasSpecialistFor(query.specialty);
        }
        return hospital.hasSpecialistFor(query.specialty);
      }).toList();
    } finally {
      if (closeClient) {
        client.close();
      }
    }
  }

  @override
  Stream<List<Hospital>> searchStreaming(HospitalSearchQuery query) async* {
    final client = _client ?? http.Client();
    final closeClient = _client == null;

    try {
      final base = await _fetchHospitalsWithRetry(client, query);
      final current = base.take(_maxEnrich).toList();
      if (current.isEmpty) {
        yield <Hospital>[];
        return;
      }

      // Phase 1: render the hospital list right away.
      yield List<Hospital>.of(current);

      // Phase 2: fill in specialist counts in small concurrent batches so the
      // list updates progressively instead of blocking on every detail call.
      for (var start = 0; start < current.length; start += _enrichBatchSize) {
        final end = start + _enrichBatchSize;
        final realEnd = end > current.length ? current.length : end;
        final enrichedSlice = await Future.wait(
          current.sublist(start, realEnd).map((hospital) async {
            try {
              final specialists = await _fetchSpecialists(client, hospital.id);
              return hospital.copyWith(
                specialists: specialists,
                source: '건강보험심사평가원',
              );
            } catch (_) {
              return hospital.copyWith(
                source: '건강보험심사평가원 (전문의 정보 확인 실패)',
              );
            }
          }),
        );
        for (var i = 0; i < enrichedSlice.length; i++) {
          current[start + i] = enrichedSlice[i];
        }
        yield List<Hospital>.of(current);
      }
    } finally {
      if (closeClient) {
        client.close();
      }
    }
  }

  /// Retries the hospital list request once on a transient failure (timeout or
  /// network blip on a cold connection) before giving up. Without this, a
  /// single slow first request drops the user to sample data.
  Future<List<Hospital>> _fetchHospitalsWithRetry(
    http.Client client,
    HospitalSearchQuery query,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _fetchHospitals(client, query);
      } catch (error) {
        if (attempt >= _listMaxRetries) {
          rethrow;
        }
        debugPrint('FINDHOSPITAL_DIAG list fetch retry after: $error');
        await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
  }

  Future<List<Hospital>> _fetchHospitals(
    http.Client client,
    HospitalSearchQuery query,
  ) async {
    final params = <String, String>{
      'pageNo': '1',
      'numOfRows': '40',
      if (query.searchByHospitalName && query.keyword.trim().isNotEmpty)
        'yadmNm': query.keyword.trim(),
      if (query.specialty.hiraCode.isNotEmpty)
        'dgsbjtCd': query.specialty.hiraCode,
      if (query.latitude != null && query.longitude != null) ...{
        'xPos': query.longitude!.toStringAsFixed(7),
        'yPos': query.latitude!.toStringAsFixed(7),
        'radius': query.radiusMeters.toString(),
      },
    };

    final uri = _buildDataGoKrUri(
      '/B551182/hospInfoServicev2/getHospBasisList',
      params,
      serviceKey: AppConfig.hiraHospitalServiceKey,
    );
    final response = await client.get(uri).timeout(_listTimeout);
    _throwIfBadResponse(response);

    final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
    return document.findAllElements('item').map(_hospitalFromXml).where((item) {
      return item.latitude != 0 && item.longitude != 0;
    }).toList();
  }

  Future<List<SpecialistCount>> _fetchSpecialists(
    http.Client client,
    String ykiho,
  ) async {
    final uri = _buildDataGoKrUri(
      '/B551182/MadmDtlInfoService2.8/getSpcSbjtSdrInfo2.8',
      {'pageNo': '1', 'numOfRows': '80', 'ykiho': ykiho, '_type': 'xml'},
      serviceKey: AppConfig.hiraDetailServiceKey,
    );
    final response = await client.get(uri).timeout(_detailTimeout);
    _throwIfBadResponse(response);

    final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
    return document.findAllElements('item').map(_specialistFromXml).where((
      item,
    ) {
      return item.count > 0 && item.name.isNotEmpty;
    }).toList();
  }

  static Hospital _hospitalFromXml(XmlElement item) {
    final latitude = _doubleValue(item, ['YPos', 'yPos', 'latitude']);
    final longitude = _doubleValue(item, ['XPos', 'xPos', 'longitude']);

    return Hospital(
      id: _text(item, ['ykiho', 'Ykiho']),
      name: _text(item, ['yadmNm', 'YadmNm']),
      category: _text(item, ['clCdNm', 'ClCdNm']),
      address: _text(item, ['addr', 'Addr']),
      phone: _text(item, ['telno', 'Telno']),
      latitude: latitude,
      longitude: longitude,
      specialists: const [],
      source: '건강보험심사평가원',
    );
  }

  static SpecialistCount _specialistFromXml(XmlElement item) {
    final code = _text(item, [
      'dgsbjtCd',
      'DgsbjtCd',
      'spcSbjtCd',
      'SpcSbjtCd',
    ]);
    final specialty = MedicalSpecialty.byHiraCode(code);
    final name = _text(item, [
      'dgsbjtCdNm',
      'DgsbjtCdNm',
      'spcSbjtNm',
      'SpcSbjtNm',
      'spcSbjtCdNm',
    ]);

    return SpecialistCount(
      hiraCode: code,
      name: name.isNotEmpty ? name : specialty?.name ?? code,
      count: _intValue(item, [
        'sdrCnt',
        'SdrCnt',
        'spcSbjtSdrCnt',
        'SpcSbjtSdrCnt',
        'dtlSdrCnt',
        'DtlSdrCnt',
        'spclSdrCnt',
        'SpclSdrCnt',
        'cnt',
      ]),
    );
  }

  static Uri _buildDataGoKrUri(
    String path,
    Map<String, String> params, {
    required String serviceKey,
  }) {
    final baseUri = Uri.https('apis.data.go.kr', path, params);
    final key = serviceKey.trim();
    final encodedKey = key.contains('%') ? key : Uri.encodeQueryComponent(key);
    final separator = baseUri.hasQuery ? '&' : '?';
    return Uri.parse('$baseUri${separator}ServiceKey=$encodedKey');
  }

  static void _throwIfBadResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      debugPrint(
        'FINDHOSPITAL_DIAG bad status ${response.statusCode} for '
        '${response.request?.url.path}: '
        '${body.substring(0, body.length < 200 ? body.length : 200)}',
      );
      throw http.ClientException(
        'HIRA API returned ${response.statusCode}',
        response.request?.url,
      );
    }
  }

  static String _text(XmlElement item, List<String> names) {
    for (final name in names) {
      final text = item.getElement(name)?.innerText.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  static double _doubleValue(XmlElement item, List<String> names) {
    return double.tryParse(_text(item, names)) ?? 0;
  }

  static int _intValue(XmlElement item, List<String> names) {
    for (final name in names) {
      final value = int.tryParse(_text(item, [name]));
      if (value != null) {
        return value;
      }
    }

    for (final child in item.children.whereType<XmlElement>()) {
      final name = child.name.local.toLowerCase();
      if (name.contains('cnt') || name.contains('num')) {
        final value = int.tryParse(child.innerText.trim());
        if (value != null) {
          return value;
        }
      }
    }
    return 0;
  }
}
