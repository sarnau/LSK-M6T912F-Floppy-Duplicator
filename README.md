# LSK M6T912F Floppy Duplicator — Firmware Reverse-Engineering

A fully-labeled, commented disassembly and analysis of the 32 KB Z80 firmware for the
**LSK Data Systems M6T912F** four-drive floppy-disk duplicator (circa 1996).

> **Note:** the firmware ROM (`LSK M6T912F D1_97.bin`) is LSK Data Systems' proprietary code,
> included here only as the subject of this reverse-engineering study. This repository is private.

## Contents

| Path | What it is |
|---|---|
| `LSK M6T912F D1_97.bin` | The original 32 KB EPROM image (the subject binary) |
| `analysis/LSK M6T912F firmware analysis.md` / `.html` | Main analysis — hardware map, memory architecture, boot sequence, I/O port map, open questions |
| `analysis/LSK M6T912F firmware internals.md` / `.html` | Companion drill-downs — duplication engine, FDC command engine, HRD diagnostics + 8253 timer, serial protocol handlers |
| `analysis/disassembly/z80dis.py` | Custom two-pass Z80 disassembler (symbols, comments, data regions, offset labels) |
| `analysis/disassembly/sourcecode.s` | Generated, fully-labeled listing (`0x0000–0x52FF`) |
| `analysis/disassembly/symbols.txt` | Generated symbol table |

## The machine, briefly

- **CPU:** Z80, 32 KB EPROM. The reset stub copies the EPROM into **DRAM bank `0xFF`** and maps
  it to `0x0000–0x7FFF` (via the `0x9C` control latch), then runs from RAM — a shadowed-ROM design.
- **Image buffer:** 8 MB banked DRAM (`0xB0` bank latch), image banks `0x00–0xFE`; bank `0xFF` is
  the program-RAM mirror.
- **Chipset:** 4× SMC FDC37C65C floppy controllers, NEC µPD8237A DMA (one channel per FDC),
  NEC µPD8253C PIT, a Zilog **Z80 SIO** (dual-channel serial: autoloader + host), HD44780 2×20 LCD,
  µPD71055 PPI + Z8420 PIO drive latches, and a `0x9C` 8-line addressable control latch. The board is
  a Terra Computer Systems **KDP-05 B** (Czech Republic, © 1993); the LSK M6T912F is the LSK-branded build.
- **Modes:** front-panel **Manual**, **Autoloader** (serial), and a **host remote-control** protocol
  (the machine acts as the server).

## Component datasheets

Every larger chip is identified from the board photo (`PCB Front.jpg`) and its markings; the
datasheets are included for reference.

| Chip | Role | Ports | Datasheet |
|---|---|---|---|
| SMC FDC37C65C ×4 | Floppy-disk controllers (765-compatible) | 00/10/20/30 | `SMC FDC37C65C 2.88MB Floppy Disk Controller.pdf` |
| NEC µPD8237A | DMA controller (one channel per FDC) | 80–8F | `NEC D8237A DMA Controller.pdf` |
| NEC µPD8253C-2 | Programmable interval timer (baud + spindle timing) | A0–AC | `NEC D8253C PROGRAMMABLE INTERVAL TIMER.PDF` |
| Zilog Z80 SIO/0 (Z0844006PSC) | Dual-channel serial — autoloader + host | D0–DC | `Zilog Z0844006PSC SIO.pdf` · `Zilog Z80SIO Technica Manual.pdf` |
| NEC µPD71055 | Parallel interface unit (PPI) — drive/motor lines | 40–70, B0–C6 | `NEC µPD71055 Parallel Interface Unit.pdf` |
| Zilog Z8420 | Z80 PIO — drive/motor lines | 40–70, B0–C6 | `Zilog Z8420 Parallel Input-Output.pdf` |
| Zilog Z80 CPU (Z0840006PSC) | Main processor (6 MHz, IM 1) | — | `Zilog Z0840006PSC Z80 CPU.pdf` |
| Hitachi HD44780 | 2×20 character LCD | E0/E8 | `Hiatchi HD44780 LCD.pdf` |
| Microchip TC232 | RS-232 line driver | — | `Microchip TC232CPE RS232.PDF` |
| Alliance AS4C14400 | 1M×4 DRAM (2× 4 MB SIMM = 8 MB image buffer) | bank @ B0 | `AS4C14400 1M×4 RAM.PDF` |

Clocking: 32.000 MHz + 48.000 MHz crystals (the 8253's 2 MHz input is 32 MHz ÷ 16); address decode is
a GAL20V8B + PALCE20V8H. The full hardware map, port table, and open questions are in the main analysis.

## Regenerating the disassembly

The disassembler is self-contained (standard library only):

```sh
cd analysis/disassembly
python3 z80dis.py "../../LSK M6T912F D1_97.bin" 0x0000 0x5300 > sourcecode.s
```

The `0x5300` end bound trims the `0xFF`-fill tail (real content ends at `0x52FF`).
Symbols and inline comments live in the `SYMBOLS` / `COMMENTS` tables inside `z80dis.py`.
