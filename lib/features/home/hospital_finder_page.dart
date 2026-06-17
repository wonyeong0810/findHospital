import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../config/app_config.dart';
import '../../data/hira_hospital_repository.dart';
import '../../data/vworld_search_service.dart';
import '../../domain/hospital.dart';
import '../../domain/medical_specialty.dart';
import '../../theme/app_palette.dart';
import '../ads/banner_ad_bar.dart';
import '../map/vworld_map_view.dart';
import 'hospital_actions.dart';

enum _SearchMode { nearby, hospitalName }

class _SearchKeywordIntent {
  const _SearchKeywordIntent({
    required this.placeQuery,
    required this.specialty,
  });

  final String placeQuery;
  final MedicalSpecialty? specialty;

  bool get usesCurrentLocation =>
      placeQuery.isEmpty ||
      RegExp(r'^(내|나|현재|현위치|내위치|여기|주변|근처)$').hasMatch(placeQuery);

  static _SearchKeywordIntent parse(String keyword) {
    var working = keyword.trim();
    MedicalSpecialty? specialty;

    for (final alias in _specialtyAliases) {
      if (alias.pattern.hasMatch(working)) {
        specialty ??= alias.specialty;
        working = working.replaceAll(alias.pattern, ' ');
      }
    }

    working = working
        .replaceAll(
          RegExp(r'(전문의|전문|상주|있는|찾아줘|찾아|검색|추천|근처|주변|가까운|병원|의원|의료원|클리닉)'),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return _SearchKeywordIntent(placeQuery: working, specialty: specialty);
  }

  static final _specialtyAliases = <_SpecialtyAlias>[
    _SpecialtyAlias('정신건강의학과|정신과', MedicalSpecialty.supported[2]),
    _SpecialtyAlias('소아청소년과|소아과|어린이', MedicalSpecialty.supported[6]),
    _SpecialtyAlias('이비인후과|이비인후', MedicalSpecialty.supported[8]),
    _SpecialtyAlias('비뇨의학과|비뇨기과', MedicalSpecialty.supported[10]),
    _SpecialtyAlias('가정의학과', MedicalSpecialty.supported[12]),
    _SpecialtyAlias('응급의학과|응급실|응급', MedicalSpecialty.supported[13]),
    _SpecialtyAlias('정형외과|정형', MedicalSpecialty.supported[4]),
    _SpecialtyAlias('산부인과|여성의학', MedicalSpecialty.supported[5]),
    _SpecialtyAlias('재활의학과|재활', MedicalSpecialty.supported[11]),
    _SpecialtyAlias('피부과|피부', MedicalSpecialty.supported[9]),
    _SpecialtyAlias('신경과', MedicalSpecialty.supported[1]),
    _SpecialtyAlias('내과', MedicalSpecialty.supported[0]),
    _SpecialtyAlias('외과', MedicalSpecialty.supported[3]),
    _SpecialtyAlias('안과', MedicalSpecialty.supported[7]),
  ];
}

class _SpecialtyAlias {
  _SpecialtyAlias(String pattern, this.specialty)
    : pattern = RegExp(pattern, caseSensitive: false);

  final RegExp pattern;
  final MedicalSpecialty specialty;
}

class HospitalFinderPage extends StatefulWidget {
  const HospitalFinderPage({super.key});

  @override
  State<HospitalFinderPage> createState() => _HospitalFinderPageState();
}

class _HospitalFinderPageState extends State<HospitalFinderPage> {
  final HospitalRepository _repository = const HybridHospitalRepository();
  final VWorldSearchService _placeSearch = const VWorldSearchService();
  final TextEditingController _searchController = TextEditingController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  static const double _sheetMin = 0.16;
  static const double _sheetInitial = 0.46;
  // Logical height of the floating search field + chip row + paddings, used to
  // keep the expanded sheet from overlapping the top controls.
  static const double _topControlsHeight = 190;

