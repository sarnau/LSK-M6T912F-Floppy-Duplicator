# LSK M6T912F Floppy Duplicator — Firmware Analysis

Reverse-engineering reference for the LSK Data Systems **M6T912F** four-drive gang floppy
duplicator (Z80, 1996). Source image: `LSK M6T912F D1_97.bin` — 32768 bytes, disassembles as
Z80 at **ORG 0x0000**.

> **Confidence tags** — `[V] Verified` read from the code directly · `[R] Reported` traced,
> consistent · `[?] Uncertain` flagged for a hardware check.

---

## 1. Overview

The device reads one master floppy into a bank of DRAM, then writes and verifies up to four
blank floppies at once. It runs standalone from a front-panel menu, drives an optional mechanical
**autoloader** over RS-232, and can be driven by a host PC in a **remote-control** mode that
streams a disk image down a dedicated data channel.

Both serial links have their own dedicated references: the
[autoloader](LSK%20M6T912F%20autoloader.md) (a separate PIC16C57/ST93C06 device — the machine is its
*client*) and the [host remote-control protocol](LSK%20M6T912F%20host%20protocol.md) (the machine is
the *server*). See §7 for the firmware-side summary.

The firmware is a single 32 KB image. At reset it copies itself into RAM, banks the EPROM out, and
runs entirely from RAM — which is what makes field firmware updates ("Code loading") possible.

Origin markers in the strings — `Adresa =` (Czech/Slovak/Croatian "address"), `controll`,
`hystheresis` — point to a Central/Eastern-European developer. Banner: *LSK Data Systems 1995*.

## 2. Chipset

| Function | Ref | Part | Ports | Role | Status | Datasheet |
|---|---|---|---|---|---|---|
| CPU | U51 | Zilog Z0840006 (Z80, 6 MHz) | — | Main processor, interrupt mode 1 | [V] | `datasheets/Zilog Z0840006PSC Z80 CPU.pdf` |
| Floppy ×4 | U1–U4 | SMC FDC37C65C | 00/10/20/30 | Four µPD765-compatible controllers | [V] | `datasheets/SMC FDC37C65C 2.88MB Floppy Disk Controller.pdf` |
| DMA | U7 | NEC µPD8237A (8237) | 80–8F | 4 channels stream sector data to the FDCs (one per controller) | [V] | `datasheets/NEC D8237A DMA Controller.pdf` |
| Timer | U70 | NEC µPD8253C-2 PIT | A0–AC | Baud clock + interval measurement | [V] | `datasheets/NEC D8253C PROGRAMMABLE INTERVAL TIMER.PDF` |
| Serial | U71 | **Zilog Z80 SIO/0** (Z0844006PSC) | D0–DC | Dual channel — A = autoloader (D0/D4), B = host (D8/DC); external baud clock from the 8253 | [V] | `datasheets/Zilog Z0844006PSC SIO.pdf` · `datasheets/Zilog Z80SIO Technica Manual.pdf` |
| Parallel I/O | U69 | NEC µPD71055 PPI (+ 74HCT373 latches) | 40–70, B0–C6 | Drive select, motor, sensors, bank/rate | [V] | `datasheets/NEC µPD71055 Parallel Interface Unit.pdf` |
| Display | K51 | HD44780 LCD (2×20) — module via connector K51 | E0/E8 | Front-panel character display | [V] | `datasheets/Hiatchi HD44780 LCD.pdf` |
| Image DRAM | U77/U78 | 2× 4 MB 30-pin SIMM (AS4C14400 1M×4) = 8 MB | bank @ B0 | Banked disk-image buffer — image banks `0x00–0xFE`; **bank `0xFF` = program-RAM mirror** (see §3) | [V] | `datasheets/AS4C14400 1M×4 RAM.PDF` |
| Line driver | U101 | Microchip TC232 | — | RS-232 level shifting | [R] | `datasheets/Microchip TC232CPE RS232.PDF` |
| Config EEPROM | U86 | Catalyst CAT24C02 (I²C, 256×8) | F0 (bit-banged I²C) | Non-volatile settings + serial number (write-protect, copy dir, serialization, err-recovery, max-cyl) | [V] | `datasheets/CAT24C02.pdf` |
| Address decode | U5, U68 | Lattice GAL20V8B + PALCE20V8H | — | I/O + memory chip-select generation | [V] | `datasheets/GAL20V8B 15LP.pdf` · `datasheets/PALCE20V8.PDF` |

The parallel I/O is a **single µPD71055 PPI** (there is no Z8420 PIO — an earlier assumption that has
been corrected); together with discrete 74HCT373 latches it drives the digital motor/select/sense
lines. The traced code writes those ports as plain write-only latches without a distinctive mode-word
init, so the exact PPI-vs-373 split per port isn't pinned from firmware alone (a minor residual).

