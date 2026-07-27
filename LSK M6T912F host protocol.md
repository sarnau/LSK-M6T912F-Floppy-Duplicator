# LSK M6T912F — Host Remote-Control Protocol

The second serial link turns the duplicator into a **server**: a host PC can drive the entire
duplication cycle remotely — download a disk image, set up a format, run a pass, or upload and execute
code — while the machine services requests and reports status. This document covers that protocol as a
device interface.

> Everything here is **[FW]** — proven from the duplicator's disassembly. Unlike the autoloader link,
> the host protocol was not observed on the wire, so there is no independent ground-truth column.

## Serial link

- **Z80 SIO channel B**, I/O ports **`0xD8`** (data) / **`0xDC`** (control). The autoloader link is the
  *other* channel, A, at `0xD0`/`0xD4`.
- **9600 baud** (×16 SIO clock from the 8253, 153 846 Hz ÷ 16). **8 data bits, switchable parity**
  (boots **8O1** — odd parity); the autoloader link by contrast is fixed 8N1. Init is an OTIR of a
  WR-register blob (`host_ser_blob*`, applied at `0x4E03`).
- Primitives: `host_tx` (`0x4E9D`, spin on TxRDY), `host_rx` (via `0x4EAD`, RxRDY + timeout).

## Server loop — `host_dispatch` (0x1E0B)

Entering host mode sets `host_mode = 1` (`0x1E0D`) and drops into the wait loop:

1. Show a blinking idle marker — a `.` that self-modifies to `!` and back (`0x1E1C`, `XOR 0x0F` on the
   character cell) so the operator sees the link is alive.
2. Read a **4-byte command packet** (`host_read_packet` `0x1DF3`). A receive error → send `'E'` (NAK) and
   re-poll.
3. Store `op_word = opcode`, `run_count = parameter`, and dispatch by opcode (`0x1E37` onward).
4. Reply, and loop.

## Command packet — `host_read_packet` (0x1DF3)

Four bytes, read in this order:

| Byte | Goes to | Meaning |
|---|---|---|
| 0 | `E` | **lead / reserved** — read off the wire but never used or validated (a sync byte) |
| 1 | `D` | **opcode** → `op_word` |
| 2 | `L` | parameter low |
| 3 | `H` | parameter high → `HL` → `run_count` (16-bit little-endian) |

## Replies

Every handler answers with an ASCII ack plus, for most, a **binary status byte**:

| Reply | ASCII | Meaning |
|---|---|---|
| `X` | 0x58 | ACK / OK |
| `E` | 0x45 | bad-packet NAK |
| *(none)* | — | a pure RX timeout just re-polls (heartbeat continues) |

| Status byte | Meaning |
|---|---|
| `0x00` | ok |
| `0x90` | command error |
| `0xA0` | transfer failed |
| `0xB0` | not a proper image |

## Opcode table

Dispatch is a linear `CP <op>; JP/JR NZ` chain from `0x1E37`. **Control opcodes:**

| Op | Handler | Addr | Action |
|---|---|---|---|
| `0x09` | `host_op_start` | 0x205C | Reset the operation word (`op_word = 0`), ACK |
| `0x0A` | `host_op_image_dl` | 0x1E37 | **Image download** — `0xAA55`-framed records streamed into banked DRAM |
| `0x0B` | `host_op_enter_run` | 0x1F9F | **Enter RUN mode** — `host_mode = 0`, install I/O vectors `0x52C9/CB/CD`, `JP 0x0161` |
| `0x0C` | `host_op_ping` | 0x204B | Ping / no-op ACK (status `0x00`) |
| `0x0D` | `host_op_disk_write` | 0x1FC6 | **Disk-write / format setup** — see below |
| `0x0E` | `host_op_diag_out` | 0x2082 | **Host↔autoloader serial bridge** — relays bytes to the autoloader link until `'W'` (0x57); diag block via OTIR |
| `0x0F` | `host_op_load_exec` | 0x206F | **Load & execute** downloaded code (`code_loader` → `0x7800`, image at `0x8000`, `JP (HL)`) |

**Duplication-run opcodes.** Anything *not* matched above falls through to `host_op_begin_run`
(`0x20E3`), where the opcode itself becomes `run_status` (the operation mode) — there is **no
unknown-opcode reject path**:

