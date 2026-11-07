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
| Bluetooth | Not documented as this RAW HID exchange. | Not opened. The menu says Bluetooth is not supported. |

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
