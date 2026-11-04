# Native client protocol — candidate 0.4

The relay is untrusted and opaque. It forwards bounded binary frames to simultaneously connected peers and has no replay/history store. Inventory and retry queues live on devices. Browser inventory is separate.

## Pairing and identity

Each device creates an Ed25519 seed held in platform secure storage. A workspace pins its owner's public key, a random 256-bit discovery secret and a membership epoch. A self-signed request identifies a device. The owner returns a signed certificate for that public key and a private approval code containing workspace access. Users transfer codes directly through a trusted channel and verify the device name/request. No QR or hardware attestation is claimed. Self-reported desktop type is checked for convenience; only explicit owner approval grants a manager role.

Solo phone owners retain management rights. Capture certificates cannot issue approvals, delete/restore vehicles, remove saved photo references or clear saved GPS pins. Peers independently verify certificates and operation signatures. A local device administrator can alter local files; these roles cannot protect a device from its own administrator.

Reset pairing rotates the group secret and epoch and reissues only the owner's certificate. Old certificates cannot join the owner's new epoch. Old devices retain their previous copies and may continue sharing in their old isolated workspace. Per-device revocation, key recovery and ownership transfer are not implemented.

## Transport

The join room is SHA-256 of the random discovery secret, workspace ID and epoch. Discovery frames use AES-256-GCM with that secret. Signed hellos contain device identity, fresh per-connection X25519 public key, 128-bit random session challenge and timestamp (five-minute clock tolerance). HKDF-SHA256 binds both identities, ephemeral public keys, challenges, workspace and epoch and derives separate direction keys. Session data uses AES-256-GCM with authenticated headers and fresh random 96-bit nonces. Strict per-direction sequence counters reject replay/gaps. Signed operation proofs survive forwarding; an intermediary cannot change the originating role or record.

Frame headers expose workspace/device identifiers, sequences, traffic timing and sizes to the relay; record fields, GPS and photo data remain encrypted. Only wss endpoints are accepted except loopback ws for testing. A malicious relay can still drop, delay or deny service.

## Inventory and photos

Local SQLite mutations atomically append operations with base/new revisions and deletion tombstones. Sender journals retain work across restart, and authenticated peer acknowledgements persist delivery receipts. Receipts are session-authenticated, not separately signed portable proofs. Operations replay idempotently by ID. Existing records require matching base revisions; simultaneous edits are kept as owner-review conflicts. Owner resolution emits a signed higher revision; old updates cannot resurrect a tombstone. Rejected operations remain in the local journal; they are marked delivered/rejected and do not block later operations.

Each operation signs a photo manifest of safe filenames, SHA-256 hashes and lengths. Receivers request 32 KiB chunks and append only at the expected offset. Content-hash staging files survive reconnect; full lengths/hashes are checked before renaming into photo storage and applying the record. A filename collision preserves existing bytes and rejects the incoming operation. Photos are capped at 25 MiB each and twelve per record. History, retained photos and abandoned staging files are not automatically pruned.

## Validation boundary

Automated tests exercise signed enrollment, tampering, epoch reset, role permissions, tombstones, conflict preservation, two-device loopback encrypted transfer, chunked photos and reconnect. Relay tests cover transport limits. These do not constitute a security audit or real-device internet acceptance. Before release, validate hostile-relay/replay behavior, clock skew, owner recovery, interrupted large transfers, revocation and actual devices on different networks. No public relay or Firebase billing is provisioned.
