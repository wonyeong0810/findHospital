import '../domain/hospital.dart';
import '../domain/medical_specialty.dart';

class SampleHospitalRepository implements HospitalRepository {
  const SampleHospitalRepository();

  @override
  Future<List<Hospital>> search(HospitalSearchQuery query) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));

    final keyword = query.keyword.trim().toLowerCase();
    final filtered = sampleHospitals.where((hospital) {
      final matchesKeyword = keyword.isEmpty
          ? true
          : query.searchByHospitalName
          ? hospital.name.toLowerCase().contains(keyword)
          : hospital.name.toLowerCase().contains(keyword) ||
                hospital.address.toLowerCase().contains(keyword) ||
                hospital.category.toLowerCase().contains(keyword);
      final matchesSpecialty =
          query.specialty.id == MedicalSpecialty.all.id ||
          hospital.hasSpecialistFor(query.specialty);
      final matchesSpecialistToggle =
          !query.onlyWithSpecialists ||
          hospital.hasSpecialistFor(query.specialty);

      return matchesKeyword && matchesSpecialty && matchesSpecialistToggle;
    }).toList();

    return filtered;
  }

  @override
  Stream<List<Hospital>> searchStreaming(HospitalSearchQuery query) async* {
    yield await search(query);
  }
}

const sampleHospitals = <Hospital>[
  Hospital(
    id: 'sample-1',
    name: '샘플서울내과의원',
    category: '의원',
    address: '서울특별시 중구 세종대로 일대',
    phone: '02-0000-0001',
    latitude: 37.5665,
    longitude: 126.978,
    source: '샘플 데이터',
    specialists: [
      SpecialistCount(hiraCode: '01', name: '내과', count: 2),
      SpecialistCount(hiraCode: '23', name: '가정의학과', count: 1),
    ],
  ),
  Hospital(
    id: 'sample-2',
    name: '샘플튼튼정형외과의원',
    category: '의원',
    address: '서울특별시 종로구 청계천로 일대',
    phone: '02-0000-0002',
    latitude: 37.5701,
    longitude: 126.9823,
    source: '샘플 데이터',
    specialists: [
      SpecialistCount(hiraCode: '05', name: '정형외과', count: 1),
      SpecialistCount(hiraCode: '21', name: '재활의학과', count: 1),
    ],
  ),
  Hospital(
    id: 'sample-3',
    name: '샘플아이소아청소년과의원',
    category: '의원',
    address: '서울특별시 마포구 월드컵북로 일대',
    phone: '02-0000-0003',
    latitude: 37.5571,
    longitude: 126.9245,
    source: '샘플 데이터',
    specialists: [
      SpecialistCount(hiraCode: '11', name: '소아청소년과', count: 1),
      SpecialistCount(hiraCode: '13', name: '이비인후과', count: 1),
    ],
  ),
  Hospital(
    id: 'sample-4',
    name: '샘플맑은피부과의원',
    category: '의원',
    address: '서울특별시 강남구 테헤란로 일대',
    phone: '02-0000-0004',
    latitude: 37.5013,
    longitude: 127.0396,
    source: '샘플 데이터',
    specialists: [SpecialistCount(hiraCode: '14', name: '피부과', count: 1)],
  ),
  Hospital(
    id: 'sample-5',
    name: '샘플여성산부인과의원',
    category: '의원',
    address: '서울특별시 서초구 서초대로 일대',
    phone: '02-0000-0005',
    latitude: 37.4923,
    longitude: 127.0144,
    source: '샘플 데이터',
    specialists: [SpecialistCount(hiraCode: '10', name: '산부인과', count: 2)],
  ),
];
