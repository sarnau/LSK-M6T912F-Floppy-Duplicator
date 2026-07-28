# LSK M6T912F — Disassembly Navigation

Generated from `sourcecode.s` by `navmap.py` — a labeled memory map, a routine
index, and a static call graph. Addresses are ROM offsets. Regenerate with:

```sh
cd disassembly && python3 navmap.py sourcecode.s > navigation.md
```

> Static graph: targets reached only through computed jumps (`JP (HL)`, dispatch
> tables) do not appear as edges, so a routine with **0 callers** may still be a
> jump-table handler. Such tables are called out in the analysis docs.

## 1. Memory map

| Range | Contents |
|---|---|
| `0x0000–0x7FFF` | Program RAM (EPROM shadow — reset copies the 32 KB image into DRAM bank `0xFF`, maps it here, runs from RAM) |
| `0x0000` / `0x0038` | Reset entry / IM 1 interrupt vector (`fdc_isr`) |
| `0x0100` | `main_entry` — post-relocation init and mode select |
| `0x8000–0xFFFF` | Banked window — DRAM image bank selected by `OUT (0xB0)`; banks `0x00–0xFE` = disk image, `0xFF` = program mirror |

**Declared data regions** (from the disassembler):

| Range | Label | Notes |
|---|---|---|
| `0x0029–0x0038` | `padding` |  |
| `0x003B–0x0040` | `padding` |  |
| `0x0046–0x0050` | `padding` |  |
| `0x0084–0x0100` | `padding` |  |
| `0x209C–0x20A9` | `host_ser_blob0` |  |
| `0x20D6–0x20E3` | `host_ser_blob1` |  |
| `0x224F–0x2255` | `padding` |  |
| `0x311C–0x3167` | `cfg_flags` | config flags word: form-factor/density/mode/spindle + max-cyl (bit7 = copy direction) |
| `0x3167–0x319F` | `hrd_desc_tbl` | precomp menu value + serialization-enable bit |
| `0x319F–0x31A3` | `rpm_residual` | spindle index-period timer residual (read back from 8253) |
| `0x31A3–0x31B9` | `hrd_hd1` | HRD measured value for head 1 (um) |
| `0x31B9–0x326E` | `param_tables` |  |
| `0x326E–0x3305` | `fmt_param_tbl` | fmt_param_tbl: 8 built-in disk formats, packed 19-byte BPB { secsz/256, spc, resv:w, nFAT, |
| `0x3305–0x334E` | `fat12_template` |  |
| `0x334E–0x335F` | `fmt_buf1` |  |
| `0x3387–0x33B2` | `fmt_buf2` |  |
| `0x4A54–0x4A58` | `fdc_saved_sp` | saved SP for the LD SP,IX rapid command loader (LD (..),SP / LD SP,(..)); +2 reserved |
| `0x4A58–0x4A59` | `panel_shadow` | port-0xF0 output shadow: panel key-column drive, buzzer bit3 (active-low), status LEDs |
| `0x4A59–0x4A61` | `fdc_drv_state` | FDC driver state: current mode/side byte, scratch pointers and misc flags (0x4A59-0x4A60) |
| `0x4A61–0x4A85` | `fdc_cmd_buf` | 4 command buffers, one per FDC, 9 bytes each; byte0 = last opcode (seek/recal marker for t |
| `0x4A85–0x4AA1` | `fdc_result_buf` | 4 result-phase buffers, one per FDC, 7 bytes each: ST0,ST1,ST2,C,H,R,N from the FDC result |
| `0x4AA1–0x4AA6` | `fdc_result_save` | 0x4AA1 per-FDC "result captured" bits; 0x4AA2/0x4AA4 saved DE/HL across the result-read pa |
| `0x4AA6–0x4AB4` | `sector_size_tbl` | sector-size lookup: 7 words 128<<N (128,256,512,1024,2048,4096,8192); fdc_dma_setup indexe |
| `0x4AB4–0x4ABC` | `fdc_gap_tbl` | format -> gap3/length byte table (8 entries), indexed by format id |
| `0x4ABC–0x4AE9` | `fdc_param_recs` | 9x 5-byte FDC parameter records {b0, rate:word, b3, b4} streamed into an FDC block by copy |
| `0x4AE9–0x4AEA` | `fdc_op_flags` | FDC command-build flags byte |
| `0x4AEA–0x4AEB` | `fdc_opcode_base` | READ/WRITE command opcode base (ORed with 0x40 for MFM before issue) |
| `0x4AEB–0x4B06` | `drive_blk_a` | drive-pair block A (27 bytes): +7 DOR/motor, +8/9 DMA start address (8237 ch0x80), +10/11  |
| `0x4B06–0x4B21` | `drive_blk_b` | drive-pair block B (27 bytes): same layout, 8237 channel 0x82 |
| `0x4B21–0x4B29` | `dma_ptr_save` | 4 words: per-FDC DMA start-address / transfer-count save slots |
| `0x4B29–0x4B89` | `fmt_geom_recs` | fmt_geom_recs: "Special format" per-head data-rate zone tables (default set) = variable-ra |
| `0x4B89–0x4B8A` | `fdc_rate_reg` | current FDC data-rate register bits (ORed then OUT to 0xB1) |
| `0x4B8A–0x4B8B` | `fdc_precomp_reg` | current FDC write-precompensation value (OUT to 0xC2) |
| `0x4B8B–0x4B99` | `ver_loader` |  |
| `0x4DD5–0x4DD9` | `padding` |  |
| `0x4E28–0x4E35` | `al_ser_blob` |  |
| `0x4E35–0x4E42` | `host_ser_blob2` |  |
| `0x4FA9–0x4FAC` | `mon_hexbuf` |  |
| `0x5227–0x522F` | `fdc_flag_tbl` |  |
| `0x52C2–0x52C9` | `menu_scratch` |  |
| `0x52CF–0x52DD` | `ver_bootloader` |  |
| `0x52DD–0x5300` | `format_desc` | format_desc: 18-byte active-format + copy descriptor. Bytes 0-11 = disk geometry (init_for |

**I/O port map** (from the disassembler's `PORTS` table):

| Port | Name |
|---|---|
| `0x40` | drv_lat0 |
| `0x50` | drv_lat1 |
| `0x60` | drv_lat2 |
| `0x70` | drv_lat3 |
| `0x80` | dma0_addr |
| `0x81` | dma0_cnt |
| `0x82` | dma1_addr |
| `0x83` | dma1_cnt |
| `0x84` | dma2_addr |
| `0x85` | dma2_cnt |
| `0x86` | dma3_addr |
| `0x87` | dma3_cnt |
| `0x88` | dma_cmd |
| `0x89` | dma_req |
| `0x8A` | dma_mask1 |
| `0x8B` | dma_mode |
| `0x8C` | dma_clrff |
| `0x8D` | dma_mclr |
| `0x8E` | dma_clrmask |
| `0x8F` | dma_wrmask |
| `0x90` | bulk_data |
| `0x94` | status_in |
| `0x98` | key_scan |
| `0x9C` | ctrl_latch |
| `0xA0` | pit_c0 |
| `0xA4` | pit_c1 |
| `0xA8` | pit_c2 |
| `0xAC` | pit_ctrl |
| `0xB0` | dram_bank |
| `0xB1` | fdc_reg |
| `0xC0` | dram_bank_hi |
| `0xC2` | fdc_precomp |
| `0xC3` | fdc_rate |
| `0xC6` | drive_sel_b |
| `0xD0` | al_data |
| `0xD4` | al_stat |
| `0xD8` | host_data |
| `0xDC` | host_stat |
| `0xE0` | lcd_cmd |
| `0xE8` | lcd_data |
| `0xF0` | panel |

## 2. Routine index

439 named routines (auto `loc_*` labels omitted), sorted by address. *Callers* is the
count of static call/branch sites into the routine.

| Addr | Routine | Callers | Purpose |
|---|---|---|---|
| `0x0022` | `boot_cont` | 0 | boot continuation: also copied to DRAM 0x8022 and re-entered there after banking |
| `0x0050` | `show_model_cycles` | 1 |  |
| `0x0100` | `boot_init` | 1 | main entry after RAM relocation: checksum RAM, init HW, size DRAM, pick operating mode |
| `0x0105` | `boot_checksum` | 0 | sum bytes 0x0100..0x52EF; compare to cksum_ref; mismatch -> CODE TRANSFER ERROR loop |
| `0x0161` | `run_entry` | 3 | run/duplication mode entry (also target of host 0x0B run vector install) |
| `0x01BD` | `show_fdd_seek_error` | 1 | draw "FDD seek error", deselect drives, beep code 5, home LCD, then reset seek/format state |
| `0x01E1` | `reset_seek_state` | 1 | reset seek/format state after error: fmt_mode=0x90, clear flag at 0x3150 |
| `0x0235` | `wait_autoloader_loop` | 3 | top idle loop: 'Wait for autoloader', poll autoloader + host serial commands |
| `0x024D` | `al_connect_probe` | 0 | probe autoloader (ping via R); classify NOT CONNECTED vs COMMUNICATION ERROR |
| `0x02B0` | `show_al_error` | 2 | draw "AL error / Status" line, wait keypress; preserves A across the message (autoloader fault) |
| `0x033D` | `manual_mode` | 2 | MANUAL operation mode top level |
| `0x03A9` | `lcd_home3` | 8 | reset LCD cursor to home (0,0), repeated 3x (multi-line addressing workaround) |
| `0x03B4` | `dram_bank_cfg` | 2 | select DRAM image bank + latch drive config from cfg block |
| `0x03D7` | `ctrl_latch_load` | 1 | restore the PPI Port-C control-latch state (OUT 0x9C, U69 BSR) from saved value |
| `0x03DD` | `dram_test` | 1 | size installed DRAM banks (walk via OUT 0xB0, test @0x8000) -> 'Test dram: N kB' |
| `0x0432` | `fdd_detect` | 1 | detect FDDs, derive media-config index, install phase_handler from phase_handler_tbl |
| `0x047B` | `fdc_cmd_both_drives` | 4 | issue FDC command A to both drives via fdc_op_dispatch; head-select byte from cyl_head bit7 |
| `0x0493` | `edit_num_copies` | 2 | 'No. of copies' editor |
| `0x04C3` | `edit_num_field` | 7 | edit a numeric field on the LCD (cursor on, +/- keys, Enter) |
| `0x05E6` | `acc32_add` | 1 | add 16-bit HL into the 32-bit accumulator at 0x3143/0x3145 (edit-field value builder) |
| `0x05FA` | `num_to_lcd_alt` | 5 | num_to_lcd variant with extra attribute bit (0xC0) selecting alternate LCD line/position |
| `0x05FC` | `num_to_lcd` | 4 | render 16-bit value as right-justified decimal on LCD at position A, field width B, pad char C |
| `0x062F` | `lcd_num_tmpl` | 0 |  |
| `0x063B` | `show_ok_bad_count` | 3 | show run counters on line 2: track_ctr and pass_ctr as two 4-digit decimals (OK/bad tally) |
| `0x0670` | `lcd_clear_line2` | 36 | blank LCD line 2 (ESC 0xC0 home + 20 spaces), preserving AF |
| `0x068D` | `lcd_clear_line1` | 1 | blank LCD line 1 (ESC 0x80 home + 20 spaces) |
| `0x06A8` | `pit_adjust_digits` | 1 | inc/dec an ASCII digit pair (config value at 0x27FC) per cfg_flags bit7 up/down, 0-9 wrap+carry |
| `0x06D9` | `pit_reload_c12` | 2 | reload 8253 counters c1/c2 (control words 0x50,0x90) to restart index timing |
| `0x06E2` | `fdc_step_to_track` | 6 | step drive toward target track A, tracking current track at 0x3133, issuing seeks until reached |
| `0x0709` | `motor_ready_wait` | 6 | spin-up/ready wait: recalibrate+seek both drives, retry up to 5x; returns Z when ready |
| `0x0725` | `fdc_wait_unit1` | 4 | poll FDC unit-1 seek/op completion, looping until done |
| `0x072D` | `seek_both_drives` | 2 | recalibrate+seek unit1 (and unit2 if double-sided), then flag not-ready error |
| `0x074F` | `set_drive_cfg` | 8 | load drv_active_cfg (0x2D active pattern) into both drive-config latches (ports 0x40/0x60); idle pattern is 0x |
| `0x0757` | `drive_cfg_latch` | 8 | write 0x0E to both drive latches (0x40/0x60): deselect / motors-off idle state |
| `0x0760` | `update_ctrl_latch` | 2 | datarate control-latch helper: build an 8255 Bit-Set/Reset byte and OUT to PPI U69 control reg 0x9C (sets one  |
| `0x0777` | `range_table_lookup` | 2 | threshold table lookup: scan B entries at HL, return value C for the band matching input (rate/precomp by cyl) |
| `0x0788` | `dup_engine_loop` | 3 | duplication engine main loop: spin-up, read source, run current phase |
| `0x078B` | `require_motor_ready` | 2 | ensure motor ready via motor_ready_wait; on failure jump to batch error tail 0x10B0 |
| `0x0811` | `show_rpm_low` | 2 | RPM out-of-range warning: A=1 draws "rpm low", A=2 "rpm high", 0 shows nothing |
| `0x0834` | `fdc_build_select` | 4 | build FDC drive/head select byte from unit_sel/cyl_head |
| `0x0940` | `fdc_datarate_precomp` | 0 | program FDC data rate & write-precomp from geometry via range tables; OUT fdc_reg/precomp/rate |
| `0x0A00` | `geom_seek_build` | 0 | geometry: logical block -> CHS via block_to_chs, store into both drive blocks |
| `0x0C27` | `read_both_sides` | 1 | process both disk sides for read: single-sided reads side1 only, else side1 then side2 |
| `0x0C38` | `write_both_sides` | 1 | process both sides for source read into buffer: single reads side1, else both sides |
| `0x0C49` | `check_double_sided` | 2 | determine if current format is double-sided (0x3135 nonzero, or cyl_head code 4/0x0E) |
| `0x0C57` | `show_in_progress` | 3 | draw "in progress" on line 2 (operation running indicator) |
| `0x0E46` | `verify_compare` | 1 | verify: DMA read-back track into 0x5800 scratch, CPI-compare vs DRAM image |
| `0x0E67` | `show_compare_error` | 2 | draw "Compare error", beep code 5, set op_word bit6 (verify-mismatch flag) |
| `0x0E8C` | `wait_read_done` | 2 | wait for FDC read/verify done on unit1 (and unit2 if double-sided); set op_word bits 6/5 on fail |
| `0x1090` | `batch_loop_tail` | 2 | end-of-pass tail: dec run_count, on last pass autoloader-accept, deselect, show OK/bad, wait key |
| `0x10C8` | `al_gate_or_reject` | 1 | if autoloader present route to accept/reject flow, else beep once (buzzer_pulse) and return A=0 |
| `0x10D2` | `al_accept_reject` | 2 | autoloader ACCEPT (mode9): show "ACCEPT", eject good disk, retry build_select+verify up to 20x |
| `0x112D` | `al_cmd_reject` | 4 | autoloader REJECT: show "REJECT", send reject cmd 0x52, await ack with "timeout" handling |
| `0x1198` | `al_calibrate` | 0 | send autoloader calibrate command (0x43) with ack; sets carry (error-exit tail) |
| `0x11A0` | `is_op_mode9` | 4 | test whether op_word low nibble == 9 (autoloader run mode); returns Z if so |
| `0x11A8` | `al_present_gate` | 5 | gate on autoloader-present flag (al_present); returns Z if no autoloader attached |
| `0x11AD` | `al_insert_disk` | 1 | enter insert/read-source flow with retry_ctr preset to 1 (single-shot insert) |
| `0x11B4` | `read_source` | 3 | read source disk (autoloader-aware): command INSERT, spin up, verify bank, retry on rpm-low/lost-data |
| `0x11FC` | `al_insert` | 2 | send autoloader insert command (0x49), wait ready; "timeout" message on no response |
| `0x122B` | `show_lost_data` | 3 | fatal image-lost error: hex-dump 0x52C7, draw "Lost data", then halt (spin forever) |
| `0x126D` | `al_reject` | 0 | send autoloader reject(0x52)+calibrate(0x43) with ack; on ok re-insert per retry_ctr |
| `0x1286` | `al_status_decode` | 2 | decode autoloader status byte -> on-screen message (bit1 seated, hi-nibble class) |
| `0x13D9` | `al_cmd_ack` | 4 | send 1-char autoloader command in B, read reply; 'X'=ok/1=timeout/2=other |
| `0x13E5` | `al_rx_response` | 2 | receive one autoloader response byte into fmt_mode; return 0 if 'X' ack, else error code 1/2 |
| `0x13FB` | `al_cmd_status` | 3 | autoloader S(tatus): read 2 ASCII-hex chars, decode to status byte |
| `0x142B` | `ascii_hex_to_nibble` | 1 | convert one ASCII hex character in A to its 0-15 nibble value |
| `0x1433` | `al_flush_rx` | 1 | drain 3 stale bytes from autoloader SIO RX (0xD0) and reset its status |
| `0x1444` | `phase_handler_tbl` | 0 |  |
| `0x1454` | `spfmt_menu_a` | 0 |  |
| `0x1472` | `spfmt_menu_c` | 0 |  |
| `0x1480` | `spfmt_menu_d` | 0 |  |
| `0x148E` | `spfmt_menu_b` | 0 |  |
| `0x149C` | `spfmt_menu_e` | 0 |  |
| `0x14AA` | `submenu_a` | 0 |  |
| `0x14B8` | `submenu_b` | 0 |  |
| `0x14CA` | `submenu_c` | 0 |  |
| `0x14E4` | `submenu_d` | 0 |  |
| `0x14EE` | `submenu_e` | 0 |  |
| `0x14FC` | `ops_menu` | 0 |  |
| `0x1522` | `hrd_test_menu` | 0 |  |
| `0x1540` | `hrd_menu` | 0 | print "HRD diagnostics" menu title |
| `0x1555` | `special_formats_menu` | 0 | print "Special formats" menu title |
| `0x156A` | `menu_show_a` | 0 | run special-format submenu A (spfmt_menu_a) via menu_run |
| `0x1571` | `menu_show_b` | 0 | run special-format submenu B (spfmt_menu_b) via menu_run |
| `0x1578` | `menu_show_c` | 0 | run special-format submenu C (spfmt_menu_c) via menu_run |
| `0x157F` | `menu_show_d` | 0 | run special-format submenu D (spfmt_menu_d) via menu_run |
| `0x1586` | `menu_show_e` | 0 | run special-format submenu E (spfmt_menu_e) via menu_run |
| `0x158D` | `spfmt_show_01` | 0 | display "Special format No. 1" screen (selects number string, stores cyl_head to 0x3165) |
| `0x1592` | `spfmt_show_02` | 0 | display "Special format No. 2" screen (shared No.-N display code) |
| `0x1597` | `spfmt_show_03` | 0 | display "Special format No. 3" screen (shared No.-N display code) |
| `0x159C` | `spfmt_show_04` | 0 | display "Special format No. 4" screen (shared No.-N display code) |
| `0x15A1` | `spfmt_show_05` | 0 | display "Special format No. 5" screen (shared No.-N display code) |
| `0x15A6` | `spfmt_show_06` | 0 | display "Special format No. 6" screen (shared No.-N display code) |
| `0x15AB` | `spfmt_show_07` | 0 | display "Special format No. 7" screen (shared No.-N display code) |
| `0x15B0` | `spfmt_show_08` | 0 | draw 'Special format No. 8' menu title, latch cyl_head into 0x3165 (slot 8 of 8-16 chain) |
| `0x15B5` | `spfmt_show_09` | 0 | draw 'Special format No. 9' menu title, latch cyl_head into 0x3165 |
| `0x15BA` | `spfmt_show_10` | 0 | draw 'Special format No.10' menu title, latch cyl_head into 0x3165 |
| `0x15BF` | `spfmt_show_11` | 0 | draw 'Special format No.11' menu title, latch cyl_head into 0x3165 |
| `0x15C4` | `spfmt_show_12` | 0 | draw 'Special format No.12' menu title, latch cyl_head into 0x3165 |
| `0x15C9` | `spfmt_show_13` | 0 | draw 'Special format No.13' menu title, latch cyl_head into 0x3165 |
| `0x15CE` | `spfmt_show_14` | 0 | draw 'Special format No.14' menu title, latch cyl_head into 0x3165 |
| `0x15D3` | `spfmt_show_15` | 0 | draw 'Special format No.15' menu title, latch cyl_head into 0x3165 |
| `0x15D8` | `spfmt_show_16` | 0 | draw 'Special format No.16' menu title, latch cyl_head into 0x3165 |
| `0x166B` | `spfmt_apply_01` | 0 | apply special-format slot 1 as DD: cyl_head=1, clear density bit, run fmt_apply |
| `0x1677` | `spfmt_apply_02` | 0 | apply special-format slot 2 as DD: cyl_head=2, clear density bit, run fmt_apply |
| `0x167C` | `spfmt_apply_03` | 0 | apply special-format slot 3 as DD: cyl_head=3, clear density bit, run fmt_apply |
| `0x1681` | `spfmt_apply_04` | 0 | apply special-format slot 4 as HD: cyl_head=4, set density bit, run fmt_apply |
| `0x1686` | `spfmt_apply_05` | 0 | apply special-format slot 5 as HD: cyl_head=5, set density bit, run fmt_apply |
| `0x168B` | `spfmt_apply_06` | 0 | apply special-format slot 6 as HD: cyl_head=6, set density bit, run fmt_apply |
| `0x1690` | `spfmt_apply_07` | 0 | apply special-format slot 7 as HD: cyl_head=7, set density bit, run fmt_apply |
| `0x1695` | `spfmt_apply_08` | 0 | apply special-format slot 8: set cyl_head=8, run fmt_apply core (no density change) |
| `0x1699` | `spfmt_apply_09` | 0 | apply special-format slot 9: set cyl_head=9, run fmt_apply core (no density change) |
| `0x169D` | `spfmt_apply_10` | 0 | apply special-format slot 10: set cyl_head=10, run fmt_apply core |
| `0x16A1` | `spfmt_apply_11` | 0 | apply special-format slot 11: set cyl_head=11, run fmt_apply core |
| `0x16A5` | `spfmt_apply_12` | 0 | apply special-format slot 12: set cyl_head=12, run fmt_apply core |
| `0x16A9` | `spfmt_apply_13` | 0 | apply special-format slot 13: set cyl_head=13, run fmt_apply core |
| `0x16AD` | `spfmt_apply_14` | 0 | apply special-format slot 14: set cyl_head=14, run fmt_apply core |
| `0x16B1` | `spfmt_apply_15` | 0 | apply special-format slot 15: set cyl_head=15, run fmt_apply core |
| `0x16B5` | `spfmt_apply_16` | 0 | apply special-format slot 16: set cyl_head=16, run fmt_apply core |
| `0x16B9` | `fmt_35_720k` | 0 | print media spec line '3.5" 720kB 9sec 80cyl 2h' for the format-select menu |
| `0x16E7` | `fmt_35_144m` | 0 | print media spec line '3.5" 1.44MB 18sec 80cyl 2h' for the format-select menu |
| `0x1715` | `fmt_525_360k` | 0 | print media spec line '5.25" 360kB 9sec 40cyl 2h' |
| `0x1743` | `fmt_525_180k` | 0 | print media spec line '5.25" 180kB 9sec 40cyl 1h' |
| `0x1771` | `fmt_525_320k` | 0 | print media spec line '5.25" 320kB 8sec 40cyl 2h' |
| `0x179F` | `fmt_525_160k` | 0 | print media spec line '5.25" 160kB 8sec 40cyl 1h' |
| `0x17CD` | `fmt_525_720k` | 0 | print media spec line '5.25" 720kB 9sec 80cyl 2h' |
| `0x17FB` | `fmt_525_12m` | 0 | print media spec line '5.25" 1.2MB 15sec 80cyl 2h' |
| `0x1829` | `fmt_apply_dd` | 0 | enter fmt_apply selecting DD density: cyl_head=0, clear format_desc[11] bit7, sync image flag |
| `0x1841` | `fmt_apply_hd` | 0 | enter fmt_apply selecting HD density: cyl_head=0, set format_desc[11] bit7, sync image flag |
| `0x1859` | `fmt_apply` | 3 | format-apply core: program both FDCs, build format block + sector layout, warn on non-std max cyl, run ops_men |
| `0x190D` | `sel_model_1` | 0 | pick drive model 1 (unit_sel low bits=01) then run fmt_apply |
| `0x1917` | `sel_model_2` | 0 | pick drive model 2 (unit_sel low bits=10) then run fmt_apply |
| `0x1921` | `sel_model_3` | 0 | pick drive model 0/3 (clear unit_sel low bits) then run fmt_apply |
| `0x1929` | `clear_image_present` | 4 | invalidate cached RAM disk image by zeroing image_present (AF preserved) |
| `0x1930` | `show_insert_model` | 0 | draw 'Insert model' prompt; decode model-ID sense (0x52E8) to 528/526/325-400 handler else Not available |
| `0x1956` | `show_not_available` | 1 | draw 'Not available' on LCD line 2 and home cursor |
| `0x19D2` | `show_read_source` | 0 | draw 'Read source disk'; show 'data image present' or 'insert source disk' per image_present |
| `0x1A25` | `show_copy_fwv` | 0 | print 'Format Write Verify' copy-mode menu label |
| `0x1A40` | `show_copy_wv` | 0 | print 'Write and verify' copy-mode menu label |
| `0x1A58` | `show_copy_crc` | 0 | print 'CRC check' copy-mode menu label |
| `0x1A69` | `show_copy_fv` | 0 | print 'Format and verify' copy-mode menu label |
| `0x1A82` | `show_copy_wd` | 0 | print 'Write disk' copy-mode menu label |
| `0x1A94` | `set_error_recovery` | 0 | force error-recovery mode (0x314A=3), run duplication then image-compare pass, restore, set image_present on s |
| `0x1AED` | `start_run_op` | 2 | set op_word=A and run_count=HL, then enter dup_engine_loop to run the duplication op |
| `0x1AF6` | `start_copy_fwv` | 0 | start Format-Write-Verify copy (op_word=1); if no image show 'data image missing', else prompt copy count and  |
| `0x1CA1` | `jump_phase_handler` | 1 | indirect jump through phase_handler vector to the current duplication-phase routine |
| `0x1CA5` | `check_cyl_limit` | 3 | test requested cyl in HL against max-cyl 0x3143; returns in-range via M flag (no carry if OK) |
| `0x1CAC` | `show_out_of_range` | 2 | draw 'Out of range' on LCD line 2, home cursor, set carry to reject the value |
| `0x1CC8` | `start_copy_wv` | 0 | start Write-and-Verify copy (op_word=2) via the shared start_copy_fwv path |
| `0x1CCD` | `start_copy_format` | 0 | start Format-only copy (op_word=3), jump to copy-count prompt and run |
| `0x1CDB` | `start_copy_fmtverify` | 0 | FORMAT: if cyl_head!=0 skip; else build blank FAT12 image in DRAM bank 0xFE from ROM template, stamp 0x55AA, z |
| `0x1CE2` | `format_track` | 0 | FORMAT: build FAT12 boot sector from ROM template, stamp 0x55AA, format tracks |
| `0x1D92` | `start_copy_write` | 0 | start a 'Copy: write' run (start_run_op with mode 6) |
| `0x1D97` | `show_copy_bitverify` | 0 | draw the 'Bit per bit verify' status line |
| `0x1DAF` | `start_copy_verify` | 0 | start a 'Copy: verify' run (start_run_op with mode 8) |
| `0x1DB4` | `show_clean_fdd` | 0 | draw the 'Cleaning FDD' status line |
| `0x1DC6` | `abort_check` | 1 | if autoloader disk present launch run op 9, else fall through to show_abort prompt |
| `0x1DCB` | `show_abort` | 2 | show 'Abort' on line2, beep once, reset LCD cursor; returns fmt_mode |
| `0x1DF3` | `host_read_packet` | 1 | read 4-byte host command packet (opcode in D) |
| `0x1E01` | `host_rx_word` | 2 | read a little-endian 16-bit word from host SIO into E,D (abort on rx error) |
| `0x1E0B` | `host_dispatch` | 10 | host remote-control server dispatcher (opcode table) |
| `0x1E37` | `host_op_image_dl` | 0 | host op 0x0A: download disk image over bulk channel - AA55 sync, validate geometry header, stream tracks into  |
| `0x1F9F` | `host_op_enter_run` | 1 | host op 0x0B: enter interactive run mode - install iovec callbacks (key/out/annun) and JP run_entry |
| `0x1FC6` | `host_op_disk_write` | 1 | host op 0x0D: receive format params from host (each byte echoed via host_rx_echo) - cfg_flags+unit -> unit_sel |
| `0x203E` | `host_rx_echo` | 4 | receive one byte from host and echo it back as ack (returns byte in B, NZ on error) |
| `0x204B` | `host_op_ping` | 1 | host op 0x0C: ping - ack with 0x58 then 0x00 |
| `0x205C` | `host_op_start` | 1 | host op 0x09: clear op_word, ack, run abort_check gate then execute run |
| `0x206F` | `host_op_load_exec` | 1 | host op 0x0F: ack then code_loader (download+execute code image), loop dispatch |
| `0x2082` | `host_op_diag_out` | 0 | host op 0x0E: diagnostic bridge - relay bytes between host (port DC) and autoloader SIO |
| `0x20E3` | `host_op_begin_run` | 1 | start a duplication/blank-check run - ack, show 'FDD', clear fmt_mode; op 0x07 sets up blank-pass ('BP') |
| `0x2134` | `bulk_read_bytes` | 3 | read B*2 bytes from the bulk-image channel into (HL++) |
| `0x2141` | `bulk_validate` | 1 | compare received image geometry header (0x334F+1/+2) with stored (0x3133/0x3135); update and return NZ if chan |
| `0x2161` | `bulk_read_word` | 2 | read a little-endian 16-bit word from the bulk-image channel into DE |
| `0x216A` | `bulk_read_byte` | 4 | read one byte from host bulk-image channel (0x90/0x94/0x9C handshake) |
| `0x2196` | `bulk_sync_aa55` | 3 | wait for 0xAA 0x55 sync word on the bulk-image channel |
| `0x21A9` | `code_loader` | 1 | code loader: copy 256-byte bootstrap to 0x7800, verify image to 0x8000, JP |
| `0x21CE` | `dl_code` | 1 | downloaded-code block (copied to 0x7800 by host opcode 0x0F); runs from RAM, labeled at its ROM source |
| `0x222D` | `dl_boot_entry_a` | 1 | download entry A (runs at 0x785F after relocation to 0x7800) |
| `0x2236` | `dl_boot_entry_b` | 5 | download entry B (runs at 0x7868 after relocation to 0x7800) |
| `0x2255` | `show_curr_prefix` | 6 | clear line2 and draw the '(curr.= ' prefix for a config current-value readout |
| `0x2267` | `config_menu` | 1 | CONFIG menu top level |
| `0x231E` | `config_err_recovery` | 3 | config menu item: toggle data-error-recovery (0x314A=1 enable / 3 disable) via ENTER/EXIT prompt |
| `0x2369` | `config_serialization` | 2 | config menu item: toggle serialization (hrd_desc_tbl bit1 & cfg_byte bit1) via ENTER/EXIT prompt |
| `0x23BF` | `config_copy_dir` | 2 | config menu item: toggle copy direction (cfg_flags bit7: in->out / out->in) |
| `0x2409` | `config_max_cyl` | 2 | config menu item: edit maximal cylinder - edit_num_field, clamp to 0x55, store in cfg_flags preserving bit7 |
| `0x2453` | `show_max_cyl` | 1 | render 'Maximal cylinder' header + current value from 0x4AFC/cfg_flags |
| `0x249E` | `config_wprotect` | 3 | config menu item: toggle write-protect recognition (ctrl_latch bit0 / 0x3155) |
| `0x24EC` | `show_wprotect` | 2 | render 'Write protect (curr.= recognize/unrecognize)' from key_scan bit2 |
| `0x252C` | `show_copy_dir` | 2 | render 'Copy direction (curr.= in->out/out->in)' from cfg_flags bit7 |
| `0x2569` | `show_err_recovery` | 2 | render 'Data error recovery (curr.= enable/disable)' from 0x314A |
| `0x25A5` | `show_serial_batch` | 2 | render 'Serialization (curr.= enable/disable)' from hrd_desc_tbl bit1 |
| `0x25C1` | `show_batch` | 0 | draw the 'Batch processing' menu header |
| `0x25D7` | `start_batch` | 0 | batch-processing entry: gate on autoloader-present, else show 'not available' |
| `0x2707` | `drive_block_ptr` | 1 | compute pointer to a drive's 0x18-byte record in the table at 0x4B29 (index from unit-select bits) |
| `0x2716` | `drive_index_bits` | 2 | map unit-select byte bits7,3 to a 0..3 drive index in E |
| `0x2725` | `drive_block_pos` | 2 | compute a drive's record offset (0x18*index + 4), returns low byte in C |
| `0x2735` | `eeprom_transfer` | 10 | bidirectional CAT24C02 EEPROM block transfer (NOT save-only). A=direction (0=load EEPROM->RAM, else save RAM-> |
| `0x2766` | `beep` | 10 | beep via the iovec_beep vector (default buzzer_beep); beep count encodes the alert/error code |
| `0x276A` | `hrd_head_edit` | 1 | BC-preserving wrapper to edit the two-head data-rate zone table (per head: 6 entries { start cyl : low byte, d |
| `0x2770` | `hrd_row_head1` | 2 | render head-1 row of the head parameter table (sets prefix '1', buffer 0x31AF) |
| `0x277C` | `hrd_row_head0` | 2 | render head-0 row: print 'H C-0' grid, then the zone entries - low byte of each word = value (hrd_fmt_num), hi |
| `0x27E7` | `hrd_fmt_num` | 1 | convert a byte to decimal (bin2dec_clear) and patch the digits into the head-table print buffer |
| `0x27F5` | `hrd_emit_num` | 5 | print a formatted head-table number cell (BC-preserving lcd_print of patched inline bytes) |
| `0x27F9` | `lcd_val_tmpl` | 0 |  |
| `0x2800` | `hrd_edit_head_pair` | 1 | render both head rows (0 and 1) of the head parameter table with framing escapes |
| `0x281D` | `hrd_edit_head_row` | 1 | render one head row (0 or 1) computing per-column LCD cursor positions |
| `0x28F4` | `save_cfg_block` | 3 | persist the 2-byte cfg_flags block to serial EEPROM (eeprom_transfer write mode) |
| `0x28F8` | `show_media_status` | 2 | render media summary from cfg_byte: size, density, S/N and HS/NS/DS; self-patches LCD cursor |
| `0x2946` | `show_size_density` | 1 | print size+density portion of media summary (5.25"/3.5", HD/DD/QD) from cfg_byte bits3,7,6 |
| `0x298B` | `show_ff_35` | 0 | draw 'Form factor 3.5"' menu header |
| `0x29A1` | `show_ff_525` | 0 | draw 'Form factor 5.25"' menu header |
| `0x29B8` | `show_density_dd` | 0 | draw 'Double density' menu header |
| `0x29CC` | `show_density_hd` | 0 | draw 'High density' menu header |
| `0x29DE` | `show_mode_simul` | 0 | draw 'Simultaneous mode' menu header |
| `0x29F5` | `show_mode_normal` | 0 | draw 'Normal mode' menu header |
| `0x2A06` | `show_spindle_high` | 0 | draw 'High spindle speed' menu header |
| `0x2A1E` | `show_spindle_normal` | 0 | draw 'Normal spindle speed' menu header |
| `0x2A38` | `show_spindle_double` | 0 | draw 'Double spindle speed' menu header |
| `0x2A5E` | `set_ff_35` | 0 | set config form factor to 3.5" (cfg_ptr: RES bit3, SET bit6, clear bit1) |
| `0x2A67` | `set_ff_525` | 0 | media-config toggle: select 5.25" form-factor (cfg flags SET3/RES6/RES1), then refresh LCD |
| `0x2A73` | `set_density_dd` | 0 | media-config toggle: select DD/double density (cfg flags RES7), then refresh LCD |
| `0x2A7B` | `set_density_hd` | 0 | media-config toggle: select HD/high density (cfg flags SET7/SET6), then refresh LCD |
| `0x2A85` | `set_mode_simul` | 0 | media-config toggle: enable simultaneous copy mode (cfg flags SET4), refresh LCD |
| `0x2A8D` | `set_mode_normal` | 0 | media-config toggle: select normal copy mode (cfg flags RES4), refresh LCD |
| `0x2A95` | `set_spindle_high` | 0 | media-config toggle: high spindle speed (cfg flags RES2/SET5), refresh LCD |
| `0x2A9F` | `set_spindle_normal` | 0 | media-config toggle: normal spindle speed (cfg flags RES2/RES5), refresh LCD |
| `0x2AA8` | `set_spindle_double` | 0 | media-config toggle: double spindle speed (cfg flags SET2/RES5), refresh LCD |
| `0x2ACB` | `eeprom_write` | 2 | bit-bang serial EEPROM: I2C start, control 0xA0 (write), then clock data byte E out MSB-first |
| `0x2AD4` | `eeprom_send_byte` | 3 | bit-bang one byte to the serial config EEPROM |
| `0x2AEF` | `eeprom_clk_idle` | 4 | return bit-banged I2C bus to idle: SCL low, SDA released high, then pulse SCL high w/ settle |
| `0x2AF5` | `eeprom_clk_high` | 3 | drive I2C SCL high on panel latch (bit5 of 0x4A58/port F0) with a short settle delay |
| `0x2B09` | `i2c_scl_lo` | 4 | drive I2C SCL low (clear bit5 of panel latch 0x4A58, OUT port F0) |
| `0x2B1D` | `i2c_sda_hi` | 4 | release I2C SDA high (set bit4 of panel latch 0x4A58, OUT port F0) |
| `0x2B2B` | `i2c_sda_lo` | 3 | pull I2C SDA low (clear bit4 of panel latch 0x4A58, OUT port F0) |
| `0x2B39` | `i2c_start` | 2 | I2C start condition (config EEPROM) |
| `0x2B3E` | `eeprom_io` | 3 | finish an EEPROM byte transfer: emit ACK clock, release SDA, then delay |
| `0x2B4D` | `i2c_ack` | 2 | generate I2C ACK bit: SCL low, SDA low, then pulse SCL high |
| `0x2B55` | `eeprom_read` | 1 | EEPROM random read: send word address via eeprom_write, then repeated-start read (0xA1) |
| `0x2B5E` | `i2c_read_start` | 2 | issue I2C (re)start and send control byte 0xA1 to address EEPROM for reading |
| `0x2B66` | `i2c_read_byte` | 2 | read one byte from the I2C config EEPROM |
| `0x2B83` | `fdd_geom_index` | 1 | map media/geometry config to a drive-geom table index; for cfg==4 add unit 0-3, else code 7/6/3 |
| `0x2BA5` | `track_buf_ptr` | 2 | compute track-image buffer pointer: derive head via block_to_chs, then scale by track size |
| `0x2BAB` | `track_ptr_scale` | 1 | advance HL by (A-1)*track_size (0x52E0) to reach a track's image slot; returns head in A |
| `0x2BB7` | `geom_sector_calc` | 1 | from the BPB record (IX = installed boot-sector BPB, not format_desc): IX+13/+15 give sectors-per-track/interl |
| `0x2BD1` | `hrd_radial_a` | 0 | HRD radial-alignment test (head variant a) |
| `0x2BDA` | `hrd_radial_b` | 0 | HRD radial-alignment diag: show header, then display drive-B radial reading (index 1) |
| `0x2BE3` | `hrd_radial_c` | 0 | HRD radial-alignment diag: show header, then display radial reading index 2 |
| `0x2BEC` | `show_radial_align` | 3 | print the radial-alignment test header line on the LCD |
| `0x2C04` | `hrd_show_radial` | 3 | read radial measurement byte (via hrd_radial_ptr[B]) and format it to the LCD |
| `0x2C1E` | `hrd_radial_ptr` | 3 | return pointer to the radial-measurement record for index B (index 0 -> 0x3179) |
| `0x2C35` | `hrd_show_ecc` | 0 | print the ECC diagnostic test header line on the LCD |
| `0x2C47` | `hrd_show_azimuth` | 0 | print the azimuth-alignment test header line on the LCD |
| `0x2C59` | `hrd_show_positioner` | 0 | print the head-positioner test header line on the LCD |
| `0x2C76` | `hrd_show_spindle` | 0 | print the spindle-speed test header line on the LCD |
| `0x2CAC` | `hrd_run_a` | 0 | HRD alignment-run entry (variant A): set test index 1, fall into measure+display tail |
| `0x2CB0` | `hrd_run_b` | 0 | HRD alignment-run entry (variant B): set test index 2, fall into measure+display tail |
| `0x2CB4` | `hrd_run_c` | 0 | HRD alignment-run entry (variant C): set test index 0/flag 1, fall into measure+display tail |
| `0x2CBB` | `hrd_run_d` | 0 | HRD alignment-run entry (variant D): set test index 0/flag 2, fall into measure+display tail |
| `0x2CC1` | `hrd_run_e` | 0 | HRD alignment run: measure radial, print head0/head1 scaled values, then jump to test's handler |
| `0x2CEE` | `hrd_show_scaled` | 2 | scale a signed measurement to display units: value * K / 10000, K = hrd_test_tbl[test].scale (ROM const: 422 r |
| `0x2D2C` | `hrd_rec_ptr` | 3 | index into the per-test result record table (stride 5) selected by hrd_test_idx |
| `0x2D5B` | `hrd_radial_measure` | 2 | HRD alignment measure: seek+capture 4 windows (hd0 A/B @ image_buf+0/+0x2000, hd1 A/B @ +0x4000/+0x6000); per- |
| `0x2E25` | `hrd_hysteresis` | 0 | HRD positioner hysteresis: step in/out, difference of approach positions (um) |
| `0x2E72` | `hrd_spindle_rpm` | 0 | HRD spindle RPM: time index period (8253 c1/c2), RPM = 9230769/ticks |
| `0x2EBA` | `hrd_seek_read` | 1 | HRD read-back: step both heads to cyl 0x3133, arm per-drive DMA, read all sides, CRC-verify, build 4-bit succe |
| `0x2FC0` | `hrd_read_verify` | 2 | wait for FDC read to complete, then CRC/status-check fdc0_result via chk_fdc_crc |
| `0x2FD4` | `hrd_result_verify` | 1 | verify fdc0_result: normal termination (ST0&0xC0==0x40) plus sector/data-mark bits set |
| `0x2FDC` | `chk_fdc_crc` | 1 | validate FDC 7-byte result: ST0 top bits==0x40 and bit5 of ST1/ST2 set (good termination) |
| `0x2FF1` | `fdc_set_xfer_cnt` | 2 | store transfer sector count A into per-drive blocks and derived end-count (0x4AFF-1) fields |
| `0x3008` | `hrd_find_burst` | 1 | scan captured read data for alignment sync bursts, return byte offset |
| `0x3025` | `hrd_disp_radial` | 0 |  |
| `0x3040` | `hrd_disp_ecc` | 0 |  |
| `0x304A` | `hrd_disp_azimuth` | 0 |  |
| `0x3060` | `hrd_disp_positioner` | 0 |  |
| `0x307A` | `show_rpm_suffix` | 1 | print the RPM units suffix string on the LCD |
| `0x3084` | `hrd_median_filter` | 1 | median filter: bubble-sort B signed 16-bit samples, sum the middle ones and divide (sign-preserved) |
| `0x30EB` | `neg16` | 3 | negate 16-bit value in HL (compute 0 - HL) |
| `0x30F4` | `config_fdd_menu` | 0 |  |
| `0x311A` | `cfg_ptr` | 0 | pointer to the active config byte (set/reset by the config toggles) |
| `0x33B2` | `fdc_op_dispatch` | 3 | top-level FDC op dispatcher: mask op (A&0x7F), pick drive block A/B from B.bit0, decode class B&0xE0 to a hand |
| `0x3406` | `fdc_format_build` | 1 | build FDC format command parameters (rate/precomp/sector fields) |
| `0x34A2` | `fdc_build_20` | 0 | op-word bits7-5=0x20 handler: set FDC pending, H=2, rejoin build at loc_3411 |
| `0x34AA` | `fdc_build_40` | 0 | op-word bits7-5=0x40 handler: build write/verify FDC rate+precomp+gap params |
| `0x34F9` | `fdc_build_60` | 0 | op-word bits7-5=0x60 handler: H=2, enter the 0x40 build body at loc_34B2 |
| `0x34FD` | `fdc_build_80` | 0 | op-word bits7-5=0x80 handler: build params with unit_sel-dependent pending, alt density |
| `0x357C` | `fdc_build_A0` | 0 | op-word bits7-5=0xA0 handler: H=2, enter the 0x80 build body at loc_3505 |
| `0x3580` | `fdc_build_C0` | 0 | op-word bits7-5=0xC0/0xE0 handler: JP fdc_format_build |
| `0x35AA` | `fdc_sub_jmptbl` | 0 | JP jump-table indexed by sub-command (C-1): 3-byte JP entries dispatched by JP (HL) @0x35A9 |
| `0x370E` | `panel_bit6_on` | 5 | assert panel latch bit6 (0x40) via port F0 (drive/head control line) |
| `0x371B` | `clr_ctrl_bit6` | 1 | clear panel latch bit6 (0x40) via port F0 |
| `0x3723` | `set_fdc_pending` | 5 | set the FDC-command-pending flag (0x4AE9 = 1) |
| `0x372B` | `clr_fdc_pending` | 12 | clear the FDC-command-pending flag (0x4AE9 = 0) |
| `0x372F` | `copy_fdc_params` | 11 | copy geometry params (sector/size fields) from IX format descriptor into IY drive block |
| `0x3751` | `fdc_dma_from_blk` | 2 | arm DMA for a track: compute byte count from block sector range, call fdc_dma_setup, store count and count*4-1 |
| `0x3784` | `fdc_home_head` | 1 | home head to track 0: pulse ~10 single-steps then step until track-0 sense, confirm via fdc_sense_ready |
| `0x37C6` | `fdc_step_pulse` | 2 | issue one FDC step/seek pulse (fdc_send_seek A=1) and poll for completion |
| `0x37DB` | `index_period_timer` | 2 | measure spindle index period via index sensor + PIT c1/c2, compare vs min/max (0x4AA2/0x4AA4) to validate RPM |
| `0x394C` | `fdc_recal_seek` | 1 | prep recal/seek step params: pick step-rate C by drive index (unit_sel) & 0x4A58 cfg, DE=target track per side |
| `0x399E` | `fdc_recal_wrap` | 1 | FDC specify wrapper: set step rate, issue specify (0x07); folds in bit0 of drv_active_cfg (const enable, not p |
| `0x39A0` | `fdc_recalibrate` | 0 | build+issue FDC RECALIBRATE (opcode 0x07) to both drives of a pair |
| `0x3A18` | `fdc_send_dma` | 4 | arm single-FDC DMA read (4 desc, cnt 0x0C): pick blk A/B by A==1, set bank/drive latch, exec via SP-swap |
| `0x3A83` | `fdc_read_dual` | 4 | read both drives at once: set dram_bank+drive_sel_b, arm DMA ch1(blkA)/ch2(blkB) reads, exec via SP-swap |
| `0x3AF6` | `fdc_dma_read2` | 1 | entry into fdc_send_dma (single-FDC DMA read) with command bit (0x80) masked off A |
| `0x3AFE` | `fdc_read_dual2` | 1 | dual-drive DMA read entry: jumps into fdc_read_dual body (both FDCs simultaneously) |
| `0x3B04` | `fdc_read_cmd` | 6 | begin FDC read: enable panel bus, select side1, set cmd tag 0x26 (read-data MFM) in 0x4AEA, build R/W cmd bloc |
| `0x3B24` | `fdc_write_poll` | 3 | issue FDC write via DMA then wait for completion |
| `0x3B2B` | `fdc_write_dma` | 1 | arm single-FDC DMA write (8 desc): pick blk A/B by A==1, set bank/drive latch, exec via SP-swap |
| `0x3B72` | `fdc_write_dual` | 2 | write both drives via DMA then wait for completion |
| `0x3B78` | `fdc_write_both` | 1 | write both drives at once: set dram_bank+drive_sel_b, arm DMA ch1(blkA)/ch2(blkB) writes (8 desc), exec |
| `0x3BE9` | `fdc_wr_side0` | 2 | begin FDC write side0: select side lo, set cmd tag 0x05 (write-data), decode drive to result buf, save SP |
| `0x3BEE` | `fdc_wr_side1` | 2 | begin FDC write side1: select side hi, set cmd tag 0x05 (write-data), decode drive to result buf |
| `0x3BF5` | `fdc_write_cmd` | 0 | FDC write-command core: set cmd tag 0x05, decode drive via key_decode, select fdc0/1/2/3 result buffer |
| `0x3BFB` | `fdc_build_rw_cmd` | 1 | build 9-byte FDC READ/WRITE command {cmd,HD,C,H,R,N,EOT,GPL,DTL} and stream it |
| `0x3C7F` | `fdc_format_cmd2` | 1 | format-command entry for drive-pair (B=2), falls into fdc_format_cmd |
| `0x3C86` | `fdc_format_cmd` | 2 | issue FDC format-track: decode drive (B), enable bus+select side0, exec via SP-swap into result buf |
| `0x3CD3` | `fdc_specify_dor` | 1 | build FDC specify/step params for both drives from step-rate/HUT state into per-side cmd blocks, set irq bits  |
| `0x3D44` | `fdc_seek_write_wrap` | 1 | issue seek via DMA then wait for completion |
| `0x3D4B` | `fdc_seek_dma` | 1 | arm FDC seek via DMA (8 desc): pick blk A/B by A bit0, set bank/drive latch, exec via SP-swap |
| `0x3D95` | `fdc_read_track` | 1 | read a full track: prep DMA read then poll completion in a timeout-guarded loop |
| `0x3DB9` | `fdc_read_dma_prep` | 2 | prep FDC DMA read: verify drive ready, OR-in irq bits 0xF0, reset all 4 fdc result buffers |
| `0x3E00` | `fdc_seek_write_dma` | 0 | seek+write both drives: send specify, arm DMA ch1(0x81)/ch2(0x82) 8 desc, exec via SP-swap |
| `0x3E64` | `fdc_dma_exec` | 1 | arm FDC DMA read then wait for completion |
| `0x3E6B` | `fdc_dma_arm2` | 2 | arm FDC DMA read: check drive ready, if ready reset result buffers then proceed |
| `0x3EEE` | `fdc_write_both_wrap` | 1 | write both drives via DMA then poll completion with timeout |
| `0x3EF4` | `fdc_write_dma_both` | 1 | write both drives via DMA: set dram_bank+drive_sel_b, arm ch1/ch2 8-desc writes, exec via SP-swap |
| `0x3F53` | `fdc_read_src` | 1 | read from source drive then latch its bank/track pointers from format_desc (0x52E9..0x52ED) for copy |
| `0x3FAA` | `fdc_src_dma` | 1 | arm source-drive DMA: set bank or drive latch by A==1, load ptr, compute byte length |
| `0x40C3` | `fdc_copy_track` | 1 | copy one track: read source track, latch dest geometry from format_desc, write to dest drive if enabled |
| `0x4117` | `fdc_write_track` | 1 | write full track to dest drive: set latches, copy DMA base ptrs, compute length, arm 4-desc DMA descriptors |
| `0x4261` | `dma_set_ptrs` | 1 | copy source(0x4AF7)/dest(0x4B12) DMA base pointers into active descriptor slots 0x4B21/0x4B25 |
| `0x427F` | `fdc_read_src_b` | 2 | write side via DMA (fdc_write_poll) then latch source geometry |
| `0x42A0` | `fdc_op_poll_keys` | 1 | set FDC step rate from per-side track state (A selects side: 0x4B03 vs 0x4B1E), enable panel bus |
| `0x42DD` | `fdc_seek` | 0 | build+issue FDC SEEK (opcode 0x0F, target cyl in C) |
| `0x432A` | `fdc_seek_sel` | 2 | select FDC block (A==1->blkA else blkB) into BC and issue seek command |
| `0x433A` | `fdc_send_seek` | 2 | issue FDC seek: enable bus, decode drive, write specify (0x0F)+precomp into cmd block, select result buf |
| `0x437A` | `fdc_seek45_both` | 1 | seek both drives to track 45 (0x2D) for alignment test: write specify+seek to FDC 0x10/0x30, wait panel ready |
| `0x43EC` | `dma_arm_desc` | 12 | read {addr,count} descriptor from low-RAM table, arm the DMA channel (0x4401) |
| `0x4401` | `dma_arm_channel` | 1 | program one 8237 DMA channel (addr/count/mode) from a descriptor |
| `0x4457` | `dma_setup` | 1 | reset+reload 8237 channels 0/1 from the drive-block DMA descriptors |
| `0x4489` | `fdc_dma_setup` | 1 | compute DMA transfer count: index sector-size table 0x4AA6[A*2], 16-bit multiply by BC, return count-1 in DE |
| `0x44D5` | `fdc_set_steprate` | 4 | pack FDC specify bytes: SRT\|E->0x4A5C, D<<1\|B bit0->0x4A5D; A bit0 selects alt path |
| `0x452C` | `fdc_senseint_all` | 1 | issue Sense-Interrupt-Status (0x08) to all 4 FDCs and read their 7-byte result phases |
| `0x4571` | `fdc_senseint_send` | 1 | write Sense-Interrupt (0x08) command byte to FDC at port C |
| `0x4579` | `fdc_result_read7` | 1 | read 7 result-phase bytes from an FDC into buffer HL |
| `0x457F` | `fdc_write_bytes` | 15 | stream B command/data bytes to an FDC (poll MSR RQM/DIO before each) |
| `0x4590` | `key_decode` | 5 | build FDC IRQ/DMA enable mask in fdc_irq_bits from drive-select (A bit0, B bit0, side L bit7) |
| `0x45DB` | `fdc_isr` | 1 | IM1 handler: read which FDC interrupted (0x94/0xF0), pull 4x 7-byte result phases |
| `0x462D` | `fdc_isr_sense_int` | 0 | ISR seek-complete path: if FDC2 result pending re-issue Sense-Int to 0x20 (and 0x30 if panel bit3), read resul |
| `0x46F1` | `fdc_read_result` | 9 | read FDC result phase (poll RQM/DIO), up to B bytes |
| `0x4704` | `fdc_poll_result` | 6 | poll FDC done flag (irq_bits bit7 drive0 / bit6 drive2 per A bit0), dispatch to result read |
| `0x472D` | `fdc_poll_complete` | 16 | poll for FDC operation complete (or timeout) |
| `0x481E` | `dram_stack_fill` | 2 | fast-fill banked DRAM (bank B via 0xB0, addr 0x8000\|HL+4*D) via SP-swap block writes, count A&0x7F |
| `0x4848` | `timeout_start` | 9 | start command timeout timer (8253 counter 2) |
| `0x4857` | `timeout_check` | 16 | check/tick the command timeout timer |
| `0x4866` | `store_rate_precomp` | 5 | save data-rate (A) and precomp (B) values to 0x4B89/0x4B8A |
| `0x486E` | `panel_bus_on` | 9 | enable FDC data bus: set panel port 0xF0 bit0, update shadow 0x4A58 |
| `0x4883` | `panel_sel_lo` | 3 | select head/side 0: clear panel bit7 (0x4A58), output to 0xF0 |
| `0x488B` | `panel_sel_hi` | 2 | select head/side 1: set panel bit7 (0x4A58), output to 0xF0 |
| `0x4893` | `fdc_error_decode` | 1 | decode ST0/ST1/ST2 -> error class (CRC/writeprot/seek/notready/overrun) |
| `0x48DB` | `delay_djnz` | 2 | busy-wait delay: DJNZ loop for B iterations |
| `0x48DE` | `read_timer_c1` | 3 | read 8253 counter-1 16-bit (latch cmd 0x44 to 0xAC, read lo/hi from 0xA4), returns HL |
| `0x48EB` | `fdc_set_cmdmode` | 1 | set FDC command-mode flags in 0x4A5A bits0-3 from op_word nibble & rd_submode/unit_sel |
| `0x4974` | `fdc_drive_ready` | 3 | check drive ready: sense drive status, test status bit6 (ready line) |
| `0x4981` | `fdc_err_notready` | 2 | report drive-not-ready error (code 0x96) then re-sense drive status |
| `0x4990` | `fdc_sense_ready` | 3 | sense drive ready: read status, XOR 0x10, test bit4; Z=ready |
| `0x499E` | `fdc_sense_drive` | 2 | FDC Sense Drive Status (cmd 0x04): build unit byte from bit0 of drv_active_cfg, exec, read ST3 |
| `0x49D2` | `fdc_result_reset` | 1 | init 4-byte FDC cmd/DMA descriptor at IX to {0x41,0x02,0x00,0x00} |
| `0x49E3` | `buzzer_beep` | 3 | beep the piezo buzzer A times (port 0xF0 bit3, active-low), ~13ms delay between (via buzzer_pulse) |
| `0x49FC` | `buzzer_pulse` | 2 | one buzzer pulse: drive 0xF0 bit3 low ~13ms then high (audible click), keep shadow 0x4A58 in sync |
| `0x4A16` | `buzzer_off` | 2 | set panel port F0 bit3 high, keeping 0x4A58 shadow in sync |
| `0x4B99` | `lcd_init` | 1 | HD44780 LCD init: function set 0x38, display/clear/entry/on, presence check |
| `0x4BE2` | `io_mute_local` | 1 | mute local I/O: disable input poll and point iovec_out at no-op stub (0x4C4F) |
| `0x4BEC` | `io_disable_poll` | 1 | disable input polling: point iovec_poll at stub that returns A=0xFF |
| `0x4BF5` | `error_report` | 3 | error beep: A*200/13 -> PIT ch1 (0xA4/0xAC) tone, pitch/duration encodes error code |
| `0x4C22` | `lcd_setpos` | 19 | busy-loop delay (HL iterations) |
| `0x4C2A` | `lcd_wait_busy` | 7 | wait for LCD busy flag clear (IN 0xE0 bit7) |
| `0x4C43` | `lcd_byte_out` | 11 | write A to LCD via iovec_out (busy-wait then OUT (C),A; C=cmd/data reg) |
| `0x4C4A` | `byte_out` | 0 | default iovec_out: wait LCD busy then OUT (C),A; 0x4C4F entry is muted no-op restoring HL |
| `0x4C53` | `lcd_print_hl` | 0 | saved caller HL across lcd_print (restored at 0x4CCB) |
| `0x4C55` | `lcd_print_bc` | 0 | saved caller BC across lcd_print (restored at 0x4CCE) |
| `0x4C57` | `lcd_byte_hl` | 0 | saved caller HL across lcd_byte_out (restored at 0x4C4F) |
| `0x4C59` | `lcd_print` | 167 | print inline string to LCD (control bytes 0x0C clr/0x0D nl/0x1B pos/0x00 end) |
| `0x4CD3` | `lcd_scroll_up` | 2 | scroll LCD display up one line: read line-2 chars and rewrite shifted, blank last |
| `0x4D0B` | `keypad_scan` | 6 | scan the 4-key keypad matrix (ports 0x98/0x94) |
| `0x4D29` | `keypad_row_read` | 2 | read keypad row: IN status 0x94, invert low nibble, return single-key code or 0 |
| `0x4D43` | `keypad_debounce` | 11 | debounced key read with auto-repeat + key-click beep |
| `0x4D49` | `keypad_wait` | 1 | wait for a debounced keypress: poll keypad_scan with LCD-timed delays and panel busy pulse |
| `0x4D89` | `get_key` | 29 | get key / dispatch input (indirect via iovec_poll 0x52CB: keypad or host) |
| `0x4D8E` | `get_key_dispatch` | 0 | poll-input tail: if A=0 scan keypad and discard caller return; else return current value |
| `0x4D9B` | `poll_host_remote` | 1 | poll host UART (0xDC) during key scan; if byte ready fetch remote word, flag cmd 0x0C |
| `0x4DD9` | `timer_uart_init` | 1 | init 8253 (baud c0, timers c1/c2) and both SIO channels; drain receivers |
| `0x4E42` | `uart_tx` | 3 | SIO TX: wait TxRDY (status bit2), OUT data |
| `0x4E4F` | `host_rx_ready` | 1 | test host SIO RxRDY: C=0xDC, IN B, bit0 = byte available |
| `0x4E53` | `al_rx_ready` | 3 | test autoloader SIO RxRDY: C=0xD4, IN B, bit0 = byte available |
| `0x4E5A` | `uart_rx` | 1 | SIO RX with timeout: wait RxRDY (bit0); return Z=byte / NZ=timeout\|err |
| `0x4E8C` | `uart_send_reset` | 3 | send SIO command 0x30 to port C (reset error flags / enter hunt) |
| `0x4E91` | `al_cmd_reset` | 2 | reset autoloader SIO (C=0xD4) via command 0x30 |
| `0x4E95` | `host_cmd_reset` | 1 | reset host SIO (C=0xDC) via command 0x30 |
| `0x4E99` | `al_tx` | 5 | transmit byte A to autoloader SIO (C=0xD4, via uart_tx) |
| `0x4E9D` | `host_tx` | 19 | transmit byte A to host SIO (C=0xDC, via uart_tx) |
| `0x4EA1` | `al_rx` | 3 | receive byte from autoloader SIO (C=0xD4); on data, clear SIO errors |
| `0x4EAD` | `host_rx` | 5 | receive byte from host SIO (C=0xDC); on data, clear SIO errors |
| `0x4EB2` | `bin2dec_clear` | 3 | 32-bit binary (DE:HL) -> decimal ASCII, right-justified in buffer at 0x4F38 down |
| `0x4EB5` | `bin2dec` | 1 | binary -> decimal ASCII conversion |
| `0x4ECB` | `div_by_10` | 1 | divide 32-bit DE:HL by 10 (BC=10 wrapper over div32_16), remainder in C for digits |
| `0x4ECE` | `div32_16` | 7 | 32/16 unsigned divide (DE:HL / BC) |
| `0x4F05` | `mul16` | 7 | 16x16 unsigned multiply |
| `0x4F1D` | `clear_dec_buf` | 1 | fill 8-byte decimal-conversion buffer at 0x4F31 with spaces |
| `0x4F2C` | `lcd_print_number` | 1 | print the decimal-conversion buffer string to LCD (via lcd_print) |
| `0x4F2F` | `lcd_dec_tmpl` | 0 |  |
| `0x4F3B` | `lcd_dump_hex` | 3 | monitor hex-dump: clear LCD (cmd 0x01) then print a hex row of bytes from (HL) |
| `0x4F5C` | `mon_hexrow` | 1 | print a full 2-line monitor hex row (mon_hex4 group + line-2 home) |
| `0x4F5F` | `mon_hexrow_b` | 1 | print monitor hex group then home to LCD line 2 |
| `0x4F66` | `mon_hex4` | 1 | monitor hex-row segment: print 4 hex bytes from (HL) plus trailing space |
| `0x4F69` | `mon_hex3` | 1 | monitor hex-row segment: print 3 hex bytes from (HL) plus trailing space |
| `0x4F6C` | `mon_hex2` | 1 | monitor hex-row segment: print 2 hex bytes from (HL) plus trailing space |
| `0x4F6F` | `mon_hex_space` | 1 | print a single space char to LCD data (0xE8) - monitor field separator |
| `0x4F77` | `mon_hex2b` | 2 | print 2 hex bytes from (HL) to LCD, advancing HL (monitor) |
| `0x4F7A` | `mon_hexbyte` | 2 | print byte at (HL) as 2 hex digits to LCD, advance HL (monitor) |
| `0x4FAC` | `mon_hexpair` | 1 | print two hex nibbles of buffered byte (0x4FAB) via RLD, ASCII-adjust, to LCD |
| `0x4FAF` | `mon_hexnib` | 1 | print one hex nibble via RLD to ASCII (0-9/A-F) to LCD data (0xE8) |
| `0x4FC4` | `lcd_line2_home` | 1 | home LCD to line 2 (via lcd_print control sequence) |
| `0x4FCB` | `build_format_block` | 2 | assemble FDC format command block: geometry + sector map + interleave + DMA/bank params from 0x3130 |
| `0x4FF2` | `block_to_chs` | 5 | logical block -> CHS + DMA descriptor (uses format_desc geometry) |
| `0x5043` | `format_sector_map` | 1 | generate per-track sector-ID (interleave) list for FORMAT |
| `0x507E` | `build_interleave_tbl` | 1 | build sector interleave table at IY (0x52F2): fill physical->logical sector ids via sector_lba |
| `0x50AB` | `sector_lba` | 1 | compute interleaved logical sector id from position: div32_16 by sectors-per-track (format_desc+5) |
| `0x50CC` | `layout_sectors` | 2 | lay out per-sector format descriptors (C/H/R/N) for whole track via block_to_chs |
| `0x5101` | `init_format_geom` | 1 | init format_desc geometry: copy 5 disk params from 0x4AFC, compute sectors-per-track and totals |
| `0x515D` | `checksum_all_banks` | 3 | checksum every loaded DRAM image bank: set image_present, LCD progress, loop banks via set_bank_checksum |
| `0x519C` | `set_bank_checksum` | 2 | select DRAM bank A (OUT 0xB0), compute image_checksum, store two's-complement at 0xFFFF so bank sums to 0 |
| `0x51A9` | `image_checksum` | 2 | checksum the whole DRAM image (sum 0x8000..0xFFFF) |
| `0x51BA` | `verify_ram_bank` | 4 | verify next DRAM bank checksum (bank counter 0x52C7): add image_checksum, expect 0; pulses panel busy + LCD |
| `0x51E7` | `fdc_build_unit_sel` | 3 | build FDC unit-select byte: index cfg table 0x5227 then OR option bits from format_desc IX+11; result stored t |
| `0x520A` | `media_cfg_index` | 3 | compute media-config table index from format_desc IX+11 density/side/option bits |
| `0x522F` | `menu_run` | 10 | generic 4-key menu driver (HL=draw+action ptr lists); see docs |
| `0x52C9` | `iovec_out` | 0 |  |
| `0x52CB` | `iovec_poll` | 0 |  |
| `0x52CD` | `iovec_beep` | 0 |  |

## 3. Call graph

**Entry points / roots** (named routines with no static callers — reset, ISR, and
computed-jump handlers):

- `0x0022` `boot_cont`
- `0x024D` `al_connect_probe`
- `0x0940` `fdc_datarate_precomp`
- `0x0A00` `geom_seek_build`
- `0x1198` `al_calibrate`
- `0x126D` `al_reject`
- `0x1540` `hrd_menu`
- `0x1555` `special_formats_menu`
- `0x156A` `menu_show_a`
- `0x1571` `menu_show_b`
- `0x1578` `menu_show_c`
- `0x157F` `menu_show_d`
- `0x1586` `menu_show_e`
- `0x158D` `spfmt_show_01`
- `0x1592` `spfmt_show_02`
- `0x1597` `spfmt_show_03`
- `0x159C` `spfmt_show_04`
- `0x15A1` `spfmt_show_05`
- `0x15A6` `spfmt_show_06`
- `0x15AB` `spfmt_show_07`
- `0x15B0` `spfmt_show_08`
- `0x15B5` `spfmt_show_09`
- `0x15BA` `spfmt_show_10`
- `0x15BF` `spfmt_show_11`
- `0x15C4` `spfmt_show_12`
- `0x15C9` `spfmt_show_13`
- `0x15CE` `spfmt_show_14`
- `0x15D3` `spfmt_show_15`
- `0x166B` `spfmt_apply_01`
- `0x1677` `spfmt_apply_02`
- `0x167C` `spfmt_apply_03`
- `0x1681` `spfmt_apply_04`
- `0x1686` `spfmt_apply_05`
- `0x168B` `spfmt_apply_06`
- `0x1690` `spfmt_apply_07`
- `0x1695` `spfmt_apply_08`
- `0x1699` `spfmt_apply_09`
- `0x169D` `spfmt_apply_10`
- `0x16A1` `spfmt_apply_11`
- `0x16A5` `spfmt_apply_12`
- `0x16A9` `spfmt_apply_13`
- `0x16AD` `spfmt_apply_14`
- `0x16B1` `spfmt_apply_15`
- `0x16B5` `spfmt_apply_16`
- `0x16B9` `fmt_35_720k`
- `0x16E7` `fmt_35_144m`
- `0x1715` `fmt_525_360k`
- `0x1743` `fmt_525_180k`
- `0x1771` `fmt_525_320k`
- `0x179F` `fmt_525_160k`
- `0x17CD` `fmt_525_720k`
- `0x17FB` `fmt_525_12m`
- `0x190D` `sel_model_1`
- `0x1917` `sel_model_2`
- `0x1921` `sel_model_3`
- `0x1930` `show_insert_model`
- `0x19D2` `show_read_source`
- `0x1A25` `show_copy_fwv`
- `0x1A40` `show_copy_wv`
- `0x1A58` `show_copy_crc`
- `0x1A69` `show_copy_fv`
- `0x1A82` `show_copy_wd`
- `0x1A94` `set_error_recovery`
- `0x1CC8` `start_copy_wv`
- `0x1CDB` `start_copy_fmtverify`
- `0x1CE2` `format_track`
- `0x1D92` `start_copy_write`
- `0x1D97` `show_copy_bitverify`
- `0x1DAF` `start_copy_verify`
- `0x1DB4` `show_clean_fdd`
- `0x1E37` `host_op_image_dl`
- `0x2082` `host_op_diag_out`
- `0x25C1` `show_batch`
- `0x25D7` `start_batch`
- `0x298B` `show_ff_35`
- `0x29A1` `show_ff_525`
- `0x29B8` `show_density_dd`
- `0x29CC` `show_density_hd`
- `0x29DE` `show_mode_simul`
- `0x29F5` `show_mode_normal`
- `0x2A06` `show_spindle_high`
- `0x2A1E` `show_spindle_normal`
- `0x2A38` `show_spindle_double`
- `0x2A5E` `set_ff_35`
- `0x2A73` `set_density_dd`
- `0x2A7B` `set_density_hd`
- `0x2A85` `set_mode_simul`
- `0x2A8D` `set_mode_normal`
- `0x2A95` `set_spindle_high`
- `0x2A9F` `set_spindle_normal`
- `0x2AA8` `set_spindle_double`
- `0x2BD1` `hrd_radial_a`
- `0x2BDA` `hrd_radial_b`
- `0x2BE3` `hrd_radial_c`
- `0x2C35` `hrd_show_ecc`
- `0x2C47` `hrd_show_azimuth`
- `0x2C59` `hrd_show_positioner`
- `0x2C76` `hrd_show_spindle`
- `0x2CAC` `hrd_run_a`
- `0x2CB0` `hrd_run_b`
- `0x2CB4` `hrd_run_c`
- `0x2CBB` `hrd_run_d`
- `0x2E25` `hrd_hysteresis`
- `0x2E72` `hrd_spindle_rpm`
- `0x3025` `hrd_disp_radial`
- `0x3040` `hrd_disp_ecc`
- `0x304A` `hrd_disp_azimuth`
- `0x3060` `hrd_disp_positioner`
- `0x34A2` `fdc_build_20`
- `0x34AA` `fdc_build_40`
- `0x34F9` `fdc_build_60`
- `0x34FD` `fdc_build_80`
- `0x357C` `fdc_build_A0`
- `0x3580` `fdc_build_C0`
- `0x35AA` `fdc_sub_jmptbl`
- `0x39A0` `fdc_recalibrate`
- `0x3E00` `fdc_seek_write_dma`
- `0x42DD` `fdc_seek`
- `0x462D` `fdc_isr_sense_int`
- `0x4C4A` `byte_out`
- `0x4D8E` `get_key_dispatch`

**Adjacency** — each named routine and the named routines it calls or jumps to
(auto labels collapsed to their enclosing named routine where possible):

- `boot_cont` → `boot_init`
- `show_model_cycles` → `lcd_print`
- `run_entry` → `config_menu`, `dram_test`, `drive_cfg_latch`, `get_key`, `lcd_byte_out`, `lcd_print`, `show_model_cycles`
- `show_fdd_seek_error` → `beep`, `drive_cfg_latch`, `lcd_clear_line2`, `lcd_print`, `lcd_setpos`
- `wait_autoloader_loop` → `lcd_print`
- `al_connect_probe` → `al_cmd_ack`, `beep`, `keypad_debounce`, `lcd_print`, `wait_autoloader_loop`
- `show_al_error` → `keypad_debounce`, `lcd_clear_line2`, `lcd_print`
- `manual_mode` → `lcd_home3`, `lcd_print`
- `dram_bank_cfg` → `eeprom_transfer`
- `dram_test` → `lcd_print`
- `fdd_detect` → `media_cfg_index`
- `edit_num_copies` → `edit_num_field`, `lcd_print`
- `edit_num_field` → `lcd_byte_out`
- `show_ok_bad_count` → `lcd_clear_line2`, `lcd_print`, `num_to_lcd_alt`
- `lcd_clear_line2` → `lcd_print`
- `lcd_clear_line1` → `lcd_print`
- `motor_ready_wait` → `seek_both_drives`, `set_drive_cfg`
- `fdc_wait_unit1` → `fdc_poll_complete`
- `seek_both_drives` → `fdc_recal_seek`, `fdc_wait_unit1`
- `dup_engine_loop` → `ctrl_latch_load`
- `require_motor_ready` → `motor_ready_wait`
- `show_rpm_low` → `lcd_print`
- `fdc_build_select` → `index_period_timer`
- `fdc_datarate_precomp` → `update_ctrl_latch`
- `geom_seek_build` → `block_to_chs`
- `read_both_sides` → `check_double_sided`, `fdc_write_dual`, `fdc_write_poll`
- `write_both_sides` → `check_double_sided`, `fdc_read_src_b`
- `show_in_progress` → `lcd_clear_line2`, `lcd_print`
- `show_compare_error` → `beep`, `lcd_clear_line2`, `lcd_print`
- `batch_loop_tail` → `al_gate_or_reject`
- `al_gate_or_reject` → `al_accept_reject`, `al_present_gate`, `buzzer_pulse`
- `al_accept_reject` → `al_present_gate`, `is_op_mode9`, `lcd_clear_line2`, `lcd_print`
- `al_cmd_reject` → `al_present_gate`, `lcd_clear_line2`, `lcd_print`
- `al_calibrate` → `al_cmd_ack`
- `read_source` → `is_op_mode9`
- `al_insert` → `al_tx`
- `show_lost_data` → `lcd_clear_line2`, `lcd_dump_hex`, `lcd_print`
- `al_reject` → `al_cmd_ack`
- `al_status_decode` → `keypad_debounce`, `lcd_clear_line2`, `lcd_print`
- `al_cmd_ack` → `al_cmd_reset`, `al_tx`
- `al_rx_response` → `al_rx`
- `al_cmd_status` → `al_flush_rx`, `al_rx`, `al_tx`, `ascii_hex_to_nibble`
- `hrd_menu` → `lcd_print`
- `special_formats_menu` → `lcd_print`
- `menu_show_a` → `menu_run`
- `menu_show_b` → `menu_run`
- `menu_show_c` → `menu_run`
- `menu_show_d` → `menu_run`
- `menu_show_e` → `menu_run`
- `fmt_35_720k` → `lcd_print`
- `fmt_35_144m` → `lcd_print`
- `fmt_525_360k` → `lcd_print`
- `fmt_525_180k` → `lcd_print`
- `fmt_525_320k` → `lcd_print`
- `fmt_525_160k` → `lcd_print`
- `fmt_525_720k` → `lcd_print`
- `fmt_525_12m` → `lcd_print`
- `sel_model_1` → `fmt_apply`
- `sel_model_2` → `fmt_apply`
- `sel_model_3` → `fmt_apply`
- `show_insert_model` → `lcd_print`
- `show_not_available` → `lcd_home3`, `lcd_print`
- `show_read_source` → `lcd_clear_line2`, `lcd_print`
- `show_copy_fwv` → `lcd_print`
- `show_copy_wv` → `lcd_print`
- `show_copy_crc` → `lcd_print`
- `show_copy_fv` → `lcd_print`
- `show_copy_wd` → `lcd_print`
- `set_error_recovery` → `lcd_clear_line2`, `lcd_print`, `start_run_op`
- `show_out_of_range` → `lcd_clear_line2`, `lcd_home3`, `lcd_print`
- `format_track` → `fdd_geom_index`, `mul16`
- `show_copy_bitverify` → `lcd_print`
- `show_clean_fdd` → `lcd_print`
- `abort_check` → `al_insert_disk`
- `show_abort` → `beep`, `lcd_clear_line2`, `lcd_print`, `lcd_setpos`
- `host_read_packet` → `host_rx`, `host_rx_word`
- `host_rx_word` → `host_rx`
- `host_op_image_dl` → `bulk_sync_aa55`, `host_op_enter_run`, `host_tx`, `lcd_print`
- `host_op_enter_run` → `host_op_disk_write`, `host_tx`, `run_entry`
- `host_op_disk_write` → `fdc_build_unit_sel`, `host_op_ping`, `host_rx_echo`, `host_tx`
- `host_rx_echo` → `host_rx`, `host_tx`
- `host_op_ping` → `host_op_start`, `host_tx`
- `host_op_start` → `abort_check`, `host_op_load_exec`, `host_tx`
- `host_op_load_exec` → `code_loader`, `host_dispatch`, `host_tx`
- `host_op_diag_out` → `host_tx`, `lcd_setpos`
- `host_op_begin_run` → `host_tx`, `lcd_clear_line2`, `lcd_print`, `require_motor_ready`
- `bulk_read_bytes` → `bulk_read_byte`
- `bulk_read_word` → `bulk_read_byte`
- `bulk_sync_aa55` → `bulk_read_byte`
- `code_loader` → `dl_code`, `lcd_print`
- `dl_boot_entry_a` → `dl_boot_entry_b`
- `show_curr_prefix` → `lcd_clear_line2`, `lcd_print`
- `config_menu` → `lcd_print`
- `config_err_recovery` → `get_key`, `lcd_print`, `show_err_recovery`
- `config_serialization` → `get_key`, `lcd_print`, `show_serial_batch`
- `config_copy_dir` → `get_key`, `lcd_print`, `show_copy_dir`
- `config_max_cyl` → `clear_image_present`, `edit_num_field`, `get_key`, `lcd_print`, `show_max_cyl`
- `show_max_cyl` → `lcd_print`, `num_to_lcd`, `show_curr_prefix`
- `config_wprotect` → `get_key`, `lcd_print`, `show_wprotect`
- `show_wprotect` → `lcd_print`, `show_curr_prefix`
- `show_copy_dir` → `lcd_print`, `show_curr_prefix`
- `show_err_recovery` → `lcd_print`, `show_curr_prefix`
- `show_serial_batch` → `lcd_print`, `show_curr_prefix`
- `show_batch` → `lcd_print`
- `start_batch` → `al_present_gate`, `show_not_available`
- `drive_block_ptr` → `drive_index_bits`, `mul16`
- `drive_block_pos` → `drive_index_bits`, `mul16`
- `hrd_head_edit` → `hrd_edit_head_pair`
- `hrd_fmt_num` → `bin2dec_clear`
- `hrd_emit_num` → `lcd_print`
- `hrd_edit_head_pair` → `hrd_edit_head_row`, `lcd_print`
- `show_media_status` → `lcd_print`, `show_size_density`
- `show_size_density` → `lcd_print`
- `show_ff_35` → `lcd_print`
- `show_ff_525` → `lcd_print`
- `show_density_dd` → `lcd_print`
- `show_density_hd` → `lcd_print`
- `show_mode_simul` → `lcd_print`
- `show_mode_normal` → `lcd_print`
- `show_spindle_high` → `lcd_print`
- `show_spindle_normal` → `lcd_print`
- `show_spindle_double` → `lcd_print`
- `eeprom_write` → `eeprom_send_byte`, `i2c_start`
- `eeprom_clk_idle` → `i2c_scl_lo`, `i2c_sda_hi`
- `eeprom_clk_high` → `lcd_setpos`
- `i2c_scl_lo` → `lcd_setpos`
- `i2c_start` → `eeprom_clk_idle`, `i2c_sda_lo`
- `eeprom_io` → `i2c_ack`, `i2c_sda_hi`, `lcd_setpos`
- `i2c_ack` → `eeprom_clk_high`, `i2c_scl_lo`, `i2c_sda_lo`
- `eeprom_read` → `eeprom_write`, `i2c_read_start`
- `i2c_read_start` → `eeprom_send_byte`, `i2c_start`
- `fdd_geom_index` → `media_cfg_index`
- `track_buf_ptr` → `block_to_chs`
- `geom_sector_calc` → `div32_16`
- `hrd_radial_a` → `hrd_show_radial`, `show_radial_align`
- `hrd_radial_b` → `hrd_show_radial`, `show_radial_align`
- `hrd_radial_c` → `hrd_show_radial`, `show_radial_align`
- `show_radial_align` → `lcd_print`
- `hrd_show_radial` → `hrd_radial_ptr`, `num_to_lcd`
- `hrd_show_ecc` → `lcd_print`
- `hrd_show_azimuth` → `lcd_print`
- `hrd_show_positioner` → `lcd_print`
- `hrd_show_spindle` → `lcd_print`
- `hrd_show_scaled` → `div32_16`, `hrd_rec_ptr`, `lcd_print`, `mul16`, `num_to_lcd`
- `hrd_rec_ptr` → `buzzer_beep`, `lcd_clear_line2`, `lcd_print`
- `hrd_radial_measure` → `lcd_home3`, `set_drive_cfg`, `show_in_progress`
- `hrd_hysteresis` → `fdc_step_to_track`, `hrd_radial_measure`, `hrd_radial_ptr`, `neg16`, `set_drive_cfg`
- `hrd_spindle_rpm` → `set_drive_cfg`, `show_in_progress`
- `hrd_seek_read` → `fdc_step_to_track`
- `hrd_read_verify` → `wait_read_done`
- `hrd_disp_radial` → `lcd_print`
- `hrd_disp_ecc` → `lcd_print`
- `hrd_disp_azimuth` → `lcd_print`
- `hrd_disp_positioner` → `lcd_print`
- `show_rpm_suffix` → `lcd_print`
- `fdc_format_build` → `set_fdc_pending`
- `fdc_build_20` → `set_fdc_pending`
- `fdc_build_C0` → `fdc_format_build`
- `fdc_dma_from_blk` → `fdc_dma_setup`
- `fdc_home_head` → `fdc_sense_ready`, `panel_bit6_on`, `panel_bus_on`
- `fdc_step_pulse` → `fdc_send_seek`
- `index_period_timer` → `panel_bus_on`
- `fdc_recalibrate` → `fdc_set_steprate`, `fdc_write_bytes`, `key_decode`, `panel_bus_on`
- `fdc_read_cmd` → `fdc_build_rw_cmd`, `panel_bus_on`, `panel_sel_hi`
- `fdc_write_poll` → `fdc_write_dma`
- `fdc_write_dual` → `fdc_write_both`
- `fdc_write_both` → `dma_arm_desc`, `fdc_wr_side1`
- `fdc_wr_side0` → `panel_sel_lo`
- `fdc_wr_side1` → `panel_sel_hi`
- `fdc_build_rw_cmd` → `key_decode`
- `fdc_specify_dor` → `fdc_write_bytes`, `panel_bus_on`, `panel_sel_lo`
- `fdc_seek_write_wrap` → `fdc_seek_dma`
- `fdc_read_track` → `fdc_read_dma_prep`
- `fdc_read_dma_prep` → `fdc_drive_ready`
- `fdc_seek_write_dma` → `dma_arm_desc`, `fdc_specify_dor`, `fdc_wr_side0`
- `fdc_dma_exec` → `fdc_dma_arm2`
- `fdc_dma_arm2` → `fdc_drive_ready`
- `fdc_write_both_wrap` → `fdc_write_dma_both`
- `fdc_write_dma_both` → `dma_arm_desc`, `fdc_format_cmd`
- `fdc_read_src` → `fdc_dma_exec`
- `fdc_copy_track` → `fdc_read_track`
- `fdc_write_track` → `dma_arm_desc`, `dma_set_ptrs`, `fdc_read_cmd`, `timeout_start`
- `dma_set_ptrs` → `fdc_seek_write_wrap`, `fdc_write_both_wrap`
- `fdc_read_src_b` → `fdc_write_poll`
- `fdc_op_poll_keys` → `panel_bus_on`
- `fdc_send_seek` → `key_decode`, `panel_bus_on`
- `fdc_seek45_both` → `fdc_write_bytes`
- `dma_arm_desc` → `dma_arm_channel`
- `fdc_set_steprate` → `fdc_write_bytes`
- `fdc_senseint_all` → `fdc_result_read7`, `fdc_senseint_send`
- `fdc_senseint_send` → `fdc_write_bytes`
- `fdc_result_read7` → `fdc_read_result`
- `fdc_isr` → `fdc_read_result`
- `fdc_poll_complete` → `error_report`
- `fdc_drive_ready` → `fdc_sense_drive`
- `fdc_err_notready` → `error_report`, `fdc_sense_ready`
- `fdc_sense_ready` → `fdc_sense_drive`
- `buzzer_pulse` → `buzzer_off`
- `lcd_init` → `lcd_byte_out`, `lcd_setpos`, `lcd_wait_busy`
- `io_mute_local` → `io_disable_poll`
- `error_report` → `div32_16`, `mul16`
- `byte_out` → `lcd_wait_busy`
- `keypad_scan` → `keypad_row_read`, `poll_host_remote`
- `keypad_debounce` → `keypad_wait`
- `get_key_dispatch` → `keypad_scan`
- `poll_host_remote` → `host_rx_word`
- `timer_uart_init` → `al_cmd_reset`, `fdc_senseint_all`, `host_cmd_reset`, `lcd_init`
- `al_cmd_reset` → `uart_send_reset`
- `host_cmd_reset` → `uart_send_reset`
- `al_tx` → `uart_tx`
- `host_tx` → `uart_tx`
- `bin2dec_clear` → `clear_dec_buf`
- `lcd_print_number` → `lcd_print`
- `lcd_dump_hex` → `lcd_byte_out`, `mon_hexrow`
- `mon_hexrow` → `mon_hexrow_b`
- `mon_hexrow_b` → `lcd_line2_home`, `mon_hex4`
- `mon_hex4` → `mon_hex3`
- `mon_hex3` → `mon_hex2`
- `mon_hex2` → `mon_hex2b`
- `mon_hex_space` → `lcd_byte_out`
- `mon_hex2b` → `mon_hexbyte`
- `mon_hexbyte` → `lcd_print`, `mon_hex2b`, `mon_hexpair`
- `mon_hexpair` → `mon_hexnib`
- `lcd_line2_home` → `lcd_print`
- `build_format_block` → `build_interleave_tbl`, `format_sector_map`, `init_format_geom`
- `init_format_geom` → `div32_16`, `mul16`
- `checksum_all_banks` → `lcd_clear_line2`, `lcd_print`
- `set_bank_checksum` → `image_checksum`
- `verify_ram_bank` → `lcd_setpos`
- `fdc_build_unit_sel` → `media_cfg_index`

