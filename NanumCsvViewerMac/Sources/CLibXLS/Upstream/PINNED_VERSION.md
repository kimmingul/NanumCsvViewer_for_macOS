# libxls Vendored Source

- Upstream: https://github.com/libxls/libxls
- Version: `v1.6.3`
- Commit: `c199d132494833da696b58aa4acf3fc5a36d930b`
- License: BSD-style license, bundled in `LICENSE`

Vendored files are limited to the reader library sources and public headers:

- `src/xlstool.c`
- `src/endian.c`
- `src/locale.c`
- `src/ole.c`
- `src/xls.c`
- `include/xls.h`
- `include/libxls/*.h`

The upstream `xls2csv` CLI and test executables are intentionally not bundled
into the app target. The main app and `CsvCore` must not depend on this target;
only `ImportService` links `CLibXLS`.
