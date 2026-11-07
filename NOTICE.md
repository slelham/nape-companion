# Third-party notices

Nape Companion is an independent read-only implementation. It does not copy
source from the projects below. Command numbers, report layout, and product
IDs are facts taken from those projects and reimplemented here. See
`docs/protocol.md` for how each fact is used.

## dobachi / NapeProConfiguration

- Repository: https://github.com/dobachi/NapeProConfiguration
- Commit inspected: `1bca8c004c02e18bf41021da4116cb2955faed24`
- License: MIT, Copyright (c) 2026 dobachi
- Files used as documentation, not as copied source:
  - `docs/nape-pro-hid-protocol.md`
  - `docs/nape-pro-device.md`
  - `docs/rotation-angle-investigation.md`
  - `docs/keychron-launcher-investigation.md`
- That repository's `NOTICE.md` says its tools, docs, and configs are MIT, and
  that a submodule of instruction kits is separate. This project does not
  include that submodule.

## OpenMouse-Project / openmouse

- Pull request: https://github.com/OpenMouse-Project/openmouse/pull/118
- License: GNU Affero General Public License v3.0
- The pull request adds a Nape Pro layer UI that calls `@openmouse/protocol`.
  No source from that pull request is included here.

## OpenMouse-Project / mouse-protocol

- Repository: https://github.com/OpenMouse-Project/mouse-protocol
- Commit inspected: `b62a1cce2b63698ac00595efdb0067ecd54e34a0`
- License: GNU Affero General Public License v3.0
- `src/keychron/index.ts` and `src/keychron/nape-hid.ts` were read to check
  the 0xA3 reply byte, the firmware-layer 1–8 to display-layer 0–7 mapping,
  and which receiver product IDs that project associates with Nape Pro.
- No Affero GPL source is copied into this repository. Nape Companion is MIT
  because it does not incorporate that code. Do not paste those files in later.

Differences that are intentional:

- OpenMouse clamps a current-layer index below 1 up to 1 and caps it at 8.
  This app rejects an index outside 1–8 and stops calling the reading live.
- OpenMouse prefixes a firmware string with `v` when the device did not send
  one. This app shows the ASCII bytes as they are.

## slelham / pocket3-companion

- Repository: https://github.com/slelham/pocket3-companion
- Commit inspected: `de458f49e946fb37123a5fb7f17a6df34c080979`
- License: MIT, Copyright (c) 2026 slelham
- Used only as a convention reference for a menu-bar app, `LSUIElement`, and
  an ad-hoc `swiftc` build. No source from that repository is copied here.
  That app installs into `/Applications`. This build script does not.

## Trademarks

Keychron and Nape Pro are trademarks of their owners. This project is not
affiliated with Keychron or with the authors of the projects above.

## What this environment did not capture

No HID packet captures from a Nape Pro were made while writing this app.
Frames in the tests that carry the documented firmware string are marked as
constructed from the published layout, not as traces.
