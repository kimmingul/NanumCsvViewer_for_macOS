# ReadStat Vendored Snapshot

- Upstream: https://github.com/WizardMac/ReadStat
- Commit: `3c68974fbb35c5bf0888fd603cd99b8253477359`
- Snapshot date: 2026-07-08
- License: MIT, bundled in `LICENSE`

This target vendors the C library source directly for read-only SPSS `.sav` and
SAS `.sas7bdat` import inside the XPC `ImportService`. The main app and
`CsvCore` must not depend on this target.
