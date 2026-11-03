# Required app protocol — design contract, not implemented sync

The relay is deliberately an opaque transport. The following requirements must be implemented and tested in the apps before any real inventory is transmitted.

1. Each device generates its own signing identity and keeps its private key in the platform keystore. A workspace has a pinned owner public key. QR enrollment must authenticate that fingerprint out of band; a relay-room string is not identity.
2. The owner explicitly approves a signed device certificate with a role. Team capture devices can propose additions/metadata edits and photo additions. Receiver-side authorization rejects capture-device deletion, photo removal, certificate issuance and permission changes. An untrusted device's self-reported OS is not an authorization decision. Solo mobile owners retain owner rights in their own solo workspace.
3. Establish authenticated ephemeral session keys using maintained cryptographic implementations. Bind handshakes to both device identities, workspace ID, certificate, fresh challenges and transcript. Use distinct direction keys and unique authenticated-encryption nonces; reject sequence replays. Do not use a workspace room ID as an encryption key.
4. Team desktops validate signed proposals and commit authoritative inventory changes. Persist outgoing operations on the sender until a durable signed acknowledgement is received. Lost relay connections must never remove unacknowledged work.
5. Transfer photos in bounded chunks, address them by cryptographic content hash and verify the complete result before committing a record reference. Resume from confirmed chunks after reconnect. Never expose absolute local paths in a sync payload.
6. Deletion produces an owner-authorized tombstone and revision. An old disconnected phone must not resurrect deleted data by uploading a stale snapshot. Conflicting edits stay locally recoverable and are presented for resolution.
7. Revocation is signed and versioned by the owner. Test lost-phone revocation, stale membership replay, clock skew, duplicate delivery, tampered ciphertext and a hostile relay. Offline devices may retain data they already possessed; revocation cannot erase arbitrary copies.
8. Internet acceptance requires simultaneously connected real devices behind different networks, interrupted photo upload and receiver-side permission tests. LAN success alone is insufficient.

Current status: transport tests exist; app enrollment and sync integration are not enabled. This file is not evidence of completed security validation.
