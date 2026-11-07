# Nape Companion

A small, free, open-source menu bar app for the Keychron Nape Pro. It shows
the onboard custom layer that is active right now, and the OctaShift angle
that goes with it.

It is read-only. It does not change layers, orientation, button mappings,
DPI, sleep, polling, or firmware, and it does not write a configuration
back to the trackball. Layer names you edit stay in UserDefaults on this Mac.

The license is MIT. See `LICENSE` and `NOTICE.md`.

## What you need

- macOS 12 or later
- Xcode Command Line Tools (`xcode-select --install`)
- A free local build. No paid Apple Developer account, no notarization, and
  no App Sandbox

The app is not sandboxed. Turning on App Sandbox without a USB HID
entitlement would make the open fail. Do not add that entitlement unless
you are also setting up a provisioning profile, which this project does not
use.

## Build and run

```sh
git clone https://github.com/slelham/nape-companion.git
cd nape-companion
swift test
./build.sh
open "build/Nape Companion.app"
```

`./build.sh` writes `build/Nape Companion.app` in the current directory. It
does not copy the app to `/Applications` and it does not launch it. The
binary is ad-hoc signed (`codesign --sign - --timestamp=none`) so Gatekeeper
has a signature to look at and the build does not contact Apple.

The first time you open it, macOS will say the app is from an unidentified
developer. Right-click `Nape Companion.app`, choose Open, and confirm. If
that button is missing, use System Settings → Privacy & Security → Open
Anyway. This build is not notarized.

Quit from the menu, or with ⌘Q while the menu is open.

`swift test` does not need the trackball. It checks the packet parser and
the menu-state rules. `./build.sh` is the step that produces the app, and
it only runs on macOS.

## Permissions

The app uses IOKit HID:

- `IOHIDManager` with match dictionaries for vendor `0x3434`, product
  `0x0440`, `0xD026`, or `0xD029`, and primary usage page `0xFF60` usage
  `0x61`
- `IOHIDManagerOpen` and `IOHIDDeviceOpen` with `kIOHIDOptionsTypeNone`
- an input-report callback on that RAW collection
- `IOHIDDeviceSetReport` of an output report, 32 bytes, report id 0

It does not open the mouse-pointer collection, install a `CGEvent` tap, or
watch the keyboard. It does not use the network, an account, or Bluetooth
APIs.

macOS may still list the app under System Settings → Privacy & Security →
Input Monitoring, because that is how some HID opens are gated. If the menu
shows `!` and the text says the open was refused, turn Nape Companion on
there and relaunch. If it says the interface is already open, quit Keychron
Launcher or the browser tab that has the trackball open in WebHID. This
permission behavior was not confirmed on hardware in this repository's
development environment.

Debug logging is off unless you launch it with `NAPE_COMPANION_DEBUG=1`.
That prints the first four bytes of each query and reply to stderr. There
is still no network.

## Menu bar

| Title | Meaning |
|---|---|
| `–` | Nothing is attached, the Mac is asleep, or the trackball was unplugged. No layer number is shown. |
| `…` | A matching interface is open and the current-layer reply has not arrived. Nothing is shown as live yet. |
| `L3` | Live layer 3, still using the default name. |
| `L3 Design` | Live layer 3 with a local name. |
| `!` | The last reply failed, timed out, or is older than 2.5 seconds. Any previous layer in the menu is labeled not live. |

Open the menu for the transport, the firmware string when the device sent
one, the VIA layer count, and the OctaShift line. **Layer names…** edits the
eight local names. They are stored under the UserDefaults key
`layerDisplayNames`, trimmed to 40 characters, and restored on the next
launch. Reset puts back "Layer 0" through "Layer 7" when you save.

The status item's accessibility label matches the state: disconnected,
connecting, live layer and angle, or not live.

## Layers and OctaShift

The device reports eight user layers as firmware indexes 1–8. The menu
shows those as layers 0–7, which is the numbering Keychron Launcher uses.
An index outside 1–8 is an error, not Layer 0. Details and the sources are
in `docs/protocol.md`.

OctaShift is the orientation stored on each layer, in 45° steps. Switching
layers switches the stored angle. It does not detect the physical rotation
and change layers by itself. The menu shows the live heading and the stored
heading. If they differ, it says so. After a layer change the old angle is
cleared until the new replies arrive.

