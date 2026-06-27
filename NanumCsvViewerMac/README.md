# Nanum CSV Viewer for macOS

Swift/AppKit 기반 macOS용 대용량 CSV 뷰어입니다. Windows WinForms 버전의 핵심 구조인 바이트 오프셋 인덱스, 가상 테이블, 보이는 행만 디코딩하는 방식을 Swift로 포팅했습니다.

## Build

```bash
swift build
swift test
swift run NanumCsvViewerMac
```

샌드박스 환경에서 SwiftPM이 모듈 캐시 권한 문제를 내면 다음처럼 로컬 캐시를 지정합니다.

```bash
CLANG_MODULE_CACHE_PATH=../.clang-cache swift build
CLANG_MODULE_CACHE_PATH=../.clang-cache swift test
CLANG_MODULE_CACHE_PATH=../.clang-cache swift run NanumCsvViewerMac
```

## App Bundle

SwiftPM 실행 파일을 간단한 `.app` 번들로 묶으려면:

```bash
Scripts/build-app.sh
open "dist/Nanum CSV Viewer.app"
```

## Mac App Store Package

Mac App Store 제출용 빌드는 Developer ID 배포용 DMG와 별도로 생성합니다.

```bash
Scripts/build-appstore-app.sh
Scripts/package-appstore.sh
```

기본 bundle id는 `com.nanumspace.mgkim.nanumcsvviewer`이고, App Sandbox entitlement를 포함합니다. 업로드에는 App Store Connect API key 또는 Apple ID app-specific password가 필요합니다.

```bash
ASC_KEY_ID="XXXXXXXXXX" \
ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
Scripts/upload-appstore.sh
```

## v1.7.3 Highlights

- 피벗 차트가 SwiftUI Charts 기반 네이티브 차트로 표시됩니다.
- 피벗 차트에서 막대, 묶은 막대, 누적 막대, 꺾은선 모드를 선택할 수 있고 범례와 hover tooltip을 제공합니다.
- Date 그룹핑된 피벗 차트는 꺾은선 차트를 기본으로 추천합니다.
- 분석 메뉴의 숫자 분포, 날짜 히스토그램, 중복 행, 그룹화, 상관분석, t-검정, 카이제곱 검정 조건 선택 창을 전용 sheet로 교체해 컬럼 선택 필드와 실행/취소 버튼이 잘리지 않도록 했습니다.
- 피벗 빌더는 다중 측정값, 측정값별 집계 선택, 날짜 행/열/필터 그룹핑, 필터 드롭다운, `null` 차원 그룹, 값만/행+값/열+값 레이아웃을 지원합니다.

## Implemented

- UTF-8 / UTF-8 BOM / CP949(EUC-KR) 자동 감지
- UTF-16/UTF-32 고속 모드 차단
- CSV 레코드 바이트 오프셋 인덱싱
- 따옴표 안 줄바꿈/구분자 처리
- `NSTableView` 기반 가상 행 표시
- 백그라운드 인덱싱 진행률
- 검색, 전체/컬럼 필터, 선택 셀 값 AND 필터
- 단일/Shift 클릭 다중 컬럼 안정 정렬
- 원본 행 번호 표시
- 우측 상세 패널
- 추론된 컬럼 타입 배지와 타입 기반 분석/피벗 기본값
- 전용 분석 조건 sheet와 텍스트 기반 분석 결과
- SwiftUI Charts 기반 피벗 차트
- Excel 스타일 피벗 빌더
- 라이트/다크 시스템 외형 대응

## Structure

- `Sources/CsvCore`: 대용량 CSV 엔진
- `Sources/NanumCsvViewerMac`: AppKit UI
- `Tests/CsvCoreTests`: C# 원본 테스트에서 포팅한 엔진 동등성 테스트
