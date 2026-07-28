# LSK M6T912F Floppy Duplicator — Firmware Analysis & Internals

Reverse-engineering reference for the LSK Data Systems **M6T912F** four-drive gang floppy
duplicator (Z80, 1996). Source image: `LSK M6T912F D1_97.bin` — 32768 bytes, disassembles as
Z80 at **ORG 0x0000**. This single document combines the system-level analysis with byte-level
subsystem internals (the FDC/DMA engine, the duplication engine, the serial protocols, and the
HRD diagnostics).

> **Confidence tags** — `[V] Verified` read from the code directly · `[R] Reported` traced,
> consistent · `[?] Uncertain` flagged for a hardware check. All addresses are ROM offsets;
> code excerpts are verbatim.

---

## 1. Overview

The device reads one master floppy into a bank of DRAM, then writes and verifies up to four
blank floppies at once. It runs standalone from a front-panel menu, drives an optional mechanical
**autoloader** over RS-232, and can be driven by a host PC in a **remote-control** mode that
streams a disk image down a dedicated data channel.

Both serial links have their own dedicated references: the
[autoloader](LSK%20M6T912F%20autoloader.md) (a separate PIC16C57/ST93C06 device — the machine is its
*client*) and the [host remote-control protocol](LSK%20M6T912F%20host%20protocol.md) (the machine is
the *server*). See §8 for the firmware-side treatment.

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
| Parallel I/O | U69 | NEC µPD71055 PPI | 90/94/98/9C | PA host bulk data · PB status_in · PC control (0x9C latch: keypad, write-protect, bulk-dir, datarate, enable, FDC strobe) | [V] | `datasheets/NEC µPD71055 Parallel Interface Unit.pdf` |
| Display | K51 | HD44780 LCD (2×20) — module via connector K51 | E0/E8 | Front-panel character display | [V] | `datasheets/Hiatchi HD44780 LCD.pdf` |
| Image DRAM | U77/U78 | 2× 4 MB 30-pin SIMM (AS4C14400 1M×4) = 8 MB | bank @ B0 | Banked disk-image buffer — image banks `0x00–0xFE`; **bank `0xFF` = program-RAM mirror** (see §3) | [V] | `datasheets/AS4C14400 1M×4 RAM.PDF` |
| Line driver | U101 | Microchip TC232 | — | RS-232 level shifting | [R] | `datasheets/Microchip TC232CPE RS232.PDF` |
| Config EEPROM | U86 | Catalyst CAT24C02 (I²C, 256×8) | F0 (bit-banged I²C) | Non-volatile settings + serial number (write-protect, copy dir, serialization, err-recovery, max-cyl) | [V] | `datasheets/CAT24C02.pdf` |
| Decode / DRAM | U5, U68 | Lattice GAL20V8B + PALCE20V8H | — | GAL20V8B (U5) = I/O chip-select decode; PALCE20V8H (U68) = DRAM controller (RAS/CAS/mux, at the SIMMs) **and** low-memory arbiter — drives EPROM `/CE` and holds the ROM→RAM shadow (probed) | [R] | `datasheets/GAL20V8B 15LP.pdf` · `datasheets/PALCE20V8.PDF` |

The parallel I/O is a **single µPD71055 PPI**; the `0x40–0x70` drive-select/motor lines are separate
discrete 74HCT373 latches.

The device is the **Terra Computer Systems KDP-05 B** (Czech Republic, © 1993) — that model number is
from the board's sticker; the bare PCB is silkscreened **KOP05B** (see `PCB_INFO.md`). The "LSK
M6T912F" is the LSK-branded build. Clocking: **32.000 MHz** and **48.000 MHz** crystals; the 8253's 2 MHz
input is 32 MHz ÷ 16. I/O address decode is handled by the GAL20V8B (U5); the PALCE20V8H (U68), sited at
the SIMM slots, is the **DRAM controller** (RAS/CAS/mux timing) and doubles as the **low-memory
arbiter** — it drives the EPROM's `/CE` (U57 pin 20) and holds the ROM→RAM shadow state (probed §3).
All larger parts are confirmed against on-board markings and manufacturer datasheets.

## 3. Memory architecture

```
0x0000 ────────────────────────── 0x8000 ────────────────────────── 0xFFFF
| Program RAM = DRAM bank 0xFF,           | Banked DRAM window —         |
| loaded with the EPROM mirror at boot    | disk image buffer, banks     |
| then mapped low by the U68 shadow       | 0x00–0xFE (bank@0xB0)         |
```

The two windows are the **same 0xB0-banked DRAM array**. At boot the bank latch is set to **`0xFF`**
and the EPROM is `LDIR`-copied into that bank's window (`0x8022`); the **U68 low-memory arbiter** then
flips its ROM→RAM shadow (on the first upper-memory fetch — `JP 0x8022`), replacing the EPROM at
`0x0000–0x7FFF` with bank `0xFF` so the running code is unaffected when `0xB0` later cycles image banks
`0x00–0xFE` in the upper window. The array is **2× 4 MB SIMMs = 8 MB** (256 × 32 KB banks; parity is
generated, not checked); with bank `0xFF` reserved for program RAM the image buffer is banks
`0x00–0xFE` (≈ 7.97 MB — several full disk images), and boot sizes the installed DRAM via the
`Test dram: N kB` routine (`0x03DD`). See "Bank 0xFF is the program mirror" below.

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
| `0x52FE/0x52FF` | `0x2198` (LE) | Unknown 16-bit word at the last word of used content, **not referenced by any instruction** — an unknown checksum or marker. |

### Bank 0xFF is the program mirror

The "static RAM" at 0x0000–0x7FFF is not a separate chip — it is **DRAM bank `0xFF`**, loaded with a
copy of the EPROM at boot and then mapped low. Traced byte-for-byte at reset:

| Addr | Code | Effect |
|---|---|---|
| `0x000E` | `LD A,0xFF; OUT (0xB0),A` | select **bank 0xFF** in the 0x8000 window |
| `0x0014` | `LD BC,0x5FFF; LD HL,0x0022; LD DE,0x8022; LDIR` | copy EPROM `0x0022–0x6021` into bank 0xFF (`0x8022+`) |
| `0x001F` | `JP 0x8022` | run the fresh copy in bank 0xFF's window — this first `A15=1` fetch flips the U68 ROM→RAM shadow (bank 0xFF now at `0x0000–0x7FFF`, EPROM out) |
| `0x0022` | `LD A,0x92; OUT (0x9C),A` | 8255 mode-set of PPI U69 (PA/PB in, PC out) — **not** the map |
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

