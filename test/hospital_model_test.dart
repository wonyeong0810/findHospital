import 'package:flutter_test/flutter_test.dart';
import 'package:find_hospital/domain/hospital.dart';
import 'package:find_hospital/domain/medical_specialty.dart';

Hospital _hospital({
  String id = 'test',
  String name = '테스트 병원',
  String phone = '02-0000-0000',
  double latitude = 37.5,
  double longitude = 127,
  List<SpecialistCount> specialists = const [],
}) {
  return Hospital(
    id: id,
    name: name,
    category: '의원',
    address: '서울',
    phone: phone,
    latitude: latitude,
    longitude: longitude,
    source: 'test',
    specialists: specialists,
  );
}

void main() {
  group('Hospital.hasSpecialistFor', () {
    final hospital = _hospital(
      specialists: const [
        SpecialistCount(hiraCode: '14', name: '피부과', count: 1),
      ],
    );

    test('matches a specialty that has specialists', () {
      expect(hospital.hasSpecialistFor(MedicalSpecialty.byHiraCode('14')!),
          isTrue);
    });

    test('does not match a specialty without specialists', () {
      expect(hospital.hasSpecialistFor(MedicalSpecialty.byHiraCode('13')!),
          isFalse);
    });

    test('matches "all" when any specialist exists', () {
      expect(hospital.hasSpecialistFor(MedicalSpecialty.all), isTrue);
      expect(_hospital().hasSpecialistFor(MedicalSpecialty.all), isFalse);
    });
  });

  group('Hospital.totalSpecialists', () {
    test('sums every specialist count', () {
      final hospital = _hospital(
        specialists: const [
          SpecialistCount(hiraCode: '01', name: '내과', count: 2),
          SpecialistCount(hiraCode: '23', name: '가정의학과', count: 3),
        ],
      );
      expect(hospital.totalSpecialists, 5);
    });
  });

  group('Hospital.specialistFor', () {
    test('returns the matching specialty entry, null for "all"', () {
      final hospital = _hospital(
        specialists: const [
          SpecialistCount(hiraCode: '05', name: '정형외과', count: 4),
        ],
      );
      expect(
        hospital.specialistFor(MedicalSpecialty.byHiraCode('05')!)?.count,
        4,
      );
      expect(hospital.specialistFor(MedicalSpecialty.all), isNull);
    });
  });

  group('MedicalSpecialty.byHiraCode', () {
    test('resolves a known code and returns null for unknown', () {
      expect(MedicalSpecialty.byHiraCode('11')?.name, '소아청소년과');
      expect(MedicalSpecialty.byHiraCode('99'), isNull);
    });
  });
}
