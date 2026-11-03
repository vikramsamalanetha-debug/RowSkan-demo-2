# RowSkan release candidate 0.2

Product of LIT America — https://litamerica.net

## What is implemented

The browser and native applications save inventory locally, without a cloud inventory database or analytics. Phone native builds use the system photo capture interface and a VIN barcode scanner. VIN decoding sends VINs to NHTSA, and manual entry remains available.

This candidate adds recoverable intake drafts, local edit conflicts, encrypted exported backups, validation before backup import, and native transaction-based imports with rollback. Native team phones cannot remove saved vehicles or saved photos through app store operations. Solo phone owners can manage their own data. Deleted native vehicles can be restored. Windows CI uses the Visual Studio 2022 runner.

The browser edition supports a solo owner. It does not claim authenticated team permissions. It can cache its application shell for offline use on HTTPS; storage persistence depends on the browser. Browser backups use .rowskan-web; native backups use .rowskan. These are separate formats and do not synchronize inventory between editions.

## Data and backup security

- Native .rowskan exports: PBKDF2-HMAC-SHA256, 210,000 iterations, random 128-bit salt, AES-256-GCM with a fresh random nonce.
- Browser .rowskan-web exports: Web Crypto PBKDF2-HMAC-SHA256 and AES-256-GCM, same iteration count, versioned authenticated format.
- Export passwords are not recoverable. The apps do not save them.
- Local databases and photos use the device's operating system protections. Application-level encryption at rest and keychain-managed workspace keys are not implemented.
- Backups contain active records. Native deleted records and unfinished drafts are excluded. Do not clear device/app storage without a verified backup.
- Native and browser archives have explicit size limits. Large inventories need streaming exports before general release.

## Validation required before commercial launch

CI checks compilation and automated data-recovery tests. It does not establish real-device camera reliability, security certification, store approval or production suitability. Run Android/iPhone camera tests, Windows/Mac install tests, restart/recovery tests, migration tests and adversarial import tests on actual devices.

Still required:
1. Administrator identity, signed device enrollment, revocation and recovery.
2. Encrypted, resumable internet sync with deletion tombstones, conflict handling and receiver-enforced roles.
3. A reachable signaling/relay host for free sync. No perpetual zero-cost hosting guarantee is possible. Hosting must be chosen before end-to-end internet acceptance tests.
4. iOS build, signing, app identities, Mac notarization and Windows distribution signing decisions.
5. Privacy policy and support/recovery process based on the final deployed services.
6. Optional cloud plans, storage quotas, billing and restoration tests. No paid service is configured or purchased.

The public website is an early-access local app until these gates pass. No fake cloud sync or subscription controls are presented as functional.

## Vehicle GPS — 0.3

Optional foreground GPS capture saves latitude/longitude, reported accuracy, timestamp and whether a pin was manually corrected. Saved pins are included in vehicle backup/import and intake drafts. The local north-up walking guide computes straight-line distance and bearing without contacting a map provider. It does not rotate with the phone and is not an aisle-routing engine. Approximate arrival is labeled as an uncertainty area, not exact vehicle identification. Yard/row/space, photos and VIN remain visible.

The guide stops when its screen is closed or the app/browser is backgrounded. No movement history or background location is collected. An optional explicit Google Maps action sends the destination coordinates to Google. Location permissions and positioning accuracy require real-device testing. GPS does not enable the still-pending device sync.