**The mapping is set-once and permanent.** `OUT (0xB0),0xFF` executes exactly once (`0x0010`); every
later `0xB0` write loads an *image* bank (`track_bank_a/b`, or `0xFE` scratch), never 0xFF, so the
bank-0xFF selection is never re-commanded and the ROM→RAM shadow (a U68 function, below) latches once
and holds. Port `0x9C` is an **addressable per-line latch**, not a plain register: `fdc_poll_complete`
pulses it (`0x0E`→6 NOPs→`0x0F`, `0x475E`) while the PC runs straight through from low RAM — a plain
register write of `0x0E` would corrupt the boot `0x92`, so each write must address one line only. That
latch is the **µPD71055 PPI (U69) control register** (§ below); the low-memory map is a separate
**U68 PAL** function, not a `0x9C` bit.

#### The 0x0000–0x7FFF map is a U68 (PAL) function [probed]

The ROM→RAM swap is a function of the DRAM-controller PAL **U68**, shown by board continuity probing:

- `U57 /OE` (pin 22) = **GND** — the EPROM's output is always enabled.
- `U57 /CE` (pin 20) → **U68 pin 20** — the PAL gates the EPROM's chip-select.
- U68's inputs are memory-side only — **/MREQ** (pin 3), **A15** (pin 9), **/RFSH** (pin 2) — with no
  I/O-decode input, so U68 cannot observe the `0x9C` write at all.

U68 is thus the low-memory arbiter: for `A15 = 0` it either asserts EPROM `/CE` or lets DRAM bank 0xFF
answer, holding the ROM→RAM shadow in a registered macrocell. The shadow flips **once**, memory-side;
the trigger is the **first `A15 = 1` fetch** — the `JP 0x8022` at `0x001F` that enters the bank-0xFF
copy (the classic "boot from ROM, run from the shadow copy" design). `OUT (0x9C),0x92` at `0x0022` is
the PPI mode-set (below), unrelated to the map.

#### 0x9C is the µPD71055 PPI (U69) control register [probed]

Port `0x9C` is the control register of the **µPD71055 PPI (U69)**, driven with 8255 **Bit-Set/Reset**
commands: each BSR write sets or clears exactly one **Port C** bit and leaves the rest intact — which
is why the `0x0E`→`0x0F` FDC strobe never disturbs the datarate/enable lines. Probing confirms U69:
register-select `A1/A0` = Z80 `A3/A2` (so control = `0x9C`; Port A/B/C = `0x90`/`0x94`/`0x98`),
chip-select off the `0x90` I/O decode, `/WR` gated through the U72 NOR cluster.

The BSR control byte is `0 x x x [C-bit 2:0] [value]` — exactly the firmware's **data = bit 0,
select = bits [3:1]**. `0x92` (bit 7 = 1) is not BSR but an 8255 **mode-set**: PA/PB = input,
PC = output, and as a side effect the entire Port C output latch resets to 0.

**Port C — all 8 lines** (✅ = confirmed by board probe; the rest firm from firmware):

| C-bit | U69 pin | line / function | evidence |
|---|---|---|---|
| PC0 | 14 | keypad column (K52) ✅ | R-M-W scan on `0x98` |
| PC1 | 15 | keypad column (K52) ✅ | R-M-W scan on `0x98` |
| PC2 | 16 | **write-protect** (WP-recognition) | `0x04`/`0x05`; host op `0x0D` @ `0x200B` |
| PC3 | 17 | **bulk-image transfer direction** → U74 DIR ✅ | bulk channel `0x216A` |
| PC4 | 13 | **datarate select, drive A** | `0x08`/`0x09`, `update_ctrl_latch` |
| PC5 | 12 | **datarate select, drive B** | `0x0A`/`0x0B` |
| PC6 | 11 | drive/write bus enable (held 1) | `0x2D` @ `0x03C2`, never cleared |
| PC7 | 10 | **FDC result-read strobe** | `0x0E`→`0x0F` rising edge |

Function derivations (firm unless noted):

- **PC3 = bulk-image transfer direction.** The host bulk channel (`0x90`/`0x94`/`0x9C`, `0x216A`) moves
  bytes through PPI Port A, buffered to the host link by **U74 (74ALS245)**: `/OE` (pin 19) = GND,
  **DIR (pin 1) = PC3** (both probed). Toggling PC3 turns the transceiver around between receive and
  send — the repeated `OUT (0x9C)` writes in the bulk loop (`0x21D0`, `0x2192`, `0x2241`) are these
  direction flips.
- **PC2 = write-protect.** The `0x24DD` handler is the front-panel **"Write protect"** config screen
  (`get_key` → `0x04`/`0x05` → store `wprot_mode` → `config_wprotect`); the `"Write protect"` string
  sits at `0x24EF`. `bit0` carries the protect flag. It's also driven remotely: host op `0x0D`
  (`0x200B`) writes a host-supplied byte to `0x9C` and caches it in `wprot_mode`.
- **PC4 & PC5 = per-drive datarate select.** `update_ctrl_latch` (`0x0760`) is called with
  `A = fdc_rate_a`/`fdc_rate_b` (a cylinder-banded rate from `range_table_lookup`) and `E = 0x08`
  (→ PC4, drive A) / `E = 0x0A` (→ PC5, drive B); it `OR 0x01`s `bit0` when the rate class is 1,
  and in parallel sets `bit2` of the drive latch (`0x50`/`0x70`, `drv_lat1/3`). The banded rate is read
  from the **Special-format zone tables** (`fmt_geom_recs`): `range_table_lookup` (`0x092A`, `B=6`)
  scans a head's 6 `{start-cyl, rate}` zones for the current cylinder and returns the `N/L/H` flag —
  so N/L/H is confirmed to be **per-cylinder data rate** (variable-rate zoned formatting).
- **PC6 = a static enable, *not* precompensation.** Its data bit is `bit0` of `drv_active_cfg` — a
  **hardcoded constant `0x2D`** (written once at `0x01B7`, never config-changed). Every consumer uses
  only that bit (all do `AND 0x01`, some even force `SET 0,A`), and it is always `1`. The same bit is
  fanned into the drive-control latches (`0x40`/`0x60`, the *active* pattern `0x2D` vs *idle* `0x0E`)
  and written once to PC6 at boot (`0x03C2`, via `dram_bank_cfg`) — never cleared. So PC6 is a
  **permanently-asserted global enable**. The real write-precompensation is a *separate* path:
  `fdc_datarate_precomp` (`0x1141`) computes it per-geometry and outputs to **FDC port `0xC2`
  (`fdc_precomp`)**. PC6's exact physical signal (write-gate / reduced-write-current / drive-enable)
  isn't determinable from firmware, but its behavior — set-once, held high — is.

