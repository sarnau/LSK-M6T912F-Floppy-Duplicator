# LSK M6T912F — Subsystem Internals

Byte-level drill-downs into the four load-bearing subsystems. Companion to
`LSK M6T912F firmware analysis.md`. All addresses are ROM offsets; excerpts are verbatim.
`[V]` verified from code · `[?]` flagged uncertainty.

> **Correction carried into the main doc:** the **DRAM image-buffer bank is selected by port 0xB0**,
> not 0x9C — proven by the boot DRAM-sizing loop (`OUT (0xB0),A; LD (0x8000),A; CP (0x8000)` @0x03EE)
> and by every image-window access in the copy/verify/format paths. 0x9C is a separate control/mode latch.

---

## A. Duplication engine

A cooperative **phase machine**. State: operation word `0x3134` + current-phase handler pointer
`0x3131` (loaded from media-indexed table `0x1444`).

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
- **Format** `0x1CE2` — FAT12 boot sector from ROM template `0x3305`, `0x55AA` at 0x81FE.
- **Write** `0x08DE` — parallel DMA; each target FDC has its own block (`0x4AEB`/`0x4B06`) + 8237 channel.
- **Verify/compare** `0x0E46` — DMA read-back into scratch `0x5800`, `CPI` vs image bank; mismatch sets ERR_A/ERR_B.

```
0E46  LD A,(0x3156)     ; per-track image bank #
0E49  OUT (0xB0),A      ; page bank into 0x8000
0E4B  LD HL,(0x3158) ; OR 0x80 -> 0x8000+offset
0E53  LD DE,0x5800      ; DMA read-back scratch
0E58  CPI               ; compare; JR NZ -> "Compare error", SET 6/5
```

**Batch/autoloader** — loop tail `0x1090` decrements run count `0x313D`; accept/reject sequencer
`0x10D2`. Each target owns its channel + block, so a failed target sets its group bit and is rejected
while others continue. `[?]` no separate per-target "alive" mask beyond the two group bits.

---

## B. FDC command engine

Command/result phases: polled PIO (`0x457F` write, `0x46F1` read). Bulk data: 8237 DMA. Commands
issued via an `LD SP,IX / POP` rapid-load of the RAM state block.

**RAM state**

| Address | Contents |
|---|---|
| 0x4A85 / 8C / 93 / 9A | 7-byte result phase per FDC (ST0,ST1,ST2,C,H,R,N) |
| 0x4A61 / 6A / 73 / 7C | command buffer; byte0 = last opcode (seek/recal marker for ISR) |
| 0x4AA1 | per-FDC "result captured" bits |
| 0x4AEB / 0x4B06 | drive-pair blocks: +7 DOR/motor, +8/9 DMA start addr, +10/11 DMA count |
| 0x52DD | format descriptor: +1 heads, +2 N, +5 sectors/track, +11 density/flags |

**READ/WRITE build** `0x3BFB` — opcode base in `0x4AEA` (0x26→0x66 READ / 0x05→0x45 WRITE after
`|0x40` MFM); 9 bytes `{CMD,HD/US,C,H,R,N,EOT,GPL,DTL}` streamed by `0x457F`; DMA armed in parallel
(see below).

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
master-clears it (`8D`) and each arm does exactly four byte-writes. Channel address is 16-bit only
(`A0–A15`); the DRAM image bank above that is paged separately by port `0xB0`. DMA only ever targets
image banks `0x00–0xFE`; bank `0xFF` is reserved as the **program-RAM mirror** (boot `LDIR`s the EPROM
into bank 0xFF at `0x8022`, then `OUT 0x9C,0x92` fixes it at `0x0000–0x7FFF` — see main §3), which is
why the bank checksum loop at `0x5193` (`INC A; CP 0xFF; RET Z`) walks `0x00–0xFE` and stops at 0xFF.
The map is set-once: `OUT (0x9C),0x92` and `OUT (0xB0),0xFF` each execute exactly once (boot), and
runtime `0x9C` strobes (`fdc_poll_complete` `0x0E→0x0F` @0x475E) run with the PC fetching straight
through from low RAM — so 0x9C is an addressable per-line latch and bank 0xFF stays mapped low.

