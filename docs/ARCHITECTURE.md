# WHOX OS iOS Architecture

## Product goal

A native iPhone control surface for WHOX OS with conversational UX comparable to ChatGPT and explicit, auditable controls for agent actions.

## Security boundary

The existing WHOX API server runs tools on the server and its `API_SERVER_KEY` grants high-impact control. That key must never ship in the app binary, app preferences, iCloud, analytics, or logs.

The iOS app connects to an HTTPS mobile relay. The relay validates Sign in with Apple, verifies a paired device, applies route-level authorization and rate limits, then calls the loopback-only WHOX API server with the server key.

```text
iPhone app
  └─ Sign in with Apple + device-bound session
      └─ HTTPS mobile relay (public, least privilege)
          └─ WHOX API server 127.0.0.1:8642 (private bearer key)
              └─ WHOX agent/tools on server
```

## MVP

1. Sign in with Apple.
2. Pair a device to one WHOX installation.
3. List, create, rename, fork, and delete conversations.
4. Stream chat text and structured tool progress.
5. Show tool approval cards with approve/deny actions.
6. Stop an active run.
7. View and manage scheduled jobs.
8. View server health, model, skills, and toolsets.
9. Receive push notifications for approval requests and completed runs.

## Native WHOX contracts

- `GET /v1/capabilities`
- `GET /api/sessions`
- `POST /api/sessions`
- `GET /api/sessions/{id}/messages`
- `POST /api/sessions/{id}/chat/stream`
- `POST /v1/runs`
- `GET /v1/runs/{id}/events`
- `POST /v1/runs/{id}/approval`
- `POST /v1/runs/{id}/stop`
- `/api/jobs` management routes
- `GET /health/detailed`

## iOS capabilities

- Sign in with Apple
- Push Notifications
- Associated Domains only when the pairing/deep-link domain is deployed

No other entitlement is enabled until a product feature requires it.

## Secrets

- App Store Connect and WHOX server keys remain server-side.
- Mobile access and refresh tokens use Keychain.
- Pairing is one-time and revocable.
- No provider credential is returned by the relay.
- Dangerous actions remain subject to WHOX approval events.