  List<Hospital> _allHospitals = const [];
  List<Hospital> _hospitals = const [];
  StreamSubscription<List<Hospital>>? _searchSub;
  MedicalSpecialty _selectedSpecialty = MedicalSpecialty.all;
  _SearchMode _searchMode = _SearchMode.nearby;
  String? _selectedHospitalId;
  double? _latitude;
  double? _longitude;
  double? _currentLatitude;
  double? _currentLongitude;
  double? _currentAccuracyMeters;
  StreamSubscription<Position>? _positionSubscription;
  String _activeKeyword = '';
  bool _activeSearchByHospitalName = false;
  String _scopeLabel = '내 위치 확인 중';
  bool _onlyWithSpecialists = true;
  bool _isLoading = false;
  bool _isLocating = false;
  String? _errorMessage;
  String? _errorActionLabel;
  VoidCallback? _errorAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _useCurrentLocation(isInitial: true);
    });
  }

  @override
  void dispose() {
    _searchSub?.cancel();
    _positionSubscription?.cancel();
    _searchController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedHospital = _selectedHospital;
    final isUsingSampleData = _hospitals.any(
      (hospital) => hospital.source == '샘플 데이터',
    );
    final hasSpecialistLookupIssue = _hospitals.any(
      (hospital) => hospital.source.contains('전문의 정보 확인 실패'),
    );

    return Scaffold(
      backgroundColor: AppPalette.bg,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          const BannerAdBar(includeTopSafeArea: true),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxHeight = constraints.maxHeight;
                // Stop the sheet just below the floating search + chips so a
                // fully expanded sheet never collides with the top controls.
                final reserved = _topControlsHeight;
                final sheetMax = (1 - reserved / maxHeight).clamp(0.55, 0.9);
                return Stack(
                  children: [
                    Positioned.fill(
                      child: VWorldMapView(
                        hospitals: _hospitals,
                        selectedHospitalId: _selectedHospitalId,
                        currentLatitude: _currentLatitude,
                        currentLongitude: _currentLongitude,
                        currentAccuracyMeters: _currentAccuracyMeters,
                        onHospitalSelected: _selectHospitalFromMap,
                      ),
                    ),
                    _buildFloatingButtons(maxHeight, sheetMax),
                    _HospitalSheet(
                      controller: _sheetController,
                      minSize: _sheetMin,
                      initialSize: _sheetInitial,
                      maxSize: sheetMax,
                      hospitals: _hospitals,
                      selectedHospital: selectedHospital,
                      selectedSpecialty: _selectedSpecialty,
                      scopeLabel: _scopeLabel,
                      referenceLatitude: _latitude ?? _currentLatitude,
                      referenceLongitude: _longitude ?? _currentLongitude,
                      isLoading: _isLoading,
                      onHospitalSelected: _selectHospital,
                      onRefresh: _isLoading ? null : _reloadActiveSearch,
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _TopControls(
                        controller: _searchController,
                        searchMode: _searchMode,
                        selectedSpecialty: _selectedSpecialty,
                        onlyWithSpecialists: _onlyWithSpecialists,
                        isLoading: _isLoading,
                        statusText: _statusText(
                          isUsingSampleData,
                          hasSpecialistLookupIssue,
                        ),
                        errorMessage: _errorMessage,
                        errorActionLabel: _errorActionLabel,
                        onErrorAction: _errorAction,
                        onSearch: _handleSearch,
                        onClear: () {
                          _searchController.clear();
                          _searchMode = _SearchMode.nearby;
                          _useCurrentLocation();
                        },
                        onSearchModeChanged: (mode) {
                          setState(() {
                            _searchMode = mode;
                          });
                        },
                        onSpecialtyChanged: (specialty) {
                          // Filter the already-loaded list in memory — no
                          // network round trip, so this is instant.
                          setState(() {
                            _selectedSpecialty = specialty;
                            _recomputeFiltered();
                          });
                        },
                        onSpecialistToggleChanged: (value) {
                          setState(() {
                            _onlyWithSpecialists = value;
                            _recomputeFiltered();
                          });
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const BannerAdBar(),
        ],
      ),
    );
  }

  String? _statusText(bool isUsingSampleData, bool hasSpecialistLookupIssue) {
    if (!AppConfig.hasDataGoKrKey) {
      return '샘플 데이터로 둘러보는 중';
    }
    if (isUsingSampleData) {
      return '공공데이터 연결 실패 · 샘플 데이터';
    }
    if (hasSpecialistLookupIssue) {
      return '전문의 수 정보를 일부 불러오지 못했어요';
    }
    return null;
  }

  Widget _buildFloatingButtons(double maxHeight, double sheetMax) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _sheetController,
        builder: (context, child) {
          final fraction = _sheetController.isAttached
              ? _sheetController.size
              : _sheetInitial;
          // Ride the sheet up to its initial stop, then hold position and fade
          // out as it expands further so the buttons never reach the controls.
          final posFraction = fraction.clamp(_sheetMin, _sheetInitial);
          final maxBottom = maxHeight - 96;
          final bottom = maxBottom <= 14.0
              ? 14.0
              : (maxHeight * posFraction + 14).clamp(14.0, maxBottom);
          final fadeRange = (sheetMax - _sheetInitial);
          final t = fadeRange <= 0
              ? 0.0
              : ((fraction - _sheetInitial) / fadeRange).clamp(0.0, 1.0);
          final opacity = 1 - t;
          return Padding(
            padding: EdgeInsets.only(right: 16, bottom: bottom),
            child: Align(
              alignment: Alignment.bottomRight,
              child: IgnorePointer(
                ignoring: opacity < 0.05,
                child: Opacity(opacity: opacity, child: child),
              ),
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CircleButton(
              icon: Icons.refresh_rounded,
              tooltip: '새로고침',
              onPressed: _isLoading ? null : _reloadActiveSearch,
            ),
            const SizedBox(height: 10),
            _CircleButton(
              icon: Icons.my_location_rounded,
              tooltip: '내 위치',
              highlighted: true,
              busy: _isLocating,
              onPressed: _isLocating ? null : () => _useCurrentLocation(),
            ),
          ],
        ),
      ),
    );
  }

  Hospital? get _selectedHospital {
    for (final hospital in _hospitals) {
      if (hospital.id == _selectedHospitalId) {
        return hospital;
      }
    }
    return _hospitals.isNotEmpty ? _hospitals.first : null;
  }

  void _reloadActiveSearch() {
    _runSearch(
      keyword: _activeKeyword,
      searchByHospitalName: _activeSearchByHospitalName,
      latitude: _activeSearchByHospitalName ? null : _latitude,
      longitude: _activeSearchByHospitalName ? null : _longitude,
      scopeLabel: _scopeLabel,
    );
  }

  /// Starts a streaming search: the basic list lands first (fast), then
  /// specialist counts fill in. The fetch is always broad (all specialties);
  /// the specialty chips and "전문의만" toggle filter the result in memory.
  void _runSearch({
    required String keyword,
    required bool searchByHospitalName,
    required double? latitude,
    required double? longitude,
    required String scopeLabel,
    MedicalSpecialty? selectedSpecialty,
  }) {
    _searchSub?.cancel();
    final refLat = latitude ?? _currentLatitude;
    final refLng = longitude ?? _currentLongitude;

    setState(() {
      _isLoading = true;
      _isLocating = false;
      _errorMessage = null;
      _errorActionLabel = null;
      _errorAction = null;
      _activeKeyword = keyword;
      _activeSearchByHospitalName = searchByHospitalName;
      _latitude = latitude;
      _longitude = longitude;
      _scopeLabel = scopeLabel;
      _selectedSpecialty =
          selectedSpecialty ??
          (searchByHospitalName ? MedicalSpecialty.all : _selectedSpecialty);
    });

    final query = HospitalSearchQuery(
      keyword: keyword,
      specialty: MedicalSpecialty.all,
      onlyWithSpecialists: false,
      searchByHospitalName: searchByHospitalName,
      latitude: searchByHospitalName ? null : latitude,
      longitude: searchByHospitalName ? null : longitude,
    );

    _searchSub = _repository
        .searchStreaming(query)
        .listen(
          (list) {
            if (!mounted) {
              return;
            }
            setState(() {
              _allHospitals = _sortByDistance(list, refLat, refLng);
              _recomputeFiltered();
              if (_hospitals.isNotEmpty) {
                _errorMessage = null;
              }
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = false;
              _errorMessage = '병원 정보를 불러오지 못했습니다.';
              _errorActionLabel = '다시 시도';
              _errorAction = _reloadActiveSearch;
            });
          },
          onDone: () {
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = false;
              if (_allHospitals.isEmpty) {
                _errorMessage = '검색 결과가 없습니다.';
              }
            });
          },
        );
  }

  void _recomputeFiltered() {
    _hospitals = _filterHospitals(_allHospitals);
    if (_selectedHospitalId == null ||
        !_hospitals.any((hospital) => hospital.id == _selectedHospitalId)) {
      _selectedHospitalId = _hospitals.isEmpty ? null : _hospitals.first.id;
    }
  }

  List<Hospital> _filterHospitals(List<Hospital> all) {
    // Hospital-name searches show every match regardless of the specialty
    // chips, matching the previous behavior.
    if (_activeSearchByHospitalName) {
      return all;
    }
    return all.where((hospital) {
      if (_onlyWithSpecialists) {
        return hospital.hasSpecialistFor(_selectedSpecialty);
      }
      return _selectedSpecialty.id == MedicalSpecialty.all.id ||
          hospital.hasSpecialistFor(_selectedSpecialty);
    }).toList();
  }

  /// Fast name probe: takes only the first (list-only) emission of the stream
  /// and cancels before specialist enrichment, so it stays cheap.
  Future<List<Hospital>> _probeHospitalNames(String keyword) {
    return _repository
        .searchStreaming(
          HospitalSearchQuery(
            keyword: keyword,
            specialty: MedicalSpecialty.all,
            onlyWithSpecialists: false,
            searchByHospitalName: true,
          ),
        )
        .first;
  }

  Future<void> _handleSearch() async {
    final keyword = _searchController.text.trim();
    FocusManager.instance.primaryFocus?.unfocus();
    if (keyword.isEmpty) {
      await _useCurrentLocation();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorActionLabel = null;
      _errorAction = null;
    });

    try {
      if (_searchMode == _SearchMode.hospitalName) {
        _runHospitalNameSearch(keyword);
        return;
      }

      final intent = _SearchKeywordIntent.parse(keyword);
      final specialty = intent.specialty ?? _selectedSpecialty;

      if (intent.specialty == null &&
          (_looksLikeHospitalName(keyword) || keyword.runes.length >= 4)) {
        final nameResults = await _probeHospitalNames(keyword);
        if (_hasStrongHospitalNameMatch(keyword, nameResults)) {
          _runHospitalNameSearch(keyword);
          return;
        }
      }

      if (intent.usesCurrentLocation) {
        await _useCurrentLocation(
          clearSearch: false,
          selectedSpecialty: specialty,
          scopeLabel: _nearbyScopeLabel('내 위치', specialty),
        );
        return;
      }

      final place = await _placeSearch.searchPlace(intent.placeQuery);
      if (place != null) {
        _runSearch(
          keyword: '',
          searchByHospitalName: false,
          latitude: place.latitude,
          longitude: place.longitude,
          scopeLabel: _nearbyScopeLabel(place.title, specialty),
          selectedSpecialty: specialty,
        );
        return;
      }

      final fallbackNameResults = await _probeHospitalNames(keyword);
      if (_hasStrongHospitalNameMatch(keyword, fallbackNameResults) ||
          _looksLikeHospitalName(keyword)) {
        _runHospitalNameSearch(keyword);
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = '지역을 찾지 못했습니다. 병원명 검색으로 바꿔보세요.';
        _errorActionLabel = '병원명으로 검색';
        _errorAction = () {
          setState(() {
            _searchMode = _SearchMode.hospitalName;
          });
          _runHospitalNameSearch(keyword);
        };
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = '검색 결과를 불러오지 못했습니다.';
        _errorActionLabel = '다시 시도';
        _errorAction = _handleSearch;
      });
    }
  }

  void _runHospitalNameSearch(String keyword) {
    setState(() {
      _searchMode = _SearchMode.hospitalName;
    });
    _runSearch(
      keyword: keyword,
      searchByHospitalName: true,
      latitude: null,
      longitude: null,
      scopeLabel: '병원명 "$keyword"',
    );
  }

  static String _nearbyScopeLabel(
    String placeName,
    MedicalSpecialty specialty,
  ) {
    final specialtyLabel = specialty.id == MedicalSpecialty.all.id
        ? ''
        : ' ${specialty.name}';
    return '$placeName 주변$specialtyLabel 5km';
  }

  Future<void> _useCurrentLocation({
    bool isInitial = false,
    bool clearSearch = true,
    MedicalSpecialty? selectedSpecialty,
    String? scopeLabel,
  }) async {
    setState(() {
      _isLocating = true;
      _isLoading = true;
      _errorMessage = null;
      _errorActionLabel = null;
      _errorAction = null;
      if (!isInitial && clearSearch) {
        _searchController.clear();
        _searchMode = _SearchMode.nearby;
      }
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const LocationServiceDisabledException();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const PermissionDeniedException('Location permission denied');
      }

      _ensureLocationStream();
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      if (!mounted) {
        return;
      }

      _updateCurrentLocation(position);
      _runSearch(
        keyword: '',
        searchByHospitalName: false,
        latitude: position.latitude,
        longitude: position.longitude,
        scopeLabel: scopeLabel ?? '내 위치 주변 5km',
        selectedSpecialty: selectedSpecialty,
      );
    } on LocationServiceDisabledException {
      _handleLocationFailure(
        isInitial: isInitial,
        message: '위치 서비스가 꺼져 있습니다. 설정에서 켜 주세요.',
        actionLabel: '위치 설정 열기',
        action: () => Geolocator.openLocationSettings(),
      );
    } on PermissionDeniedException {
      final permission = await Geolocator.checkPermission();
      final permanentlyDenied = permission == LocationPermission.deniedForever;
      _handleLocationFailure(
        isInitial: isInitial,
        message: permanentlyDenied
            ? '위치 권한이 차단되어 있습니다. 앱 설정에서 허용해 주세요.'
            : '주변 병원을 보려면 위치 권한이 필요합니다.',
        actionLabel: permanentlyDenied ? '앱 설정 열기' : '다시 시도',
        action: permanentlyDenied
            ? () => Geolocator.openAppSettings()
            : _useCurrentLocation,
      );
    } catch (_) {
      _handleLocationFailure(
        isInitial: isInitial,
        message: '현재 위치를 확인하지 못했습니다.',
        actionLabel: '다시 시도',
        action: _useCurrentLocation,
      );
    }
  }

  void _handleLocationFailure({
    required bool isInitial,
    required String message,
    required String actionLabel,
    required VoidCallback action,
  }) {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLocating = false;
      _isLoading = false;
      _scopeLabel = isInitial ? '내 위치 권한 필요' : _scopeLabel;
      _errorMessage = message;
      _errorActionLabel = actionLabel;
      _errorAction = action;
    });
  }

  void _selectHospital(String id) {
    setState(() {
      _selectedHospitalId = id;
    });
  }

  void _selectHospitalFromMap(String id) {
    _selectHospital(id);
    // Reveal the list when a marker is tapped so the detail is visible.
    if (_sheetController.isAttached && _sheetController.size < _sheetInitial) {
      _sheetController.animateTo(
        _sheetInitial,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _ensureLocationStream() {
    if (_positionSubscription != null) {
      return;
    }

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen(
          _updateCurrentLocation,
          onError: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _errorMessage ??= '현재 위치를 갱신하지 못했습니다.';
            });
          },
        );
  }

  void _updateCurrentLocation(Position position) {
    if (!mounted) {
      return;
    }

    setState(() {
      _currentLatitude = position.latitude;
      _currentLongitude = position.longitude;
      _currentAccuracyMeters = position.accuracy;
    });
  }

  static List<Hospital> _sortByDistance(
    List<Hospital> hospitals,
    double? latitude,
    double? longitude,
  ) {
    if (latitude == null || longitude == null) {
      return hospitals;
    }

    final sorted = [...hospitals];
    sorted.sort((a, b) {
      final hasA = a.latitude != 0 || a.longitude != 0;
      final hasB = b.latitude != 0 || b.longitude != 0;
      if (!hasA || !hasB) {
        // Push coordinate-less entries to the end without reordering them.
        return hasA == hasB ? 0 : (hasA ? -1 : 1);
      }
      final distanceA = Geolocator.distanceBetween(
        latitude,
        longitude,
        a.latitude,
        a.longitude,
      );
      final distanceB = Geolocator.distanceBetween(
        latitude,
        longitude,
        b.latitude,
        b.longitude,
      );
      return distanceA.compareTo(distanceB);
    });
    return sorted;
  }

  static bool _looksLikeHospitalName(String keyword) {
    return RegExp('병원|의원|의료원|클리닉|치과|한의원|요양병원|보건소').hasMatch(keyword);
  }

  static bool _hasStrongHospitalNameMatch(
    String keyword,
    List<Hospital> hospitals,
  ) {
    final normalizedKeyword = _normalizeSearchText(keyword);
    if (normalizedKeyword.length < 3 || hospitals.isEmpty) {
      return false;
    }

    var hasContainedMatch = false;
    return hospitals.any((hospital) {
          final normalizedName = _normalizeSearchText(hospital.name);
          if (normalizedName == normalizedKeyword ||
              normalizedKeyword.contains(normalizedName)) {
            return true;
          }

          hasContainedMatch =
              hasContainedMatch ||
              (normalizedKeyword.length >= 4 &&
                  normalizedName.contains(normalizedKeyword));
          return false;
        }) ||
        (hospitals.length <= 8 && hasContainedMatch);
  }

  static String _normalizeSearchText(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }
}

