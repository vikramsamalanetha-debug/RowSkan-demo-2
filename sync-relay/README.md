# Relay transport groundwork — apps are not connected yet

This bounded WebSocket transport forwards frames between simultaneously connected devices without a database, disk writes, inventory API, message history or replay queue. Network buffers transiently hold bytes during transmission. It is not a complete synchronization service.

Run npm ci, npm test, then npm start. Default bind: 127.0.0.1:8787. Internet deployments must use a maintained HTTPS reverse proxy and wss://. No host has been purchased or deployed.

A connection joins with {"type":"join","room":"<64 lowercase hex characters>","peer":"<16–80 safe characters>"}. A room must derive from an unguessable workspace secret, never from a business name or VIN. Subsequent frames must be binary. The relay cannot establish whether bytes are actually encrypted; client authenticated encryption and signed device permissions must be implemented before real inventory is sent.

Device key custody, signed enrollment/revocation, replay prevention, receiver-enforced roles, durable change journals and resumable photo transfers remain app protocol work. Do not use this transport alone as a security boundary. Current RowSkan apps do not connect to it.

Limits: 512 connections, 8 peers/room, 256 KiB/frame, 4 MiB/s/sender, bounded output buffers, 5-second join timeout, heartbeat. Transient socket addresses support admission limits; reverse proxies need external admission controls. Application request logging is off; configure proxy logging appropriately.
