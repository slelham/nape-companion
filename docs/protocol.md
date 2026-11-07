# Nape Pro read path

This note is the behavior Nape Companion implements. It is not a firmware
dump and it is not a packet capture. Sources are listed in `NOTICE.md`.

The app sends only the reads in the allowlist below. It does not send layer
changes, orientation changes, keymap writes, DPI, sleep, polling, or any
other SET. Keychron Launcher persists those SETs immediately, so a write
would change the device. There is no separate save step to undo one.

## Device

| | |
|---|---|
| Vendor | `0x3434` |
| Wired product | `0x0440` (Nape Pro) |
| Config collection | usage page `0xFF60`, usage `0x61` |
| Report | id 0, 32-byte packet |
| Host to device | HID output report |
| Device to host | HID input report, and only as a reply |

The trackball exposes more than one HID interface. The pointer collection is
the one macOS uses as a mouse. This app's match dictionaries require
`0xFF60` / `0x61`, so that pointer interface is not opened and normal mouse
input is left alone. Keychron keyboards can also expose `0xFF60`; they are
not opened, because the product id must be the wired Nape Pro or one of the
two receiver ids below.

No unsolicited layer-change report is described in the sources. Input
reports are answers to queries. The menu stays current by polling about
every 0.45 seconds. A reading older than 2.5 seconds is not shown as live.
Unplug and sleep clear the layer number rather than leaving the last digit
on the menu bar.

## Reads

Each packet is 32 bytes. Bytes not listed are zero.

| Query | Bytes | Reply used |
|---|---|---|
| Firmware text | `A1` | ASCII from byte 1 until the first NUL |
| VIA layer count | `11` | byte 1, must be greater than 0 |
| Current layer | `A3` | byte 1 |
| Live orientation | `A7 20` | byte 2, step 0–7 |
| Stored orientation | `A7 38 <firmware layer>` | byte 2, step 0–7 |

`0xA3`'s reply byte is taken from OpenMouse `keychronDecodeCurrentLayer`
(mouse-protocol `b62a1cce2b63698ac00595efdb0067ecd54e34a0`). dobachi's
protocol table names `0xA3` but does not say which reply byte holds the
layer. dobachi does say orientation comes back in byte 2.

A 32-byte buffer is used as-is. A longer buffer that starts with report id
0 and then a known command drops that leading byte. A longer buffer that
already starts with a known command keeps the first 32 bytes.

## Layers 0–7

Two published descriptions agree on the direction of the numbering and
disagree on what to do with a bad value.

- dobachi, `docs/nape-pro-device.md`, calls this a hypothesis that is not
  confirmed from firmware source. VIA index 0 is a hidden base. Launcher
  Layer 0 is device index 1, through Launcher Layer 7 at device index 8.
  The same document's measured VIA count is 9, which is the spare slot plus
  eight user layers.
- OpenMouse labels firmware layers 1–8 as "Layer 0" through "Layer 7"
  (`keychronLayerDisplayIndex` is the firmware index minus 1). Its decoder
  clamps an index below 1 up to 1 and caps it at 8.

This app shows display layer `firmware - 1` for firmware indexes 1–8.
Firmware index 0 or 9 or anything else is an error. The menu switches to
`!` and does not pretend the device is on Layer 0. The last good reading
can remain in the menu only with the words "not live".

The stored-orientation request uses that same firmware index, 1–8. dobachi
writes the orientation layer argument as 0–8. OpenMouse uses the 1–8 index
that `GET_CURRENT_LAYER` returns. Those are not the same instruction if
index 0 is meaningful. The hardware checklist asks you to confirm that
Launcher Layer 0 produces `0xA3` byte 1 equal to 1, and that the stored
angle for that layer is the reply to `A7 38 01`.

## OctaShift

OctaShift is the orientation stored for a layer. It is not automatic
orientation detection. Changing the layer changes which stored angle is in
effect. dobachi's device note says the angle increases counterclockwise:

| Step | Degrees | Side described as "up" |
|---|---|---|
| 0 | 0° | 03 / 04 |
| 2 | 90° | 01 / 03 |
| 4 | 180° | 01 / 02 |
| 6 | 270° | 02 / 04 |