// ---------------------------------------------------------------------------
// Top floating controls: brand header, search field, specialty chips, status.
// ---------------------------------------------------------------------------

class _TopControls extends StatelessWidget {
  const _TopControls({
    required this.controller,
    required this.searchMode,
    required this.selectedSpecialty,
    required this.onlyWithSpecialists,
    required this.isLoading,
    required this.statusText,
    required this.errorMessage,
    required this.errorActionLabel,
    required this.onErrorAction,
    required this.onSearch,
    required this.onClear,
    required this.onSearchModeChanged,
    required this.onSpecialtyChanged,
    required this.onSpecialistToggleChanged,
  });

  final TextEditingController controller;
  final _SearchMode searchMode;
  final MedicalSpecialty selectedSpecialty;
  final bool onlyWithSpecialists;
  final bool isLoading;
  final String? statusText;
  final String? errorMessage;
  final String? errorActionLabel;
  final VoidCallback? onErrorAction;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final ValueChanged<_SearchMode> onSearchModeChanged;
  final ValueChanged<MedicalSpecialty> onSpecialtyChanged;
  final ValueChanged<bool> onSpecialistToggleChanged;

  @override
  Widget build(BuildContext context) {
    final specialties = [MedicalSpecialty.all, ...MedicalSpecialty.supported];

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchField(
            controller: controller,
            hintText: searchMode == _SearchMode.nearby
                ? '지역 · 진료과 검색'
                : '병원명 검색',
            isLoading: isLoading,
            onSearch: onSearch,
            onClear: onClear,
          ),
          const SizedBox(height: 8),
          _SearchModeSwitch(value: searchMode, onChanged: onSearchModeChanged),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.zero,
              itemCount: specialties.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _ToggleChip(
                    label: '전문의만',
                    icon: Icons.verified_rounded,
                    selected: onlyWithSpecialists,
                    onTap: () =>
                        onSpecialistToggleChanged(!onlyWithSpecialists),
                  );
                }
                final specialty = specialties[index - 1];
                return _SpecialtyChip(
                  label: specialty.name,
                  selected: specialty.id == selectedSpecialty.id,
                  onTap: () => onSpecialtyChanged(specialty),
                );
              },
            ),
          ),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _StatusChip(
                icon: Icons.info_outline_rounded,
                text: errorMessage!,
                tone: _StatusTone.alert,
                actionLabel: errorActionLabel,
                onAction: onErrorAction,
              ),
            )
          else if (statusText != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _StatusChip(
                icon: Icons.dataset_outlined,
                text: statusText!,
                tone: _StatusTone.muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchModeSwitch extends StatelessWidget {
  const _SearchModeSwitch({required this.value, required this.onChanged});

  final _SearchMode value;
  final ValueChanged<_SearchMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_SearchMode>(
      segments: const [
        ButtonSegment(
          value: _SearchMode.nearby,
          icon: Icon(Icons.travel_explore_rounded, size: 16),
          label: Text('주변'),
        ),
        ButtonSegment(
          value: _SearchMode.hospitalName,
          icon: Icon(Icons.local_hospital_rounded, size: 16),
          label: Text('병원명'),
        ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (values) => onChanged(values.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppPalette.brand
              : AppPalette.surface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : AppPalette.ink;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          return BorderSide(
            color: states.contains(WidgetState.selected)
                ? AppPalette.brand
                : AppPalette.line,
          );
        }),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.isLoading,
    required this.onSearch,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final bool isLoading;
  final VoidCallback onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AppPalette.shadow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppPalette.brand,
                  ),
                )
              : const Icon(Icons.search_rounded, color: AppPalette.brand),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSearch(),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppPalette.ink,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: AppPalette.inkFaint,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 15,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) {
                return const SizedBox(width: 6);
              }
              return IconButton(
                tooltip: '지우기',
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppPalette.inkFaint,
                onPressed: onClear,
              );
            },
          ),
          IconButton(
            tooltip: '검색',
            icon: const Icon(Icons.arrow_forward_rounded, size: 21),
            color: AppPalette.brand,
            onPressed: isLoading ? null : onSearch,
          ),
        ],
      ),
    );
  }
}

