import 'medical_specialty.dart';

class Hospital {
  const Hospital({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.specialists,
    required this.source,
    this.isDesignatedSpecialHospital = false,
  });

  final String id;
  final String name;
  final String category;
  final String address;
  final String phone;
  final double latitude;
  final double longitude;
  final List<SpecialistCount> specialists;
  final String source;
  final bool isDesignatedSpecialHospital;

  Hospital copyWith({
    List<SpecialistCount>? specialists,
    String? source,
  }) {
    return Hospital(
      id: id,
      name: name,
      category: category,
      address: address,
      phone: phone,
      latitude: latitude,
      longitude: longitude,
      specialists: specialists ?? this.specialists,
      source: source ?? this.source,
      isDesignatedSpecialHospital: isDesignatedSpecialHospital,
    );
  }

  int get totalSpecialists {
    return specialists.fold(0, (sum, item) => sum + item.count);
  }

  bool hasSpecialistFor(MedicalSpecialty specialty) {
    if (specialty.id == MedicalSpecialty.all.id) {
      return totalSpecialists > 0;
    }

    return specialists.any(
      (item) => item.hiraCode == specialty.hiraCode && item.count > 0,
    );
  }

  SpecialistCount? specialistFor(MedicalSpecialty specialty) {
    if (specialty.id == MedicalSpecialty.all.id) {
      return null;
    }

    for (final item in specialists) {
      if (item.hiraCode == specialty.hiraCode) {
        return item;
      }
    }
    return null;
  }
}

class SpecialistCount {
  const SpecialistCount({
    required this.hiraCode,
    required this.name,
    required this.count,
  });

  final String hiraCode;
  final String name;
  final int count;
}

class HospitalSearchQuery {
  const HospitalSearchQuery({
    required this.keyword,
    required this.specialty,
    required this.onlyWithSpecialists,
    this.searchByHospitalName = false,
    this.latitude,
    this.longitude,
    this.radiusMeters = 5000,
  });

  final String keyword;
  final MedicalSpecialty specialty;
  final bool onlyWithSpecialists;
  final bool searchByHospitalName;
  final double? latitude;
  final double? longitude;
  final int radiusMeters;
}

abstract class HospitalRepository {
  Future<List<Hospital>> search(HospitalSearchQuery query);

  /// Emits results progressively: the basic hospital list first (so the UI can
  /// render immediately), then updated lists as specialist counts are filled
  /// in. Implementations that have nothing to stream may emit a single list.
  Stream<List<Hospital>> searchStreaming(HospitalSearchQuery query);
}