| Op | Action |
|---|---|
| `0x07` | **BP** duplication run (prints "BP", `run_status = 1`, `OUT 0x9C,0x04`, require motor ready) |
| `0x01–0x06`, `0x08` | **FDD** duplication: `run_status = opcode` → duplication engine (mode = op-word phase: 1 FWV · 2 WV · 3 Format · 4 Format+V · 6 Write · 8 Verify) |

## Image download — `0x0A` (host_op_image_dl 0x1E37)

- ACKs with `'X'`, resets the track/record counters, shows **"wait for data"**, then waits for an
  **`0xAA55`** sync word on the link (`bulk_sync_aa55` `0x2196`).
- Reads a stream of **records**, each re-synced with `0xAA55`. A record starts with a **type byte**;
  bit 7 is the *last-record* flag, the low 7 bits are the type (type 1 = a track/geometry record).
- Track data is streamed straight into the **banked DRAM image buffer** (`OUT 0xB0` selects the bank);
  the download validates a geometry header and verifies a checksum, then sets `image_present`.

## Disk-write / format setup — `0x0D` (host_op_disk_write 0x1FC6)

Streams a small parameter block from the host and echoes each byte: `cfg_flags` + unit, a
**write-protect byte** (→ `0x9C` line 2 + `wprot_mode`, `0x200B`), an `err_recovery` byte, then a
**24-byte per-head zone table** written to `hrd_hd0`. This lets a host define a **variable-rate "Special"
format** remotely (the same zoned per-cylinder data-rate tables the front-panel Special-format menu
builds). Clears `image_present`.

## Load & execute — `0x0F` (host_op_load_exec 0x206F)

`code_loader` (`0x21A9`) prints **"Code loading"**, `LDIR`-copies a 256-byte bootstrap loader
(`dl_code`) into RAM at **`0x7800`**, and `JP`s into it. The relocated loader then pulls the new image
over the **bulk parallel channel** — *not* the SIO: port `0x90` = data, port `0x94` bit 6 = data-ready,
with a per-byte handshake toggled on the `0x9C` latch (`0x0E` assert / `0x0F` deassert).

Download protocol (`dl_code`, running at `0x7800`):

1. **Sync** on a ramp — 16 ascending bytes `0,1,…,15` then 16 descending `15,…,0`; any mismatch restarts.
2. **Header** — three 16-bit words: byte count, destination address, entry address.
3. **Payload** — stream `count` bytes into the DRAM **staging bank `0xFE`** at `0x8000`, accumulating an additive checksum.
4. **Verify** — read the expected checksum byte; mismatch → abort (`RET NZ`).
5. **Commit** — `LDIR` the staged bytes to the header's destination, then `JP (HL)` into the entry point.

Because the running firmware lives in writable **bank-`0xFF` RAM**, a downloaded image can rewrite the
firmware in place and re-checksum it — the whole reason for the shadowed-ROM / bank-`0xFF` design. The
same `code_loader` is also reachable from the front-panel **Config → "Code loading"** menu, so it isn't
host-only. By design it is an **arbitrary-code-execution path**; the dead `fmt_param_tbl` DOS-geometry
table (`0x326E`) is the kind of thing an externally-supplied loader module would consume.

## I/O-vector retargeting

Byte-level I/O (`get`/`put`/`beep`) goes through three RAM vectors — `iovec_out 0x52C9`,
`iovec_poll 0x52CB`, `iovec_beep 0x52CD` — dispatched via `0x4D89`/`0x4C43`/`0x2766`. The same call sites
serve the local keypad, the autoloader, or the host depending on the installed vectors; the `0x0B`
(enter-run) opcode **rewrites all three** and jumps to the shared run loop, so a host-initiated run reuses
the identical duplication code path as a front-panel run.

## Cross-reference

The duplicator-side handlers are also summarised in the firmware internals, §D (Serial protocol
handlers). The physical link (Z80 SIO channel B + TC232 line driver, the `KS` edge connectors) is in the
README *Serial / RS-232 connections*. The autoloader link (the machine as *client*) is documented
separately in the **Autoloader** reference.