**Seek family** — RECALIBRATE 0x07 (`0x39A0`), SEEK 0x0F (`0x42DD`, target cyl in C→NCN). After a
seek/recal interrupt the ISR path `0x462D` **auto-issues SENSE INTERRUPT STATUS 0x08**. Data-rate/
precomp via FDC register interface 0xB1/0xC2/0xC3 (250 DD / 500 HD kbps). `[?]` step-timing/SPECIFY
param block `0x3CD3` has a runtime-computed opcode, not a literal 0x03.

**FORMAT 0x4D** — descriptor `0x52DD`; interleave/sector-map builder `0x5043`/`0x507E` emits per-sector
C/H/R/N field list into the 0x8000 buffer for the execution phase.

**Built-in disk formats — `fmt_param_tbl` `0x326E`.** Eight 19-byte DOS BPB records declare the
supported geometries (fields: +3 bytes/sector · +5 root entries · +7 total sectors · +9 media byte ·
+10 sectors/FAT · +12 sectors/track · +14 heads):

| Rec | Media | Total | spt | Heads | Format |
|---|---|---|---|---|---|
| 0 | F9 | 1440 | 9 | 2 | 720 K (3.5″ DD) |
| 1 | F0 | 2880 | 18 | 2 | 1.44 M (3.5″ HD) |
| 2 | F9 | 1440 | 9 | 2 | 720 K variant (144 root) |
| 3 | F9 | 2400 | 15 | 2 | 1.2 M (5.25″ HD) |
| 4 | FE | 320 | 8 | 1 | 160 K (5.25″ SS) |
| 5 | FC | 360 | 9 | 1 | 180 K (5.25″ SS) |
| 6 | FF | 640 | 8 | 2 | 320 K (5.25″ DS) |
| 7 | FD | 720 | 9 | 2 | 360 K (5.25″ DS) |

**The table is dead / vestigial** — it is never read by any code in this image `[V]`. No base-address
load of 0x326E exists anywhere in the 32 KB ROM (an exhaustive pointer search returns only two
false-positive hits, both bytes inside other instructions). The download/code-load loader
(`code_loader` `0x21A9` → `dl_code` `0x21CE`→0x7800) — the natural "STIBG11 loader module" — was
checked directly and never touches it either; it is a serial firmware downloader (sync preamble →
address/count → stream into `image_buf`). The geometry the engine actually uses lives in `format_desc`
`0x52DD`, assembled from the config-menu selection via `media_cfg_index` `0x520A` (form-factor /
density / mode bits → 0–7 index → phase handler + FDC flags + `init_format_geom` `0x5101`); the FAT12
boot sector is built from `fat12_template` `0x3305`, not from this table. Most likely a leftover from
an earlier build (or read only by an externally-downloaded program, which is outside this ROM).

**Error decode — priority encoder `0x4893`** over ST0/ST1/ST2:

| Status bit | Meaning | Message |
|---|---|---|
| ST1.5 / ST1.2 / ST1.0 / ST2.5 | CRC · no-data · missing AM · data CRC | "unreadable" |
| ST1.4 | overrun | "Lost data" |
| ST1.1 | not writable (write-protect) | "FDD write fault" |
| ST2.4 / ST2.1 | wrong / bad cylinder | "FDD seek error" |
| ST0.4 | equipment check | "FDD seek error" |
| ST3 (SENSE DRIVE 0x04) | WP / ready / track0 | "FDD not ready" |

---

## C. HRD diagnostics & the 8253 timer

8253 counter 0 (mode 3, ÷13) = **153 846 Hz** — Z80 SIO baud clock *and* the cascade clock into
counters 1 & 2 (interval timers; c1=head0, c2=head1).

**Spindle RPM** (`0x37DB` → `0x2E72`): preload counter 0xFFFF (mode 2), gate one index-to-index
revolution, latch (ctrl 0x84), read residual, `elapsed = 0xFFFF − residual`, then
`RPM = 0x008CD9B1 / ticks = 9 230 769 / ticks`.

`9 230 769 = 60 × (2 MHz ÷ 13)` — exact integer match → confirms the counter clock and the **2 MHz**
8253 input, which the board derives as **32.000 MHz ÷ 16** (the board carries 32 MHz + 48 MHz
crystals). Checks: 300 RPM → 30 769 ticks; 360 RPM → 25 641 ticks.

### The alignment-diagnostic suite

The **HRD diagnostics** menu (`hrd_menu` 0x1540) offers five measurement types, all read from a
factory alignment diskette and computed **in software from the FDC read stream — there is no ADC.**
The selected type (`hrd_test_idx`, 0–4) maps 1:1 onto a record of the ROM table **`hrd_test_tbl`**
(0x3186):

