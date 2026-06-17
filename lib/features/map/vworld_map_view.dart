import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/app_config.dart';
import '../../domain/hospital.dart';

class VWorldMapView extends StatefulWidget {
  const VWorldMapView({
    super.key,
    required this.hospitals,
    required this.selectedHospitalId,
    required this.currentLatitude,
    required this.currentLongitude,
    required this.currentAccuracyMeters,
    required this.onHospitalSelected,
  });

  final List<Hospital> hospitals;
  final String? selectedHospitalId;
  final double? currentLatitude;
  final double? currentLongitude;
  final double? currentAccuracyMeters;
  final ValueChanged<String> onHospitalSelected;

  @override
  State<VWorldMapView> createState() => _VWorldMapViewState();
}

class _VWorldMapViewState extends State<VWorldMapView> {
  late final WebViewController? _controller;
  bool _isLoaded = false;
  String _lastHospitalSignature = '';

  @override
  void initState() {
    super.initState();

    if (!AppConfig.hasVworldKey) {
      _controller = null;
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF4F7F8))
      ..addJavaScriptChannel(
        'HospitalChannel',
        onMessageReceived: (message) {
          widget.onHospitalSelected(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _isLoaded = true;
            _syncHospitals();
            _syncCurrentLocation();
          },
        ),
      )
      ..loadHtmlString(
        _mapHtml.replaceAll('__VWORLD_API_KEY__', AppConfig.vworldApiKey),
      );
  }

  @override
  void didUpdateWidget(covariant VWorldMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.hospitals != widget.hospitals) {
      _syncHospitals();
    } else if (oldWidget.selectedHospitalId != widget.selectedHospitalId) {
      _selectHospital();
    }

    if (oldWidget.currentLatitude != widget.currentLatitude ||
        oldWidget.currentLongitude != widget.currentLongitude ||
        oldWidget.currentAccuracyMeters != widget.currentAccuracyMeters) {
      _syncCurrentLocation();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasVworldKey) {
      return const _MapSetupNotice();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(0),
      child: WebViewWidget(controller: _controller!),
    );
  }

  Future<void> _syncHospitals() async {
    if (!_isLoaded || !AppConfig.hasVworldKey) {
      return;
    }

    final payload = jsonEncode(
      widget.hospitals.map((hospital) {
        return {
          'id': hospital.id,
          'name': hospital.name,
          'latitude': hospital.latitude,
          'longitude': hospital.longitude,
          'totalSpecialists': hospital.totalSpecialists,
        };
      }).toList(),
    );

    // Only refit the camera when the set of hospitals changes. Progressive
    // specialist updates keep the same ids, so they recolor markers in place
    // without re-animating the map.
    final signature = widget.hospitals.map((h) => h.id).join(',');
    final shouldFit = signature != _lastHospitalSignature;
    _lastHospitalSignature = signature;

    await _controller?.runJavaScript('window.setHospitals($payload, $shouldFit);');
    await _selectHospital();
  }

  Future<void> _selectHospital() async {
    if (!_isLoaded || !AppConfig.hasVworldKey) {
      return;
    }

    final id = jsonEncode(widget.selectedHospitalId);
    await _controller?.runJavaScript('window.selectHospital($id);');
  }

  Future<void> _syncCurrentLocation() async {
    if (!_isLoaded || !AppConfig.hasVworldKey) {
      return;
    }

    final latitude = widget.currentLatitude;
    final longitude = widget.currentLongitude;
    final payload = latitude == null || longitude == null
        ? 'null'
        : jsonEncode({
            'latitude': latitude,
            'longitude': longitude,
            'accuracyMeters': widget.currentAccuracyMeters,
          });

    await _controller?.runJavaScript('window.setCurrentLocation($payload);');
  }
}

