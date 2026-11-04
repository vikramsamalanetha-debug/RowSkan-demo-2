# RowSkan opaque sync relay

This bounded WebSocket transport forwards frames between simultaneously connected devices without a database, disk writes, inventory API, message history or replay queue. Network buffers transiently hold bytes during transmission. Native RowSkan 0.4 implements the client pairing and synchronization protocol. The relay remains an untrusted forwarding service.

Run npm ci, npm test, then npm start. Default bind: 127.0.0.1:8787. Internet deployments must use a maintained HTTPS reverse proxy and wss://. No host has been purchased or deployed.

A connection joins with {"type":"join","room":"<64 lowercase hex characters>","peer":"<16–80 safe characters>"}. A room must derive from an unguessable workspace secret, never from a business name or VIN. Subsequent frames must be binary. The relay cannot establish whether bytes are actually encrypted; native clients authenticate and encrypt payloads; the relay itself cannot enforce device roles.

See PROTOCOL.md for the implemented native protocol and remaining acceptance work. Do not use this transport alone as a security boundary. Browser inventory is not integrated with this relay.

Limits: 512 connections, 8 peers/room, 256 KiB/frame, 4 MiB/s/sender, bounded output buffers, 5-second join timeout, heartbeat. Transient socket addresses support admission limits; reverse proxies need external admission controls. Application request logging is off; configure proxy logging appropriately.


## Deployment on an existing host

With Docker Compose and an existing public domain pointed to the server, set `ROWSKAN_SYNC_DOMAIN` to your hostname and run `docker compose up -d --build` in this directory. Review compose.yaml and Caddyfile first. The app endpoint is `wss://YOUR_DOMAIN/relay`; check `https://YOUR_DOMAIN/healthz`. Open only ports 80/443 publicly. Caddy keeps TLS certificate files; relay message data has no volume. Check that your server/proxy/platform does not enable payload or access logging and configure external admission limits for internet exposure.

This does not supply free hosting or a domain. Do not upgrade Firebase or attach billing merely to test the client. Local testing can use `ws://127.0.0.1:8787/relay` on the same computer. Production clients reject unencrypted non-loopback endpoints. Before launch, test devices across separate networks, relay restarts, interrupted photos, simultaneous edits, revoked keys and restored inventory.