| idx | test (ROM label) | scale `K` | unit |
|---|---|---|---|
| 0 | Radial alignment (3 tracks) | 422 | µm |
| 1 | Eccentricity | 422 | µm |
| 2 | Head azimuth | 696 | arc-min (`'`) |
| 3 | Positioner "hystheresis" *(sic in ROM)* | 422 | µm |
| 4 | Spindle motor speed | 1 | RPM (raw) |

Each 5-byte record is `{ scale K : word, handler address : word, result mask : byte }`; the handler
field is reached by a computed jump (`PUSH DE; RET`, 0x2CED) and points to the per-test LCD formatter
(`hrd_disp_radial`/`_ecc`/`_azimuth`/`_positioner`, and the shared `show_rpm_suffix` for spindle).
The formatters fix the displayed units: radial/eccentricity/positioner in **µm**, azimuth in
**arc-minutes** (`'`), spindle in **rpm**.

**Measurement pipeline** (`hrd_radial_measure` 0x2D5B): seek the alignment track and capture **four
read windows** into the image buffer — head 0 reads A/B at `image_buf+0x0000`/`+0x2000`, head 1 at
`+0x4000`/`+0x6000`. `hrd_find_burst` (0x3008) scans each window for the sync burst (three bytes
summing to `0xFF`, ×7) and returns its byte offset. The per-head result is the **difference of the
two burst offsets** (`SBC HL,DE`), cancelling common-mode timing and leaving the radial displacement.
This is repeated **10×** and passed through `hrd_median_filter` (0x3084, bubble-sort + average the
middle samples) to yield the stored `hrd_hd0`/`hrd_hd1` per head.

**The display scale is a ROM constant** — *this resolves the earlier open question.* `hrd_show_scaled`
(0x2CEE) computes **`displayed = raw × K / 10000`** (`mul16`, then `÷ 0x2710`), where `K` is
`hrd_test_tbl[test].scale`. `hrd_test_tbl` is **never written by any code** — it is a static,
ROM-initialised table — so the geometric→display scale is a firmware constant, **not** a value
embedded in the captured disk (as previously suspected). The three radial-displacement tests share
`K = 422` (µm), azimuth uses `K = 696` (angular), and spindle uses `K = 1` (raw RPM — RPM is derived
separately via the 8253, above).

The capture reuses the **normal FDC read path**; the `0x9C` `0x0E→0x0F` strobe seen during it is just
the general `fdc_poll_complete` (0x472D) result-read pulse — one line of the 0x9C addressable latch
(decode **data = bit 0, select = bits [3:1]**: `0x0E`→`0x0F` is a 0→1 edge on select-`111`/line 7;
other lines `001` EPROM/RAM map, `010` write-protect, `100`/`101` datarate, `110` static enable).
See main §3.

---

## D. Serial protocol handlers

Both links polled. TX `0x4E42` (spin TxRDY=bit2), RX `0x4E5A` (RxRDY=bit0, timeout). Autoloader
wrappers 0xD0/0xD4; host 0xD8/0xDC.

**Autoloader client — command+ACK `0x13D9`**: flush RX ×3 → reset cmd-reg → TX byte → RX reply →
compare `'X'` (A=0 ok / 1 timeout / 2 wrong).
- **Only S, C, I, A, R are ever transmitted** `[V]` (exhaustive scan). The **O** and **V** commands are
  never issued by this ROM; the cycle count is an internal 32-bit counter `0x3269/0x326B` bumped per
  successful INSERT.
- **S returns two ASCII hex chars** (e.g. `"0B"`); `0x13FB` decodes to the status byte.
- Connection probe `0x0220` pings with **R**: pure timeout (0x314C=0) → "NOT CONNECTED"; framing bits
  → "COMMUNICATION ERROR".

**Status decode `0x1286` vs ground truth**

| Status | GT meaning | Firmware message | |
|---|---|---|---|
| 0x07 / 0x0B | ok / disk-in-drive | "AL status ok" | match |
| 0x27 | hopper empty | "Hopper empty" | match |
| 0x47 / 0x4B | no-disk / disk fwd | generic "AL error Status .." | no dedicated msg |
| 0x87 / 0x8B | reject-bin jam | "Calibration error" | label differs |
| 0x97 / 0x9B | eject jam | "Eject timeout" | ≈ same fault |
| bit1=0 | hopper seat open | "Hopper not seated" | match |

