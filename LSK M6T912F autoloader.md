# LSK M6T912F — Autoloader

The **autoloader** is the mechanical disk changer bolted to the LSK M6T912F duplicator: an input
hopper, a motorised arm that feeds diskettes into the master/first drive, and accept / reject output
bins. It is a self-contained embedded device with **its own microcontroller and firmware**, driven by
the duplicator over a serial link. This document covers the autoloader as a device — its hardware, its
serial protocol, and how the duplicator's firmware talks to it.

> Sources are marked: **[GT]** = ground truth from observing the wire + poking with a terminal;
> **[FW]** = proven from the duplicator's disassembly; **[HW]** = from the chip datasheets / board.
> The autoloader's own firmware was not dumped, so its internals are described from the outside.

Banner printed on power-up `[GT]`: **`LSK Autoloader`** / **`Copyright - LSK Data Systems 1995`**.

## Hardware

| Chip | Role | Datasheet |
|---|---|---|
| **Microchip PIC16C57** | 8-bit MCU — the autoloader's brain: sequences the hopper/arm/bin motors, reads the position/jam sensors, and runs the serial command interpreter. 28-pin, 20 I/O, 2K×12 EPROM, 72 B RAM, DC–20 MHz. `[HW]` | `datasheets/controller/PIC16C57.PDF` |
| **SGS-Thomson ST93C06** | 256-bit (16×16 / 32×8) Microwire serial EEPROM — non-volatile store for the autoloader's **lifetime cycle count** (reported by `V`) and any calibration/config. 1 M write cycles, 5 V. `[HW]` | `datasheets/controller/ST93C06.PDF` |

The PIC's 20 I/O lines are enough to drive the three motor paths (hopper feed, drive arm, accept/reject
diversion) and read the sensor set the status byte reports (hopper-seated, hopper-empty, disk-in-drive,
reject-bin, accept-output). The ST93C06's 256 bits (32 bytes) comfortably hold the 32-bit counter plus a
few calibration bytes. `[HW, inferred]`

## Serial link

- **RS-232, 9600 baud, 8N1** `[GT]`.
- On the duplicator it is **Z80 SIO channel A**, I/O ports **`0xD0`** (data) / **`0xD4`** (control) `[FW]`.
  (The host-PC remote-control link is the *other* SIO channel, B, at `0xD8`/`0xDC`.)
- The protocol is **one ASCII byte per command**; the autoloader answers with a single ASCII status
  character (and, for `S`/`O`/`V`, additional ASCII text). `[GT]`

## Command set `[GT]`

| Cmd | ASCII | Meaning | Used by the duplicator? |
|---|---|---|---|
| `S` | 0x53 | **Status** — returns two ASCII hex chars (the status byte, below) | ✔ `al_cmd_status` 0x13FB |
| `C` | 0x43 | **Calibrate / clear** — home the mechanism, clear a fault | ✔ 0x1198 / 0x1272 |
| `I` | 0x49 | **Insert** — feed the next diskette from the hopper into the drive | ✔ 0x11FC |
| `A` | 0x41 | **Accept** — eject the diskette to the *accept* output bin | ✔ 0x10D6 / 0x1129 |
| `R` | 0x52 | **Reject** — eject the diskette to the *reject* bin | ✔ 0x1149 / 0x126D; also used as a **presence ping** (0x0252) |
| `O` | 0x4F | prints the **version** string | ✘ never issued by this ROM `[FW]` |
| `V` | 0x56 | prints the **cycle count** — 32-bit, big-endian, as a hex string | ✘ never issued by this ROM `[FW]` |

`S` keeps returning the same status until a `C` (calibrate/clear) resets it `[GT]`. The duplicator's
presence probe sends `R` while idle: an autoloader with nothing to eject still answers, so a reply means
"connected" and a pure timeout means "not connected" (0x0220 → 0x024D) `[FW]`.

## Responses `[GT]`

| Reply | ASCII | Meaning |
|---|---|---|
| `X` | 0x58 | executed successfully (ACK) |
| `E` | 0x45 | error — follow with `S` to read the error code |
| `?` | 0x3F | "what?" — unrecognised command |