class _MapSetupNotice extends StatelessWidget {
  const _MapSetupNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE7EEF0),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 40, color: Color(0xFF265C59)),
            const SizedBox(height: 12),
            Text(
              '브이월드 API 키 필요',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF183C3A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '--dart-define=VWORLD_API_KEY=발급키 로 실행하면 지도가 표시됩니다.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF496462),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _mapHtml = '''
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/ol@10.6.1/ol.css">
  <script src="https://cdn.jsdelivr.net/npm/ol@10.6.1/dist/ol.js"></script>
  <style>
    html, body, #map {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: #e7eef0;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    .ol-control button {
      background: #ffffff;
      color: #173d3a;
      border-radius: 8px;
      box-shadow: 0 2px 10px rgba(0, 0, 0, 0.12);
    }
    .ol-zoom {
      display: none;
    }
    .ol-attribution {
      font-size: 9px;
      bottom: 4px;
      right: 4px;
    }
    .ol-attribution button {
      display: none;
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    const apiKey = '__VWORLD_API_KEY__';
    const center = ol.proj.fromLonLat([126.9780, 37.5665]);
    const vectorSource = new ol.source.Vector();
    const locationSource = new ol.source.Vector();
    let currentLocationFeature = null;
    let currentAccuracyFeature = null;
    let hasCenteredOnCurrentLocation = false;
    let selectedId = null;

    const vworldLayer = new ol.layer.Tile({
      source: new ol.source.XYZ({
        url: 'https://api.vworld.kr/req/wmts/1.0.0/' + apiKey + '/Base/{z}/{y}/{x}.png',
        attributions: 'VWorld',
        crossOrigin: 'anonymous'
      })
    });

    const vectorLayer = new ol.layer.Vector({
      source: vectorSource,
      style: function(feature) {
        const isSelected = feature.get('id') === selectedId;
        const count = feature.get('totalSpecialists') || 0;
        const fillColor = count > 0 ? '#0E7C66' : '#9AA7A4';
        const strokeColor = isSelected ? '#EFA92C' : '#ffffff';
        const radius = isSelected ? 18 : 13;

        return new ol.style.Style({
          image: new ol.style.Circle({
            radius: radius,
            fill: new ol.style.Fill({ color: fillColor }),
            stroke: new ol.style.Stroke({ color: strokeColor, width: isSelected ? 5 : 3 })
          }),
          text: new ol.style.Text({
            text: String(count),
            offsetY: 1,
            fill: new ol.style.Fill({ color: '#ffffff' }),
            font: '700 12px system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
          })
        });
      }
    });

    const locationLayer = new ol.layer.Vector({
      source: locationSource,
      style: function(feature) {
        if (feature.get('kind') === 'accuracy') {
          return new ol.style.Style({
            fill: new ol.style.Fill({ color: 'rgba(32, 116, 255, 0.14)' }),
            stroke: new ol.style.Stroke({ color: 'rgba(32, 116, 255, 0.28)', width: 1.5 })
          });
        }

        return new ol.style.Style({
          image: new ol.style.Circle({
            radius: 9,
            fill: new ol.style.Fill({ color: '#2074ff' }),
            stroke: new ol.style.Stroke({ color: '#ffffff', width: 4 })
          })
        });
      }
    });

    const defaultControlOptions = {
      rotate: false,
      attributionOptions: { collapsible: true }
    };
    const defaultControls = typeof ol.control.defaults === 'function'
      ? ol.control.defaults(defaultControlOptions)
      : ol.control.defaults.defaults(defaultControlOptions);

    const map = new ol.Map({
      target: 'map',
      layers: [vworldLayer, vectorLayer, locationLayer],
      view: new ol.View({
        center: center,
        zoom: 12,
        minZoom: 7,
        maxZoom: 19
      }),
      controls: defaultControls
    });

    window.setHospitals = function(hospitals, fit) {
      vectorSource.clear();
      hospitals.forEach(function(hospital) {
        if (!hospital.longitude || !hospital.latitude) {
          return;
        }
        const feature = new ol.Feature({
          geometry: new ol.geom.Point(ol.proj.fromLonLat([hospital.longitude, hospital.latitude])),
          id: hospital.id,
          name: hospital.name,
          totalSpecialists: hospital.totalSpecialists
        });
        vectorSource.addFeature(feature);
      });

      const features = vectorSource.getFeatures();
      if (fit && features.length > 0) {
        const extent = vectorSource.getExtent();
        map.getView().fit(extent, {
          // Leave room for the floating search controls (top) and the
          // draggable result sheet (bottom) so pins stay in the visible band.
          padding: [170, 50, 360, 50],
          maxZoom: 15,
          duration: 220
        });
      }
    };

    window.setCurrentLocation = function(location) {
      locationSource.clear();
      currentLocationFeature = null;
      currentAccuracyFeature = null;

      if (!location || !location.longitude || !location.latitude) {
        return;
      }

      const projected = ol.proj.fromLonLat([location.longitude, location.latitude]);
      const accuracyMeters = Number(location.accuracyMeters || 0);

      if (accuracyMeters > 0) {
        currentAccuracyFeature = new ol.Feature({
          geometry: new ol.geom.Circle(projected, Math.min(Math.max(accuracyMeters, 15), 300)),
          kind: 'accuracy'
        });
        locationSource.addFeature(currentAccuracyFeature);
      }

      currentLocationFeature = new ol.Feature({
        geometry: new ol.geom.Point(projected),
        kind: 'current'
      });
      locationSource.addFeature(currentLocationFeature);

      if (!hasCenteredOnCurrentLocation && vectorSource.getFeatures().length === 0) {
        hasCenteredOnCurrentLocation = true;
        map.getView().animate({
          center: projected,
          zoom: Math.max(map.getView().getZoom() || 12, 14),
          duration: 220
        });
      }
    };

    window.selectHospital = function(id) {
      selectedId = id;
      vectorLayer.changed();
      if (!id) {
        return;
      }

      const feature = vectorSource.getFeatures().find(function(item) {
        return item.get('id') === id;
      });
      if (!feature) {
        return;
      }

      const zoom = map.getView().getZoom() || 12;
      map.getView().animate({
        center: feature.getGeometry().getCoordinates(),
        zoom: Math.max(zoom, 14),
        duration: 220
      });
    };

    map.on('singleclick', function(event) {
      const feature = map.forEachFeatureAtPixel(event.pixel, function(item) {
        return item;
      });
      if (feature && window.HospitalChannel) {
        window.HospitalChannel.postMessage(feature.get('id'));
      }
    });
  </script>
</body>
</html>
''';
