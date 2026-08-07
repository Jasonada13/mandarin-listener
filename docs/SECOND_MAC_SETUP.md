# Second Mac and travel handoff

The GitHub repository is the source of truth. Downloaded speech models, native
frameworks, build products, provisioning profiles, and credentials are intentionally
excluded. The bootstrap script recreates everything that is safe to recreate.

## Before travelling

On the second Mac, while a reliable connection is available:

1. Install full Xcode, open it once, and install the iOS 26 platform.
2. Sign in to Xcode with the same Apple ID used for the Personal Team.
3. Install Homebrew if needed, then install the small development tools:

   ```sh
   brew install git node xcodegen gh
   ```

4. Authenticate GitHub and clone the private repository:

   ```sh
   gh auth login
   gh repo clone Jasonada13/mandarin-listener
   cd mandarin-listener
   make bootstrap
   ```

The bootstrap downloads checksum-verified sherpa-onnx frameworks and the Mandarin
model from their official GitHub release, installs pinned relay packages, regenerates
the Xcode project, and runs the automated checks. These downloads are large, so doing
this before relying on a hotel or mobile connection is strongly recommended.

## Build and refresh the iPhone app

1. Connect the iPhone and accept the computer trust prompt if shown.
2. Open `ios/MandarinListener.xcodeproj`.
3. Select the `MandarinListener` target, then **Signing & Capabilities**.
4. Select the Personal Team. The current identifiers are:
   - Team: `C3YXB4UD2H`
   - Bundle ID: `com.jasonadams.MandarinListener`
5. Select the connected iPhone as the run destination and press **Run**.
6. If iOS blocks first launch, open **Settings → General → VPN & Device Management →
   Developer App**, then trust the Apple ID shown there.

A free Personal Team profile lasts approximately seven days. Rebuilding and running
from Xcode refreshes it. A paid Apple Developer membership removes this weekly travel
maintenance but is not required for development.

## Relay and credentials

The existing relay remains deployed at:

```text
https://mandarin-listener-relay.jasonadams-mandarin-listener.workers.dev
```

Kimi and optional ElevenLabs provider keys stay encrypted in Cloudflare and are not
needed to build the iOS app. The private client token is also excluded from GitHub.
Installing over the existing app normally preserves its Keychain token and settings.

If the app must be configured from scratch, transfer the client token privately from
the current Mac's ignored file:

```text
ios/.local-deps/client-auth-token.txt
```

Use AirDrop, an end-to-end encrypted password manager, or another private channel.
Never paste that token into GitHub, an issue, a commit, or chat. The token is not the
Kimi API key; it only authenticates this app to the personal relay.

To administer or redeploy the relay from the second Mac, authenticate Wrangler to the
same Cloudflare account. Existing Worker secrets remain server-side:

```sh
cd relay
npx wrangler login
npm run deploy
```

Do not run `wrangler secret put` unless deliberately rotating a secret.

## Normal development loop

```sh
git pull --ff-only
make check
make open-project
```

After editing `ios/project.yml`, run `make generate-project`. After a dependency or
model refresh, run `make sherpa-assets`. Commit source and documentation changes, but
never force-add ignored model, framework, credential, or signing files.