class _SpecialtyChip extends StatelessWidget {
  const _SpecialtyChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PillButton(
      onTap: onTap,
      color: selected ? AppPalette.brand : AppPalette.surface,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: selected ? Colors.white : AppPalette.ink,
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PillButton(
      onTap: onTap,
      color: selected ? AppPalette.accent : AppPalette.surface,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: selected ? Colors.white : AppPalette.inkFaint,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: selected ? Colors.white : AppPalette.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.child,
    required this.color,
    required this.onTap,
  });

  final Widget child;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(30),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: AppPalette.shadow,
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.highlighted = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool highlighted;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final background = highlighted ? AppPalette.brand : AppPalette.surface;
    final foreground = highlighted ? Colors.white : AppPalette.ink;

    return Material(
      color: background,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppPalette.shadow,
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: busy
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: foreground,
                  ),
                )
              : Icon(icon, color: foreground, size: 23),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Draggable bottom sheet with the result list.
// ---------------------------------------------------------------------------

class _HospitalSheet extends StatelessWidget {
  const _HospitalSheet({
    required this.controller,
    required this.minSize,
    required this.initialSize,
    required this.maxSize,
    required this.hospitals,
    required this.selectedHospital,
    required this.selectedSpecialty,
    required this.scopeLabel,
    required this.referenceLatitude,
    required this.referenceLongitude,
    required this.isLoading,
    required this.onHospitalSelected,
    required this.onRefresh,
  });

