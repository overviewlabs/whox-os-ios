# WHOX OS for iPhone

Native SwiftUI control surface for WHOX OS.

## Current foundation

- Chat-first native interface
- Activity and approval surfaces
- Control Center and secure pairing settings
- Typed WHOX session/run models
- Incremental server-sent-event decoder
- Authenticated relay request builder
- Linux-verifiable Swift package
- Hosted-Xcode simulator build workflow

## Security

The iOS app must never contain `API_SERVER_KEY`, provider keys, SSH credentials, or App Store Connect credentials. It authenticates to a mobile relay using a short-lived user/device session. The relay holds the WHOX API-server credential and applies route-level authorization.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Local verification

```bash
./scripts/verify.sh
```

## Generate the Xcode project on macOS

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open WHOXOS.xcodeproj
```

The App Store record uses bundle ID `com.whox.whoxos` and Apple App ID `6795136394`.