The device is the **Terra Computer Systems KDP-05 B** (Czech Republic, © 1993) — that model number is
from the board's sticker; the bare PCB is silkscreened **KOP05B** (see `PCB_CONNECTORS.md`). The "LSK
M6T912F" is the LSK-branded build. Clocking: **32.000 MHz** and **48.000 MHz** crystals; the 8253's 2 MHz
input is 32 MHz ÷ 16. Address decode is handled by a GAL20V8B (U5) + PALCE20V8H (U68). All larger parts are confirmed
against on-board markings and manufacturer datasheets.

## 3. Memory architecture

```
0x0000 ────────────────────────── 0x8000 ────────────────────────── 0xFFFF
| Program RAM = DRAM bank 0xFF,           | Banked DRAM window —         |
| loaded with the EPROM mirror at boot    | disk image buffer, banks     |
| then mapped low by OUT 0x9C,0x92        | 0x00–0xFE (bank@0xB0)         |
```

The two windows are the **same 0xB0-banked DRAM array**. At boot the bank latch is set to **`0xFF`**
and the EPROM is `LDIR`-copied into that bank's window (`0x8022`); `OUT 0x9C,0x92` then fixes bank
`0xFF` permanently at `0x0000–0x7FFF` (decoupled from `0xB0`) so the running code is unaffected when
`0xB0` later cycles image banks `0x00–0xFE` in the upper window. See "Bank 0xFF is the program
mirror" below.

- **Variables:** `0x3100–0x33FF` main state · `0x4A00–0x4BFF` per-drive FDC + keypad state blocks ·
  `0x5200–0x52FF` system & config (I/O-mode vectors `0x52C9/CB/CD`, checksum bytes at end).

### Content boundary

The real firmware content occupies **0x0000–0x52FF** (21248 bytes). **0x5300–0x7FFF is 100%
`0xFF` fill** — unused EPROM. (The boot `LDIR` copies 0x0022–0x6021 regardless, so the fill lands
in RAM but is never used.) The disassembly is trimmed to 0x0000–0x52FF.

### Checksums (end of image, 0x52F0–0x52FF)

| Bytes | Value | Role |
|---|---|---|
| `0x52F0` | `0xC7` | **Firmware self-check reference.** Verified: `sum8(0x0100..0x52EF) = 0xC7`. Boot compares this at `0x0128`; mismatch → "CODE TRANSFER ERROR". (The computed sum is stored at `0x52EF`, which is `0x00` in the static image.) |
| `0x52F1` | `0xAA` | Validity magic marker. |
| `0x52FE/0x52FF` | `0x2198` (LE) | 16-bit value at end-of-content, **not referenced by any instruction**. Doesn't match CRC-16 (CCITT/ARC) or additive sums over the obvious ranges — most likely an **external programmer / build checksum or image signature** applied by the EPROM tooling, not verified by the firmware itself. |

### Is 0x0000–0x7FFF RAM, not the EPROM?

The physical part is an EPROM, but at runtime that range is answered by **static RAM**. Proofs:

1. **316 store instructions target addresses below 0x8000** — you cannot write an EPROM with
   `LD (nnnn),A`; the machine's own variables live here.
2. **Boot checksum stores then reads back:** `LD (0x52EF),A` writes the computed sum into `0x52EF`
   (which is `0x00` in the static image), then `0x0128` reads it back and compares to reference
   `0x52F0 = 0xC7`. The store-of-a-computed-value-then-readback only works in RAM.
3. **"Variable" regions are zero-filled holes** in the image — initialized-data + BSS laid into a
   RAM image (e.g. `0x4A50–0x4AB0` is all `00`).
4. **The boot ceremony is pointless otherwise** — it `LDIR`s the image up to RAM and bank-switches
   before `JP 0x0100`; in-place EPROM would just jump at reset.
5. **"Code loading" requires it** — field firmware updates can only replace the running image if it
   sits in writable RAM, guarded by that checksum.

The image DRAM and the program RAM are the **same banked array** — **2× 4 MB 30-pin SIMMs = 8 MB**
(parity-type SIMMs, but the parity bit is *simulated*/generated rather than checked). Port **`0xB0`**
selects which 32 KB bank appears in the 0x8000–0xFFFF window (8 MB = **256 banks**). One bank is
reserved: **bank `0xFF` is the program RAM**, so the image buffer is banks **`0x00–0xFE`** (255
banks ≈ 7.97 MB) — enough to cache several full disk images (≈ 5× 1.44 MB). The `Test dram: N kB`
routine (`0x03DD`) sizes the installed DRAM at boot by walking banks — `OUT (0xB0),A; LD (0x8000),A;
CP (0x8000)` — and counting those that read back. (Port `0x9C`, written `0x92` at boot, is a separate
multi-function control/mode latch — see the port map.)