Board probing confirms the chip (**U69**), the register decode, and the destinations of PC0/PC1
(→ K52 keypad) and PC3 (→ U74). PC2 and PC4–PC7 are firm from firmware; their FDC/drive-side pins are
not yet board-traced.

## 4. Boot sequence

| # | Addr | Action |
|---|---|---|
| 1 | 0000 | Init 8237 DMA (`OUT 0x88,0xA0`; `0x8D,0x8F=0x0F`), `SP=0x8000`, **select DRAM bank 0xFF (program-RAM window)** via `OUT 0xB0,0xFF`; then `OUT 0xC0,0xFF` (the DRAM bank **high byte** — see port map, §5) |
| 2 | 001D | `LDIR` copies EPROM 0x0022–0x6021 → **bank 0xFF** at 0x8022, then `JP 0x8022` (runs the copy in bank 0xFF's window) |
| 3 | 001F | `JP 0x8022` (first upper-memory fetch) flips U68's ROM→RAM shadow → bank 0xFF at 0x0000–0x7FFF, EPROM out |
| 3b | 0022 | `OUT 0x9C,0x92` = 8255 mode-set of PPI U69 (not the map) → `JP 0x0100` |
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
| 40/50/60/70 C6 | 74HCT373 drive latches | drive select · motor · side | reset `OUT 0x40/0x60,0x0E`; DOR builder `0x3CD3` | [?] |
| 80–8F | µPD8237A DMA | ch0–3 addr/count (80–87), cmd/status 88, mode 8B, mask 8A/8E/8F, clear-ff 8C, mclr 8D | arm `dma_arm_channel` 0x4401 (bit7 of selector → ch0/1 @0x441B or ch2/3 @0x4408); reset `OUT 0x88,0xA0` | [V] |
| 90/94/98/9C | **PPI U69** (µPD71055) | PA=host bulk data (0x90) · PB=status_in (0x94) · PC=control (0x98 data / 0x9C ctrl-reg BSR) | Port C lines: PC0/1 keypad columns, PC2 write-protect, PC3 bulk-dir (→U74), PC4/5 datarate A/B, PC6 drive enable, PC7 FDC strobe | [V] |
| 90/94 | bulk channel (PPI PA/PB) | image data-in / ready (bit6) | download `0x216A`, `0xAA55` frame sync; PA buffered via U74 | [R] |
| 94/98 | keypad (PPI PB/PC) | 4 keys via 2×2 matrix | columns on `0x98` (PC0/1), rows on `0x94`; scan `0x4D0B`, decode `0x4590` | [V] |
| A0/A4/A8 | 8253 PIT | counter 0 / 1 / 2 | ctrl words `16/50/90` select each counter | [V] |
| AC | 8253 PIT | control register | c0 mode-3 baud (÷13); c1/c2 mode-2 RPM/hysteresis timing | [V] |
| B0 | DRAM bank latch | image-buffer 32 KB bank select | DRAM sizing `OUT (0xB0),A` @0x03EE; per-track bank before every 0x8000 access (`0x0E49/0x1D55/0x1CEC`) | [V] |
| B1/C2/C3 | FDC glue | data-rate / precomp select | precomp init `0x0980` (250/500 kbps) | [R] |
| C0 | **DRAM bank latch — high byte** (U66) | upper half of the `{0xC0,0xB0}` DRAM bank address; boot sets `0xFF` alongside the B0 write | continuity-probed: U66 data-fed via U58, outputs → `157` mux row inputs, strobed by U60 (`74138`) Y4 = `0xC0` decode | [V] |
| D0/D4 | Z80 SIO ch A | data (D0) / control+status (D4) — autoloader | Tx `BIT 2` (RR0 Tx-empty), Rx `BIT 0` (RR0 Rx-avail), data port = control `& ~4` (`RES/SET 2,C`, `0x4E42`); errors via WR0-ptr→RR1 `AND 0x70`; `WR0=0x30` error-reset | [V] |
| D8/DC | Z80 SIO ch B | data (D8) / control+status (DC) — host | same SIO cores, C=0xD8/0xDC | [V] |
| E0 | HD44780 LCD | instruction reg (RS=0), bit7=busy | `lcd_init` `0x4B99`, printer `0x4C59`, busy-wait `0x4C2A` | [V] |
| E8 | HD44780 LCD | data reg (RS=1); presence self-test (write `0x55`, read back) | `lcd_byte_out` `0x4C43` with C=0xE8; probe `0x4BCC`, readback `0x4BDD` → headless on mismatch | [V] |
| F0 | panel latch + I2C EEPROM | beeper · serial NVRAM (U86) | beeper on `0xF0`; EEPROM bit-bang `0x2ACB` | [R] |

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

### FDC command engine

Command/result phases run as polled PIO (`0x457F` write, `0x46F1` read); bulk data goes through the
8237 DMA. Commands are issued via an `LD SP,IX / POP` rapid-load of a RAM state block.

**RAM state**

| Address | Contents |
|---|---|
| 0x4A85 / 8C / 93 / 9A | 7-byte result phase per FDC (ST0,ST1,ST2,C,H,R,N) |
| 0x4A61 / 6A / 73 / 7C | command buffer; byte0 = last opcode (seek/recal marker for the ISR) |
| 0x4AA1 | per-FDC "result captured" bits |
| 0x4AEB / 0x4B06 | drive-pair blocks: +7 DOR/motor, +8/9 DMA start addr, +10/11 DMA count |
| 0x52DD | `format_desc`: +1/+5 sectors/track, +2 N, +11 density/side/flags (full field map below) |

**READ/WRITE build** `0x3BFB` — opcode base in `0x4AEA` (0x26→0x66 READ / 0x05→0x45 WRITE after
`|0x40` MFM); 9 bytes `{CMD,HD/US,C,H,R,N,EOT,GPL,DTL}` streamed by `0x457F`; DMA armed in parallel
(below).

**DMA — µPD8237A @ base 0x80** `[V]` (register map confirmed against the µPD8237A datasheet). Standard
register layout, **one channel per FDC**:

| Port | Reg | | Port | Reg |
|---|---|---|---|---|
| 80/81 | ch0 addr / count | | 88 | command (W) · status (R) |
| 82/83 | ch1 addr / count | | 89 | software request |
| 84/85 | ch2 addr / count | | 8A | mask one channel |
| 86/87 | ch3 addr / count | | 8B | mode |
| 8C | clear byte-ptr flip-flop | | 8D | master clear (W) · temp (R) |
| 8E | clear all masks | | 8F | write all four mask bits |

Boot init `@0x0000`: master clear (`OUT 8D`), mask all (`OUT 8F,0x0F`), command `0xA0` (controller
enabled, fixed priority, DACK active-high, extended write). Per-transfer arm is **`dma_arm_channel`
`0x4401`** (via wrapper `0x43EC`, which SP-swaps `drive_blk+8..11` into the DMA address/count): `BIT 7`
of the channel selector picks the **ch0/ch1** branch (`0x441B`: `A==0x01`→ch0 `C=0x80`, else ch1
`C=0x82`) or the **ch2/ch3** branch (`0x4408`: `A==0x81`→ch2 `C=0x84`, else ch3 `C=0x86`). Each branch
writes the channel-index | transfer-type byte to the single-mask (`8A`) and **mode** (`8B`) registers —
mode `0x08|ch` = read-transfer (memory→FDC = disk **write**), `0x04|ch` = write-transfer (FDC→memory =
disk **read**) — writes the two-byte address then count through the port in `C`, then rewrites `8A` to
its final enable state. The `8C` clear-flip-flop is pulsed **only in the ch0/ch1 branch** (before its
16-bit writes); the ch2/ch3 branch omits it and relies on the flip-flop staying balanced — boot
master-clears it (`8D`) and each arm does exactly four byte-writes. The channel address is 16-bit only
(`A0–A15`); the DRAM image bank above that is paged separately by port `0xB0`, and DMA only ever
targets image banks `0x00–0xFE` (bank `0xFF` is the program-RAM mirror — see §3). This is why the
per-bank checksum loop at `0x5193` (`INC A; CP 0xFF; RET Z`) walks `0x00–0xFE` and stops at 0xFF.

**Seek family** — RECALIBRATE 0x07 (`0x39A0`), SEEK 0x0F (`0x42DD`, target cyl in C→NCN). After a
seek/recal interrupt the ISR path `0x462D` **auto-issues SENSE INTERRUPT STATUS 0x08**. Data-rate/
precomp via the FDC register interface 0xB1/0xC2/0xC3 (250 DD / 500 HD kbps). `[?]` the step-timing/
SPECIFY param block `0x3CD3` has a runtime-computed opcode, not a literal 0x03.

**FORMAT 0x4D** — descriptor `0x52DD`; the interleave/sector-map builder `0x5043`/`0x507E` emits a
per-sector C/H/R/N field list into the 0x8000 buffer for the execution phase.

**Error decode — priority encoder `0x4893`** over ST0/ST1/ST2:

| Status bit | Meaning | Message |
|---|---|---|
| ST1.5 / ST1.2 / ST1.0 / ST2.5 | CRC · no-data · missing AM · data CRC | "unreadable" |
| ST1.4 | overrun | "Lost data" |
| ST1.1 | not writable (write-protect) | "FDD write fault" |
| ST2.4 / ST2.1 | wrong / bad cylinder | "FDD seek error" |
| ST0.4 | equipment check | "FDD seek error" |
| ST3 (SENSE DRIVE 0x04) | WP / ready / track0 | "FDD not ready" |

### Built-in formats

The engine works from these geometries (all 512 B/sector), plus 16 user "Special formats" and the
named alignment models 528-400 / 526-400 / 325-400 (see §9 HRD). The 2.88 MB (ED) capability of the
FDC37C65C is present in silicon but no ED format ships in this table.

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

> **`fmt_param_tbl` (0x326E) is dead code.** These eight geometries are also declared as 19-byte DOS
> BPB records at `fmt_param_tbl` (0x326E), but that table is **never read by any code in this image**
> `[V]` — no base-address load of 0x326E exists anywhere in the 32 KB ROM (an exhaustive pointer search
> returns only two false-positive hits, both bytes inside other instructions), and the download/code-load
> loader (`code_loader` `0x21A9` → `dl_code` `0x21CE`) never touches it either. The geometry the engine
> actually uses lives in `format_desc` (below), assembled from the config-menu selection via
> `media_cfg_index` `0x520A`; the FAT12 boot sector is built from `fat12_template` `0x3305`, not from
> this table. Most likely a leftover from an earlier build (or read only by an externally-downloaded
> program, outside this ROM).

### The active-format / copy descriptor — `format_desc` (0x52DD)

`format_desc` is the 18-byte working record (`0x52DD–0x52EE`) that the FDC engine and the
duplication engine both read from. It is **two overlaid halves**: a *geometry* descriptor
(bytes 0–11) and a block of *copy-engine scratch* (bytes 12–17). It is not a fixed on-disk
structure — it is assembled at run time from the config-menu selection.

The geometry half is rebuilt by **`init_format_geom` (0x5101)**: it `LDIR`-copies **5 nominal
parameters** from the selected drive block (`drive_blk_a+0x11`) into `+0..+4`, then **computes**
`+5..+10` (dividing the 32 KB image-bank size by the per-sector product to fill the bank). So the
record deliberately holds both the *nominal* values (`+1`, `+3/4`) and their *computed* counterparts
(`+5`, `+7/8`) — that redundancy is by design, not a bug.

| Off | Sz | Field | Source | Evidence |
|---|---|---|---|---|
| +0 | 1 | nominal cylinder/track count | copied | `0x085B`, `0x0DC4` |
| +1 | 1 | nominal sectors-per-track | copied | `0x5089`, `0x50B2`, `0x50D3` |
| +2 | 1 | sector-size code **N** | copied | `0x50F2` + init math |
| +3 | 2 | per-track byte size (added to image ptr per track) | copied | `0x1C5E`, `0x2BAF` |
| +5 | 1 | **computed** sectors-per-track | `init` `0x512A` | `0x5057`, `0x50C1` |
| +6 | 1 | **computed** N × 4 (sector-size / gap value) | `init` `0x514E` | `0x5066` |
| +7 | 2 | **computed** track byte-count (= total, mirrored to +9) | `init` `0x5141` | `0x504E` |
| +9 | 2 | **computed** total length (tracks × N) | `init` `0x513B` | `0x506D` |
| +11 | 1 | **format-flags / model-ID byte** (bit map below) | menu | see below |
| +12 | 1 | source image-bank byte (drive A); also *start-bank − 1* | copy engine | `0x3F75`, `0x51D9` |
| +13 | 2 | source track/buffer pointer | copy engine | `0x3F72`, `0x40D5` |
| +15 | 1 | destination image-bank byte (drive B) | copy engine | `0x3F67`, `0x40CC` |
| +16 | 2 | destination track/buffer pointer | copy engine | `0x3F64`, `0x40C9` |

**Byte +11 — format flags / model-ID** (`0x52E8`). Set from the menu selection; the copy engine
also reads/writes it as the reported model-ID byte (`0x1943`, `0x199A`, `0x1FE2`):

| Bit | Meaning | Consumed by |
|---|---|---|
| 7 | HD (1) / DD (0) density | `RES/SET 7` at `0x1831`/`0x1849`; → media-cfg index bit 0 (`0x521F`) |
| 6 | media-config index bit 1 | `media_cfg_index` `0x5217` |
| 5 | FDC unit-select option → sel bit 6 | `fdc_build_unit_sel` `0x51FA` |
| 4 | double-sided (2 heads) | seek 2nd head `0x0739`; sel bit 5 `0x51F2`; datarate latch `0x5153` |
| 3 | media-config index bit 2 | `media_cfg_index` `0x520F` |
| 2 | FDC unit-select option → sel bit 7 | `fdc_build_unit_sel` `0x5202` |

The **copy scratch** (`+12..+17`) is populated per operation by the duplication engine
(`0x3F64`, `0x40C9`) and then latched into `drive_blk_a`/`drive_blk_b` at `+7` (bank) and `+0xC`
(pointer) — i.e. it carries the source-drive and destination-drive bank + image-buffer pointers for
one track-copy pass.

> **Not `format_desc`:** `geom_sector_calc` (`0x2BB7`, called only from `0x1D4D`) reads `IX+13/+15`,
> but there `IX` points at the **installed boot-sector BPB record** (copied in at `0x1D38`), *not* at
> `format_desc`. Those two offsets are BPB sectors-per-track / interleave, unrelated to the copy-scratch
> bytes at `format_desc+13/+15`.

### The formatted boot sector — `fat12_template` (0x3305)

Formatting (as opposed to copying a master) builds a real, **PC-bootable FAT12 boot sector** from a
73-byte ROM template. The template supplies the fixed shell; the **BPB geometry fields** (bytes/sector,
sector counts, media byte, FAT layout, sectors/track, heads) are patched in from the selected format's
19-byte BPB record, copied to `image_buf+0xB` at `0x1D36`. The `0x55AA` signature is stamped separately
at `0x81FE`.

| Field | Value |
|---|---|
| Jump | `EB 4E 90` (`JMP 0x4E; NOP`) |
| **OEM name** | `"Jumbo   "` |
| BPB (offset 0x0B…) | *filled per-format from the BPB record* |
| FS type | `"FAT12   "` |
| Boot code | prints **"Non system disk"**, then reboots (below) |
| Signature @ 0x1FE | `55 AA` (stamped at `0x81FE`) |

The boot code is the textbook "non-system disk" stub — `E8 10 00` calls past the inline message string,
then:
```
5B         POP BX          ; BX -> "Non system disk" message
B4 0E      MOV AH,0x0E     ; INT 10h teletype
2E 8A 07   MOV AL,CS:[BX]  ; next char
3C 00      CMP AL,0        ; end of string?
74 05      JZ  +5
CD 10      INT 10h         ; print it
43         INC BX
EB F2      JMP loop
30 E4      XOR AH,AH       ; INT 16h read-key
CD 16      INT 16h         ; wait for a keypress
EA 00 00 FF FF  JMP FFFF:0000  ; reboot
```
So a blank formatted on this machine actually **boots on a PC and prints "Non system disk"** — the OEM
string in the produced media is `Jumbo`.

## 7. Duplication engine

The copy orchestration is a cooperative **phase machine**. State: operation word `0x3134` + a
current-phase handler pointer `0x3131` (loaded from the media-indexed table `0x1444`).

**0x3134 operation word**

| Bits | Field | Meaning |
|---|---|---|
| 7 | ADV/STOP | phase-advance; distinguishes "stopped" vs "unreadable" |
| 6 | ERR_A | write/verify error, drive-group A |
| 5 | ERR_B | write/verify error, drive-group B |
| 4 | SIDE/RETRY | side / retry qualifier |
| 3–0 | PHASE | 0 idle · 1 FWV · 2 WV · 3 Format · 4 Format+V · 6 Write · 7 RD+meta · 8 Verify · 9 CRC · A wait-for-data |
| 7–5 | ERR? | aggregate `AND 0xE0` → gates image-valid flag 0x52C8 |

The RD+ family is meta-phase 7 + sub-mode `0x314F` (1=FWV, 2=WV, 5=FW, 6=W); launcher `0x25E6`.

**Phases**
- **Read source** `0x11B4` — master read *once* into DRAM (bank via `OUT (0xB0)`), autoloader-aware; 32-bit position `0x3269/0x326B`; image checksum `0x51A9` (sum 0x8000–0xFFFF, complement at 0xFFFF).
- **Format** `0x1CE2` — FAT12 boot sector from ROM template `0x3305`, `0x55AA` at 0x81FE (see §6).
- **Write** `0x08DE` — parallel DMA; each target FDC has its own block (`0x4AEB`/`0x4B06`) + 8237 channel.
- **Verify/compare** `0x0E46` — DMA read-back into scratch `0x5800`, `CPI` vs image bank; mismatch sets ERR_A/ERR_B.

```
0E46  LD A,(0x3156)     ; per-track image bank #
0E49  OUT (0xB0),A      ; page bank into 0x8000
0E4B  LD HL,(0x3158) ; OR 0x80 -> 0x8000+offset
0E53  LD DE,0x5800      ; DMA read-back scratch
0E58  CPI               ; compare; JR NZ -> "Compare error", SET 6/5
```

**Batch/autoloader** — the loop tail `0x1090` decrements the run count `0x313D`; accept/reject
sequencer `0x10D2`. Each target owns its channel + block, so a failed target sets its group bit and is
rejected while others continue. `[?]` no separate per-target "alive" mask beyond the two group bits.

### Serialization — disk auto-numbering

When enabled (`cfg_byte`/`hrd_desc_tbl` bit 1), the machine stamps a **unique, auto-incrementing
serial number** into every copy at a user-configured location — the classic commercial-duplicator
licensing/tracking feature. The number is a **32-bit** value written as **4 bytes** into one sector.

The **config editor** (`config_serialization` `0x2369` enables it; the field editor at `0x1B6A–0x1C98`
is reached from the run setup) prompts for six fields in order, each validated against the current
`format_desc` geometry:

| Screen | Stores to | Meaning |
|---|---|---|
| "Initial serial Nr." | `serial_num_lo`/`serial_num_hi` (`0x3168`/`0x316A`) | starting number (8 decimal digits → 32-bit) |
| "Increment" | `serial_incr` (`0x316C`) | amount added to the number per copy |
| "Cylinder" | `serial_cyl` (`0x316D`) | target cylinder |
| "Head" | `serial_head` (`0x316E`) | target head |
| "Sector" | `serial_sector` (`0x316F`) | target sector |
| "Offset" | `serial_offset` (`0x3170`) | byte offset within the sector |

After the last field, `track_buf_ptr` (`0x2BA5`) turns cyl/head/sector into a DRAM image **bank**
(`serial_bank` `0x3172`) + **write address** (`serial_addr` `0x3173`), and `track_ptr_scale` yields a
**scaled byte pointer** (`serial_ptr` `0x3175`).

**Stamp** (`0x08A4`, on write-type ops 2/4/6 only): `OUT (0xB0)` selects `serial_bank`, then a 4-byte
`LDIR` copies `serial_num_lo`/`_hi` into the image at `serial_addr`, and **`set_bank_checksum`
(`0x519C`) recomputes that bank's checksum** so the later verify pass still matches the now-patched
image. During verify (`0x0E11`, `0x0EE2`) the same 4 bytes are mirrored into the read-back scratch on
the matching cylinder/head so the serial region isn't falsely flagged as a mismatch. After each copy the
number advances (`0x105F`: `serial_num += serial_incr`, carry propagated across the 32-bit value).
The `serial_*` labels for the block `0x3168–0x3175` are fixed by the config editor's on-screen prompts.

## 8. Serial & protocols

Two independent Z80 SIO channels at 9600 baud (×16 clock from the 8253), fully polled (no interrupt
ring buffers). Each channel is set up at boot by `OTIR`-ing a 13-byte WR-register blob to its control
port (`al_ser_blob`→0xD4, `host_ser_blob2`→0xDC): channel-reset, WR3/WR4/WR5/WR1, then enable Rx+Tx
with RTS/DTR. Framing is 8 data bits, 1 stop; the **autoloader channel is 8N1**, and the **host
channel switches parity per operation** (boots 8O1; `host_ser_blob0/1` reprogram it 8N1/8O1).
Channel A = autoloader; channel B = host. A third channel (0x90/0x94/0x9C, `0xAA55`-framed) carries
bulk image data. Both links are polled: TX `0x4E42` (spin TxRDY=bit2), RX `0x4E5A` (RxRDY=bit0, timeout).

### Autoloader — machine is the client (disk-handling mechanism)

The main board does **not** drive the disk-insert/eject motors directly. The autoloader is a separate
mechanical unit with its own controller (banner "LSK Autoloader / Copyright LSK Data Systems 1995"),
and channel A (`0xD0/0xD4`) is the link that **commands its motors and reads its sensors** — insert,
accept, reject, calibrate, and a status byte encoding the mechanical state (hopper empty, disk-in-drive,
jams, bin full, eject timeout). The main board sends single ASCII commands and expects `X` (ok) /
`E` (error) / `?` (unknown).

The command+ACK primitive `0x13D9`: flush RX ×3 → reset cmd-reg → TX byte → RX reply → compare `'X'`
(A=0 ok / 1 timeout / 2 wrong). **Only S, C, I, A, R are ever transmitted** `[V]` (exhaustive scan);
the **O** and **V** commands are never issued by this ROM (the cycle count is an internal 32-bit
counter `0x3269/0x326B` bumped per successful INSERT). **S returns two ASCII hex chars** (e.g. `"0B"`),
decoded to a status byte at `0x13FB`. The connection probe `0x0220` pings with **R**: a pure timeout
(`0x314C=0`) → "NOT CONNECTED"; framing bits → "COMMUNICATION ERROR".

| Cmd | Meaning | Cmd | Meaning |
|---|---|---|---|
| S | status (2-byte reply) | R | reject |
| C | calibrate / clear | O | print version *(never sent)* |
| I | insert | V | cycle count *(never sent)* |
| A | accept | | |

**Status decode `0x1286` vs ground truth** (the firmware's message set is coarser than the
autoloader's real status codes):

| Status | Ground-truth meaning | Firmware message | |
|---|---|---|---|
| 0x07 / 0x0B | ok / disk-in-drive | "AL status ok" | match |
| 0x27 | hopper empty | "Hopper empty" | match |
| 0x47 / 0x4B | no-disk / disk fwd | generic "AL error Status .." | no dedicated msg |
| 0x87 / 0x8B | reject-bin jam | "Calibration error" | label differs |
| 0x97 / 0x9B | eject jam | "Eject timeout" | ≈ same fault |
| bit1=0 | hopper seat open | "Hopper not seated" | match |

### Host remote control — machine is the server

The two serial links have **opposite roles**: on the autoloader link the machine is the *client*
(above); on the host link (`0xD8/0xDC`) it is the **server**. Entered via the "Remote controll" menu,
dispatcher `host_dispatch` (`0x1E0B`) is a server loop — it shows a blinking `.`/`!` heartbeat on the
LCD, reads a 4-byte packet, dispatches by opcode, and replies.

- **Command packet** — `host_read_packet` `0x1DF3`, 4 bytes: `{lead byte → E, opcode → D, 16-bit LE
  parameter → HL}`. The **lead byte is read off the wire but never used or validated** (a sync/reserved
  byte). On a valid packet the dispatcher sets `op_word = opcode` and `run_count = parameter`.
- **Replies** — `'X'` (0x58) = ACK/OK, `'E'` (0x45) = bad packet / framing NAK; a pure RX timeout just
  re-polls (heartbeat). Handlers additionally return a binary **status byte**: `0x00` ok; `0x90` / `0xA0`
  / `0xB0` = command error / transfer failed / not-proper-image.

**Opcode table** — dispatch is a linear `CP <op>; JP/JR NZ` chain from `0x1E37`.

*Control opcodes* (explicit handlers):

| Op | Handler | Addr | Action |
|---|---|---|---|
| 0x09 | host_op_start | 0x205C | Reset operation word (`op_word=0`), ACK |
| 0x0A | host_op_image_dl | 0x1E37 | Image download (0xAA55-framed records into banked DRAM) |
| 0x0B | host_op_enter_run | 0x1F9F | Enter RUN mode — `host_mode=0`, install I/O vectors 0x52C9/CB/CD, `JP 0x0161` |
| 0x0C | host_op_ping | 0x204B | Ping / no-op ACK (+ status 0x00) |
| 0x0D | host_op_disk_write | 0x1FC6 | Disk-write / format setup: streams `cfg_flags`+unit, a **write-protect** byte (→ `0x9C` PC2 + `wprot_mode`, `0x200B`), `err_recovery`, then a **24-byte per-head zone table** → `hrd_hd0` — i.e. a host can **define a variable-rate Special format remotely**. Echoes each byte; clears `image_present` |
| 0x0E | host_op_diag_out | 0x2082 | Host↔autoloader serial **bridge** (relays until `'W'`=0x57), diag block via OTIR |
| 0x0F | host_op_load_exec | 0x206F | Load & execute downloaded code (`code_loader` → 0x7800, image 0x8000, `JP (HL)`) |

*Duplication-run opcodes* — anything not matched above falls through to `host_op_begin_run` `0x20E3`,
where **the opcode itself becomes `run_status`** (the operation mode); there is **no unknown-opcode
reject path**:

| Op | Action |
|---|---|
| 0x07 | **BP** duplication run (prints "BP", `run_status=1`, `OUT 0x9C,0x04`, `require_motor_ready`) |
| 0x01–0x06, 0x08 | **FDD** duplication: `run_status = opcode` → `dup_engine_loop` (mode = op-word phase: 1 FWV · 2 WV · 3 Format · 4 Format+V · 6 Write · 8 Verify) |

The **I/O-vector mechanism** (`0x4D89`/`0x4C43`/`0x2766` → `0x52C9/CB/CD`) retargets identical
byte-I/O sites between local keypad, autoloader, and host; opcode 0x0B rewrites all three vectors and
jumps to the shared run loop, which is how the same duplication engine serves local and remote runs.

## 9. UI & features

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
  cylinder/head/sector/offset, optionally re-verified bit-for-bit (see §7).
- **Simultaneous mode** writes all fitted drives in one pass via the parallel DMA path.

### Audio feedback

There are no distinct tones — `beep` (`0x2766`, via `iovec_beep` → `buzzer_beep` `0x49E3`) simply pulses
the buzzer *A* times (each `buzzer_pulse` ≈ 13 ms, with a gap between). The "code" is the pulse count:

| Beeps | Trigger |
|---|---|
| 1 | **ACCEPT** — a copy passed and was accepted (`0x10EC`) |
| 3 | **REJECT** — a copy failed and was rejected (`0x1141`) |
| 5 | Error / alert — seek error, compare error, comms error, key/limit feedback |

### HRD diagnostics & the 8253 timer

8253 counter 0 (mode 3, ÷13) = **153 846 Hz** — the Z80 SIO baud clock *and* the cascade clock into
counters 1 & 2 (interval timers; c1=head0, c2=head1).

**Spindle RPM** (`0x37DB` → `0x2E72`): preload counter 0xFFFF (mode 2), gate one index-to-index
revolution, latch (ctrl 0x84), read residual, `elapsed = 0xFFFF − residual`, then
`RPM = 0x008CD9B1 / ticks = 9 230 769 / ticks`. `9 230 769 = 60 × (2 MHz ÷ 13)` — an exact integer
match, confirming the counter clock and the **2 MHz** 8253 input (32.000 MHz ÷ 16). Checks: 300 RPM →
30 769 ticks; 360 RPM → 25 641 ticks.

**The alignment-diagnostic suite.** The **HRD diagnostics** menu (`hrd_menu` 0x1540) offers five
measurement types, all read from a factory alignment diskette and computed **in software from the FDC
read stream — there is no ADC.** The selected type (`hrd_test_idx`, 0–4) maps 1:1 onto a record of the
ROM table **`hrd_test_tbl`** (0x3186):

| idx | test (ROM label) | scale `K` | unit |
|---|---|---|---|
| 0 | Radial alignment (3 tracks) | 422 | µm |
| 1 | Eccentricity | 422 | µm |
| 2 | Head azimuth | 696 | arc-min (`'`) |
| 3 | Positioner "hystheresis" *(sic in ROM)* | 422 | µm |
| 4 | Spindle motor speed | 1 | RPM (raw) |

Each 5-byte record is `{ scale K : word, handler address : word, result mask : byte }`; the handler
field is reached by a computed jump (`PUSH DE; RET`, 0x2CED) and points to the per-test LCD formatter.
**The display scale is a ROM constant** — `hrd_show_scaled` (0x2CEE) computes
**`displayed = raw × K / 10000`** (`mul16`, then `÷ 0x2710`), where `K` is `hrd_test_tbl[test].scale`.
`hrd_test_tbl` is **never written by any code** — a static, ROM-initialised table — so the
geometric→display scale is a firmware constant, **not** a value embedded in the captured disk.

**Measurement pipeline** (`hrd_radial_measure` 0x2D5B): seek the alignment track and capture **four
read windows** into the image buffer — head 0 reads A/B at `image_buf+0x0000`/`+0x2000`, head 1 at
`+0x4000`/`+0x6000`. `hrd_find_burst` (0x3008) scans each window for the sync burst (three bytes
summing to `0xFF`, ×7) and returns its byte offset. The per-head result is the **difference of the
two burst offsets** (`SBC HL,DE`), cancelling common-mode timing and leaving the radial displacement.
This is repeated **10×** and passed through `hrd_median_filter` (0x3084, bubble-sort + average the
middle samples) to yield the stored `hrd_hd0`/`hrd_hd1` per head. The capture reuses the **normal FDC
read path**; the `0x9C` `0x0E→0x0F` strobe seen during it is just `fdc_poll_complete`'s result-read
pulse (PC7 of the PPI Port C — see §3).

**Supported drive models & which tracks are measured.** HRD alignment is only supported on **three
drive models**, and the model isn't chosen from a menu — it is **auto-detected** from the drive's
model-ID sense byte `format_desc[0xB]` (masked `0xC8`/`0x48`) at `0x1943`. The detected name is shown
as `"Insert model <name>"`; an unrecognised drive gets **"Not available"**. Each model sets
`hrd_model_idx` (`0x3178`), which selects a row of alignment tracks.

| Model | ID pattern | idx | `cyl_head` | Geometry | Alignment tracks | Likely drive *(inferred)* |
|---|---|---|---|---|---|---|
| **528-400** | `0x08` | 0 | `0x14` | 40-track · DD | 16, 39, 20, 34 | 5.25″ 360 KB |
| **526-400** | `0xC8` | 1 | `0x13` | 80-track · **HD** | 32, 79, 44, 76 | 5.25″ 1.2 MB |
| **325-400** | `0x40` | 2 | `0x12` | 80-track · **DD** | 40, 79, 44, 76 | 3.5″ 720 KB |
| *unrecognised* | — | — | — | — | → "Not available" | — |

The seek target for a test is read from the table at `0x317A` as
`track = byte[0x317A + hrd_model_idx×4 + (index−1)]` (a ROM constant, never written at run time).
**Density** comes from bit 7 of the model-ID byte (`format_desc[0xB]`, HD = 1 / DD = 0, see §6):
`526-400` keeps it set (HD, 500 kbps); **`325-400` forces DD** via `RES 7` at `0x199D` (250 kbps);
`528-400` is the 40-track DD drive. So **`526-400` and `325-400` are the same 80-track mechanism at
different densities** — the only alignment-test difference is the middle radial cylinder (**32** vs
**40**); their eccentricity (44) and azimuth (76) tracks are identical, and `cyl_head` differs by one
(19 vs 18). The "likely drive" column reads the leading digit as form factor (5.25″ vs 3.5″) — a strong
inference from the numbers, not stated by the ROM.

Per test (shown for model 0):

| Test | Track index | Track(s) |
|---|---|---|
| Radial alignment | low entries + the index-0 slot (`0x3179` = 0) | **0, 16, 39** (the "3 tracks") |
| Eccentricity | record index 3 | **20** |
| Azimuth | record index 4 | **34** |
| Positioner / hysteresis | one track, seeked from **both directions** (`\|out\| − \|in\|`) | one alignment track |
| Spindle speed | any readable track — needs only the index hole | — |

**The alignment diskette** must therefore carry the `hrd_find_burst` pattern — a `0x55` tone (any three
consecutive bytes sum to `0xFF`) — as **two radially-offset bursts per head** on those cylinders, so a
centred head reads them symmetrically (`A − B ≈ 0`). `528-400` needs it on ≈ tracks 0/16/20/34/39;
the 80-track models on ≈ 32/40/44/76/79.

## 10. Config & provenance

Configuration lives in the `0x31xx` RAM block and is persisted to a small **bit-banged serial
EEPROM** (helpers `0x2ACB`/`0x2B3E`), re-saved whenever the config wizard completes. The boot
checksum validates it; corruption forces "Run config again".

The Config menu (hold EXIT at boot) writes these flags into the `0x31xx` block:

| Item | Variable | Values / effect |
|---|---|---|
| Write protect | `wprot_mode` `0x3155` | drives `0x9C` PC2 (`0x04` on / `0x05` off) |
| Data-error recovery | `err_recovery` `0x314A` | enable = `1` / disable = `3` (read in the read/verify path `0x0DAF`) |
| Serialization | `cfg_byte`/`hrd_desc_tbl` bit 1 | on/off (see §7) |
| Copy direction | `cfg_flags` bit 7 | in→out / out→in |
| Maximal cylinder | `cfg_flags` low bits | edited, clamped to `0x55`, bit 7 preserved |
| Precomp setting | `precomp_sel` `0x3166` | write-precomp index → FDC port `0xC2` |
| Batch processing | `cfg_batch` `0x311F` | batch run count |

### Config storage — CAT24C02 I²C EEPROM (`eeprom_transfer` 0x2735)

`eeprom_transfer` is a **bidirectional** block transfer to the CAT24C02 (bit-banged I²C on port `0xF0`),
despite the name — the direction is a parameter:

| Reg | Meaning |
|---|---|
| `A` | direction — **0 = load** (EEPROM → RAM), **non-zero = save** (RAM → EEPROM) |
| `HL` | RAM buffer (destination on load, source on save) |
| `B` | byte count |
| `C` | EEPROM word address (0–255) |

*Save* writes one byte per I²C transaction (`eeprom_write` start + device + word-addr, one data byte,
stop; `INC` address each pass — this honours the per-byte write cycle). *Load* is a single sequential
read (start, addr, restart, then `B` bytes: ACK each, NAK+stop the last).

**EEPROM (256 bytes) layout, from the call sites:**

| Offset | Bytes | Contents | RAM buffer |
|---|---|---|---|
| `0x00` | 4 | Settings block: `cfg_flags`, `cfg_byte`, `drv_active_cfg`, `cfg_batch` (write-protect, copy dir, serialization, err-recovery, max-cyl packed here) | `0x311C` |
| `0x04`+ | 96 | The four **Special-format zone tables** (24 B/slot; whole set saved at `0x26CE`, individual slots at computed offsets) | `fmt_geom_recs` / `hrd_hd0` |
| `0xFC` | 4 | 32-bit **lifetime cycle counter** — total copies made, shown by `show_model_cycles` | `cycle_cnt` (`0x3269`) |

Boot loads the settings block (`0x03BC`) and the cycle counter (`0x006B`); the config menus save
sub-ranges of `0x00–0x03`; a completed run bumps and re-saves the counter (`0x0337`/`0x0F85`).

### Provenance — version tags

Three 14-byte version fields (7-char module name + date) are indexed by a **pointer table at
0x0040–0x0045** (`DW 0x0054, 0x4B8B, 0x52CF`):

| Tag | Offset | Date | Likely meaning |
|---|---|---|---|
| `M6T9I2F 961002` | 0x0054 | 1996-10-02 | Main firmware build (shown at power-on) |
| `STIBG11 950503` | 0x4B8B | 1995-05-03 | Downloadable-code / loader module |
| `R6R1A   940329` | 0x52CF | 1994-03-29 | Boot-loader module |

The third tag is `R6R1A` at 0x52CF (a naive `strings` shows "IR6R1A" at 0x52CE — the leading `I` is
the adjacent `iovec_annun` pointer's high byte `0x49`, not part of the string).

---

## Files & method

- `LSK M6T912F firmware analysis.html` — styled reference document (same content, richer layout).
- `LSK M6T912F firmware analysis.md` — this file.
- `disassembly/z80dis.py` — purpose-written Z80 disassembler (full CB/ED/DD/FD coverage). Handles
  the `CALL 0x4C59` inline-string print convention (renders the string as `DB` and realigns code
  after the `0x00`), emits readable **labels** for known functions/variables, rewrites operand
  addresses to those labels, and annotates I/O ports. Usage: `python3 z80dis.py "<bin>" <start> <end>`
- `disassembly/sourcecode.s` — full **0x0000–0x52FF** listing, labeled (**1,218 labels** — 539 named + 679 auto `loc_`; ~3,240 operand references resolved to labels or `label+offset`).
- `disassembly/symbols.txt` — the symbol map (address → label + I/O ports) used to annotate the listing.

**Method.** Disassembled with the included Z80 disassembler, cross-referenced against the on-board
datasheets, and verified by reading the actual hardware primitives — not pattern-matched. Each
subsystem (FDC/DMA engine, duplication engine, serial protocols, HRD diagnostics) was traced
independently, then cross-checked; register-level details were confirmed against the SMC FDC37C65C,
µPD8237A DMA, µPD71055 PPI, 8253 PIT, Z80 CPU, and HD44780 LCD datasheets. The DRAM-banking, `0x9C`,
`0xC0`, and U68/U74 findings were verified by continuity-probing the board. Analysis dated 2026-07-22.
