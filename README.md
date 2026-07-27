# LSK M6T912F Floppy Duplicator — Firmware Reverse-Engineering

A fully-labeled, commented disassembly and analysis of the 32 KB Z80 firmware for the
**LSK Data Systems M6T912F** four-drive floppy-disk duplicator (circa 1996).

> **Note:** the firmware ROM (`LSK M6T912F D1_97.bin`) is LSK Data Systems' proprietary code,
> included here only as the subject of this reverse-engineering study. This repository is private.

## Contents

| Path | What it is |
|---|---|
| `LSK M6T912F D1_97.bin` | The original 32 KB EPROM image (the subject binary) |
| `LSK M6T912F firmware analysis.md` / `.html` | Main analysis — hardware map, memory architecture, boot sequence, I/O port map, open questions |
| `LSK M6T912F firmware internals.md` / `.html` | Companion drill-downs — duplication engine, FDC command engine, HRD diagnostics + 8253 timer, serial protocol handlers |
| `LSK M6T912F autoloader.md` / `.html` | Autoloader device reference — PIC16C57 / ST93C06 hardware, serial command set (S/C/I/A/R/O/V), status codes |
| `LSK M6T912F host protocol.md` / `.html` | Host remote-control protocol reference — server loop, 4-byte packet, opcode table, image download / load-exec |
| `disassembly/z80dis.py` | Custom two-pass Z80 disassembler (symbols, comments, data regions, offset labels) |
| `disassembly/inline_comments.py` | Per-instruction inline comments (address → note), consumed by the disassembler |
| `disassembly/sourcecode.s` | Generated, fully-labeled + fully-commented listing (`0x0000–0x52FF`) |
| `disassembly/symbols.txt` | Generated symbol table |
| `disassembly/navmap.py` | Generator for the navigation aids (parses `sourcecode.s`) |
| `disassembly/navigation.md` | Generated navigation aids — memory map, routine index, call graph |
| `datasheets/` | Datasheets for the identified board chips (13 PDFs — see [Component datasheets](#component-datasheets)) |
| `datasheets/controller/` | Autoloader controller datasheets — PIC16C57 MCU + ST93C06 EEPROM |
| `PCB Front.jpg` | Top-side board photo (used in [Board layout](#board-layout)) |
| `PCB_INFO.md` | Board reference — connector pinouts (incl. serial `K54`) and full U1–U101 chip designator map |

## The machine, briefly

- **CPU:** Z80, 32 KB EPROM. The reset stub copies the EPROM into **DRAM bank `0xFF`** and maps
  it to `0x0000–0x7FFF` (via the `0x9C` control latch), then runs from RAM — a shadowed-ROM design.
- **Image buffer:** 8 MB banked DRAM (`0xB0` bank latch), image banks `0x00–0xFE`; bank `0xFF` is
  the program-RAM mirror.
- **Chipset:** 4× SMC FDC37C65C floppy controllers, NEC µPD8237A DMA (one channel per FDC),
  NEC µPD8253C PIT, a Zilog **Z80 SIO** (dual-channel serial: autoloader + host), HD44780 2×20 LCD,
  a µPD71055 PPI + 74HCT373 drive latches, and a `0x9C` 8-line addressable control latch. The device is
  the Terra Computer Systems **KDP-05 B** (Czech Republic, © 1993) — model from the board sticker; the
  bare PCB is silkscreened **KOP05B** (see [`PCB_INFO.md`](PCB_INFO.md)). The LSK M6T912F is
  the LSK-branded build.
- **Modes:** front-panel **Manual**, **Autoloader** (serial), and a **host remote-control** protocol
  (the machine acts as the server).

## Component datasheets

Every larger chip is identified from the board photo (`PCB Front.jpg`) and its markings; the
datasheets are included for reference under [`datasheets/`](datasheets/).

| Chip | Role | Ports | Datasheet |
|---|---|---|---|
| SMC FDC37C65C ×4 | Floppy-disk controllers (765-compatible) | 00/10/20/30 | `datasheets/SMC FDC37C65C 2.88MB Floppy Disk Controller.pdf` |
| NEC µPD8237A | DMA controller (one channel per FDC) | 80–8F | `datasheets/NEC D8237A DMA Controller.pdf` |
| NEC µPD8253C-2 | Programmable interval timer (baud + spindle timing) | A0–AC | `datasheets/NEC D8253C PROGRAMMABLE INTERVAL TIMER.PDF` |
| Zilog Z80 SIO/0 (Z0844006PSC) | Dual-channel serial — autoloader + host | D0–DC | `datasheets/Zilog Z0844006PSC SIO.pdf` · `datasheets/Zilog Z80SIO Technica Manual.pdf` |
| NEC µPD71055 | Parallel interface unit (PPI) — drive/motor lines | 40–70, B0–C6 | `datasheets/NEC µPD71055 Parallel Interface Unit.pdf` |
| Zilog Z80 CPU (Z0840006PSC) | Main processor (6 MHz, IM 1) | — | `datasheets/Zilog Z0840006PSC Z80 CPU.pdf` |
| Hitachi HD44780 | 2×20 character LCD | E0/E8 | `datasheets/Hiatchi HD44780 LCD.pdf` |
| Microchip TC232 | RS-232 line driver | — | `datasheets/Microchip TC232CPE RS232.PDF` |
| Alliance AS4C14400 | 1M×4 DRAM (2× 4 MB SIMM = 8 MB image buffer) | bank @ B0 | `datasheets/AS4C14400 1M×4 RAM.PDF` |
| Catalyst CAT24C02 | I²C serial EEPROM (256×8) — config + serial-number NVRAM | F0 (bit-banged I²C) | `datasheets/CAT24C02.pdf` |
| Lattice GAL20V8B (U5) | Address-decode PLD | — | `datasheets/GAL20V8B 15LP.pdf` |
| Lattice/AMD PALCE20V8H (U68) | DRAM controller (RAS/CAS/mux timing) | — | `datasheets/PALCE20V8.PDF` |

Clocking: 32.000 MHz + 48.000 MHz crystals (the 8253's 2 MHz input is 32 MHz ÷ 16). The **GAL20V8B (U5)**
handles I/O chip-select decode; the **PALCE20V8H (U68)**, sited right at the SIMM slots, is the DRAM
controller (see [Board layout](#board-layout)). The full hardware map, port table, and open questions are in the main analysis.

The **autoloader** is a separate device on the RS-232 link, built around its own controller — see the
[autoloader reference](LSK%20M6T912F%20autoloader.md):

| Chip | Role | Datasheet |
|---|---|---|
| Microchip PIC16C57 | Autoloader MCU (hopper/arm/bin motors, sensors, serial interpreter) | `datasheets/controller/PIC16C57.PDF` |
| SGS-Thomson ST93C06 | Autoloader NVRAM (256-bit Microwire EEPROM) — cycle count + config | `datasheets/controller/ST93C06.PDF` |

## Board layout

![LSK M6T912F firmware board — Terra Computer Systems KDP-05 B (KOP05B PCB), front](PCB%20Front.jpg)

Approximate placement of the major chips on the front side (image above):

| Region | Chips |
|---|---|
| Top-left | 4× SMC FDC37C65C floppy controllers (PLCC) |
| Top-center | GAL20V8B (U5, address-decode PLD); 74HCT glue logic |
| Top-right | 32.000 MHz + 48.000 MHz crystals |
| Center | NEC µPD8237A DMA (U7, under the "KDP-05" model/serial sticker); NEC µPD8253C-2 PIT (U70); MC74HCT138 I/O decoders (U56/U59/U60); Terra Computer Systems logo |
| Bottom-left | NEC µPD71055 PPI (U69, above the SIO); Zilog Z80 SIO/0 (U71, Z0844006PSC); Microchip TC232 line driver (U101) |
| Bottom-center | Zilog Z80 CPU (U51, Z0840006PSC); the M6T912F firmware EPROM (**U57**, windowed, "D1/97"); PALCE20V8H (U68, DRAM controller — see below) |
| Right | 2× AS4C14400 DRAM SIMMs (U77/U78, 8 MB image buffer); banks of 74HCT373 latches / 74HCT157 DRAM address muxes; Catalyst CAT24C02 I²C config EEPROM (U86, near the connector) |

Full connector pinouts and the complete **U1–U101** chip designator map are in
[`PCB_INFO.md`](PCB_INFO.md).

### DRAM interface

The two 30-pin SIMM slots (**U77/U78**, `AS4C14400` 1M×4 → 8 MB) are driven by a small discrete-logic
DRAM controller clustered around them (inferred from the IC types + their board placement):

| Chips | Role |
|---|---|
| **U68** PALCE20V8H | **DRAM controller** — sequences `/RAS0`/`/RAS1`, `/CAS`, mux-select, refresh |
| **U52/U53/U54** 74HCT157 ×3 | row/column **address multiplexer** (next to the RAM) |
| **U65/U66/U83/U85** 74HCT373 ×4 | bank (`0xB0`) + DRAM address latches |
| **U58/U87** 74HCT245 ×2 | bidirectional **data buffers** to the SIMM `DQ` pins |
| **U55/U61** 74HCT74 + NOR/inverter glue | `/RAS`→mux→`/CAS` timing |

The flat image address is `{0xB0 bank latch[7:0], Z80 A14:0}`: the **top bank bit selects which SIMM**
(`/RAS0` vs `/RAS1`), and the lower bits are multiplexed to the SIMM's row/column address pins. Each
30-pin SIMM presents the standard set — multiplexed address, `D0–D7` **+ one parity bit**, and a single
`/RAS`, `/CAS`, `/WE` — so the controller drives **one `/RAS` per slot** while address/data, `/CAS` and
`/WE` are shared; the 9th (parity) bit is **generated but not checked**.

Standard 30-pin SIMM edge pinout the controller interfaces to (address `A0–A11`, data `DQ0–7` + parity,
`/RAS`, `/CAS`, `/WE`, `/CASP`):

| Pin | Sig | Pin | Sig | Pin | Sig |
|---|---|---|---|---|---|
| 1 | Vcc | 11 | A4 | 21 | /WE |
| 2 | /CAS | 12 | A5 | 22 | Vss |
| 3 | DQ0 | 13 | DQ3 | 23 | DQ6 |
| 4 | A0 | 14 | A6 | 24 | A11 |
| 5 | A1 | 15 | A7 | 25 | DQ7 |
| 6 | DQ1 | 16 | DQ4 | 26 | DQ8 (parity Q) |
| 7 | A2 | 17 | A8 | 27 | /RAS |
| 8 | A3 | 18 | A9 | 28 | /CASP |
| 9 | Vss | 19 | A10 | 29 | parity D |
| 10 | DQ2 | 20 | DQ5 | 30 | Vcc |

The other similar parts (U19 `157`, U47 `245`, U62 `74`) sit away from the slots and serve the CPU/FDC
paths, not the DRAM. Exact nets need the board schematic.

### Clock generation

Two packaged oscillators feed **fast (`74F`/`74S`) divider logic** clustered around them (`LS`/`HCT`
can't toggle at 32–48 MHz), producing two clock domains:

| Source | Divider | Feeds |
|---|---|---|
| **32 MHz (U21)** | `74LS93` (U17) ÷16 → **2 MHz** `[V]` | 8253 PIT (U70) — SIO baud (÷13 → 9600) + interval timers |
| **48 MHz (U20)** | direct; `74S112` (U13/U14) ÷2 chain | the four FDC37C65C data separators (2.88 MB / **1 Mbps**), and ÷8 → **6 MHz** Z80 (U51) |

`74F04` (U16) buffers/fans-out the clocks to the four FDCs + CPU; `74F08` (U15/U22) gate or select them.
Two crystals let each domain divide cleanly — 32 MHz → 2 MHz → 9600 baud, 48 MHz → the
250/300/500/1000 kbps floppy data rates. Only `32 MHz ÷ 16 = 2 MHz` is firmware-proven (from the spindle-RPM
timing); the 48 MHz routing is inferred from the part ratings and the fast-logic divider chain.

### Serial / RS-232 connections

The RS-232 hardware is in the **bottom-left corner**:

- **Zilog Z80 SIO/0** (**U71**, `Z0844006PSC`) — the serial *controller*, driving both channels at TTL levels: channel A = autoloader (`D0/D4`), channel B = host PC (`D8/DC`).
- **Microchip TC232CPE** (**U101**, immediately **right of the SIO**) — a dual RS-232 transmitter/receiver; its charge-pump caps convert the SIO's TTL to ±RS-232 line levels and back. Probe TTL on its SIO side, ±RS-232 on its connector side.

Both channels leave the board on a single connector, **`K54`** (pinout from `PCB_INFO.md`):

| Pin | Signal | | Pin | Signal |
|---|---|---|---|---|
| 3 | SIO DCD **B** (host) | | 4 | SIO DCD **A** (autoloader) |
| 5 | SIO RTS B | | 6 | SIO RTS A |
| 7 | SIO CTS B | | 8 | SIO CTS A |
| 9 | R2 in | | 10 | R1 in |
| 11 | T1 out | | 12 | T2 out |
| 13 | B53 | | 14 | B54 |

This **resolves the earlier "which connector carries which channel" question**: both channels share `K54`, with the **A**-suffixed handshake lines on the autoloader link and the **B**-suffixed on the host link; the TC232 (U101) supplies the two transmit/receive pairs (`T1`/`R1`, `T2`/`R2`) for TxD/RxD.

## Regenerating the disassembly

The disassembler is self-contained (standard library only):

```sh
cd disassembly
python3 z80dis.py "../LSK M6T912F D1_97.bin" 0x0000 0x5300 > sourcecode.s
```

The `0x5300` end bound trims the `0xFF`-fill tail (real content ends at `0x52FF`).
Labels and block/header comments live in the `SYMBOLS` / `COMMENTS` tables inside `z80dis.py`;
the per-instruction inline comments (one per line) live in `inline_comments.py` (`ILINE`, keyed by
address) and are merged onto each line automatically.

The navigation aids (memory map, routine index, call graph) are generated from the listing:

```sh
cd disassembly
python3 navmap.py sourcecode.s > navigation.md
```
