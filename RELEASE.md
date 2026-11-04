# RowSkan release candidate 0.4

Product of LIT America — https://litamerica.net

## What is implemented

The browser and native applications save inventory locally, without a cloud inventory database or analytics. Phone native builds use the system photo capture interface and a VIN barcode scanner. VIN decoding sends VINs to NHTSA, and manual entry remains available.

This candidate adds recoverable intake drafts, local edit conflicts, encrypted exported backups, validation before backup import, and native transaction-based imports with rollback. Native team phones cannot remove saved vehicles or saved photos through app store operations. Solo phone owners can manage their own data. Deleted native vehicles can be restored. Windows CI uses the Visual Studio 2022 runner.

The browser edition supports a solo owner. It does not claim authenticated team permissions. It can cache its application shell for offline use on HTTPS; storage persistence depends on the browser. Browser backups use .rowskan-web; native backups use .rowskan. These are separate formats and do not synchronize inventory between editions.

## Data and backup security

- Native .rowskan exports: PBKDF2-HMAC-SHA256, 210,000 iterations, random 128-bit salt, AES-256-GCM with a fresh random nonce.
- Browser .rowskan-web exports: Web Crypto PBKDF2-HMAC-SHA256 and AES-256-GCM, same iteration count, versioned authenticated format.
- Export passwords are not recoverable. The apps do not save them.
- Local databases and photos use the device's operating system protections. Local inventory encryption at rest is not implemented. Native signing seeds and pairing profiles use platform secure storage.
- Backups contain active records. Native deleted records and unfinished drafts are excluded. Do not clear device/app storage without a verified backup.
- Native and browser archives have explicit size limits. Large inventories need streaming exports before general release.

## Validation required before commercial launch

CI checks compilation and automated data-recovery tests. It does not establish real-device camera reliability, security certification, store approval or production suitability. Run Android/iPhone camera tests, Windows/Mac install tests, restart/recovery tests, migration tests and adversarial import tests on actual devices.

Still required:
1. Owner identity recovery and an independent review of the implemented pairing/permission protocol.
2. Real-device internet acceptance of the implemented encrypted sync, including interruptions, revoked devices, clock skew and receiver-enforced permissions.
3. A reachable signaling/relay host for free sync. No perpetual zero-cost hosting guarantee is possible. Hosting must be chosen before end-to-end internet acceptance tests.
4. iOS build, signing, app identities, Mac notarization and Windows distribution signing decisions.
5. Privacy policy and support/recovery process based on the final deployed services.
6. Optional cloud plans, storage quotas, billing and restoration tests. No paid service is configured or purchased.

The public website is an early-access local app until these gates pass. No fake cloud sync or subscription controls are presented as functional.

## Vehicle GPS — 0.3

Optional foreground GPS capture saves latitude/longitude, reported accuracy, timestamp and whether a pin was manually corrected. Saved pins are included in vehicle backup/import and intake drafts. The local north-up walking guide computes straight-line distance and bearing without contacting a map provider. It does not rotate with the phone and is not an aisle-routing engine. Approximate arrival is labeled as an uncertainty area, not exact vehicle identification. Yard/row/space, photos and VIN remain visible.

The guide stops when its screen is closed or the app/browser is backgrounded. No movement history or background location is collected. An optional explicit Google Maps action sends the destination coordinates to Google. Location permissions and positioning accuracy require real-device testing. Paired native sync includes saved GPS pins. The browser edition remains local and separate.


## Native synchronization — 0.4

Signed owner approvals assign capture and trusted desktop manager roles. Authenticated ephemeral X25519 sessions use HKDF-derived direction keys and AES-256-GCM over the opaque relay. Local operation journals retain signed author proofs and peer delivery receipts. Receivers validate signatures, certificates, roles, record revisions and photo hashes. Deletions use retained tombstones; simultaneous edits become reviewable conflicts rather than automatic overwrites. Owner conflict choices create a higher revision for propagation.

Photos transfer as 32 KiB stop-and-wait chunks into content-hash staging files and are verified before record insertion. Reconnect requests the staging file's current offset. This protocol is a release candidate, not audited production cryptography. Acknowledgements are authenticated within the peer session, not separately portable signed receipts. Revocation rotates all approvals and discovery secrets for the owner's current epoch; isolated old devices may continue sharing their previously retained copies with one another.

No public relay endpoint, Firebase project deployment, subscription checkout, cloud inventory store or paid resource is created by this release. Internet acceptance requires actual devices on different networks. CI's loopback two-device fixture does not replace that requirement.
