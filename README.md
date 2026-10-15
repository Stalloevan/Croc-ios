# Croc for iOS

An iPhone and iPad app for sending and receiving files with
[croc](https://github.com/schollz/croc). The app compiles croc's Go code into an
iOS framework with `gomobile`, so the transfer protocol is the same one the
command-line tool uses. Two devices (or an iPhone and a computer running croc)
can exchange files with a shared code phrase.

## How it fits together

```
go/crocmobile/     Go wrapper: GenerateCode, Send, Receive (gomobile-friendly API)
scripts/           build-croc-framework.sh -> Frameworks/Croc.xcframework
project.yml        XcodeGen spec for the iOS app
CrocApp/           SwiftUI app (Send / Receive / Settings)
  CrocBridge.swift   the only file that calls the generated Go bindings
```

## Requirements

- A Mac with Xcode 15 or later (iOS 17 SDK)
- Go (the croc v11 module declares its required Go version in `go.mod`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- `gomobile`, installed by the build script

## Build

```bash
# 1. Build the Go framework (creates Frameworks/Croc.xcframework)
./scripts/build-croc-framework.sh

# 2. Generate the Xcode project
xcodegen generate

# 3. Open CrocApp.xcodeproj, pick your team under Signing, and run on a device
open CrocApp.xcodeproj
```

After the first successful build, commit `go/go.sum` and pin the croc version
in `go/go.mod` (for example `go get github.com/schollz/croc/v11@v11.x.y`) so
later builds are reproducible.

## Using the app

- **Send:** tap *Add files…*, pick files, then tap *Send*. Give the code shown on
  screen to the receiver. Keep the app open until the transfer finishes.
- **Receive:** type the code from the sender and tap *Receive*. Files are saved to
  the app's *Received* folder, visible in the Files app under *Croc*.
- **Settings:** change the relay (`host:port`) and password. Both sides must use
  the same relay. The default is the public relay `croc.schollz.com:9009`.

## Known limitations (first version)

- **Not tested on a device.** The Go wrapper was checked for formatting only. The
  framework build and the Swift code have not been compiled. Expect to fix small
  compile issues the first time you build.
- **Generated binding names.** `CrocBridge.swift` assumes the names gomobile
  generates for package-level functions (`CrocmobileGenerateCode`, etc.). If Xcode
  reports different names, update only that file.
- **Foreground only.** iOS suspends apps in the background, so keep the app open
  during a transfer.
- **No progress bar.** The UI shows "working" until croc returns. Progress needs
  a callback added to the Go wrapper.
- **No LAN discovery.** Transfers go through a relay. Local discovery is turned off
  to avoid the iOS local-network permission prompt.
- **One transfer at a time.** Receive changes the process working directory while
  it runs, so the wrapper serialises transfers.
- **Staged copies.** Picked files are copied into the app's temporary folder before
  sending, which needs free space equal to the files' total size.

## Security

croc encrypts transfers end-to-end with a PAKE key exchange derived from the code
phrase. Treat the code like a password: share it only with the person you are
sending to, and use it once.

## Credits

Transfer engine: [schollz/croc](https://github.com/schollz/croc) (MIT).