### Bank 0xFF is the program mirror

The "static RAM" at 0x0000–0x7FFF is not a separate chip — it is **DRAM bank `0xFF`**, loaded with a
copy of the EPROM at boot and then mapped low. Traced byte-for-byte at reset:

| Addr | Code | Effect |
|---|---|---|
| `0x000E` | `LD A,0xFF; OUT (0xB0),A` | select **bank 0xFF** in the 0x8000 window |
| `0x0014` | `LD BC,0x5FFF; LD HL,0x0022; LD DE,0x8022; LDIR` | copy EPROM `0x0022–0x6021` into bank 0xFF (`0x8022+`) |
| `0x001F` | `JP image_buf+0x22` | run the fresh copy **inside bank 0xFF's window** |
| `0x0022` | `LD A,0x92; OUT (0x9C),A` | latch bank 0xFF permanently at `0x0000–0x7FFF`, drop EPROM |
| `0x0026` | `JP boot_init (0x0100)` | continue from the RAM copy |

Two independent facts confirm bank 0xFF is *reserved for code*, not an image bank:

1. **The relocation writes there.** The `LDIR` target `0x8022` is the 0x8000 window with `0xB0=0xFF`
   already selected, and the very next instruction executes from that window — so bank 0xFF *is* the
   memory that becomes the program at 0x0000–0x7FFF.
2. **Every image-bank walk stops before it.** The boot DRAM sizing and the per-bank checksum loop
   (`0x5193`: `INC A; CP 0xFF; RET Z`) iterate banks `0x00–0xFE` and terminate the instant the bank
   index reaches `0xFF` — bank 0xFF is never sized, checksummed, or used to hold image data.

This is why "code loading" (field firmware update) can work at all: the running image lives in
writable bank-0xFF RAM, so a new image can be streamed into it and re-checksummed in place.

**The mapping is set-once and permanent** (verified). `OUT (0x9C),0x92` executes exactly once, at
boot `0x0022` — the only other `LD A,0x92` is `0x07EA: LD (fmt_mode),A`, a RAM store. `OUT (0xB0),0xFF`
also executes exactly once (`0x0010`); every later `0xB0` write loads an *image* bank
(`track_bank_a/b`, or `0xFE` scratch), never 0xFF. So neither the 0x9C map bit nor the bank-0xFF
selection is ever re-commanded. Runtime writes to both ports demonstrably leave low RAM intact: the
copy loop does `OUT (0xB0),A` then keeps fetching from low RAM while building a `≥0x8000` pointer
(`0x0E49`), and `fdc_poll_complete` pulses the *same* port 0x9C (`0x0E`→6 NOPs→`0x0F`, `0x475E`) with
the PC running straight through those NOPs. A plain 8-bit register at 0x9C couldn't survive this
(writing `0x0E` after `0x92` would clear 0x92's high bits); 0x9C must be an **addressable per-line
latch** (74259-class) where the boot commands the map line once and every runtime write selects a
different line — so bank 0xFF stays mapped low for the machine's entire runtime.

#### 0x9C latch decode (verified)

The addressable-latch decode is pinned from firmware to **data = bit 0, select = bits [3:1]**:

- *Bit 0 is data* — `update_ctrl_latch` (`0x0760`, `CP 0x01; OR 0x01`) and the `0x24DD` path
  (`LD A,0x05; XOR 0x01` → `0x04`/`0x05`) both toggle **only bit 0** on a fixed select; the FDC
  strobe `0x0E`→`0x0F` differs only in bit 0.
- *Select is the low bits, not the high nibble* — `0x04` (write-protect) and `0x0E` (FDC strobe) are
  distinct runtime functions, so they must occupy different lines; only a bits-[3:1] select separates
  them (lines 2 vs 7). A high-nibble select would collide them → contradiction. The high nibble
  (`0x92`'s `0x90`, `0x2D`'s `0x20`) is therefore don't-care.

**Six distinct lines** are observed, all consistent with the decode:

| sel `D3:D1` | line | function | values | data (D0) |
|---|---|---|---|---|
| `001` | 1 | **EPROM/RAM map** | `0x92` — **boot only** | 0 = RAM low, EPROM out |
| `010` | 2 | **write-protect** | `0x04`/`0x05` | protect on / off |
| `100` | 4 | **datarate select, drive A** | `0x08`/`0x09` | rate class (from `fdc_rate_a`) |
| `101` | 5 | **datarate select, drive B** | `0x0A`/`0x0B` | rate class (from `fdc_rate_b`) |
| `110` | 6 | static drive/write enable | `0x2D` (boot, `bit0=1`) | 1 = asserted (permanent) |
| `111` | 7 | **FDC result-read strobe** | `0x0E`→`0x0F` | 0→1 rising edge |

Function derivations (firm unless noted):

- **Line 2 = write-protect.** The `0x24DD` handler is the front-panel **"Write protect"** config screen
  (`get_key` → `0x04`/`0x05` → store `wprot_mode` → `config_wprotect`); the `"Write protect"` string
  sits at `0x24EF`. `bit0` carries the protect flag. It's also driven remotely: host op `0x0D`
  (`0x200B`) writes a host-supplied byte to `0x9C` and caches it in `wprot_mode`.
- **Lines 4 & 5 = per-drive datarate select.** `update_ctrl_latch` (`0x0760`) is called with
  `A = fdc_rate_a`/`fdc_rate_b` (a cylinder-banded rate from `range_table_lookup`) and `E = 0x08`
  (→ line 4, drive A) / `E = 0x0A` (→ line 5, drive B); it `OR 0x01`s `bit0` when the rate class is 1,
  and in parallel sets `bit2` of the drive latch (`0x50`/`0x70`, `drv_lat1/3`). The banded rate is read
  from the **Special-format zone tables** (`fmt_geom_recs`): `range_table_lookup` (`0x092A`, `B=6`)
  scans a head's 6 `{start-cyl, rate}` zones for the current cylinder and returns the `N/L/H` flag —
  so N/L/H is confirmed to be **per-cylinder data rate** (variable-rate zoned formatting).
- **Line 6 = a static enable, *not* precompensation.** Its data bit is `bit0` of `drv_active_cfg` — a
  **hardcoded constant `0x2D`** (written once at `0x01B7`, never config-changed). Every consumer uses
  only that bit (all do `AND 0x01`, some even force `SET 0,A`), and it is always `1`. The same bit is
  fanned into the drive-control latches (`0x40`/`0x60`, the *active* pattern `0x2D` vs *idle* `0x0E`)
  and written once to 0x9C line 6 at boot (`0x03C2`, via `dram_bank_cfg`) — never cleared. So line 6 is
  a **permanently-asserted global enable**. The real write-precompensation is a *separate* path:
  `fdc_datarate_precomp` (`0x1141`) computes it per-geometry and outputs to **FDC port `0xC2`
  (`fdc_precomp`)**. Line 6's exact physical signal (write-gate / reduced-write-current / drive-enable)
  isn't determinable from firmware, but its behavior — set-once, held high — is. *(The disassembly
  symbol was renamed from the misleading `precomp_val` to `drv_active_cfg` to reflect this.)*