  final DraggableScrollableController controller;
  final double minSize;
  final double initialSize;
  final double maxSize;
  final List<Hospital> hospitals;
  final Hospital? selectedHospital;
  final MedicalSpecialty selectedSpecialty;
  final String scopeLabel;
  final double? referenceLatitude;
  final double? referenceLongitude;
  final bool isLoading;
  final ValueChanged<String> onHospitalSelected;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      snap: true,
      snapSizes: [minSize, initialSize, maxSize],
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 22,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: CustomScrollView(
              controller: scrollController,
              physics: const ClampingScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _GrabHandle()),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SheetHeaderDelegate(
                    count: hospitals.length,
                    scopeLabel: scopeLabel,
                    onRefresh: onRefresh,
                  ),
                ),
                if (hospitals.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: isLoading
                        ? const _LoadingState()
                        : const _EmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                    sliver: SliverList.separated(
                      itemCount: hospitals.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final hospital = hospitals[index];
                        return _HospitalCard(
                          rank: index + 1,
                          hospital: hospital,
                          selectedSpecialty: selectedSpecialty,
                          distanceMeters: _distanceTo(hospital),
                          isSelected: hospital.id == selectedHospital?.id,
                          onTap: () => onHospitalSelected(hospital.id),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  double? _distanceTo(Hospital hospital) {
    final lat = referenceLatitude;
    final lng = referenceLongitude;
    if (lat == null || lng == null) {
      return null;
    }
    if (hospital.latitude == 0 && hospital.longitude == 0) {
      return null;
    }
    return Geolocator.distanceBetween(
      lat,
      lng,
      hospital.latitude,
      hospital.longitude,
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 2),
        width: 42,
        height: 5,
        decoration: BoxDecoration(
          color: AppPalette.line,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _SheetHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SheetHeaderDelegate({
    required this.count,
    required this.scopeLabel,
    required this.onRefresh,
  });

  final int count;
  final String scopeLabel;
  final VoidCallback? onRefresh;

  @override
  double get minExtent => 62;
  @override
  double get maxExtent => 62;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppPalette.surface,
      padding: const EdgeInsets.fromLTRB(18, 2, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.brand,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Text(
                      '곳',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.ink,
                      ),
                    ),
                  ],
                ),
                Text(
                  scopeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('새로고침'),
              style: TextButton.styleFrom(
                foregroundColor: AppPalette.brand,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SheetHeaderDelegate oldDelegate) {
    return count != oldDelegate.count ||
        scopeLabel != oldDelegate.scopeLabel ||
        onRefresh != oldDelegate.onRefresh;
  }
}

// ---------------------------------------------------------------------------
// Hospital card.
// ---------------------------------------------------------------------------

class _HospitalCard extends StatelessWidget {
  const _HospitalCard({
    required this.rank,
    required this.hospital,
    required this.selectedSpecialty,
    required this.distanceMeters,
    required this.isSelected,
    required this.onTap,
  });

  final int rank;
  final Hospital hospital;
  final MedicalSpecialty selectedSpecialty;
  final double? distanceMeters;
  final bool isSelected;
  final VoidCallback onTap;

  static String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()}m';
    }
    return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)}km';
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = hospital.specialistFor(selectedSpecialty)?.count;
    final displayedSpecialists = hospital.specialists
        .take(isSelected ? 12 : 3)
        .toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? AppPalette.brand : AppPalette.line,
          width: isSelected ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected ? const Color(0x1F0E7C66) : AppPalette.shadow,
            blurRadius: isSelected ? 18 : 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RankAvatar(rank: rank, selected: isSelected),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hospital.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.ink,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              if (hospital.category.isNotEmpty) ...[
                                _CategoryTag(text: hospital.category),
                                const SizedBox(width: 6),
                              ],
                              if (distanceMeters != null) ...[
                                const Icon(
                                  Icons.near_me_rounded,
                                  size: 13,
                                  color: AppPalette.brand,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _formatDistance(distanceMeters!),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppPalette.brand,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SpecialistBadge(
                      count: selectedCount ?? hospital.totalSpecialists,
                      label: selectedCount == null
                          ? '전문의'
                          : selectedSpecialty.name,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: AppPalette.inkFaint,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        hospital.address,
                        maxLines: isSelected ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppPalette.inkSoft,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: displayedSpecialists.isEmpty
                      ? const [_SpecialtyPill(text: '전문의 정보 없음', muted: true)]
                      : displayedSpecialists
                            .map(
                              (item) => _SpecialtyPill(
                                text: '${item.name} ${item.count}',
                              ),
                            )
                            .toList(),
                ),
                if (isSelected) _HospitalActions(hospital: hospital),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RankAvatar extends StatelessWidget {
  const _RankAvatar({required this.rank, required this.selected});

  final int rank;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppPalette.brand, AppPalette.brandDark],
              )
            : null,
        color: selected ? null : AppPalette.brandSofter,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: selected ? Colors.white : AppPalette.brand,
        ),
      ),
    );
  }
}

