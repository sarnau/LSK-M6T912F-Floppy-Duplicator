# LSK M6T912F Floppy Duplicator — Firmware Reverse-Engineering

A fully-labeled, commented disassembly and analysis of the 32 KB Z80 firmware for the
**LSK Data Systems M6T912F** four-drive floppy-disk duplicator (circa 1996).

> **Note:** the firmware ROM (`LSK M6T912F D1:97.bin`) is LSK Data Systems' proprietary code,
> included here only as the subject of this reverse-engineering study. This repository is private.

## Contents

| Path | What it is |
|---|---|
| `LSK M6T912F D1:97.bin` | The original 32 KB EPROM image (the subject binary) |
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
  NEC D8253 PIT, two 8251-class USARTs (autoloader + host), HD44780 2×20 LCD, µPD71055 PPI +
  Z8420 PIO drive latches, and a `0x9C` 8-line addressable control latch.
- **Modes:** front-panel **Manual**, **Autoloader** (serial), and a **host remote-control** protocol
  (the machine acts as the server).

## Regenerating the disassembly

The disassembler is self-contained (standard library only):

```sh
cd analysis/disassembly
python3 z80dis.py "../../LSK M6T912F D1:97.bin" 0x0000 0x5300 > sourcecode.s
```

The `0x5300` end bound trims the `0xFF`-fill tail (real content ends at `0x52FF`).
Symbols and inline comments live in the `SYMBOLS` / `COMMENTS` tables inside `z80dis.py`.
