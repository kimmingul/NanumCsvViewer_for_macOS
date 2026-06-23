# Release Notes

## v0.1.0 - 2026-06-24

Nanum CSV Viewer for macOS의 첫 Developer ID 배포 릴리즈입니다.

### Highlights

- Swift/AppKit 기반 macOS 네이티브 CSV viewer
- 1GiB 이상 대용량 CSV 파일을 위한 byte offset indexing 및 virtual table rendering
- UTF-8, UTF-8 BOM, CP949(EUC-KR) 자동 감지
- 따옴표 안 줄바꿈, 구분자, escaped quote 처리
- Apple 스타일 toolbar, filter bar, 선택 값 표시 바, inspector, status bar UI
- 검색, 컬럼 필터, 선택 셀 값 필터, 단일/다중 컬럼 정렬
- `mmap` 기반 file source, 병렬 no-quote indexing fast path, fast filter/sort path
- Developer ID Application 서명 및 Apple notarization/stapling 배포 스크립트

### Benchmark

1GiB synthetic CSV 기준 최근 release benchmark 결과입니다.

```text
index        0.235 s
filter       0.288 s
contains     1.154 s
sort         4.232 s
```

측정 파일은 repository에 포함하지 않으며, `CsvBench`로 재생성할 수 있습니다.

### Distribution

- Bundle version: `0.1.0`
- Minimum macOS: `14.0`
- Signing identity: `Developer ID Application: MINGUL KIM (XB673TQF3A)`
- Notarization: Apple notary service accepted and stapled
- Release artifact: `Nanum-CSV-Viewer-v0.1.0.zip`

### Notes

- 현재는 `.app` bundle zip 배포 방식입니다.
- installer package, Sparkle auto-update, App Store 배포는 아직 포함하지 않았습니다.
- 공개 배포 전 별도 `LICENSE` 파일 추가를 권장합니다.
