# Third-Party Notices

## libxls

- Upstream: https://github.com/libxls/libxls
- Version: `v1.6.3`
- Commit: `c199d132494833da696b58aa4acf3fc5a36d930b`
- License: BSD-style license
- Bundled license: `Sources/CLibXLS/Upstream/LICENSE`

`libxls` is vendored as source and linked only into the sandboxed
`ImportService` XPC service for read-only legacy `.xls` import.

## ReadStat

- Upstream: https://github.com/WizardMac/ReadStat
- Commit: `3c68974fbb35c5bf0888fd603cd99b8253477359`
- License: MIT
- Bundled license: `Sources/CReadStat/Upstream/LICENSE`

`ReadStat` is vendored as source and linked only into the sandboxed
`ImportService` XPC service for read-only SPSS `.sav` and SAS `.sas7bdat`
import.

## Vendored Source Refresh Process

- Refresh vendored parser source only for security fixes or required format
  support.
- Snapshot a specific upstream commit, update `Upstream/PINNED_VERSION.md`,
  and keep the bundled license in the corresponding `Upstream/LICENSE`.
- Keep parser targets linked only by `ImportService`; the main app and
  `CsvCore` must not depend on `CLibXLS` or `CReadStat`.
- Re-run fixture, malformed/corpus, full `swift test`, app build/sign, XPC
  smoke tests, and parser-linkage audits before shipping.