There is no documented push report for a layer change, so the app polls.
A value that has not been confirmed for 2.5 seconds is not called live.

## USB, the receiver, and Bluetooth

Wired USB (`0x0440` plus the RAW collection) is the path the published
notes describe. Prefer that.

Keychron Link-KM (`0xD026`) and Link-KM Type C (`0xD029`) are opened only
when they expose the same RAW collection. The menu marks that path
**unverified**. OpenMouse lists those two receivers next to the Nape Pro,
and the check in that project is not a capture of a Nape Pro on a dongle.
Other Keychron receivers are not opened. Bluetooth is not supported.

If both the cable and a receiver are attached, the cable is used.

## Development checks

From a checkout:

```sh
swift test
./build.sh
```

GitHub Actions runs `swift test` on Linux with Swift 6.0.3, and on a macOS
runner it runs `swift test` and `./build.sh`.

While this repository was being written, `swift test` was run here on Linux
with Swift 6.0.3 and the protocol suite passed (26 tests). This environment
is not a Mac. `swiftc`, Xcode, and `codesign` were not available, so the
`.app` was **not** built here. A green macOS job on the pull request is the
compile check. Nothing in that job plugs in a trackball.

## Hardware checklist

Do this on your Mac with your Nape Pro. None of it was run in development.

- [ ] `swift test` passes.
- [ ] `./build.sh` produces `build/Nape Companion.app`, and the menu bar
      shows `–` before the trackball is plugged in.
- [ ] Wired USB: the title becomes `…`, then `L0` (or your name) when
      Launcher would show Layer 0. The menu says the wired path is
      documented.
- [ ] The firmware line matches Launcher. Note the exact string if it does
      not.
- [ ] Switch layers on the device. The title follows, including every layer
      from 0 through 7. It does not stick on the previous number.
- [ ] Unplug the cable. The title becomes `–` immediately and the menu does
      not keep a layer number.
- [ ] Plug it back in. The title goes through `…` and back to a live layer.
- [ ] Sleep the Mac and wake it. During sleep the menu is not showing a
      layer as live. After wake it recovers, or it shows `!` / `–` rather
      than a stale `L` number.
- [ ] The pointer, buttons, and wheel still work while the app is running.
- [ ] OctaShift degrees match the device. If live and stored differ, the
      menu says both.
- [ ] Rename layer 0, quit, launch again. The name is still there. The
      trackball's own layout is unchanged.
- [ ] With Launcher or a WebHID page connected, the menu shows `!` and says
      the interface is already open, instead of a layer. Quit that app and
      the layer returns.
- [ ] Receiver, if you use one: write down the product id macOS shows, say
      whether a `0xFF60` / `0x61` interface appears, and say whether the
      reads succeed. Treat a success as unverified until it matches the
      layer you selected on the device. Other dongles are expected to stay
      on `–`.
- [ ] Bluetooth is expected to stay on `–`.
- [ ] Confirm the current-layer reply is firmware index 1 when Launcher
      shows Layer 0. If it is 0, the numbering in `docs/protocol.md` is
      wrong and the menu should not be trusted.

## Layout of the source

- `Sources/NapeProtocol/` is the parser, the allowlist, and the menu-state
  machine. It does not import AppKit or IOKit, so `swift test` runs on Linux.
- `App/` is the menu bar app. `build.sh` compiles it together with the
  protocol sources.
- `Tests/NapeProtocolTests/` uses documented values and labeled synthetic
  frames. There are no captured traces in this repository.

## License

MIT, Copyright (c) 2026 slelham.

The Nape Pro command numbers and the OctaShift description come from
[dobachi/NapeProConfiguration](https://github.com/dobachi/NapeProConfiguration)
at `1bca8c004c02e18bf41021da4116cb2955faed24` (MIT). The current-layer reply
byte, the 1–8 to 0–7 label, and the receiver ids that are even attempted
were checked against
[OpenMouse-Project/mouse-protocol](https://github.com/OpenMouse-Project/mouse-protocol)
at `b62a1cce2b63698ac00595efdb0067ecd54e34a0` (AGPL-3.0). That code is not
included. The menu-bar shape follows
[slelham/pocket3-companion](https://github.com/slelham/pocket3-companion)
at `de458f49e946fb37123a5fb7f17a6df34c080979` (MIT) without copying it.
Full wording is in `NOTICE.md`.