`A7 20` is the live heading. `A7 38` is the angle stored for one layer.
The menu shows one number when they match. When they differ it says which
is live and which is stored. A layer change drops both values until the
next replies, so the previous layer's angle is not shown on the new layer.

## Firmware text

dobachi records `v1.2.3-ZK …` for the earlier firmware and a form such as
`010205…` for v1.2.5. The published v1.2.3-ZK measurement cited in the
tests is `v1.2.3-ZK Jun 3 2026 17:59:21`. The 32-byte frame in the tests is
built from that string and the documented layout. It is not a capture.
This app does not insert a `v` when the device omitted one.

## Transports

| Product | What the sources say | What this app does |
|---|---|---|
| `0x0440` | Wired Nape Pro, RAW HID | Opened when the RAW collection is present. Menu says this path is documented. |
| `0xD026` | Keychron Link-KM. OpenMouse puts it in the Nape product map. Their check is a software fake plus orientation and DPI ranges, not a dongle capture. | Opened only with usage `0xFF60` / `0x61`. Menu says the 2.4 GHz path is unverified. |
| `0xD029` | Keychron Link-KM Type C in the Nape product map. The same id is also the M6's Link-KM receiver, and that mouse uses usage page `0xFFC1`, not `0xFF60`. | Opened only with usage `0xFF60` / `0x61`. An `0xFFC1` interface is left alone. Menu says the 2.4 GHz path is unverified. |
| `0xD024`, `0xD027`, `0xD028`, `0xD030`, `0xD031`, `0xD05A` | Named in OpenMouse's general receiver list. Not in the Nape product map. | Not opened. |
| `0xD05B`, `0xD078` | OpenMouse lists these with the 8K Nordic platform and says the pairing is not confirmed. That protocol uses usage page `0xFF0A`. | Not opened. |
| `0xD060` and other M-series ids | M6 wired is `0xD060` on usage page `0xFFC1`. Other Keychron mice use `0xFFC1`, `0x008C`, or `0xFF0A`. | Not opened. |
| Bluetooth | The trackball pairs and points over Bluetooth. The documented layer query has no published Bluetooth transport. See below. | Not opened. A visible Bluetooth interface is reported and left closed. |

If the wired trackball and a receiver are both present, the wired interface
wins. A receiver that does not expose `0xFF60` / `0x61` stays disconnected.
That is the safe failure: the menu does not invent a layer.

## macOS discovery

The app lists `IOHIDDevice` services in the I/O Registry and reads vendor,
product, product name, transport, primary usage, and `DeviceUsagePairs`.
It does not read the serial number or the location id into the menu.

`IOHIDManagerOpen` is not used. Opening the manager would open every matched
interface. A Nape Pro also exposes a mouse collection, and that collection
is not opened and has no input callback.

A service is opened only when its primary usage is page `0xFF60` usage
`0x61`, the vendor is `0x3434`, the product is the wired id or one of the
two unverified receivers, and the transport is not Bluetooth. The open is
`IOHIDDeviceOpen` with `kIOHIDOptionsTypeNone`. A vendor pair that only
appears beside a mouse primary usage is reported and left closed, because
opening that service would be the pointer device.

These states are different on purpose:

| What the census saw | Menu |
|---|---|
| No watched interface | `–` and the product id that was looked for |
| Product present, but not primary `0xFF60` / `0x61` | `!` plus the usage pages that were seen |
| Bluetooth only | `!` and a line that Bluetooth was not opened |
| Registry list itself failed | `!` and the IOKit status |
| Open returned exclusive access (`0xE00002C5`) | `!`. Launcher can be using the interface at the same time. That does not mean this app can open it too. |
| Open returned not privileged / not permitted (`0xE00002C1`, `0xE00002E2`) | `!` and the Input Monitoring hint |
| Interface opened, layer read timed out | `!` and a line that this is not a missing device |

No trackball was attached while this was written, so none of those branches
has been seen on hardware.

## Bluetooth feasibility

The onboard layer is not something a pointer packet carries. The only
documented way to read it is `0xA3` on the 32-byte vendor collection, usage
page `0xFF60` usage `0x61`. That collection is what this feasibility
question turns on.

What is published:

