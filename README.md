# RowSkan

Local-first vehicle inventory for dealerships, junkyards and tow yards. A product of [LIT America](https://litamerica.net).

## Current release candidate

- `index.html` and `web/`: solo-owner browser application with local inventory, photographs, recoverable drafts, encrypted browser backups, supported-browser VIN barcode scanning and offline application shell.
- `docs/`: matching browser distribution for GitHub Pages configurations that use /docs.
- `native/`: Flutter application for Android, iOS, Windows and macOS with SQLite storage, system phone camera capture and VIN barcode scanning.
- GitHub Actions: browser validation and native Android/Windows/Mac builds and data-recovery tests.

The browser app starts empty for new installations. Existing local inventory is preserved. Its data remains within that browser profile, not in GitHub or a cloud inventory database. VIN lookup calls NHTSA when requested.

## Test the applications

Use the published GitHub Pages site for the browser edition. To test native builds, open **Actions → RowSkan release checks → a successful run → Artifacts**. Android packages are debug APKs; desktop packages are preview builds. Real-device validation and distribution signing are still required.

This is an early-access candidate, not a completed commercial release. Internet device sync, signed administrator/device enrollment, cloud subscriptions and store distribution are not enabled. GitHub Pages is a demonstration host; a dedicated application domain is required before commercial use with sensitive inventory. Native and browser backup formats are separate.

See [RELEASE.md](RELEASE.md) for implemented protections, limitations and remaining release gates. The original separate RowSkan repository is not modified by this work.