The map line (`001`) is written by exactly one instruction in the whole image (`OUT (0x9C),0x92`
@ `0x0022`); no runtime write ever selects it. **Not** derivable from firmware: the physical A0–A2
ordering (permuting relabels the line numbers but preserves the grouping), which Q-pin drives
which board signal, and the meaning of the don't-care high bits — all need the schematic.

## 4. Boot sequence

| # | Addr | Action |
|---|---|---|
| 1 | 0000 | Init 8237 DMA (`OUT 0x88,0xA0`; `0x8D,0x8F=0x0F`), `SP=0x8000`, **select DRAM bank 0xFF (program-RAM window)** via `OUT 0xB0,0xFF`; then `OUT 0xC0,0xFF` (a *separate* one-shot control-latch init — see port map) |
| 2 | 001D | `LDIR` copies EPROM 0x0022–0x6021 → **bank 0xFF** at 0x8022, then `JP 0x8022` (runs the copy in bank 0xFF's window) |
| 3 | 0022 | `OUT 0x9C,0x92` fixes bank 0xFF at 0x0000–0x7FFF (EPROM drops out; bank decoupled from later `0xB0` changes) → `JP 0x0100` |
| 4 | 0105 | Checksum RAM copy (sum 0x0100–0x52EF). Mismatch → **"CODE TRANSFER ERROR"**, retry |
| 5 | 4DD9 | `IM 1`; program 8253 counter 0 (baud) + c1/c2; init both Z80 SIO channels; drain receivers |
| 6 | 03DD | Size DRAM banks → **"Test dram: N kB"** |
| 7 | 0432 | Detect FDDs, load format descriptor. Bad config → **"Unsupported FDD / Run config again"** |
| 8 | 0235 | Enter **Autoloader** or **Manual** operating mode |

Maskable interrupts (IM 1) vector through `0x0038` → `JP 0x45DB`, the FDC result-phase handler:
it reads which controller interrupted (port `0x94`) and pulls the 7-byte result phase from each
of the four FDCs.

## 5. I/O port map

| Port(s) | Chip | Register / role | Evidence | Status |
|---|---|---|---|---|
| 00/01 10/11 20/21 30/31 | 4× FDC37C65C | MSR (base+0) / Data (base+1) | 765 handshake `0x457F` (`AND 0xC0;CP 0x80`) & `0x46F1` | [V] |
| 80–8F | µPD8237A DMA | ch0–3 addr/count (80–87), cmd/status 88, mode 8B, mask 8A/8E/8F, clear-ff 8C, mclr 8D | arm `dma_arm_channel` 0x4401 (bit7 of selector → ch0/1 @0x441B or ch2/3 @0x4408); reset `OUT 0x88,0xA0` | [V] |
| A0/A4/A8 | 8253 PIT | counter 0 / 1 / 2 | ctrl words `16/50/90` select each counter | [V] |
| AC | 8253 PIT | control register | c0 mode-3 baud (÷13); c1/c2 mode-2 RPM/hysteresis timing | [V] |
| D0/D4 | Z80 SIO ch A | data (D0) / control+status (D4) — autoloader | Tx `BIT 2` (RR0 Tx-empty), Rx `BIT 0` (RR0 Rx-avail), data port = control `& ~4` (`RES/SET 2,C`, `0x4E42`); errors via WR0-ptr→RR1 `AND 0x70`; `WR0=0x30` error-reset | [V] |
| D8/DC | Z80 SIO ch B | data (D8) / control+status (DC) — host | same SIO cores, C=0xD8/0xDC | [V] |
| E0 | HD44780 LCD | instruction reg (RS=0), bit7=busy | `lcd_init` `0x4B99`, printer `0x4C59`, busy-wait `0x4C2A` | [V] |
| E8 | HD44780 LCD | data reg (RS=1); presence self-test (write `0x55`, read back) | `lcd_byte_out` `0x4C43` with C=0xE8; probe `0x4BCC`, readback `0x4BDD` → headless on mismatch | [V] |
| B0 | DRAM bank latch | image-buffer 32 KB bank select | DRAM sizing `OUT (0xB0),A` @0x03EE; per-track bank before every 0x8000 access (`0x0E49/0x1D55/0x1CEC`) | [V] |
| C0 | control latch — **boot init only** | written `0xFF` once at boot (with the B0 bank latch), never read or re-written | only `OUT (0xC0),0xFF` @0x0012; sits in the drive/FDC-control block (C2 precomp, C3 rate, C6 drive-sel-b); reads as an all-ones idle/deselect init but **exact function isn't determinable from firmware** | [?] |
| 9C | control/mode latch | boot memory-mode (`0x92`); host bulk-channel strobe (`0x0E/0x0F`); drive/analog control (`0x04`) | `OUT 0x9C,0x92` at boot; strobe in `0x216A`; exact bit-map unresolved | [R] |
| 90/94 | bulk channel | image data-in / ready (bit6) | download `0x216A`, `0xAA55` frame sync | [R] |
| B1/C2/C3 | FDC glue | data-rate / precomp select | precomp init `0x0980` (250/500 kbps) | [R] |
| 40/50/60/70 B0/C6 | µPD71055 PPI / 74HCT373 | drive select · motor · side | reset `OUT 0x40/0x60,0x0E`; DOR builder `0x3CD3` | [?] |
| 94/98/F0 | panel + EEPROM | 4 keys · beeper · serial NVRAM | key scan `0x4D0B`; key decode `0x4590`; beeper on `0xF0`; EEPROM `0x2ACB` | [R] |

**Corrected during analysis** — direct disassembly settled three initially-disputed assignments:
0x00/10/20/30 are four FDCs (textbook 765 MSR polling), not sensor latches; 0xD0–0xDC are the two
Z80 SIO channels (they carry the autoloader + host protocols), not FDC data; 0x80–0x8F is the 8237 DMA, not an MMU.
The 8253 datasheet then re-homed 0xA0–0xAC from "PPI" to the timer, which also explains baud gen.

## 6. Floppy subsystem

Four FDC37C65C controllers, one per drive, commanded by polled PIO but fed bulk sector data by the
8237 — one DMA channel per controller. To write four disks at once, the firmware arms all four
channels against the **same** track buffer (`0x8000`) and lets the DMA engines clock it out
concurrently.

**Primitives**
- Write bytes — `0x457F`: poll MSR (`AND 0xC0;CP 0x80` = RQM set, DIO clear), then `INC C;OUTI` to data (base+1).
- Read result — `0x46F1`: wait RQM (BIT 7), test DIO (BIT 6), `INI` each byte.
- DMA arm — `0x4401`: select channel, clear flip-flop (`OUT 0x8C`), set mask/mode (`0x8A/0x8B`), stream addr+count.
- Precomp/rate — `0x0980`: 250 kbps (DD) / 500 kbps (HD) via 0xB1/0xC2/0xC3.
- Format — `0x1CEC`: builds FAT12 boot sector from ROM template `0x3305` (OEM "Jumbo", "Non system disk"), stamps `0x55AA` at `0x81FE`.

**Built-in formats** (all 512 B/sector)

| Media | Capacity | Sec/trk | Cyl | Heads | Rate |
|---|---|---|---|---|---|
| 3.5″ | 720 kB | 9 | 80 | 2 | 250k |
| 3.5″ | 1.44 MB | 18 | 80 | 2 | 500k |
| 5.25″ | 360 kB | 9 | 40 | 2 | 250k |
| 5.25″ | 180 kB | 9 | 40 | 1 | 250k |
| 5.25″ | 320 kB | 8 | 40 | 2 | 250k |
| 5.25″ | 160 kB | 8 | 40 | 1 | 250k |
| 5.25″ | 720 kB | 9 | 80 | 2 | 250k |
| 5.25″ | 1.2 MB | 15 | 80 | 2 | 500k |

Plus 16 user "Special formats" and named models 528-400 / 526-400 / 325-400. The 2.88 MB (ED)
capability of the FDC37C65C is present in silicon but no ED format ships in this table.

## 7. Serial & protocols

Two independent Z80 SIO channels at 9600 baud (×16 clock from the 8253), fully polled (no interrupt
ring buffers). Each channel is set up at boot by `OTIR`-ing a 13-byte WR-register blob to its control
port (`al_ser_blob`→0xD4, `host_ser_blob2`→0xDC): channel-reset, WR3/WR4/WR5/WR1, then enable Rx+Tx
with RTS/DTR. Framing is 8 data bits, 1 stop; the **autoloader channel is 8N1**, and the **host
channel switches parity per operation** (boots 8O1; `host_ser_blob0/1` reprogram it 8N1/8O1).
Channel A = autoloader; channel B = host. A third channel (0x90/0x94/0x9C, `0xAA55`-framed) carries
bulk image data.

### Autoloader — machine is the client (disk-handling mechanism)

The main board does **not** drive the disk-insert/eject motors directly. The autoloader is a separate
mechanical unit with its own controller (banner "LSK Autoloader / Copyright LSK Data Systems 1995"),
and channel A (`0xD0/0xD4`) is the link that **commands its motors and reads its sensors** — insert,
accept, reject, calibrate, and a status byte encoding the mechanical state (hopper empty, disk-in-drive,
jams, bin full, eject timeout). The main board sends single ASCII commands and expects `X` (ok) /
`E` (error) / `?` (unknown). Dispatcher `0x13D9`.

| Cmd | Meaning | Cmd | Meaning |
|---|---|---|---|
| S | status (2-byte reply) | R | reject |
| C | calibrate / clear | O | print version |
| I | insert | V | cycle count (32-bit) |
| A | accept | | |

Status decode `0x1286`: `BIT 1` gates "Hopper not seated"; high nibble selects message —
`0x0`→ok, `0x2`→hopper empty, `0x8`→calibration error, `0x9`→eject timeout, `0xA`→accept hopper
full, `0xC`→reject error, `0xD`→bad bin full.

### Host remote control — machine is the server

The two serial links have **opposite roles**: on the autoloader link the machine is the *client*
(above); on the host link (`0xD8/0xDC`) it is the **server**. Entered via the "Remote controll" menu,
dispatcher `host_dispatch` (`0x1E0B`) is a server loop — it shows a blinking `.` heartbeat, reads a
4-byte packet `{lead byte (read but unused), opcode, 16-bit LE parameter}`, dispatches by opcode, and replies `X`
(0x58 ack) / `E` (0x45 bad-packet NAK) plus a binary **status byte** (`0x00` ok; `0x90/0xA0/0xB0` =
command error / transfer failed / not-proper-image). A host PC can drive the whole duplication cycle
remotely — download an image, format/write, run a pass, even upload and execute code.

**Control opcodes** (`0x09`–`0x0F`, explicit handlers):

| Op | Action |
|---|---|
| `0x09` | reset operation word, ACK |
| `0x0A` | image download — `0xAA55`-framed records streamed into banked DRAM |
| `0x0B` | enter RUN mode — install I/O vectors (0x52C9/CB/CD), `JP 0x0161` |
| `0x0C` | ping / no-op ACK |
| `0x0D` | disk-write / format setup — streams write-protect (`→0x9C`), `err_recovery` and a 24-byte per-head zone table (host defines a variable-rate format) |
| `0x0E` | host↔autoloader serial **bridge** + diagnostic block |
| `0x0F` | load & execute downloaded code (→ 0x7800) |

**Duplication opcodes** — every other value falls through to `host_op_begin_run` (`0x20E3`), where the
opcode *is* the run mode: `0x07` = **BP** duplication; `0x01`–`0x06`/`0x08` = **FDD** duplication
(FWV / WV / Format / Format+V / Write / Verify). There is **no unknown-opcode reject path**. Full
byte-level table in the internals companion.

## 8. UI & features

Four front-panel keys — **Next** (`0x08`), **Previous** (`0x04`), **Exit** (`0x02`), **Enter**
(`0x01`) — plus an audio beeper. Menus run on a generic driver, `menu_run` (`0x522F`): each menu is
two parallel null-terminated pointer lists (a *draw* proc and a *do* proc per item); Next/Previous
scroll and redraw, Enter runs the item's action, Exit returns. Two-choice screens put one option per
LCD line with an `…EXIT`/`…ENTER` hint. Holding a key at power-on enters the Config menu. The beeper
gives key-click feedback and error/alert tones (port `0xF0`).

### Display — Hitachi HD44780 (2-line)

Two ports: **`0xE0` = instruction register** (RS=0 — write command, read busy flag on bit 7) and
**`0xE8` = data register** (RS=1 — write character). `IN (0xE8)` also reads the board-ID signature
`0x55`. All writes go through `lcd_byte_out` (`0x4C43`), which first spin-waits the busy flag
(`lcd_wait_busy`, `0x4C2A`) then `OUT (C),A` with `C` = `0xE0` (command) or `0xE8` (data).

**Init sequence** (`lcd_init`, `0x4B99`) — a textbook HD44780 bring-up:

| Command | HD44780 meaning |
|---|---|
| `0x30` ×3 (raw, with delays) | Function set, 8-bit — the power-on reset handshake |
| `0x38` | Function set: **8-bit, 2 lines, 5×8 font** |
| `0x08` | Display off |
| `0x01` | Clear display |
| `0x06` | Entry mode: cursor auto-increment, no shift |
| `0x0C` | Display on, cursor off, blink off |
| `0x02` | Return home |
| write `0x55` → `0xE8`, read back | hardware/board presence check |

`N=1` in the function set confirms a **2-line** panel; line 2 is DDRAM `0x40` (`0xC0` command),
matching the 2×20 layout. Other runtime `lcd_byte_out` control commands: `0x0E` cursor-**on** during
numeric field entry (`edit_num_field`, `0x04C9`) and `0x0C` cursor-off afterward (`0x05E0`); `0xC0`
to jump to line 2 on newline; `0x01`/`0x02` clear/home from the inline-string control bytes; and one
`0x48` "set CGRAM addr" at boot (`0x0196`) for a custom character glyph.

```
OPERATING MODE  (autoloader auto-detected)
├─ Autoloader  — hopper / accept / reject, with jam & timeout status
└─ Manual operation
     ├─ No. of copies
     ├─ Read source disk        → image present / missing
     ├─ Copy mode: Format-Write-Verify · Write+Verify · CRC check
     │              Format+Verify · Write disk · Bit-per-bit verify
     └─ Combined:  RD+FWV · RD+WV · RD+FW · RD+W

CONFIG  (hold EXIT at boot)
├─ Code loading · Precomp · Set maximal cylinder
├─ Write protect · Copy direction (in↔out) · Data-error recovery
├─ Serialization ─▶ Initial Nr · Increment · Cyl · Head · Sector · Offset
├─ Batch processing
├─ Form factor 3.5″/5.25″ · Density DD/HD · Spindle speed N/H/Double
└─ Simultaneous / Normal mode

HRD DIAGNOSTICS
├─ Radial alignment · Eccentricity · Head azimuth
├─ Positioner hysteresis  (µm, timed via 8253 c1/c2)
└─ Spindle motor speed    (RPM, per head)

SPECIAL FORMATS  1–16   ·   REMOTE CONTROL  (host link)
```

- **Serialization** stamps an auto-incrementing serial number onto each copy at a configurable
  cylinder/head/sector/offset, optionally re-verified bit-for-bit.
- **HRD diagnostics** measure drive mechanics using the 8253 counters as interval timers.
- **Simultaneous mode** writes all fitted drives in one pass via the parallel DMA path.

## 9. Config & provenance

Configuration lives in the `0x31xx` RAM block and is persisted to a small **bit-banged serial
EEPROM** (helpers `0x2ACB`/`0x2B3E`), re-saved whenever the config wizard completes. The boot
checksum validates it; corruption forces "Run config again".

Three 14-byte version fields (7-char module name + date) are indexed by a **pointer table at
0x0040–0x0045** (`DW 0x0054, 0x4B8B, 0x52CF`):

| Tag | Offset | Date | Likely meaning |
|---|---|---|---|
| `M6T9I2F 961002` | 0x0054 | 1996-10-02 | Main firmware build (shown at power-on) |
| `STIBG11 950503` | 0x4B8B | 1995-05-03 | Downloadable-code / loader module |
| `R6R1A   940329` | 0x52CF | 1994-03-29 | Boot-loader module |

*(Correction: the third tag is `R6R1A` at 0x52CF, not "IR6R1A" at 0x52CE — the leading `I` a
`strings` artifact from the adjacent `iovec_annun` pointer's high byte `0x49`.)*

## 10. Open questions

One genuine unknown remains (the board photo + datasheets resolved the other two):

- **Port 0xC0's function** `[hardware]` — written `0xFF` **exactly once** at boot (`0x0012`, alongside the `0xB0` bank latch) and never read or re-written. **Narrowed:** the whole `0x40–0x70` / `0xC0–0xC7` range is **write-only** (verified — *zero* `IN` reads; all inputs come from `0xF0` and the bulk channel), so `0xC0` is a **write-only output latch** in the drive/FDC-control group (with `0xC2` precomp, `0xC3` rate, `0xC6` drive-sel-b) — *not* a configured-PPI input port (which rules out the "`0xFF` = all-input mode-word" reading). Its chip-select is generated by the board's decode logic — **GAL20V8B (U5) / PALCE20V8H (U68) / MC74HCT138 (U56/U59/U60)** (per the board designator map in `PCB_CONNECTORS.md`; note U57 is the EPROM, not a decoder). `0xFF` is an all-ones idle/deselect init. What's *not* determinable from the ROM or the single top-side board photo is the exact latch it drives — that needs the schematic, a back-side/inner-layer view, or continuity probing (find the decode output that asserts on `/IOWR` with `A7..0 = 0xC0`). (§5)

**Resolved during analysis** (were open in earlier revisions):

- **Serial controller = Zilog Z80 SIO/0** (Z0844006PSC), *not* an 8251 — confirmed by the board photo, the **Zilog Z8440/Z84C40 SIO datasheet** (`datasheets/Zilog Z0844006PSC SIO.pdf`, in the repo — the `Z0844x06` = 6 MHz Z80 SIO, SIO/0 bonding), **and** the firmware's SIO register model: Tx via RR0 bit 2, Rx via RR0 bit 0, data port = control port with A2 cleared (`RES/SET 2,C`), errors read from RR1 (WR0-pointer=1, mask `0x70`), and `WR0=0x30` error-reset. One SIO carries both channels (A = autoloader `0xD0/D4`, B = host `0xD8/DC`); the 8253 supplies the external clock in ×16 mode (153,846 Hz ÷ 16 ≈ 9600 baud). (§2, §5)
- **Parallel I/O = a single µPD71055 PPI** (no Z8420 PIO — an earlier mis-assumption from a spurious datasheet, since removed). The `0x40–0x70`/`B0`/`C6` write-only latches are PPI ports and/or discrete 74HCT373s; the firmware's write-only usage doesn't reveal the exact split, but the parallel-interface chip is the PPI. (§2)
- **0x9C is an 8-line addressable latch** (decode `data = bit0, select = bits [3:1]`) — line 1 EPROM/RAM map, line 2 write-protect, lines 4/5 per-drive datarate, line 6 static drive/write enable, line 7 FDC result-read strobe (§3). *Residual (still needs the board):* the physical A0–A2 ordering and which board signal each line drives.
- **0xB0** is a flat 8-bit DRAM bank latch — no drive-select field; drive UNIT/HEAD select is in the FDC `HD/US` command byte. (§5; internals §B)
- **0xE8 / 0x55** is an LCD presence/health self-test with a headless fallback, not a board-ID strap.
- **Host opcode table** fully mapped: control opcodes 0x09–0x0F plus a duplication-run fall-through (0x07 = BP, 0x01–0x06/0x08 = FDD). (internals §D)
- **`fmt_param_tbl` (0x326E)** declares 8 standard DOS formats but is dead/unreferenced — verified that no code (including the download loader) reads it. (internals §B)

---

## Files in this analysis

- `LSK M6T912F firmware analysis.html` — styled reference document (same content, richer layout).
- `LSK M6T912F firmware analysis.md` — this file.
- `disassembly/z80dis.py` — purpose-written Z80 disassembler (full CB/ED/DD/FD coverage). Handles
  the `CALL 0x4C59` inline-string print convention (renders the string as `DB` and realigns code
  after the `0x00`), emits readable **labels** for known functions/variables, rewrites operand
  addresses to those labels, and annotates I/O ports. Usage: `python3 z80dis.py "<bin>" <start> <end>`
- `disassembly/sourcecode.s` — full **0x0000–0x52FF** listing, labeled (**1,218 labels** — 539 named + 679 auto `loc_`; ~3,240 operand references resolved to labels or `label+offset`).
- `disassembly/symbols.txt` — the symbol map (address → label + I/O ports) used to annotate the listing.

*Subsystem deep-dives are documented in the companion `LSK M6T912F firmware internals.md` / `.html`.*

**Method.** Disassembled with the included Z80 disassembler, cross-referenced against the on-board
datasheets, and verified by reading the actual hardware primitives — not pattern-matched.
Analysis dated 2026-07-22.