**Host remote control — the machine is the server.** The two serial links have opposite roles: on
the autoloader link the machine is the **client** (it issues S/C/I/A/R, above); on the host link
(USART 0xD8/0xDC) it is the **server**. A host PC can drive the entire duplication cycle remotely —
download an image, format/write, run a duplication pass, or even upload and execute code — while the
machine just services requests.

`host_dispatch` `0x1E0B` is the server loop: it shows a blinking `"."` heartbeat on the LCD (toggled
`.`/`!`), polls the host link for a command packet, dispatches by opcode, replies, and loops.

- **Command packet** — `host_read_packet` `0x1DF3`, 4 bytes: `{lead byte → E, opcode → D, 16-bit LE
  parameter → HL}` — the **lead byte is read off the wire but never used or validated** (a sync/reserved byte). On a valid packet the dispatcher sets `op_word = opcode` and `run_count = parameter`.
- **Replies** — `'X'` (0x58) = ACK/OK, `'E'` (0x45) = bad packet / framing NAK; a pure RX timeout just
  re-polls (heartbeat). Handlers additionally return a binary **status byte**: 0x00 ok; 0x90 / 0xA0 /
  0xB0 = command error / transfer failed / not-proper-image.

**Opcode table** — dispatch is a linear `CP <op>; JP/JR NZ` chain from `0x1E37`.

*Control opcodes* (explicit handlers):

| Op | Handler | Addr | Action |
|---|---|---|---|
| 0x09 | host_op_start | 0x205C | Reset operation word (`op_word=0`), ACK |
| 0x0A | host_op_image_dl | 0x1E37 | Image download (0xAA55-framed records into banked DRAM) |
| 0x0B | host_op_enter_run | 0x1F9F | Enter RUN mode — `host_mode=0`, install I/O vectors 0x52C9/CB/CD, `JP 0x0161` |
| 0x0C | host_op_ping | 0x204B | Ping / no-op ACK (+ status 0x00) |
| 0x0D | host_op_disk_write | 0x1FC6 | Disk-write / format setup: streams `cfg_flags`+unit, a **write-protect** byte (→ `0x9C` line 2 + `wprot_mode`, `0x200B`), `err_recovery`, then a **24-byte per-head zone table** → `hrd_hd0` — i.e. a host can **define a variable-rate Special format remotely**. Echoes each byte; clears `image_present` |
| 0x0E | host_op_diag_out | 0x2082 | Host↔autoloader serial **bridge** (relays until `'W'`=0x57), diag block via OTIR |
| 0x0F | host_op_load_exec | 0x206F | Load & execute downloaded code (`code_loader` → 0x7800, image 0x8000, `JP (HL)`) |

*Duplication-run opcodes* — anything not matched above falls through to `host_op_begin_run` `0x20E3`,
where **the opcode itself becomes `run_status`** (the operation mode); there is **no unknown-opcode
reject path**:

| Op | Action |
|---|---|
| 0x07 | **BP** duplication run (prints "BP", `run_status=1`, `OUT 0x9C,0x04`, `require_motor_ready`) |
| 0x01–0x06, 0x08 | **FDD** duplication: `run_status = opcode` → `dup_engine_loop` (mode = op-word phase: 1 FWV · 2 WV · 3 Format · 4 Format+V · 6 Write · 8 Verify) |

Reply `'X'`/`'E'` + binary status (0x00 ok; 0x90/0xA0/0xB0 = command error / transfer failed /
not-proper-image). The **I/O-vector mechanism** (`0x4D89`/`0x4C43`/`0x2766` → `0x52C9/CB/CD`) retargets
identical byte-I/O sites between local keypad, autoloader, and host; opcode 0x0B rewrites all three and
jumps to the shared run loop.

---

*Method: each subsystem traced independently then cross-checked; the 0xB0-vs-0x9C banking correction
was verified against the boot DRAM-sizing loop before being folded into the main analysis. Datasheets
used for register-level confirmation: SMC FDC37C65C, µPD8237A DMA, µPD71055 PPI, Z8420 PIO, 8253 PIT,
Z80 CPU, HD44780 LCD — the µPD8237A confirmed the 0x80-base DMA register map and one-channel-per-FDC layout.*