- dobachi’s protocol note, commit `1bca8c0`, records the exchange as WebHID
  against vendor `0x3434` and product `0x0440`, and says three HID interfaces
  are visible with configuration on `0xFF60` only. It does not describe a
  Bluetooth report map.
  https://github.com/dobachi/NapeProConfiguration/blob/1bca8c004c02e18bf41021da4116cb2955faed24/docs/nape-pro-hid-protocol.md
- The same repository’s device note lists Bluetooth, 2.4 GHz, and USB as
  connections, and calls the firmware ZMK-based with Keychron extensions. The
  commands actually captured are the vendor HID reports above, not the
  upstream ZMK Studio serial or GATT RPC.
  https://github.com/dobachi/NapeProConfiguration/blob/1bca8c004c02e18bf41021da4116cb2955faed24/docs/nape-pro-device.md
- OpenMouse, mouse-protocol commit `b62a1cc`, accepts a Nape only when the
  product is `0x0440`, `0xD026`, or `0xD029` and a collection is `0xFF60` /
  `0x61`. Its connection label is wired USB or 2.4 GHz. There is no
  Bluetooth product id. That code is AGPL-3.0 and is not included here.
  https://github.com/OpenMouse-Project/mouse-protocol/blob/b62a1cce2b63698ac00595efdb0067ecd54e34a0/src/drivers/keychron/nape-hid.ts
- Keychron’s Japan product page says the trackball is tri-mode, and that
  Launcher connects in wired mode or 2.4 GHz mode.
  https://keychron.jp/products/keychron-nape-pro-wireless-trackball-mouse
- Keychron Korea’s Nape Pro guide says Launcher does not support a Bluetooth
  connection, and that settings saved on the device remain after switching
  to Bluetooth. Firmware update is wired only.
  https://keychron.kr/products/nape_pro/guide
- Gizmodo Japan’s post-release FAQ, written with Keychron, says settings
  cannot be changed while connected by Bluetooth. Wired and 2.4 GHz are the
  Launcher paths.
  https://www.gizmodo.jp/article/napepro_faq-re/
- WebHID is not limited to USB. The HID specification covers Bluetooth as a
  transport, and Chromium implements WebHID for Bluetooth HID devices.
  https://hid.spec.whatwg.org/
  The WebHID blocklist forbids the generic mouse collection (`0x0001` /
  `0x0002`) and the keyboard collection (`0x0001` / `0x0006`). Usage page
  `0xFF60` is not in that list.
  https://github.com/WICG/webhid/blob/master/blocklist.txt
  Launcher asking for a cable or a receiver is therefore not evidence that
  a browser is incapable of a vendor HID report over Bluetooth.
- A separate macOS app, NapeProFix, reads battery over Bluetooth from the
  standard Battery Service `0x180F` characteristic `0x2A19`. It sends
  `A7 31` only to an `0xFF60` HID interface whose name matches the receiver
  or the Nape Pro. Its author states that the device layer does not arrive
  in the key events they receive.
  https://github.com/jprabadi-ship-it/NapeProFix/blob/master/Sources/NapeProFix/BatteryMonitor.swift
  https://github.com/jprabadi-ship-it/NapeProFix/blob/master/README.md
  Those key events are not a layer query. The same button can be assigned
  the same keycode on more than one layer, and pointer motion has no layer
  field at all.

What is not published: a Bluetooth HID report descriptor for this trackball,
or a capture of `0xA3` on that link. macOS publishes HID devices from USB
and from Bluetooth as `IOHIDDevice` services. `IOHIDDeviceOpen` can address
a vendor collection only when a service for it is actually listed. Nothing
here shows that the Nape Pro’s Bluetooth map contains `0xFF60` / `0x61`.
The Battery Service is a different GATT service and does not carry `0xA3`.

Until that map is seen, the documented read has nowhere to go over
Bluetooth. The app leaves a Bluetooth interface closed for that reason.
Pointing over Bluetooth, and keeping settings that were written over USB or
2.4 GHz, are separate facts and already work without this query.

The observation that would settle it, with the cable and the receiver
unplugged and the side switch on Bluetooth: the USB product id is not
required. Copy the Bluetooth HID device’s product id, transport, and each
collection’s usage page and usage from System Information. Do not copy the
serial number. If no collection is `0xFF60` / `0x61`, the documented query
is not on that link. If that collection is present and is not the mouse
collection, a later read-only open could try `0xA3`. This repository has
not done that.
