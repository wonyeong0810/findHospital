class MedicalSpecialty {
  const MedicalSpecialty({
    required this.id,
    required this.name,
    required this.hiraCode,
  });

  final String id;
  final String name;
  final String hiraCode;

  static const all = MedicalSpecialty(id: 'all', name: '전체', hiraCode: '');

  static const supported = <MedicalSpecialty>[
    MedicalSpecialty(id: 'internal', name: '내과', hiraCode: '01'),
    MedicalSpecialty(id: 'neurology', name: '신경과', hiraCode: '02'),
    MedicalSpecialty(id: 'psychiatry', name: '정신건강의학과', hiraCode: '03'),
    MedicalSpecialty(id: 'surgery', name: '외과', hiraCode: '04'),
    MedicalSpecialty(id: 'orthopedics', name: '정형외과', hiraCode: '05'),
    MedicalSpecialty(id: 'obgyn', name: '산부인과', hiraCode: '10'),
    MedicalSpecialty(id: 'pediatrics', name: '소아청소년과', hiraCode: '11'),
    MedicalSpecialty(id: 'ophthalmology', name: '안과', hiraCode: '12'),
    MedicalSpecialty(id: 'ent', name: '이비인후과', hiraCode: '13'),
    MedicalSpecialty(id: 'dermatology', name: '피부과', hiraCode: '14'),
    MedicalSpecialty(id: 'urology', name: '비뇨의학과', hiraCode: '15'),
    MedicalSpecialty(id: 'rehab', name: '재활의학과', hiraCode: '21'),
    MedicalSpecialty(id: 'family', name: '가정의학과', hiraCode: '23'),
    MedicalSpecialty(id: 'emergency', name: '응급의학과', hiraCode: '24'),
  ];

  static MedicalSpecialty? byHiraCode(String code) {
    for (final specialty in supported) {
      if (specialty.hiraCode == code) {
        return specialty;
      }
    }
    return null;
  }
}