The duplicator's command wrapper (`al_cmd_ack` 0x13D9) transmits the command byte and tests the reply
against `'X'` (0x58): equal → ok, timeout → code 1, anything else → code 2 `[FW]`.

## Status byte (`S` command)

`S` returns the status as **two ASCII hex characters** (e.g. `"0B"`), which the duplicator decodes at
0x13FB into a single byte `[FW]`. The byte is structured as a **fault class in the high nibble** and
**disk-presence bits in the low nibble** `[GT + FW]`:

- **bit 1** — *seated* qualifier: the duplicator treats bit 1 = 0 as "hopper not seated" (0x1286) `[FW]`.
- **bit 3** (`0x08`) — *disk in the drive* (`0x07` empty → `0x0B` loaded; `0x47` → `0x4B`) `[GT]`.
- **high nibble** — the event / fault class (`0x2x` hopper, `0x4x` no-disk/arm-forward, `0x8x` reject
  jam, `0x9x` eject jam) `[GT]`.

| Code | Bits | Ground-truth meaning `[GT]` |
|---|---|---|
| `07` | 0000 0111 | ok — drive empty |
| `0B` | 0000 1011 | ok — disk in drive |
| `27` | 0010 0111 | input hopper empty |
| `47` | 0100 0111 | no disk in drive (asked to eject with none present) |
| `4B` | 0100 1011 | disk in drive, motor arm forward |
| `87` | 1000 0111 | disk jam — reject-bin sensor |
| `8B` | 1000 1011 | disk jam — reject-bin sensor |
| `97` | 1001 0111 | disk jam — ejected from drive but did not exit accept output |
| `9B` | 1001 1011 | disk jam while ejecting (reject bin selected) |

## How the duplicator decodes it — and where the labels diverge

`al_status_decode` (0x1286) masks the high nibble (`AND 0xF0`) and dispatches to an LCD message `[FW]`.
The firmware's captions do **not** always match the autoloader's ground-truth condition:

| Class | Firmware LCD message | Ground truth `[GT]` | Match? |
|---|---|---|---|
| 0x00 | "AL status ok" | ok (`07`/`0B`) | ✓ |
| 0x20 | "Hopper empty" | hopper empty (`27`) | ✓ |
| 0x40 | *generic* "AL error   Status ᴴᴴ" | no-disk / arm-forward (`47`/`4B`) | no dedicated message |
| 0x80 | **"Calibration error"** | reject-bin **disk jam** (`87`/`8B`) | **label differs** |
| 0x90 | "Eject timeout" | eject **jam** (`97`/`9B`) | ≈ same fault |
| 0xA0 | "Accept hopper full" | — | — |
| 0xC0 | "Reject error" | — | — |
| 0xD0 | "Bad bin full" | — | — |
| bit 1 = 0 | "Hopper not seated" | hopper not seated | ✓ |

So a `Status 87` (mechanical reject-bin jam) is captioned **"Calibration error"** on the panel — a
firmware mislabel; clear the jammed diskette from the reject path, not recalibrate. Unrecognised classes
such as `47`/`4B` fall through to the generic **"AL error   Status ᴴᴴ"** line (`show_al_error` 0x02B0),
which patches the raw hex into the text so the code is readable off the LCD `[FW]`.

## Two independent cycle counters

Do not confuse them `[FW]`:

- **Autoloader's own count** — a 32-bit total kept in the ST93C06 EEPROM, read only by the `V` command.
  This ROM never issues `V`, so the duplicator never reads it.
- **Duplicator's count** — a separate 32-bit counter in the *duplicator's* CAT24C02 EEPROM (offset
  `0xFC`, RAM `cycle_cnt` 0x3269/0x326B), bumped once per successful `I`/insert and shown by
  `show_model_cycles`. This is the number the duplicator's menus display.

## Cross-reference

The duplicator-side handlers are documented in the firmware analysis, §8 (Serial & protocols):
the client command/ACK loop (`0x13D9`), the status decode (`0x1286`), the connection probe (`0x0220`),
and the status-vs-ground-truth comparison. The link's electrical side (Z80 SIO + TC232) is in the README
*Serial / RS-232 connections* note.
