# Nanum CSV Viewer for macOS

Swift/AppKit 기반 macOS용 대용량 CSV viewer입니다. 1GB 이상의 CSV 파일을 빠르게 열고, 백그라운드 인덱싱 중에도 가상 테이블로 데이터를 탐색할 수 있도록 설계했습니다.

## 주요 기능

- UTF-8, UTF-8 BOM, CP949(EUC-KR) 자동 감지
- CSV 레코드 byte offset indexing
- 따옴표 안 줄바꿈, 구분자, escaped quote 처리
- `NSTableView` 기반 virtual row rendering
- 백그라운드 indexing progress
- 검색, 컬럼 필터, 선택 셀 값 필터
- 단일 컬럼 fast filter/sort path
- Shift-click 다중 정렬
- 선택 값 표시 바, filter bar, Inspector 패널
- macOS light/dark appearance 대응
- 1GiB CSV benchmark CLI 포함

## 프로젝트 구조

```text
NanumCsvViewerMac/
  Package.swift
  Sources/
    CsvCore/              # 대용량 CSV engine
    NanumCsvViewerMac/    # AppKit UI
    CsvBench/             # 1GiB benchmark CLI
  Tests/CsvCoreTests/     # CSV parser/index/filter/sort tests
  Scripts/build-app.sh    # .app bundle 생성 스크립트
```

## 요구 사항

- macOS 14 이상
- Swift 6.x / Xcode command line tools

## 빌드 및 테스트

```bash
cd NanumCsvViewerMac
swift build
swift test
```

SwiftPM module cache 권한 문제가 있으면 로컬 캐시를 지정합니다.

```bash
CLANG_MODULE_CACHE_PATH=../.clang-cache swift build
CLANG_MODULE_CACHE_PATH=../.clang-cache swift test
```

## 앱 실행

```bash
cd NanumCsvViewerMac
swift run NanumCsvViewerMac
```

앱 번들을 만들려면:

```bash
cd NanumCsvViewerMac
Scripts/build-app.sh
open "dist/Nanum CSV Viewer.app"
```

## 벤치마크

1GiB benchmark CSV는 repository에 포함하지 않습니다. 필요할 때 생성합니다.

```bash
cd NanumCsvViewerMac
swift build -c release --product CsvBench
.build/release/CsvBench --generate
```

이후 같은 파일을 재사용해서 측정합니다.

```bash
.build/release/CsvBench
```

최근 1GiB benchmark 결과:

```text
index        0.235 s
filter       0.288 s
contains     1.154 s
sort         4.232 s
```

측정 파일:

```text
NanumCsvViewerMac/BenchmarkData/one_gib.csv
```

이 파일은 1GiB 크기라 `.gitignore`에 포함되어 있습니다.

## 성능 설계

- 파일 전체를 row 단위로 미리 파싱하지 않고 record start offset만 인덱싱합니다.
- 화면에 보이는 row만 디코딩하고 LRU cache에 보관합니다.
- quote 없는 단순 CSV는 병렬 newline scan으로 빠르게 인덱싱합니다.
- quote가 포함된 CSV는 정확도를 위해 상태 머신 기반 인덱서로 fallback합니다.
- 특정 컬럼 equality/contains 필터는 전체 row parse 없이 해당 컬럼만 추출합니다.
- 단일 컬럼 정렬은 정렬 key만 추출해서 전체 row parse 비용을 줄입니다.
- macOS에서는 `mmap` 기반 byte source를 우선 사용하고 실패 시 `pread` 기반 source로 fallback합니다.

## 라이선스

라이선스는 아직 지정하지 않았습니다. 공개 배포 전 `LICENSE` 파일을 추가하는 것을 권장합니다.