class _CategoryTag extends StatelessWidget {
  const _CategoryTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppPalette.brandSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppPalette.brandDark,
        ),
      ),
    );
  }
}

class _HospitalActions extends StatelessWidget {
  const _HospitalActions({required this.hospital});

  final Hospital hospital;

  Future<void> _call(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await callHospital(hospital.phone);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('전화번호 정보가 없습니다.')));
    }
  }

  Future<void> _directions(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await openDirections(hospital);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('지도 앱을 열 수 없습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = hospital.phone
        .replaceAll(RegExp(r'[^0-9]'), '')
        .isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: hasPhone ? () => _call(context) : null,
              icon: const Icon(Icons.call_rounded, size: 18),
              label: const Text('전화'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.brand,
                side: const BorderSide(color: AppPalette.brandSoft, width: 1.4),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _directions(context),
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: const Text('길찾기'),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.brand,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialistBadge extends StatelessWidget {
  const _SpecialistBadge({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Container(
      constraints: const BoxConstraints(minWidth: 52),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppPalette.brand, AppPalette.brandDark],
              )
            : null,
        color: active ? null : AppPalette.line,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 17,
              height: 1,
              fontWeight: FontWeight.w900,
              color: active ? Colors.white : AppPalette.inkFaint,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white70 : AppPalette.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialtyPill extends StatelessWidget {
  const _SpecialtyPill({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: muted ? AppPalette.bg : AppPalette.accentBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: muted ? AppPalette.inkFaint : AppPalette.accentInk,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum _StatusTone { muted, alert }

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.text,
    required this.tone,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final _StatusTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isAlert = tone == _StatusTone.alert;
    final accent = isAlert ? AppPalette.danger : AppPalette.inkSoft;

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: AppPalette.shadow,
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: accent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: AppPalette.ink,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppPalette.brand,
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          else
            const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 56),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 30,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppPalette.brand,
            ),
          ),
          SizedBox(height: 16),
          Text(
            '주변 병원을 찾는 중…',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppPalette.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppPalette.brandSofter,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 30,
              color: AppPalette.brand,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '검색 결과가 없어요',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '다른 지역이나 병원명으로 검색하거나\n전문의 필터를 꺼 보세요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppPalette.inkSoft,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
