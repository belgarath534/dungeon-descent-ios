# TestFlight builds from GitHub

For when Codemagic's build minutes run out. This repository is public, so
GitHub's Mac runners are free. The **TestFlight (GitHub)** workflow
(`.github/workflows/testflight.yml`) builds the Swift version three times, side
by side, signs each and uploads it to TestFlight: **iPhone** (with its Live
Activity and Apple Watch app), **Apple Vision Pro** and **Mac** (Mac Catalyst).
It runs on GitHub's `xcode-27` image, since Apple wants the newest SDK. If one
platform fails, the others still go up.

It works the same way as the truck and RPG games: **fastlane match** keeps the
shared App Store certificate, and a profile for each of the three parts
(`com.dungeon.descent`, `com.dungeon.descent.DDLiveActivity`,
`com.dungeon.descent.watchkitapp`, plus a Mac Catalyst profile and a Mac
Installer certificate for the Mac package), encrypted in the private
**ios-certificates** repository. The first run makes the three profiles there.
The App Store Connect key comes from that repository too: every
`AuthKey_<KEY ID>.p8` in it is tried until Apple accepts one. Each build is
numbered one higher than the newest build on TestFlight for any of the three platforms.

## One-time setup: repository secrets

On github.com, open this repository, then **Settings**, **Secrets and
variables**, **Actions**, **New repository secret**. Use the same values as
the truck simulator:

| Name | Value |
|---|---|
| `MATCH_PASSWORD` | The match password the other games use (it unlocks the certificates) |
| `CERTS_REPO_TOKEN` | A fine-grained token with **Contents: Read and write** on ios-certificates |
| `ASC_ISSUER_ID` | The Issuer ID: App Store Connect, Users and Access, Integrations, App Store Connect API |

Never paste a key, password or token into a chat. They only go into GitHub secrets.

## Sending a build

Push the code to the `testflight` branch: `git push origin swift-rewrite:testflight`
(Claude can do this for you). GitHub only shows a **Run workflow** button for
workflows on the default branch, so the push is the way to start it from
`swift-rewrite`. It takes about 30 minutes, then the build appears in
TestFlight like a Codemagic one.
