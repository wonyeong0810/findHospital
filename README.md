# 전문의 병원 지도

한국 병원 중 진료과목명만 보고 전문의 상주 여부를 오해하기 쉬운 문제를 줄이기 위한 Flutter 지도 앱입니다. Android 우선 MVP이며, 브이월드 WMTS 지도와 건강보험심사평가원 공공데이터 연동을 기준으로 구성했습니다.

## 실행

`.env` 파일을 프로젝트 루트에 만들고 아래 값을 넣습니다.

```dotenv
VWORLD_API_KEY=브이월드_인증키
DATA_GO_KR_SERVICE_KEY=공공데이터포털_서비스키
```

공공데이터포털의 두 활용신청 화면에서 인증키가 다르게 보이면 아래처럼 분리해서 넣습니다.

```dotenv
HIRA_HOSPITAL_SERVICE_KEY=병원정보서비스_서비스키
HIRA_DETAIL_SERVICE_KEY=의료기관별상세정보서비스_서비스키
```

```bash
flutter pub get
flutter run -d R3CX20AT0KJ --dart-define-from-file=.env
```

키 없이 실행하면 병원 목록은 샘플 데이터로 표시되고, 브이월드 키를 넣으면 지도 타일이 표시됩니다.

## 데이터 흐름

- 병원 기본 목록: `https://apis.data.go.kr/B551182/hospInfoServicev2/getHospBasisList`
- 전문과목별 전문의 수: `https://apis.data.go.kr/B551182/MadmDtlInfoService2.8/getSpcSbjtSdrInfo2.8`
- 지도 타일: `https://api.vworld.kr/req/wmts/1.0.0/{key}/Base/{z}/{y}/{x}.png`

## 주요 파일

- `lib/features/home/hospital_finder_page.dart`: 검색, 전문과 필터, 목록 UI
- `lib/features/map/vworld_map_view.dart`: WebView 기반 브이월드 지도와 마커 연동
- `lib/data/hira_hospital_repository.dart`: 심평원 API 어댑터
- `lib/data/vworld_search_service.dart`: 브이월드 지역/장소 검색
- `lib/data/sample_hospitals.dart`: 키가 없을 때 쓰는 샘플 데이터
- `lib/features/home/hospital_actions.dart`: 전화 걸기·길찾기 실행
- `lib/config/app_config.dart`: `--dart-define` 설정

## 검색 동작

- 앱 시작 시 위치 권한을 요청하고 내 위치 주변 5km 병원을 보여줍니다.
- 앱이 켜져 있는 동안 현재 위치가 지도 위 파란 점과 정확도 원으로 실시간 갱신됩니다.
- 지역명이나 장소명을 검색하면 브이월드 검색 API로 좌표를 찾은 뒤 그 주변 병원을 보여줍니다.
- 병원명으로 검색하면 병원명 검색 결과를 보여주고, 선택한 병원의 전문과목별 전문의 수를 확인할 수 있습니다.
- 목록은 기준 위치(검색 중심 또는 내 위치)에서 가까운 순으로 정렬되며, 각 항목에 거리를 표시합니다.
- 선택한 병원에서 바로 전화 걸기, 지도 앱으로 길찾기를 실행할 수 있습니다.
- 병원 목록 요청은 18초 타임아웃 + 1회 재시도로 처리합니다(심평원 API가 모바일에서 느린 경우 대비). 그래도 실패하면 샘플 데이터로 폴백하고 배너의 "다시 시도"로 재요청할 수 있습니다.
- 위치 서비스가 꺼져 있거나 권한이 차단되면 배너에서 해당 설정 화면을 바로 엽니다.

## Android 권한

`android/app/src/main/AndroidManifest.xml`에 인터넷과 위치 권한, 그리고 전화/지도 앱 호출을 위한 `<queries>`를 추가했습니다. 위치 권한은 주변 병원 검색 반경 기준으로 사용합니다.

## 배포 (Play Store)

애플리케이션 ID는 `com.kawkdev.findhospital`입니다.

### 1. 업로드 키스토어 생성 (최초 1회)

```bash
keytool -genkey -v -keystore ~/findhospital-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

> 키스토어 파일과 비밀번호는 안전하게 백업하세요. 분실하면 같은 앱 등록 정보로 업데이트를 올릴 수 없습니다.

### 2. 서명 설정 연결

`android/key.properties.example`를 `android/key.properties`로 복사하고 값을 채웁니다. 이 파일과 `.jks`는 `.gitignore`에 포함되어 커밋되지 않습니다. `key.properties`가 없으면 릴리스 빌드는 디버그 키로 서명되어 로컬 실행만 가능합니다.

### 3. 릴리스 빌드

```bash
# Play Store 업로드용 App Bundle
flutter build appbundle --release --dart-define-from-file=.env

# 단말 직접 설치용 APK
flutter build apk --release --dart-define-from-file=.env
```

릴리스 빌드는 R8 코드 축소와 리소스 축소(`isMinifyEnabled`, `isShrinkResources`)가 적용됩니다. 규칙은 `android/app/proguard-rules.pro`에 있습니다.

> API 키는 `--dart-define`으로 빌드에 포함되므로 빌드 산출물에 키가 들어갑니다. 공개 배포 시에는 키 제한(브이월드 도메인/앱 제한, data.go.kr 트래픽 한도)을 반드시 설정하세요. Play Store 등록에는 위치 권한 사용에 대한 개인정보 처리방침 URL이 필요합니다.

## 광고 (AdMob)

화면 하단에 상시 배너 광고(앵커 적응형 배너)가 표시됩니다. 광고가 로드되지 않으면 배너 영역은 접혀서 빈 공간을 남기지 않습니다.

- 광고 위젯: `lib/features/ads/banner_ad_bar.dart`
- SDK 초기화: `lib/main.dart`의 `MobileAds.instance.initialize()`
- 단위 ID 설정: `lib/config/app_config.dart`

**개발 중에는 구글 공식 테스트 광고 ID가 기본값**이므로 그대로 실행하면 테스트 광고가 표시됩니다. 실제 광고로 전환하려면 AdMob 콘솔에서 앱과 배너 광고 단위를 만든 뒤:

1. `android/app/src/main/AndroidManifest.xml`의 `com.google.android.gms.ads.APPLICATION_ID` 값을 본인 앱 ID(`ca-app-pub-XXXX~YYYY`)로 교체합니다.
2. 릴리스 빌드 시 배너 단위 ID를 주입합니다.

```bash
flutter build appbundle --release \
  --dart-define-from-file=.env \
  --dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-XXXX/ZZZZ
```

> 실제 기기에서 본인 광고를 반복 클릭하면 AdMob 정책 위반(무효 트래픽)으로 계정이 정지될 수 있습니다. 개발/테스트는 반드시 테스트 광고 ID로 진행하세요.
