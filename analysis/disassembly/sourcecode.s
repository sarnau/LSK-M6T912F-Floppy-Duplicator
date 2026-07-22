0000  3E 0F         LD A,0x0F
0002  D3 8D         OUT (0x8D),A  ; dma_mclr
0004  D3 8F         OUT (0x8F),A  ; dma_wrmask
0006  3E A0         LD A,0xA0
0008  D3 88         OUT (0x88),A  ; dma_cmd
000A  21 00 80      LD HL,image_buf
000D  F9            LD SP,HL
000E  3E FF         LD A,0xFF
0010  D3 B0         OUT (0xB0),A  ; dram_bank
0012  D3 C0         OUT (0xC0),A
0014  01 FF 5F      LD BC,0x5FFF
0017  21 22 00      LD HL,boot_cont
001A  11 22 80      LD DE,image_buf+0x22
001D  ED B0         LDIR
001F  C3 22 80      JP image_buf+0x22

; boot continuation: also copied to DRAM 0x8022 and re-entered there after banking
boot_cont:
0022  3E 92         LD A,0x92
0024  D3 9C         OUT (0x9C),A  ; ctrl_latch
0026  C3 00 01      JP boot_init

padding:
0029  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00    |...............|
0038  C3 DB 45      JP fdc_isr

padding:
003B  00 00 00 00 00                                  |.....|

ptr_ver_firmware:
0040  54 00         DW ver_firmware+0x1   ; -> 0x0054

ptr_ver_loader:
0042  8B 4B         DW ver_loader   ; -> 0x4B8B

ptr_ver_bootloader:
0044  CF 52         DW ver_bootloader   ; -> 0x52CF

padding:
0046  00 00 00 00 00 00 00 00 00 00                   |..........|

show_model_cycles:
0050  CD 59 4C      CALL lcd_print

ver_firmware:
0053  0C 4D 36 54 39 49 +  DB \f, "M6T9I2F 961002", 0
0063  21 69 32      LD HL,cycle_cnt_lo
0066  06 04         LD B,0x04
0068  0E FC         LD C,0xFC
006A  AF            XOR A
006B  CD 35 27      CALL config_save
006E  2A 69 32      LD HL,(cycle_cnt_lo)
0071  ED 5B 6B 32   LD DE,(cycle_cnt_hi)
0075  06 08         LD B,0x08
0077  0E 20         LD C,0x20
0079  AF            XOR A
007A  CD FA 05      CALL num_to_lcd_alt
007D  3E 01         LD A,0x01
007F  CD 89 4D      CALL get_key
0082  00            NOP
0083  C9            RET

padding:
0084  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
0094  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
00A4  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
00B4  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
00C4  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
00D4  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
00E4  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
00F4  00 00 00 00 00 00 00 00 00 00 00 00             |............|

; main entry after RAM relocation: checksum RAM, init HW, size DRAM, pick operating mode
boot_init:
0100  F3            DI
0101  21 00 80      LD HL,image_buf
0104  F9            LD SP,HL

; sum bytes 0x0100..0x52EF; compare to cksum_ref; mismatch -> CODE TRANSFER ERROR loop
boot_checksum:
0105  3E 00         LD A,0x00
0107  21 EF 52      LD HL,cksum_calc

loc_010A:
010A  86            ADD A,(HL)
010B  2B            DEC HL
010C  47            LD B,A
010D  7C            LD A,H
010E  B7            OR A
010F  78            LD A,B
0110  C2 0A 01      JP NZ,loc_010A
0113  32 EF 52      LD (cksum_calc),A
0116  CD D9 4D      CALL timer_uart_init
0119  CD 3E 2B      CALL eeprom_io
011C  CD 5E 2B      CALL i2c_read_start
011F  CD 66 2B      CALL i2c_read_byte
0122  CD EF 2A      CALL eeprom_clk_idle
0125  CD 3E 2B      CALL eeprom_io
0128  3A EF 52      LD A,(cksum_calc)
012B  21 F0 52      LD HL,cksum_ref
012E  BE            CP (HL)
012F  28 30         JR Z,run_entry
0131  CD D9 4D      CALL timer_uart_init

loc_0134:
0134  CD 59 4C      CALL lcd_print
0137  0C 43 4F 44 45 20 +  DB \f, "CODE TRANSFER", \r, \n, "ERROR", 0
014D  3E 05         LD A,0x05
014F  CD 66 27      CALL beep
0152  3E 02         LD A,0x02
0154  21 EF 52      LD HL,cksum_calc
0157  CD 3B 4F      CALL lcd_dump_hex
015A  3E 05         LD A,0x05
015C  CD 66 27      CALL beep
015F  18 D3         JR loc_0134

; run/duplication mode entry (also target of host 0x0B run vector install)
run_entry:
0161  F3            DI
0162  21 00 80      LD HL,image_buf
0165  F9            LD SP,HL
0166  3E FF         LD A,0xFF
0168  32 58 4A      LD (panel_shadow),A
016B  D3 F0         OUT (0xF0),A  ; panel
016D  CD 57 07      CALL drive_cfg_latch
0170  AF            XOR A
0171  CD 89 4D      CALL get_key
0174  E6 0F         AND 0x0F
0176  FE 02         CP 0x02
0178  CC 67 22      CALL Z,config_menu
017B  CD DD 03      CALL dram_test
017E  DB D0         IN A,(0xD0)  ; al_data
0180  DB D0         IN A,(0xD0)  ; al_data
0182  DB D0         IN A,(0xD0)  ; al_data
0184  DB D0         IN A,(0xD0)  ; al_data
0186  DB D0         IN A,(0xD0)  ; al_data
0188  DB D8         IN A,(0xD8)  ; host_data
018A  DB D8         IN A,(0xD8)  ; host_data
018C  DB D8         IN A,(0xD8)  ; host_data
018E  DB D8         IN A,(0xD8)  ; host_data
0190  DB D8         IN A,(0xD8)  ; host_data
0192  0E E0         LD C,0xE0
0194  3E 48         LD A,0x48
0196  CD 43 4C      CALL lcd_byte_out
0199  CD 59 4C      CALL lcd_print
019C  20 20 11 11 11 13 +  DB "  ", \x11, \x11, \x11, \x13, \x1D, \x10, 0
01A5  AF            XOR A
01A6  CD 89 4D      CALL get_key
01A9  C4 50 00      CALL NZ,show_model_cycles

loc_01AC:
01AC  AF            XOR A
01AD  CD 89 4D      CALL get_key
01B0  20 FA         JR NZ,loc_01AC
01B2  CD B4 03      CALL dram_bank_cfg
01B5  3E 2D         LD A,0x2D
01B7  32 1E 31      LD (drv_active_cfg),A
01BA  C3 35 02      JP wait_autoloader_loop

; draw "FDD seek error", deselect drives, beep code 5, home LCD, then reset seek/format state
show_fdd_seek_error:
01BD  CD 70 06      CALL lcd_clear_line2
01C0  CD 59 4C      CALL lcd_print
01C3  0C 46 44 44 20 73 +  DB \f, "FDD seek error", 0
01D3  CD 57 07      CALL drive_cfg_latch
01D6  3E 05         LD A,0x05
01D8  CD 66 27      CALL beep
01DB  21 00 00      LD HL,0x0000
01DE  CD 22 4C      CALL lcd_setpos

; reset seek/format state after error: fmt_mode=0x90, clear flag at 0x3150
reset_seek_state:
01E1  3E 90         LD A,0x90
01E3  32 4C 31      LD (fmt_mode),A
01E6  AF            XOR A
01E7  32 50 31      LD (edit_ndigits),A
01EA  C9            RET

loc_01EB:
01EB  CD EC 24      CALL show_wprotect
01EE  CD A9 03      CALL lcd_home3
01F1  CD 69 25      CALL show_err_recovery
01F4  CD A9 03      CALL lcd_home3
01F7  CD A5 25      CALL show_serial_batch
01FA  CD A9 03      CALL lcd_home3
01FD  CD 2C 25      CALL show_copy_dir
0200  CD A9 03      CALL lcd_home3
0203  CD F8 28      CALL show_media_status
0206  CD A9 03      CALL lcd_home3
0209  AF            XOR A
020A  CD 89 4D      CALL get_key
020D  28 26         JR Z,wait_autoloader_loop
020F  3E 01         LD A,0x01
0211  CD 89 4D      CALL get_key
0214  E6 0F         AND 0x0F
0216  FE 02         CP 0x02
0218  20 1B         JR NZ,wait_autoloader_loop
021A  CD 9E 24      CALL config_wprotect
021D  CD 1E 23      CALL config_err_recovery
0220  CD 69 23      CALL config_serialization
0223  CD BF 23      CALL config_copy_dir
0226  CD 09 24      CALL config_max_cyl
0229  0E 00         LD C,0x00
022B  06 02         LD B,0x02
022D  3E 01         LD A,0x01
022F  21 1C 31      LD HL,cfg_flags
0232  CD 35 27      CALL config_save

; top idle loop: 'Wait for autoloader', poll autoloader + host serial commands
wait_autoloader_loop:
0235  CD 59 4C      CALL lcd_print
0238  0C 57 61 69 74 20 +  DB \f, "Wait for autoloader", 0

; probe autoloader (ping via R); classify NOT CONNECTED vs COMMUNICATION ERROR
al_connect_probe:
024D  3E 01         LD A,0x01
024F  32 62 31      LD (al_present),A
0252  06 52         LD B,0x52
0254  CD D9 13      CALL al_cmd_ack
0257  28 40         JR Z,loc_0299
0259  FE 01         CP 0x01
025B  20 30         JR NZ,loc_028D
025D  3A 4C 31      LD A,(fmt_mode)
0260  B7            OR A
0261  CA D9 02      JP Z,loc_02D9
0264  CD 59 4C      CALL lcd_print
0267  0C 43 4F 4D 4D 55 +  DB \f, "COMMUNICATION ERROR", 0
027C  3E 05         LD A,0x05
027E  CD 66 27      CALL beep
0281  DB D0         IN A,(0xD0)  ; al_data
0283  DB D0         IN A,(0xD0)  ; al_data
0285  DB D0         IN A,(0xD0)  ; al_data
0287  CD 43 4D      CALL keypad_debounce
028A  C3 35 02      JP wait_autoloader_loop

loc_028D:
028D  3E 52         LD A,0x52
028F  B8            CP B
0290  C2 99 02      JP NZ,loc_0299
0293  CD 3D 03      CALL manual_mode
0296  C3 5C 03      JP loc_035C

loc_0299:
0299  06 43         LD B,0x43
029B  CD D9 13      CALL al_cmd_ack
029E  CA 60 03      JP Z,loc_0360
02A1  78            LD A,B
02A2  FE 45         CP 0x45
02A4  20 33         JR NZ,loc_02D9
02A6  CD FB 13      CALL al_cmd_status
02A9  20 2E         JR NZ,loc_02D9
02AB  CD B0 02      CALL show_al_error
02AE  18 61         JR loc_0311

; draw "AL error / Status" line, wait keypress; preserves A across the message (autoloader fault)
show_al_error:
02B0  F5            PUSH AF
02B1  2A 4C 31      LD HL,(fmt_mode)
02B4  22 D1 02      LD (show_al_error+0x21),HL
02B7  CD 70 06      CALL lcd_clear_line2
02BA  CD 59 4C      CALL lcd_print
02BD  1B C0 41 4C 20 65 +  DB ESC(0xC0), "AL error   Status ..", 0
02D4  CD 43 4D      CALL keypad_debounce
02D7  F1            POP AF
02D8  C9            RET

loc_02D9:
02D9  CD 59 4C      CALL lcd_print
02DC  0C 41 55 54 4F 4C +  DB \f, "AUTOLOADER", \r, \n, "NOT CONNECTED", 0
02F7  21 8A 33      LD HL,retry_ctr
02FA  AF            XOR A
02FB  77            LD (HL),A
02FC  CD 0B 4D      CALL keypad_scan
02FF  20 02         JR NZ,loc_0303
0301  CB C6         SET 0,(HL)

loc_0303:
0303  E5            PUSH HL
0304  3E 05         LD A,0x05
0306  CD 66 27      CALL beep
0309  E1            POP HL
030A  CD 0B 4D      CALL keypad_scan
030D  28 02         JR Z,loc_0311
030F  CB CE         SET 1,(HL)

loc_0311:
0311  E5            PUSH HL
0312  CD 3D 03      CALL manual_mode
0315  3E 05         LD A,0x05
0317  CD 66 27      CALL beep
031A  E1            POP HL
031B  CD 0B 4D      CALL keypad_scan
031E  20 3C         JR NZ,loc_035C
0320  3E 03         LD A,0x03
0322  BE            CP (HL)
0323  20 37         JR NZ,loc_035C
0325  21 00 00      LD HL,0x0000
0328  22 69 32      LD (cycle_cnt_lo),HL
032B  22 6B 32      LD (cycle_cnt_hi),HL
032E  21 69 32      LD HL,cycle_cnt_lo
0331  06 04         LD B,0x04
0333  0E FC         LD C,0xFC
0335  3E 01         LD A,0x01
0337  CD 35 27      CALL config_save
033A  C3 61 01      JP run_entry

; MANUAL operation mode top level
manual_mode:
033D  CD 59 4C      CALL lcd_print
0340  0C 4D 41 4E 55 41 +  DB \f, "MANUAL", \r, \n, "OPERATION MODE", 0
0358  CD A9 03      CALL lcd_home3
035B  C9            RET

loc_035C:
035C  AF            XOR A
035D  32 62 31      LD (al_present),A

loc_0360:
0360  06 00         LD B,0x00
0362  CD 9D 4E      CALL host_tx
0365  CD 09 07      CALL motor_ready_wait
0368  CD 84 37      CALL fdc_home_head
036B  DC BD 01      CALL C,show_fdd_seek_error
036E  CD 57 07      CALL drive_cfg_latch
0371  3A 1D 31      LD A,(cfg_byte)
0374  DD 21 DD 52   LD IX,format_desc
0378  DD BE 0B      CP (IX+11)
037B  DD 77 0B      LD (IX+11),A
037E  32 4C 31      LD (fmt_mode),A
0381  28 04         JR Z,loc_0387
0383  AF            XOR A
0384  32 C8 52      LD (image_present),A

loc_0387:
0387  3E FE         LD A,0xFE
0389  32 C7 52      LD (menu_scratch+0x5),A
038C  CD 32 04      CALL fdd_detect
038F  CD E7 51      CALL fdc_build_unit_sel
0392  32 37 31      LD (unit_sel),A
0395  3E 81         LD A,0x81
0397  32 63 31      LD (side_sel),A
039A  3A 37 31      LD A,(unit_sel)
039D  CD 7B 04      CALL fdc_cmd_both_drives
03A0  2A 31 31      LD HL,(phase_handler)
03A3  CD 2F 52      CALL menu_run
03A6  C3 EB 01      JP loc_01EB

; reset LCD cursor to home (0,0), repeated 3x (multi-line addressing workaround)
lcd_home3:
03A9  06 03         LD B,0x03
03AB  21 00 00      LD HL,0x0000

loc_03AE:
03AE  CD 22 4C      CALL lcd_setpos
03B1  10 FB         DJNZ loc_03AE
03B3  C9            RET

; select DRAM image bank + latch drive config from cfg block
dram_bank_cfg:
03B4  21 1C 31      LD HL,cfg_flags
03B7  0E 00         LD C,0x00
03B9  06 04         LD B,0x04
03BB  AF            XOR A
03BC  CD 35 27      CALL config_save
03BF  3A 1E 31      LD A,(drv_active_cfg)
03C2  D3 9C         OUT (0x9C),A  ; ctrl_latch
03C4  32 55 31      LD (wprot_mode),A
03C7  3A 1F 31      LD A,(cfg_batch)
03CA  32 4A 31      LD (err_recovery),A
03CD  3A 1D 31      LD A,(cfg_byte)
03D0  E6 03         AND 0x03
03D2  21 67 31      LD HL,hrd_desc_tbl
03D5  77            LD (HL),A
03D6  C9            RET

; restore active DRAM bank (OUT 0x9C) from saved value
ctrl_latch_load:
03D7  3A 55 31      LD A,(wprot_mode)
03DA  D3 9C         OUT (0x9C),A  ; ctrl_latch
03DC  C9            RET

; size installed DRAM banks (walk via OUT 0xB0, test @0x8000) -> 'Test dram: N kB'
dram_test:
03DD  CD 59 4C      CALL lcd_print
03E0  0C 54 65 73 74 20 +  DB \f, "Test dram:", 0
03EC  3E FE         LD A,0xFE

loc_03EE:
03EE  D3 B0         OUT (0xB0),A  ; dram_bank
03F0  21 00 80      LD HL,image_buf
03F3  77            LD (HL),A
03F4  BE            CP (HL)
03F5  20 29         JR NZ,loc_0420
03F7  E5            PUSH HL
03F8  D1            POP DE
03F9  E5            PUSH HL
03FA  C1            POP BC
03FB  13            INC DE
03FC  ED B0         LDIR
03FE  F5            PUSH AF
03FF  ED 44         NEG
0401  6F            LD L,A
0402  26 00         LD H,0x00
0404  5C            LD E,H
0405  06 05         LD B,0x05

loc_0407:
0407  CB 25         SLA L
0409  CB 14         RL H
040B  CB 13         RL E
040D  10 F8         DJNZ loc_0407
040F  CD B2 4E      CALL bin2dec_clear
0412  CD 2C 4F      CALL lcd_print_number
0415  CD 59 4C      CALL lcd_print
0418  20 6B 42 00   DB " kB", 0
041C  F1            POP AF
041D  3D            DEC A
041E  18 CE         JR loc_03EE

loc_0420:
0420  3C            INC A
0421  32 30 31      LD (dram_bank_count),A
0424  CD 59 4C      CALL lcd_print
0427  20 6F 6B 00   DB " ok", 0
042B  21 00 00      LD HL,0x0000
042E  CD 22 4C      CALL lcd_setpos
0431  C9            RET

; detect FDDs, derive media-config index, install phase_handler from phase_handler_tbl
fdd_detect:
0432  3A 4C 31      LD A,(fmt_mode)
0435  CD 0A 52      CALL media_cfg_index
0438  FE 00         CP 0x00
043A  28 18         JR Z,loc_0454
043C  FE 01         CP 0x01
043E  28 14         JR Z,loc_0454
0440  FE 05         CP 0x05
0442  28 10         JR Z,loc_0454
0444  6F            LD L,A
0445  26 00         LD H,0x00
0447  29            ADD HL,HL
0448  11 44 14      LD DE,phase_handler_tbl
044B  19            ADD HL,DE
044C  5E            LD E,(HL)
044D  23            INC HL
044E  56            LD D,(HL)
044F  ED 53 31 31   LD (phase_handler),DE
0453  C9            RET

loc_0454:
0454  CD 59 4C      CALL lcd_print
0457  0C 55 6E 73 75 70 +  DB \f, "Unsupported FDD", \r, \n, "Run config again", 0
047A  76            HALT

; issue FDC command A to both drives via fdc_op_dispatch; head-select byte from cyl_head bit7
fdc_cmd_both_drives:
047B  47            LD B,A
047C  3A 64 31      LD A,(cyl_head)
047F  CB 7F         BIT 7,A
0481  0E 11         LD C,0x11
0483  20 01         JR NZ,loc_0486
0485  4F            LD C,A

loc_0486:
0486  C5            PUSH BC
0487  3E 01         LD A,0x01
0489  CD B2 33      CALL fdc_op_dispatch
048C  C1            POP BC
048D  3E 02         LD A,0x02
048F  CD B2 33      CALL fdc_op_dispatch
0492  C9            RET

; 'No. of copies' editor
edit_num_copies:
0493  CD 59 4C      CALL lcd_print
0496  1B C0 4E 6F 2E 20 +  DB ESC(0xC0), "No. of copies", 0
04A6  2A 3D 31      LD HL,(run_count)
04A9  22 43 31      LD (edit_value),HL
04AC  21 00 00      LD HL,0x0000
04AF  22 45 31      LD (edit_value_hi),HL
04B2  06 04         LD B,0x04
04B4  3E 0E         LD A,0x0E
04B6  CD C3 04      CALL edit_num_field
04B9  2A 43 31      LD HL,(edit_value)
04BC  22 3D 31      LD (run_count),HL
04BF  22 41 31      LD (copy_count),HL
04C2  C9            RET

; edit a numeric field on the LCD (cursor on, +/- keys, Enter)
edit_num_field:
04C3  4F            LD C,A
04C4  C5            PUSH BC
04C5  3E 0E         LD A,0x0E
04C7  0E E0         LD C,0xE0
04C9  CD 43 4C      CALL lcd_byte_out
04CC  AF            XOR A
04CD  32 4C 31      LD (fmt_mode),A

loc_04D0:
04D0  ED 5B 45 31   LD DE,(edit_value_hi)
04D4  2A 43 31      LD HL,(edit_value)
04D7  C1            POP BC
04D8  C5            PUSH BC
04D9  79            LD A,C
04DA  0E 30         LD C,0x30
04DC  CD FA 05      CALL num_to_lcd_alt
04DF  01 07 00      LD BC,0x0007
04E2  21 4D 31      LD HL,al_status1
04E5  11 4E 31      LD DE,run_status
04E8  36 00         LD (HL),0x00
04EA  ED B0         LDIR
04EC  C1            POP BC
04ED  C5            PUSH BC
04EE  48            LD C,B
04EF  06 00         LD B,0x00
04F1  21 38 4F      LD HL,lcd_dec_tmpl+0x9
04F4  11 4D 31      LD DE,al_status1

loc_04F7:
04F7  7E            LD A,(HL)
04F8  D6 30         SUB 0x30
04FA  77            LD (HL),A
04FB  ED A8         LDD
04FD  13            INC DE
04FE  13            INC DE
04FF  EA F7 04      JP PE,loc_04F7
0502  CD 2A 4C      CALL lcd_wait_busy
0505  C1            POP BC
0506  C5            PUSH BC
0507  79            LD A,C
0508  80            ADD A,B
0509  21 4C 31      LD HL,fmt_mode
050C  96            SUB (HL)
050D  3D            DEC A
050E  F6 C0         OR 0xC0
0510  01 E0 00      LD BC,0x00E0
0513  ED 79         OUT (C),A
0515  3E 01         LD A,0x01
0517  CD 89 4D      CALL get_key
051A  FE 04         CP 0x04
051C  C2 C5 05      JP NZ,loc_05C5
051F  21 4C 31      LD HL,fmt_mode
0522  5E            LD E,(HL)
0523  16 00         LD D,0x00
0525  21 4D 31      LD HL,al_status1
0528  19            ADD HL,DE
0529  34            INC (HL)
052A  3E 0A         LD A,0x0A
052C  BE            CP (HL)
052D  20 02         JR NZ,loc_0531
052F  36 00         LD (HL),0x00

loc_0531:
0531  11 E8 03      LD DE,0x03E8
0534  3A 54 31      LD A,(edit_max)
0537  0E 00         LD C,0x00
0539  CD 05 4F      CALL mul16
053C  EB            EX DE,HL
053D  3E 10         LD A,0x10
053F  0E 27         LD C,0x27
0541  CD 05 4F      CALL mul16
0544  22 43 31      LD (edit_value),HL
0547  ED 53 45 31   LD (edit_value_hi),DE
054B  11 E8 03      LD DE,0x03E8
054E  3A 53 31      LD A,(edit_min)
0551  0E 00         LD C,0x00
0553  CD 05 4F      CALL mul16
0556  EB            EX DE,HL
0557  3E E8         LD A,0xE8
0559  0E 03         LD C,0x03
055B  CD 05 4F      CALL mul16
055E  CD E6 05      CALL acc32_add
0561  11 E8 03      LD DE,0x03E8
0564  3A 52 31      LD A,(edit_col)
0567  0E 00         LD C,0x00
0569  CD 05 4F      CALL mul16
056C  EB            EX DE,HL
056D  3E 64         LD A,0x64
056F  0E 00         LD C,0x00
0571  CD 05 4F      CALL mul16
0574  CD E6 05      CALL acc32_add
0577  11 E8 03      LD DE,0x03E8
057A  3A 51 31      LD A,(edit_width)
057D  0E 00         LD C,0x00
057F  CD 05 4F      CALL mul16
0582  EB            EX DE,HL
0583  3E 0A         LD A,0x0A
0585  0E 00         LD C,0x00
0587  CD 05 4F      CALL mul16
058A  CD E6 05      CALL acc32_add
058D  11 E8 03      LD DE,0x03E8
0590  3A 50 31      LD A,(edit_ndigits)
0593  0E 00         LD C,0x00
0595  CD 05 4F      CALL mul16
0598  CD E6 05      CALL acc32_add
059B  11 64 00      LD DE,0x0064
059E  3A 4F 31      LD A,(rd_submode)
05A1  0E 00         LD C,0x00
05A3  CD 05 4F      CALL mul16
05A6  CD E6 05      CALL acc32_add
05A9  11 0A 00      LD DE,0x000A
05AC  3A 4E 31      LD A,(run_status)
05AF  0E 00         LD C,0x00
05B1  CD 05 4F      CALL mul16
05B4  CD E6 05      CALL acc32_add
05B7  3A 4D 31      LD A,(al_status1)
05BA  6F            LD L,A
05BB  26 00         LD H,0x00
05BD  54            LD D,H
05BE  5C            LD E,H
05BF  CD E6 05      CALL acc32_add
05C2  C3 D0 04      JP loc_04D0

loc_05C5:
05C5  FE 08         CP 0x08
05C7  20 10         JR NZ,loc_05D9
05C9  C1            POP BC
05CA  C5            PUSH BC
05CB  21 4C 31      LD HL,fmt_mode
05CE  34            INC (HL)
05CF  78            LD A,B
05D0  BE            CP (HL)
05D1  C2 D0 04      JP NZ,loc_04D0
05D4  36 00         LD (HL),0x00
05D6  C3 D0 04      JP loc_04D0

loc_05D9:
05D9  FE 02         CP 0x02
05DB  F5            PUSH AF
05DC  3E 0C         LD A,0x0C
05DE  0E E0         LD C,0xE0
05E0  CD 43 4C      CALL lcd_byte_out
05E3  F1            POP AF
05E4  C1            POP BC
05E5  C9            RET

; add 16-bit HL into the 32-bit accumulator at 0x3143/0x3145 (edit-field value builder)
acc32_add:
05E6  D5            PUSH DE
05E7  ED 5B 43 31   LD DE,(edit_value)
05EB  19            ADD HL,DE
05EC  22 43 31      LD (edit_value),HL
05EF  E1            POP HL
05F0  ED 5B 45 31   LD DE,(edit_value_hi)
05F4  ED 5A         ADC HL,DE
05F6  22 45 31      LD (edit_value_hi),HL
05F9  C9            RET

; num_to_lcd variant with extra attribute bit (0xC0) selecting alternate LCD line/position
num_to_lcd_alt:
05FA  F6 C0         OR 0xC0

; render 16-bit value as right-justified decimal on LCD at position A, field width B, pad char C
num_to_lcd:
05FC  F6 80         OR 0x80
05FE  32 30 06      LD (lcd_num_tmpl+0x1),A
0601  E5            PUSH HL
0602  C5            PUSH BC
0603  06 08         LD B,0x08
0605  21 31 06      LD HL,lcd_num_tmpl+0x2

loc_0608:
0608  36 00         LD (HL),0x00
060A  23            INC HL
060B  10 FB         DJNZ loc_0608
060D  C1            POP BC
060E  C5            PUSH BC
060F  21 38 4F      LD HL,lcd_dec_tmpl+0x9

loc_0612:
0612  71            LD (HL),C
0613  2B            DEC HL
0614  10 FC         DJNZ loc_0612
0616  C1            POP BC
0617  E1            POP HL
0618  C5            PUSH BC
0619  CD B5 4E      CALL bin2dec
061C  21 38 4F      LD HL,lcd_dec_tmpl+0x9
061F  C1            POP BC
0620  48            LD C,B
0621  06 00         LD B,0x00
0623  A7            AND A
0624  ED 42         SBC HL,BC
0626  23            INC HL
0627  11 31 06      LD DE,lcd_num_tmpl+0x2
062A  ED B0         LDIR
062C  CD 59 4C      CALL lcd_print

lcd_num_tmpl:
062F  1B 00 31 32 33 34 +  DB ESC(0x00), "12345678", 0
063A  C9            RET

; show run counters on line 2: track_ctr and pass_ctr as two 4-digit decimals (OK/bad tally)
show_ok_bad_count:
063B  E5            PUSH HL
063C  F5            PUSH AF
063D  CD 70 06      CALL lcd_clear_line2
0640  2A 39 31      LD HL,(track_ctr)
0643  11 00 00      LD DE,0x0000
0646  3E 00         LD A,0x00
0648  0E 20         LD C,0x20
064A  06 04         LD B,0x04
064C  CD FA 05      CALL num_to_lcd_alt
064F  CD 59 4C      CALL lcd_print
0652  20 6F 6B 00   DB " ok", 0
0656  2A 3B 31      LD HL,(pass_ctr)
0659  11 00 00      LD DE,0x0000
065C  3E 08         LD A,0x08
065E  0E 20         LD C,0x20
0660  06 04         LD B,0x04
0662  CD FA 05      CALL num_to_lcd_alt
0665  CD 59 4C      CALL lcd_print
0668  20 62 61 64 00  DB " bad", 0
066D  F1            POP AF
066E  E1            POP HL
066F  C9            RET

; blank LCD line 2 (ESC 0xC0 home + 20 spaces), preserving AF
lcd_clear_line2:
0670  F5            PUSH AF
0671  CD 59 4C      CALL lcd_print
0674  1B C0 20 20 20 20 +  DB ESC(0xC0), "                    ", 0
068B  F1            POP AF
068C  C9            RET

; blank LCD line 1 (ESC 0x80 home + 20 spaces)
lcd_clear_line1:
068D  CD 59 4C      CALL lcd_print
0690  1B 80 20 20 20 20 +  DB ESC(0x80), "                    ", 0
06A7  C9            RET

; inc/dec an ASCII digit pair (config value at 0x27FC) per cfg_flags bit7 up/down, 0-9 wrap+carry
pit_adjust_digits:
06A8  3E D2         LD A,0xD2
06AA  32 FA 27      LD (lcd_val_tmpl+0x1),A
06AD  21 FC 27      LD HL,lcd_val_tmpl+0x3
06B0  3A 1C 31      LD A,(cfg_flags)
06B3  CB 7F         BIT 7,A
06B5  28 03         JR Z,loc_06BA
06B7  34            INC (HL)
06B8  18 01         JR loc_06BB

loc_06BA:
06BA  35            DEC (HL)

loc_06BB:
06BB  3E 3A         LD A,0x3A
06BD  BE            CP (HL)
06BE  3E 30         LD A,0x30
06C0  28 07         JR Z,loc_06C9
06C2  3E 2F         LD A,0x2F
06C4  BE            CP (HL)
06C5  20 0F         JR NZ,loc_06D6
06C7  3E 39         LD A,0x39

loc_06C9:
06C9  77            LD (HL),A
06CA  2B            DEC HL
06CB  3A 1C 31      LD A,(cfg_flags)
06CE  CB 7F         BIT 7,A
06D0  28 03         JR Z,loc_06D5
06D2  34            INC (HL)
06D3  18 01         JR loc_06D6

loc_06D5:
06D5  35            DEC (HL)

loc_06D6:
06D6  CD F5 27      CALL hrd_emit_num

; reload 8253 counters c1/c2 (control words 0x50,0x90) to restart index timing
pit_reload_c12:
06D9  3E 50         LD A,0x50
06DB  D3 AC         OUT (0xAC),A  ; pit_ctrl
06DD  3E 90         LD A,0x90
06DF  D3 AC         OUT (0xAC),A  ; pit_ctrl
06E1  C9            RET

; step drive toward target track A, tracking current track at 0x3133, issuing seeks until reached
fdc_step_to_track:
06E2  21 33 31      LD HL,cur_track
06E5  BE            CP (HL)
06E6  C8            RET Z
06E7  FA EC 06      JP M,loc_06EC
06EA  34            INC (HL)
06EB  34            INC (HL)

loc_06EC:
06EC  F5            PUSH AF
06ED  35            DEC (HL)
06EE  7E            LD A,(HL)
06EF  32 EB 4A      LD (drive_blk_a),A
06F2  AF            XOR A
06F3  32 EC 4A      LD (drive_blk_a+0x1),A
06F6  3E 01         LD A,0x01
06F8  CD 2A 43      CALL fdc_seek_sel
06FB  3E 01         LD A,0x01
06FD  CD 25 07      CALL fdc_wait_unit1
0700  21 00 02      LD HL,0x0200
0703  CD 22 4C      CALL lcd_setpos
0706  F1            POP AF
0707  18 D9         JR fdc_step_to_track

; spin-up/ready wait: recalibrate+seek both drives, retry up to 5x; returns Z when ready
motor_ready_wait:
0709  AF            XOR A
070A  32 33 31      LD (cur_track),A
070D  CD 4F 07      CALL set_drive_cfg
0710  CD 2D 07      CALL seek_both_drives
0713  C8            RET Z
0714  06 05         LD B,0x05

loc_0716:
0716  C5            PUSH BC
0717  CD 4F 07      CALL set_drive_cfg
071A  CD 2D 07      CALL seek_both_drives
071D  C1            POP BC
071E  C8            RET Z
071F  CD E1 01      CALL reset_seek_state
0722  10 F2         DJNZ loc_0716
0724  C9            RET

; poll FDC unit-1 seek/op completion, looping until done
fdc_wait_unit1:
0725  3E 01         LD A,0x01
0727  CD 2D 47      CALL fdc_poll_complete
072A  28 F9         JR Z,fdc_wait_unit1
072C  C9            RET

; recalibrate+seek unit1 (and unit2 if double-sided), then flag not-ready error
seek_both_drives:
072D  3E 01         LD A,0x01
072F  CD 4C 39      CALL fdc_recal_seek
0732  CD 25 07      CALL fdc_wait_unit1
0735  DD 21 DD 52   LD IX,format_desc
0739  DD CB 0B 66   BIT 4,(IX+11)
073D  28 0C         JR Z,loc_074B
073F  3E 02         LD A,0x02
0741  CD 4C 39      CALL fdc_recal_seek

loc_0744:
0744  3E 02         LD A,0x02
0746  CD 2D 47      CALL fdc_poll_complete
0749  28 F9         JR Z,loc_0744

loc_074B:
074B  CD 81 49      CALL fdc_err_notready
074E  C9            RET

; load drv_active_cfg (0x2D active pattern) into both drive-config latches (ports 0x40/0x60); idle pattern is 0x0E
set_drive_cfg:
074F  3A 1E 31      LD A,(drv_active_cfg)
0752  D3 40         OUT (0x40),A  ; drv_lat0
0754  D3 60         OUT (0x60),A  ; drv_lat2
0756  C9            RET

; write 0x0E to both drive latches (0x40/0x60): deselect / motors-off idle state
drive_cfg_latch:
0757  3E 0E         LD A,0x0E
0759  D3 40         OUT (0x40),A  ; drv_lat0
075B  3E 0E         LD A,0x0E
075D  D3 60         OUT (0x60),A  ; drv_lat2
075F  C9            RET

; datarate ctrl-latch helper: set/clear bit2 of (HL), OUT to port C, mirror bit0 into ctrl_latch 0x9C
update_ctrl_latch:
0760  B7            OR A
0761  CB 96         RES 2,(HL)
0763  20 02         JR NZ,loc_0767
0765  CB D6         SET 2,(HL)

loc_0767:
0767  57            LD D,A
0768  7E            LD A,(HL)
0769  ED 79         OUT (C),A
076B  C8            RET Z
076C  7A            LD A,D
076D  FE 01         CP 0x01
076F  7B            LD A,E
0770  20 02         JR NZ,loc_0774
0772  F6 01         OR 0x01

loc_0774:
0774  D3 9C         OUT (0x9C),A  ; ctrl_latch
0776  C9            RET

; threshold table lookup: scan B entries at HL, return value C for the band matching input (rate/precomp by cyl)
range_table_lookup:
0777  C5            PUSH BC
0778  D5            PUSH DE
0779  51            LD D,C

loc_077A:
077A  7A            LD A,D
077B  BE            CP (HL)
077C  23            INC HL
077D  FA 81 07      JP M,loc_0781
0780  4E            LD C,(HL)

loc_0781:
0781  23            INC HL
0782  10 F6         DJNZ loc_077A
0784  79            LD A,C
0785  D1            POP DE
0786  C1            POP BC
0787  C9            RET

; duplication engine main loop: spin-up, read source, run current phase
dup_engine_loop:
0788  CD D7 03      CALL ctrl_latch_load

; ensure motor ready via motor_ready_wait; on failure jump to batch error tail 0x10B0
require_motor_ready:
078B  CD 09 07      CALL motor_ready_wait
078E  28 03         JR Z,loc_0793
0790  C3 B0 10      JP loc_10B0

loc_0793:
0793  21 00 00      LD HL,0x0000
0796  22 39 31      LD (track_ctr),HL
0799  22 3B 31      LD (pass_ctr),HL

loc_079C:
079C  CD 4F 07      CALL set_drive_cfg
079F  3A 34 31      LD A,(op_word)
07A2  A7            AND A
07A3  20 06         JR NZ,loc_07AB
07A5  3A 4E 31      LD A,(run_status)
07A8  A7            AND A
07A9  20 10         JR NZ,loc_07BB

loc_07AB:
07AB  CD B4 11      CALL read_source
07AE  28 0B         JR Z,loc_07BB
07B0  CD CB 1D      CALL show_abort
07B3  21 34 31      LD HL,op_word
07B6  CB FE         SET 7,(HL)
07B8  C3 B0 10      JP loc_10B0

loc_07BB:
07BB  CD A0 11      CALL is_op_mode9
07BE  CA 43 08      JP Z,loc_0843
07C1  CD 34 08      CALL fdc_build_select
07C4  30 7D         JR NC,loc_0843
07C6  F5            PUSH AF
07C7  CD 70 06      CALL lcd_clear_line2
07CA  F1            POP AF
07CB  FE 00         CP 0x00
07CD  20 3D         JR NZ,loc_080C
07CF  CD 59 4C      CALL lcd_print
07D2  1B C0 46 44 44 20 +  DB ESC(0xC0), "FDD not ready", 0

loc_07E2:
07E2  3E 05         LD A,0x05
07E4  CD 66 27      CALL beep
07E7  CD 2D 11      CALL al_cmd_reject
07EA  3E 92         LD A,0x92
07EC  32 4C 31      LD (fmt_mode),A
07EF  AF            XOR A
07F0  32 50 31      LD (edit_ndigits),A
07F3  3A 61 31      LD A,(host_mode)
07F6  B7            OR A
07F7  C2 B0 10      JP NZ,loc_10B0
07FA  AF            XOR A
07FB  CD 89 4D      CALL get_key
07FE  28 9C         JR Z,loc_079C
0800  3E 01         LD A,0x01
0802  CD 89 4D      CALL get_key
0805  E6 0F         AND 0x0F
0807  FE 02         CP 0x02
0809  20 91         JR NZ,loc_079C
080B  C9            RET

loc_080C:
080C  CD 11 08      CALL show_rpm_low
080F  18 D1         JR loc_07E2

; RPM out-of-range warning: A=1 draws "rpm low", A=2 "rpm high", 0 shows nothing
show_rpm_low:
0811  B7            OR A
0812  C8            RET Z
0813  FE 02         CP 0x02
0815  28 0E         JR Z,loc_0825
0817  CD 59 4C      CALL lcd_print
081A  1B C0 72 70 6D 20 +  DB ESC(0xC0), "rpm low", 0
0824  C9            RET

loc_0825:
0825  CD 59 4C      CALL lcd_print
0828  1B C0 72 70 6D 20 +  DB ESC(0xC0), "rpm high", 0
0833  C9            RET

; build FDC drive/head select byte from unit_sel/cyl_head
fdc_build_select:
0834  3A 37 31      LD A,(unit_sel)
0837  47            LD B,A
0838  3A 64 31      LD A,(cyl_head)
083B  E6 7F         AND 0x7F
083D  4F            LD C,A
083E  3E 01         LD A,0x01
0840  C3 DB 37      JP index_period_timer

loc_0843:
0843  CD 81 49      CALL fdc_err_notready
0846  C4 09 07      CALL NZ,motor_ready_wait
0849  C0            RET NZ
084A  CD D9 06      CALL pit_reload_c12
084D  21 30 2F      LD HL,0x2F30
0850  3A 1C 31      LD A,(cfg_flags)
0853  CB 7F         BIT 7,A
0855  20 18         JR NZ,loc_086F
0857  E6 7F         AND 0x7F
0859  20 04         JR NZ,loc_085F
085B  3A DD 52      LD A,(format_desc)
085E  3D            DEC A

loc_085F:
085F  3C            INC A
0860  11 00 00      LD DE,0x0000
0863  6F            LD L,A
0864  63            LD H,E
0865  CD B2 4E      CALL bin2dec_clear
0868  21 38 4F      LD HL,lcd_dec_tmpl+0x9
086B  56            LD D,(HL)
086C  2B            DEC HL
086D  5E            LD E,(HL)
086E  EB            EX DE,HL

loc_086F:
086F  22 FB 27      LD (lcd_val_tmpl+0x2),HL
0872  3A 34 31      LD A,(op_word)
0875  CB 67         BIT 4,A
0877  20 11         JR NZ,loc_088A
0879  E6 0F         AND 0x0F
087B  FE 00         CP 0x00
087D  28 0B         JR Z,loc_088A
087F  FE 07         CP 0x07
0881  28 07         JR Z,loc_088A
0883  FE 09         CP 0x09
0885  28 03         JR Z,loc_088A
0887  CD 3B 06      CALL show_ok_bad_count

loc_088A:
088A  21 67 31      LD HL,hrd_desc_tbl
088D  CB 4E         BIT 1,(HL)
088F  28 27         JR Z,loc_08B8
0891  3A 34 31      LD A,(op_word)
0894  FE 01         CP 0x01
0896  28 0C         JR Z,loc_08A4
0898  FE 04         CP 0x04
089A  28 08         JR Z,loc_08A4
089C  FE 02         CP 0x02
089E  28 04         JR Z,loc_08A4
08A0  FE 06         CP 0x06
08A2  20 14         JR NZ,loc_08B8

loc_08A4:
08A4  3A 72 31      LD A,(serial_flag)
08A7  ED 5B 73 31   LD DE,(serial_addr)
08AB  21 68 31      LD HL,serial_nr
08AE  01 04 00      LD BC,0x0004
08B1  D3 B0         OUT (0xB0),A  ; dram_bank
08B3  ED B0         LDIR
08B5  CD 9C 51      CALL set_bank_checksum

loc_08B8:
08B8  21 1C 31      LD HL,cfg_flags
08BB  CB 7E         BIT 7,(HL)
08BD  20 14         JR NZ,loc_08D3
08BF  7E            LD A,(HL)
08C0  E6 7F         AND 0x7F
08C2  20 04         JR NZ,loc_08C8
08C4  3A DD 52      LD A,(format_desc)
08C7  3D            DEC A

loc_08C8:
08C8  F5            PUSH AF
08C9  CD E2 06      CALL fdc_step_to_track
08CC  CD 34 08      CALL fdc_build_select
08CF  F1            POP AF
08D0  6F            LD L,A
08D1  18 02         JR loc_08D5

loc_08D3:
08D3  2E 00         LD L,0x00

loc_08D5:
08D5  26 00         LD H,0x00
08D7  22 35 31      LD (datarate_idx),HL
08DA  AF            XOR A
08DB  32 49 31      LD (op_flag_49),A
08DE  DD 21 DD 52   LD IX,format_desc
08E2  DD 46 00      LD B,(IX+0)
08E5  3A 1C 31      LD A,(cfg_flags)
08E8  E6 7F         AND 0x7F
08EA  28 02         JR Z,loc_08EE
08EC  3C            INC A
08ED  47            LD B,A

loc_08EE:
08EE  21 77 31      LD HL,serial_ptr+0x2
08F1  CB C6         SET 0,(HL)

loc_08F3:
08F3  C5            PUSH BC
08F4  2A 35 31      LD HL,(datarate_idx)
08F7  FD 21 EB 4A   LD IY,drive_blk_a
08FB  FD 75 00      LD (IY+0),L
08FE  FD 74 01      LD (IY+1),H
0901  3E 01         LD A,0x01
0903  CD 2A 43      CALL fdc_seek_sel
0906  21 2F 31      LD HL,fmt_geom_ptr+0xF
0909  CB C6         SET 0,(HL)
090B  CD A8 06      CALL pit_adjust_digits
090E  DD 21 DD 52   LD IX,format_desc
0912  DD 46 01      LD B,(IX+1)

loc_0915:
0915  C5            PUSH BC
0916  21 5F 31      LD HL,fdc_rate_a
0919  AF            XOR A
091A  77            LD (HL),A
091B  23            INC HL
091C  77            LD (HL),A
091D  DB F0         IN A,(0xF0)  ; panel
091F  CB 7F         BIT 7,A
0921  3A 35 31      LD A,(datarate_idx)
0924  4F            LD C,A
0925  06 06         LD B,0x06
0927  21 A1 31      LD HL,hrd_hd0
092A  CD 77 07      CALL range_table_lookup
092D  32 5F 31      LD (fdc_rate_a),A
0930  21 AD 31      LD HL,hrd_test_idx+0x8
0933  CD 77 07      CALL range_table_lookup
0936  32 60 31      LD (fdc_rate_b),A
0939  DD 7E 0B      LD A,(IX+11)
093C  CB 67         BIT 4,A
093E  28 1C         JR Z,loc_095C

; program FDC data rate & write-precomp from geometry via range tables; OUT fdc_reg/precomp/rate
fdc_datarate_precomp:
0940  21 1C 4B      LD HL,drive_blk_b+0x16
0943  0E 70         LD C,0x70
0945  1E 0A         LD E,0x0A
0947  3A 60 31      LD A,(fdc_rate_b)
094A  CD 60 07      CALL update_ctrl_latch

loc_094D:
094D  3A 5F 31      LD A,(fdc_rate_a)

loc_0950:
0950  21 01 4B      LD HL,drive_blk_a+0x16
0953  0E 50         LD C,0x50
0955  1E 08         LD E,0x08
0957  CD 60 07      CALL update_ctrl_latch
095A  18 0C         JR loc_0968

loc_095C:
095C  3A 36 31      LD A,(precomp_idx)
095F  CB 7F         BIT 7,A
0961  3A 60 31      LD A,(fdc_rate_b)
0964  20 EA         JR NZ,loc_0950
0966  18 E5         JR loc_094D

loc_0968:
0968  3A 35 31      LD A,(datarate_idx)
096B  4F            LD C,A
096C  06 04         LD B,0x04
096E  21 B9 31      LD HL,param_tables
0971  CD 77 07      CALL range_table_lookup
0974  5F            LD E,A
0975  21 11 32      LD HL,datarate_tbl+0x50
0978  CD 77 07      CALL range_table_lookup
097B  0F            RRCA
097C  0F            RRCA
097D  CB 03         RLC E
097F  CB 03         RLC E
0981  B3            OR E
0982  F6 30         OR 0x30
0984  E6 FC         AND 0xFC
0986  21 89 4B      LD HL,fdc_rate_reg
0989  B6            OR (HL)
098A  23            INC HL
098B  CB A7         RES 4,A
098D  CB EF         SET 5,A
098F  4F            LD C,A
0990  D3 B1         OUT (0xB1),A  ; fdc_reg
0992  7E            LD A,(HL)
0993  D3 C2         OUT (0xC2),A  ; fdc_precomp
0995  2A 35 31      LD HL,(datarate_idx)
0998  26 00         LD H,0x00
099A  E5            PUSH HL
099B  11 C1 31      LD DE,datarate_tbl
099E  19            ADD HL,DE
099F  7E            LD A,(HL)
09A0  D3 C3         OUT (0xC3),A  ; fdc_rate
09A2  E1            POP HL
09A3  11 19 32      LD DE,precomp_tbl
09A6  19            ADD HL,DE
09A7  79            LD A,C
09A8  CB E7         SET 4,A
09AA  CB AF         RES 5,A
09AC  D3 B1         OUT (0xB1),A  ; fdc_reg
09AE  7E            LD A,(HL)
09AF  D3 C2         OUT (0xC2),A  ; fdc_precomp
09B1  79            LD A,C
09B2  F6 30         OR 0x30
09B4  D3 B1         OUT (0xB1),A  ; fdc_reg
09B6  18 00         JR loc_09B8

loc_09B8:
09B8  2A 35 31      LD HL,(datarate_idx)
09BB  E5            PUSH HL
09BC  7C            LD A,H
09BD  B5            OR L
09BE  28 1A         JR Z,loc_09DA
09C0  3A 66 31      LD A,(precomp_sel)
09C3  B7            OR A
09C4  28 2F         JR Z,loc_09F5
09C6  3A 37 31      LD A,(unit_sel)
09C9  47            LD B,A
09CA  3A 64 31      LD A,(cyl_head)
09CD  4F            LD C,A
09CE  3E 01         LD A,0x01
09D0  CD B2 33      CALL fdc_op_dispatch
09D3  21 66 31      LD HL,precomp_sel
09D6  36 00         LD (HL),0x00
09D8  18 1B         JR loc_09F5

loc_09DA:
09DA  3A 64 31      LD A,(cyl_head)
09DD  FE 04         CP 0x04
09DF  28 04         JR Z,loc_09E5
09E1  FE 0E         CP 0x0E
09E3  20 10         JR NZ,loc_09F5

loc_09E5:
09E5  3A 37 31      LD A,(unit_sel)
09E8  47            LD B,A
09E9  0E 11         LD C,0x11
09EB  3E 01         LD A,0x01
09ED  CD B2 33      CALL fdc_op_dispatch
09F0  21 66 31      LD HL,precomp_sel
09F3  36 01         LD (HL),0x01

loc_09F5:
09F5  E1            POP HL
09F6  FD 21 EB 4A   LD IY,drive_blk_a
09FA  FD 75 00      LD (IY+0),L
09FD  FD 74 01      LD (IY+1),H

; geometry: logical block -> CHS via block_to_chs, store into both drive blocks
geom_seek_build:
0A00  FD 21 06 4B   LD IY,drive_blk_b
0A04  FD 75 00      LD (IY+0),L
0A07  3A 63 31      LD A,(side_sel)
0A0A  FD 77 01      LD (IY+1),A
0A0D  E5            PUSH HL
0A0E  4C            LD C,H
0A0F  45            LD B,L
0A10  CD F2 4F      CALL block_to_chs
0A13  DD 21 EB 4A   LD IX,drive_blk_a
0A17  DD 77 07      LD (IX+7),A
0A1A  DD 73 08      LD (IX+8),E
0A1D  DD 72 09      LD (IX+9),D
0A20  DD 75 0C      LD (IX+12),L
0A23  DD 74 0D      LD (IX+13),H
0A26  E1            POP HL
0A27  3A 63 31      LD A,(side_sel)
0A2A  4F            LD C,A
0A2B  45            LD B,L
0A2C  CD F2 4F      CALL block_to_chs
0A2F  DD 21 06 4B   LD IX,drive_blk_b
0A33  DD 77 07      LD (IX+7),A
0A36  DD 73 08      LD (IX+8),E
0A39  DD 72 09      LD (IX+9),D
0A3C  DD 75 0C      LD (IX+12),L
0A3F  DD 74 0D      LD (IX+13),H
0A42  21 49 31      LD HL,op_flag_49
0A45  34            INC (HL)
0A46  DD 21 DD 52   LD IX,format_desc
0A4A  3E 00         LD A,0x00
0A4C  DD CB 0B 66   BIT 4,(IX+11)
0A50  28 02         JR Z,loc_0A54
0A52  3E 02         LD A,0x02

loc_0A54:
0A54  CD EB 48      CALL fdc_set_cmdmode
0A57  21 2F 31      LD HL,fmt_geom_ptr+0xF
0A5A  CB 46         BIT 0,(HL)
0A5C  CB 86         RES 0,(HL)
0A5E  C4 25 07      CALL NZ,fdc_wait_unit1
0A61  DD 21 DD 52   LD IX,format_desc
0A65  3A 35 31      LD A,(datarate_idx)
0A68  FE 01         CP 0x01
0A6A  28 05         JR Z,loc_0A71
0A6C  DD 46 00      LD B,(IX+0)
0A6F  05            DEC B
0A70  B8            CP B

loc_0A71:
0A71  CC 7A 43      CALL Z,fdc_seek45_both
0A74  3A 1D 31      LD A,(cfg_byte)
0A77  E6 A4         AND 0xA4
0A79  FE 84         CP 0x84
0A7B  20 06         JR NZ,loc_0A83
0A7D  21 00 0C      LD HL,0x0C00
0A80  CD 22 4C      CALL lcd_setpos

loc_0A83:
0A83  21 34 31      LD HL,op_word
0A86  7E            LD A,(HL)
0A87  E6 0F         AND 0x0F
0A89  FE 00         CP 0x00
0A8B  20 32         JR NZ,loc_0ABF
0A8D  3A 4E 31      LD A,(run_status)
0A90  B7            OR A
0A91  C2 F3 0A      JP NZ,loc_0AF3
0A94  CB 66         BIT 4,(HL)
0A96  20 07         JR NZ,loc_0A9F
0A98  E5            PUSH HL
0A99  CD 57 0C      CALL show_in_progress
0A9C  E1            POP HL
0A9D  CB E6         SET 4,(HL)

loc_0A9F:
0A9F  3E 64         LD A,0x64
0AA1  D3 AC         OUT (0xAC),A  ; pit_ctrl
0AA3  3E 00         LD A,0x00
0AA5  D3 A4         OUT (0xA4),A  ; pit_c1
0AA7  3E 0E         LD A,0x0E
0AA9  D3 9C         OUT (0x9C),A  ; ctrl_latch
0AAB  DD CB 0B 66   BIT 4,(IX+11)
0AAF  20 08         JR NZ,loc_0AB9
0AB1  3E 01         LD A,0x01
0AB3  CD 18 3A      CALL fdc_send_dma
0AB6  C3 71 0D      JP loc_0D71

loc_0AB9:
0AB9  CD 83 3A      CALL fdc_read_dual
0ABC  C3 71 0D      JP loc_0D71

loc_0ABF:
0ABF  FE 01         CP 0x01
0AC1  20 14         JR NZ,loc_0AD7

loc_0AC3:
0AC3  DD CB 0B 66   BIT 4,(IX+11)
0AC7  20 08         JR NZ,loc_0AD1
0AC9  3E 01         LD A,0x01
0ACB  CD 53 3F      CALL fdc_read_src
0ACE  C3 6C 0C      JP loc_0C6C

loc_0AD1:
0AD1  CD C3 40      CALL fdc_copy_track
0AD4  C3 6C 0C      JP loc_0C6C

loc_0AD7:
0AD7  FE 02         CP 0x02
0AD9  20 14         JR NZ,loc_0AEF

loc_0ADB:
0ADB  DD CB 0B 66   BIT 4,(IX+11)
0ADF  20 08         JR NZ,loc_0AE9
0AE1  3E 01         LD A,0x01
0AE3  CD 7F 42      CALL fdc_read_src_b
0AE6  C3 6C 0C      JP loc_0C6C

loc_0AE9:
0AE9  CD 38 0C      CALL write_both_sides
0AEC  C3 6C 0C      JP loc_0C6C

loc_0AEF:
0AEF  FE 03         CP 0x03
0AF1  20 59         JR NZ,loc_0B4C

loc_0AF3:
0AF3  DD 21 DD 52   LD IX,format_desc
0AF7  DD 46 0C      LD B,(IX+12)
0AFA  DD 5E 0D      LD E,(IX+13)
0AFD  DD 56 0E      LD D,(IX+14)
0B00  DD 21 EB 4A   LD IX,drive_blk_a
0B04  DD 7E 07      LD A,(IX+7)
0B07  DD 6E 0C      LD L,(IX+12)
0B0A  DD 66 0D      LD H,(IX+13)
0B0D  32 56 31      LD (track_bank_a),A
0B10  22 58 31      LD (track_off),HL
0B13  DD 70 07      LD (IX+7),B
0B16  DD 73 0C      LD (IX+12),E
0B19  DD 72 0D      LD (IX+13),D
0B1C  DD 21 DD 52   LD IX,format_desc
0B20  DD 46 0F      LD B,(IX+15)
0B23  DD 5E 10      LD E,(IX+16)
0B26  DD 56 11      LD D,(IX+17)
0B29  DD 21 06 4B   LD IX,drive_blk_b
0B2D  DD 7E 07      LD A,(IX+7)
0B30  DD 6E 0C      LD L,(IX+12)
0B33  DD 66 0D      LD H,(IX+13)
0B36  32 57 31      LD (track_bank_b),A
0B39  22 5A 31      LD (read_addr),HL
0B3C  DD 70 07      LD (IX+7),B
0B3F  DD 73 0C      LD (IX+12),E
0B42  DD 72 0D      LD (IX+13),D
0B45  DD 21 DD 52   LD IX,format_desc
0B49  C3 9F 0A      JP loc_0A9F

loc_0B4C:
0B4C  FE 04         CP 0x04
0B4E  20 03         JR NZ,loc_0B53
0B50  C3 C3 0A      JP loc_0AC3

loc_0B53:
0B53  FE 05         CP 0x05
0B55  20 14         JR NZ,loc_0B6B

loc_0B57:
0B57  DD CB 0B 66   BIT 4,(IX+11)
0B5B  20 08         JR NZ,loc_0B65
0B5D  3E 01         LD A,0x01
0B5F  CD 6B 3E      CALL fdc_dma_arm2
0B62  C3 71 0D      JP loc_0D71

loc_0B65:
0B65  CD B9 3D      CALL fdc_read_dma_prep
0B68  C3 71 0D      JP loc_0D71

loc_0B6B:
0B6B  FE 06         CP 0x06
0B6D  20 14         JR NZ,loc_0B83

loc_0B6F:
0B6F  DD CB 0B 66   BIT 4,(IX+11)
0B73  20 08         JR NZ,loc_0B7D
0B75  3E 01         LD A,0x01
0B77  CD 24 3B      CALL fdc_write_poll
0B7A  C3 6C 0C      JP loc_0C6C

loc_0B7D:
0B7D  CD 27 0C      CALL read_both_sides
0B80  C3 6C 0C      JP loc_0C6C

loc_0B83:
0B83  FE 08         CP 0x08
0B85  CA F3 0A      JP Z,loc_0AF3
0B88  FE 09         CP 0x09
0B8A  C2 96 0B      JP NZ,loc_0B96
0B8D  21 00 10      LD HL,0x1000
0B90  CD 22 4C      CALL lcd_setpos
0B93  C3 A4 0D      JP loc_0DA4

loc_0B96:
0B96  FE 07         CP 0x07
0B98  C2 BF 0A      JP NZ,loc_0ABF
0B9B  21 77 31      LD HL,serial_ptr+0x2
0B9E  CB 46         BIT 0,(HL)
0BA0  28 45         JR Z,loc_0BE7

loc_0BA2:
0BA2  CD 74 49      CALL fdc_drive_ready
0BA5  20 2A         JR NZ,loc_0BD1
0BA7  3A C8 52      LD A,(image_present)
0BAA  B7            OR A
0BAB  20 0F         JR NZ,loc_0BBC
0BAD  CD 2D 11      CALL al_cmd_reject
0BB0  38 05         JR C,loc_0BB7
0BB2  CD B4 11      CALL read_source
0BB5  28 EB         JR Z,loc_0BA2

loc_0BB7:
0BB7  E1            POP HL
0BB8  E1            POP HL
0BB9  C3 B0 10      JP loc_10B0

loc_0BBC:
0BBC  3A 4F 31      LD A,(rd_submode)
0BBF  32 4E 31      LD (run_status),A
0BC2  CD 70 06      CALL lcd_clear_line2
0BC5  CD 59 4C      CALL lcd_print
0BC8  1B C0 63 6F 70 79 +  DB ESC(0xC0), "copy", 0
0BCF  18 16         JR loc_0BE7

loc_0BD1:
0BD1  3E 00         LD A,0x00
0BD3  32 4E 31      LD (run_status),A
0BD6  CD 70 06      CALL lcd_clear_line2
0BD9  CD 59 4C      CALL lcd_print
0BDC  1B C0 72 65 61 64 +  DB ESC(0xC0), "read", 0
0BE3  AF            XOR A
0BE4  32 C8 52      LD (image_present),A

loc_0BE7:
0BE7  3A 4E 31      LD A,(run_status)
0BEA  FE 00         CP 0x00
0BEC  20 03         JR NZ,loc_0BF1
0BEE  C3 9F 0A      JP loc_0A9F

loc_0BF1:
0BF1  FE 01         CP 0x01
0BF3  20 03         JR NZ,loc_0BF8
0BF5  C3 C3 0A      JP loc_0AC3

loc_0BF8:
0BF8  FE 02         CP 0x02
0BFA  20 03         JR NZ,loc_0BFF
0BFC  C3 DB 0A      JP loc_0ADB

loc_0BFF:
0BFF  FE 05         CP 0x05
0C01  20 03         JR NZ,loc_0C06
0C03  C3 57 0B      JP loc_0B57

loc_0C06:
0C06  FE 06         CP 0x06
0C08  20 03         JR NZ,loc_0C0D
0C0A  C3 6F 0B      JP loc_0B6F

loc_0C0D:
0C0D  CD 59 4C      CALL lcd_print
0C10  0C 42 50 20 6E 6F +  DB \f, "BP not available>", \x01, \xCD, \x89, "M", \xC9

; process both disk sides for read: single-sided reads side1 only, else side1 then side2
read_both_sides:
0C27  CD 49 0C      CALL check_double_sided
0C2A  C2 72 3B      JP NZ,fdc_write_dual
0C2D  3E 01         LD A,0x01
0C2F  CD 24 3B      CALL fdc_write_poll
0C32  D8            RET C
0C33  3E 02         LD A,0x02
0C35  C3 24 3B      JP fdc_write_poll

; process both sides for source read into buffer: single reads side1, else both sides
write_both_sides:
0C38  CD 49 0C      CALL check_double_sided
0C3B  C2 89 42      JP NZ,loc_4289
0C3E  3E 01         LD A,0x01
0C40  CD 7F 42      CALL fdc_read_src_b
0C43  D8            RET C
0C44  3E 02         LD A,0x02
0C46  C3 7F 42      JP fdc_read_src_b

; determine if current format is double-sided (0x3135 nonzero, or cyl_head code 4/0x0E)
check_double_sided:
0C49  3A 35 31      LD A,(datarate_idx)
0C4C  B7            OR A
0C4D  C0            RET NZ
0C4E  3A 64 31      LD A,(cyl_head)
0C51  FE 04         CP 0x04
0C53  C8            RET Z
0C54  FE 0E         CP 0x0E
0C56  C9            RET

; draw "in progress" on line 2 (operation running indicator)
show_in_progress:
0C57  CD 70 06      CALL lcd_clear_line2
0C5A  CD 59 4C      CALL lcd_print
0C5D  1B C3 69 6E 20 70 +  DB ESC(0xC3), "in progress", 0
0C6B  C9            RET

loc_0C6C:
0C6C  21 34 31      LD HL,op_word
0C6F  F5            PUSH AF
0C70  3E 1F         LD A,0x1F
0C72  A6            AND (HL)
0C73  77            LD (HL),A
0C74  F1            POP AF
0C75  DA 4F 0D      JP C,loc_0D4F
0C78  C3 74 0D      JP loc_0D74
0C7B  7E            LD A,(HL)
0C7C  FE 01         CP 0x01
0C7E  28 09         JR Z,loc_0C89
0C80  FE 04         CP 0x04
0C82  28 05         JR Z,loc_0C89
0C84  FE 02         CP 0x02
0C86  C2 74 0D      JP NZ,loc_0D74

loc_0C89:
0C89  2A 35 31      LD HL,(datarate_idx)
0C8C  7C            LD A,H
0C8D  B5            OR L
0C8E  C2 74 0D      JP NZ,loc_0D74
0C91  DD 21 DD 52   LD IX,format_desc
0C95  DD 46 0C      LD B,(IX+12)
0C98  DD 5E 0D      LD E,(IX+13)
0C9B  DD 56 0E      LD D,(IX+14)
0C9E  DD 21 EB 4A   LD IX,drive_blk_a
0CA2  DD 70 07      LD (IX+7),B
0CA5  DD 73 0C      LD (IX+12),E
0CA8  DD 72 0D      LD (IX+13),D
0CAB  DD 21 DD 52   LD IX,format_desc
0CAF  DD 46 0F      LD B,(IX+15)
0CB2  DD 5E 10      LD E,(IX+16)
0CB5  DD 56 11      LD D,(IX+17)
0CB8  DD 21 06 4B   LD IX,drive_blk_b
0CBC  DD 70 07      LD (IX+7),B
0CBF  DD 73 0C      LD (IX+12),E
0CC2  DD 72 0D      LD (IX+13),D
0CC5  DD 21 DD 52   LD IX,format_desc
0CC9  DD CB 0B 66   BIT 4,(IX+11)
0CCD  20 07         JR NZ,loc_0CD6
0CCF  3E 01         LD A,0x01
0CD1  CD 18 3A      CALL fdc_send_dma
0CD4  18 06         JR loc_0CDC

loc_0CD6:
0CD6  CD 83 3A      CALL fdc_read_dual
0CD9  C3 DC 0C      JP loc_0CDC

loc_0CDC:
0CDC  3E 01         LD A,0x01
0CDE  CD 2D 47      CALL fdc_poll_complete
0CE1  28 F9         JR Z,loc_0CDC
0CE3  30 03         JR NC,loc_0CE8
0CE5  C3 4F 0D      JP loc_0D4F

loc_0CE8:
0CE8  DD CB 0B 66   BIT 4,(IX+11)
0CEC  28 0C         JR Z,loc_0CFA

loc_0CEE:
0CEE  3E 02         LD A,0x02
0CF0  CD 04 47      CALL fdc_poll_result
0CF3  28 F9         JR Z,loc_0CEE
0CF5  30 03         JR NC,loc_0CFA
0CF7  C3 4F 0D      JP loc_0D4F

loc_0CFA:
0CFA  DD 21 EB 4A   LD IX,drive_blk_a
0CFE  DD 4E 0E      LD C,(IX+14)
0D01  DD 46 0F      LD B,(IX+15)
0D04  03            INC BC
0D05  C5            PUSH BC
0D06  DD 7E 07      LD A,(IX+7)
0D09  DD 6E 0C      LD L,(IX+12)
0D0C  DD 66 0D      LD H,(IX+13)
0D0F  D3 B0         OUT (0xB0),A  ; dram_bank
0D11  7C            LD A,H
0D12  F6 80         OR 0x80
0D14  67            LD H,A
0D15  11 00 58      LD DE,0x5800
0D18  ED B0         LDIR
0D1A  3A 56 31      LD A,(track_bank_a)
0D1D  D3 B0         OUT (0xB0),A  ; dram_bank
0D1F  2A 58 31      LD HL,(track_off)
0D22  7C            LD A,H
0D23  F6 80         OR 0x80
0D25  67            LD H,A
0D26  C1            POP BC
0D27  11 00 58      LD DE,0x5800

loc_0D2A:
0D2A  1A            LD A,(DE)
0D2B  13            INC DE
0D2C  ED A1         CPI
0D2E  20 1F         JR NZ,loc_0D4F
0D30  EA 2A 0D      JP PE,loc_0D2A
0D33  18 3F         JR loc_0D74
0D35  CD 59 4C      CALL lcd_print
0D38  1B C0 46 44 44 20 +  DB ESC(0xC0), "FDD write fault", 0
0D4A  3E 01         LD A,0x01
0D4C  CD 89 4D      CALL get_key

loc_0D4F:
0D4F  3E 60         LD A,0x60
0D51  B6            OR (HL)
0D52  77            LD (HL),A
0D53  3E 64         LD A,0x64
0D55  D3 AC         OUT (0xAC),A  ; pit_ctrl
0D57  3E 80         LD A,0x80
0D59  D3 A4         OUT (0xA4),A  ; pit_c1
0D5B  3E 0E         LD A,0x0E
0D5D  D3 9C         OUT (0x9C),A  ; ctrl_latch
0D5F  06 0A         LD B,0x0A
0D61  0E 01         LD C,0x01

loc_0D63:
0D63  3E 40         LD A,0x40
0D65  D3 AC         OUT (0xAC),A  ; pit_ctrl
0D67  DB A4         IN A,(0xA4)  ; pit_c1
0D69  B9            CP C
0D6A  20 F7         JR NZ,loc_0D63
0D6C  0C            INC C
0D6D  10 F4         DJNZ loc_0D63
0D6F  18 03         JR loc_0D74

loc_0D71:
0D71  CD 8C 0E      CALL wait_read_done

loc_0D74:
0D74  3E 0F         LD A,0x0F
0D76  D3 9C         OUT (0x9C),A  ; ctrl_latch
0D78  3A 61 31      LD A,(host_mode)
0D7B  B7            OR A
0D7C  20 26         JR NZ,loc_0DA4
0D7E  AF            XOR A
0D7F  CD 89 4D      CALL get_key
0D82  28 20         JR Z,loc_0DA4
0D84  CD 70 06      CALL lcd_clear_line2
0D87  CD 59 4C      CALL lcd_print
0D8A  1B C6 73 74 6F 70 +  DB ESC(0xC6), "stop", 0

loc_0D91:
0D91  AF            XOR A
0D92  CD 89 4D      CALL get_key
0D95  20 FA         JR NZ,loc_0D91
0D97  21 34 31      LD HL,op_word
0D9A  CB FE         SET 7,(HL)
0D9C  21 49 31      LD HL,op_flag_49
0D9F  36 00         LD (HL),0x00
0DA1  C3 35 0F      JP loc_0F35

loc_0DA4:
0DA4  21 34 31      LD HL,op_word
0DA7  7E            LD A,(HL)
0DA8  E6 60         AND 0x60
0DAA  28 2A         JR Z,loc_0DD6
0DAC  21 49 31      LD HL,op_flag_49
0DAF  3A 4A 31      LD A,(err_recovery)
0DB2  BE            CP (HL)
0DB3  C2 D0 0D      JP NZ,loc_0DD0
0DB6  21 00 00      LD HL,0x0000
0DB9  CD 22 4C      CALL lcd_setpos
0DBC  2A 35 31      LD HL,(datarate_idx)
0DBF  7D            LD A,L
0DC0  B4            OR H
0DC1  CA B8 09      JP Z,loc_09B8
0DC4  3A DD 52      LD A,(format_desc)
0DC7  3D            DEC A
0DC8  95            SUB L
0DC9  B4            OR H
0DCA  CA B8 09      JP Z,loc_09B8
0DCD  C3 35 0F      JP loc_0F35

loc_0DD0:
0DD0  F2 B8 09      JP P,loc_09B8
0DD3  C3 35 0F      JP loc_0F35

loc_0DD6:
0DD6  21 49 31      LD HL,op_flag_49
0DD9  36 00         LD (HL),0x00
0DDB  21 34 31      LD HL,op_word
0DDE  7E            LD A,(HL)
0DDF  E6 0F         AND 0x0F
0DE1  20 03         JR NZ,loc_0DE6
0DE3  3A 4E 31      LD A,(run_status)

loc_0DE6:
0DE6  FE 08         CP 0x08
0DE8  C2 3D 0F      JP NZ,loc_0F3D
0DEB  DD 21 EB 4A   LD IX,drive_blk_a
0DEF  DD 4E 0E      LD C,(IX+14)
0DF2  DD 46 0F      LD B,(IX+15)
0DF5  C5            PUSH BC
0DF6  DD 7E 07      LD A,(IX+7)
0DF9  DD 6E 0C      LD L,(IX+12)
0DFC  DD 66 0D      LD H,(IX+13)
0DFF  D3 B0         OUT (0xB0),A  ; dram_bank
0E01  7C            LD A,H
0E02  F6 80         OR 0x80
0E04  67            LD H,A
0E05  11 00 58      LD DE,0x5800
0E08  ED B0         LDIR
0E0A  3A 67 31      LD A,(hrd_desc_tbl)
0E0D  CB 4F         BIT 1,A
0E0F  28 35         JR Z,verify_compare
0E11  2A 35 31      LD HL,(datarate_idx)
0E14  3A 6D 31      LD A,(serial_head)
0E17  BD            CP L
0E18  20 2C         JR NZ,verify_compare
0E1A  7C            LD A,H
0E1B  E6 80         AND 0x80
0E1D  07            RLCA
0E1E  67            LD H,A
0E1F  3A 6E 31      LD A,(serial_sector)
0E22  BC            CP H
0E23  20 21         JR NZ,verify_compare
0E25  11 00 58      LD DE,0x5800
0E28  2A 75 31      LD HL,(serial_ptr)
0E2B  19            ADD HL,DE
0E2C  E5            PUSH HL
0E2D  C1            POP BC
0E2E  3A 56 31      LD A,(track_bank_a)
0E31  D3 B0         OUT (0xB0),A  ; dram_bank
0E33  2A 58 31      LD HL,(track_off)
0E36  7C            LD A,H
0E37  F6 80         OR 0x80
0E39  57            LD D,A
0E3A  5D            LD E,L
0E3B  2A 75 31      LD HL,(serial_ptr)
0E3E  19            ADD HL,DE
0E3F  C5            PUSH BC
0E40  D1            POP DE
0E41  01 04 00      LD BC,0x0004
0E44  ED B0         LDIR

; verify: DMA read-back track into 0x5800 scratch, CPI-compare vs DRAM image
verify_compare:
0E46  3A 56 31      LD A,(track_bank_a)
0E49  D3 B0         OUT (0xB0),A  ; dram_bank
0E4B  2A 58 31      LD HL,(track_off)
0E4E  7C            LD A,H
0E4F  F6 80         OR 0x80
0E51  67            LD H,A
0E52  C1            POP BC
0E53  11 00 58      LD DE,0x5800

loc_0E56:
0E56  1A            LD A,(DE)
0E57  13            INC DE
0E58  ED A1         CPI
0E5A  20 05         JR NZ,loc_0E61
0E5C  EA 56 0E      JP PE,loc_0E56
0E5F  18 55         JR loc_0EB6

loc_0E61:
0E61  CD 67 0E      CALL show_compare_error
0E64  C3 35 0F      JP loc_0F35

; draw "Compare error", beep code 5, set op_word bit6 (verify-mismatch flag)
show_compare_error:
0E67  E5            PUSH HL
0E68  D5            PUSH DE
0E69  CD 70 06      CALL lcd_clear_line2
0E6C  CD 59 4C      CALL lcd_print
0E6F  1B C0 43 6F 6D 70 +  DB ESC(0xC0), "Compare error", 0
0E7F  3E 05         LD A,0x05
0E81  CD 66 27      CALL beep
0E84  21 34 31      LD HL,op_word
0E87  CB F6         SET 6,(HL)
0E89  D1            POP DE
0E8A  E1            POP HL
0E8B  C9            RET

; wait for FDC read/verify done on unit1 (and unit2 if double-sided); set op_word bits 6/5 on fail
wait_read_done:
0E8C  21 34 31      LD HL,op_word
0E8F  3E 1F         LD A,0x1F
0E91  A6            AND (HL)
0E92  77            LD (HL),A

loc_0E93:
0E93  3E 01         LD A,0x01
0E95  CD 2D 47      CALL fdc_poll_complete
0E98  28 F9         JR Z,loc_0E93
0E9A  21 34 31      LD HL,op_word
0E9D  30 02         JR NC,loc_0EA1
0E9F  CB F6         SET 6,(HL)

loc_0EA1:
0EA1  DD CB 0B 66   BIT 4,(IX+11)
0EA5  28 0E         JR Z,loc_0EB5
0EA7  3E 02         LD A,0x02
0EA9  CD 04 47      CALL fdc_poll_result
0EAC  28 F3         JR Z,loc_0EA1
0EAE  21 34 31      LD HL,op_word
0EB1  30 02         JR NC,loc_0EB5
0EB3  CB EE         SET 5,(HL)

loc_0EB5:
0EB5  C9            RET

loc_0EB6:
0EB6  DD 21 DD 52   LD IX,format_desc
0EBA  DD CB 0B 66   BIT 4,(IX+11)
0EBE  28 7D         JR Z,loc_0F3D
0EC0  DD 21 06 4B   LD IX,drive_blk_b
0EC4  DD 4E 0E      LD C,(IX+14)
0EC7  DD 46 0F      LD B,(IX+15)
0ECA  DD 7E 07      LD A,(IX+7)
0ECD  DD 6E 0C      LD L,(IX+12)
0ED0  DD 66 0D      LD H,(IX+13)
0ED3  D3 B0         OUT (0xB0),A  ; dram_bank
0ED5  7C            LD A,H
0ED6  F6 80         OR 0x80
0ED8  67            LD H,A
0ED9  11 00 58      LD DE,0x5800
0EDC  C5            PUSH BC
0EDD  ED B0         LDIR
0EDF  3A 67 31      LD A,(hrd_desc_tbl)
0EE2  CB 4F         BIT 1,A
0EE4  28 31         JR Z,loc_0F17
0EE6  2A 35 31      LD HL,(datarate_idx)
0EE9  3A 6D 31      LD A,(serial_head)
0EEC  BD            CP L
0EED  20 28         JR NZ,loc_0F17
0EEF  3A 6E 31      LD A,(serial_sector)
0EF2  FE 01         CP 0x01
0EF4  20 21         JR NZ,loc_0F17
0EF6  11 00 58      LD DE,0x5800
0EF9  2A 75 31      LD HL,(serial_ptr)
0EFC  19            ADD HL,DE
0EFD  E5            PUSH HL
0EFE  C1            POP BC
0EFF  3A 57 31      LD A,(track_bank_b)
0F02  D3 B0         OUT (0xB0),A  ; dram_bank
0F04  2A 5A 31      LD HL,(read_addr)
0F07  7C            LD A,H
0F08  F6 80         OR 0x80
0F0A  57            LD D,A
0F0B  5D            LD E,L
0F0C  2A 75 31      LD HL,(serial_ptr)
0F0F  19            ADD HL,DE
0F10  C5            PUSH BC
0F11  D1            POP DE
0F12  01 04 00      LD BC,0x0004
0F15  ED B0         LDIR

loc_0F17:
0F17  3A 57 31      LD A,(track_bank_b)
0F1A  D3 B0         OUT (0xB0),A  ; dram_bank
0F1C  2A 5A 31      LD HL,(read_addr)
0F1F  7C            LD A,H
0F20  F6 80         OR 0x80
0F22  67            LD H,A
0F23  C1            POP BC
0F24  11 00 58      LD DE,0x5800

loc_0F27:
0F27  1A            LD A,(DE)
0F28  13            INC DE
0F29  ED A1         CPI
0F2B  20 05         JR NZ,loc_0F32
0F2D  EA 27 0F      JP PE,loc_0F27
0F30  18 0B         JR loc_0F3D

loc_0F32:
0F32  CD 67 0E      CALL show_compare_error

loc_0F35:
0F35  C1            POP BC
0F36  D1            POP DE
0F37  06 01         LD B,0x01
0F39  16 01         LD D,0x01
0F3B  D5            PUSH DE
0F3C  C5            PUSH BC

loc_0F3D:
0F3D  2A 35 31      LD HL,(datarate_idx)
0F40  3A 63 31      LD A,(side_sel)
0F43  67            LD H,A
0F44  22 35 31      LD (datarate_idx),HL
0F47  C1            POP BC
0F48  DD 21 DD 52   LD IX,format_desc
0F4C  DD CB 0B 66   BIT 4,(IX+11)
0F50  28 02         JR Z,loc_0F54
0F52  06 01         LD B,0x01

loc_0F54:
0F54  10 1F         DJNZ loc_0F75
0F56  2A 35 31      LD HL,(datarate_idx)
0F59  2C            INC L
0F5A  3A 1C 31      LD A,(cfg_flags)
0F5D  CB 7F         BIT 7,A
0F5F  20 02         JR NZ,loc_0F63
0F61  2D            DEC L
0F62  2D            DEC L

loc_0F63:
0F63  26 00         LD H,0x00
0F65  22 35 31      LD (datarate_idx),HL
0F68  21 77 31      LD HL,serial_ptr+0x2
0F6B  CB 86         RES 0,(HL)
0F6D  C1            POP BC
0F6E  10 02         DJNZ loc_0F72
0F70  18 06         JR loc_0F78

loc_0F72:
0F72  C3 F3 08      JP loc_08F3

loc_0F75:
0F75  C3 15 09      JP loc_0915

loc_0F78:
0F78  3E 0F         LD A,0x0F
0F7A  D3 9C         OUT (0x9C),A  ; ctrl_latch
0F7C  21 69 32      LD HL,cycle_cnt_lo
0F7F  06 04         LD B,0x04
0F81  0E FC         LD C,0xFC
0F83  3E 01         LD A,0x01
0F85  CD 35 27      CALL config_save
0F88  CD D9 06      CALL pit_reload_c12
0F8B  CD 09 07      CALL motor_ready_wait
0F8E  C2 B0 10      JP NZ,loc_10B0
0F91  AF            XOR A
0F92  32 4C 31      LD (fmt_mode),A
0F95  32 50 31      LD (edit_ndigits),A
0F98  21 34 31      LD HL,op_word
0F9B  3E E0         LD A,0xE0
0F9D  A6            AND (HL)
0F9E  28 72         JR Z,loc_1012
0FA0  2A 3B 31      LD HL,(pass_ctr)
0FA3  23            INC HL
0FA4  22 3B 31      LD (pass_ctr),HL
0FA7  21 50 31      LD HL,edit_ndigits
0FAA  CB C6         SET 0,(HL)
0FAC  CB FE         SET 7,(HL)
0FAE  CD 2D 11      CALL al_cmd_reject
0FB1  30 05         JR NC,loc_0FB8
0FB3  FE 01         CP 0x01
0FB5  C2 B0 10      JP NZ,loc_10B0

loc_0FB8:
0FB8  3A 61 31      LD A,(host_mode)
0FBB  B7            OR A
0FBC  C2 B0 10      JP NZ,loc_10B0
0FBF  21 34 31      LD HL,op_word
0FC2  3E 0F         LD A,0x0F
0FC4  A6            AND (HL)
0FC5  20 16         JR NZ,loc_0FDD
0FC7  CB 7E         BIT 7,(HL)
0FC9  28 28         JR Z,loc_0FF3
0FCB  CD 70 06      CALL lcd_clear_line2
0FCE  CD 59 4C      CALL lcd_print
0FD1  1B C1 73 74 6F 70 +  DB ESC(0xC1), "stopped", 0
0FDB  18 29         JR loc_1006

loc_0FDD:
0FDD  CB 7E         BIT 7,(HL)
0FDF  CA 9C 07      JP Z,loc_079C
0FE2  C3 B0 10      JP loc_10B0

loc_0FE5:
0FE5  FE 00         CP 0x00
0FE7  CA B0 10      JP Z,loc_10B0
0FEA  CD 93 04      CALL edit_num_copies
0FED  CA B0 10      JP Z,loc_10B0
0FF0  C3 9C 07      JP loc_079C

loc_0FF3:
0FF3  CD 70 06      CALL lcd_clear_line2
0FF6  CD 59 4C      CALL lcd_print
0FF9  1B C0 75 6E 72 65 +  DB ESC(0xC0), "unreadable", 0

loc_1006:
1006  3E 01         LD A,0x01
1008  CD 89 4D      CALL get_key
100B  AF            XOR A
100C  32 C8 52      LD (image_present),A
100F  C3 B0 10      JP loc_10B0

loc_1012:
1012  3A 34 31      LD A,(op_word)
1015  E6 0F         AND 0x0F
1017  20 11         JR NZ,loc_102A
1019  3A 4E 31      LD A,(run_status)
101C  B7            OR A
101D  20 18         JR NZ,loc_1037
101F  CD 5D 51      CALL checksum_all_banks
1022  3A 61 31      LD A,(host_mode)
1025  B7            OR A
1026  28 14         JR Z,loc_103C
1028  18 0D         JR loc_1037

loc_102A:
102A  FE 07         CP 0x07
102C  20 09         JR NZ,loc_1037
102E  3A 4E 31      LD A,(run_status)
1031  B7            OR A
1032  20 03         JR NZ,loc_1037
1034  CD 5D 51      CALL checksum_all_banks

loc_1037:
1037  CD D2 10      CALL al_accept_reject
103A  38 3D         JR C,loc_1079

loc_103C:
103C  2A 39 31      LD HL,(track_ctr)
103F  23            INC HL
1040  22 39 31      LD (track_ctr),HL
1043  21 67 31      LD HL,hrd_desc_tbl
1046  CB 4E         BIT 1,(HL)
1048  28 46         JR Z,batch_loop_tail
104A  3A 34 31      LD A,(op_word)
104D  E6 0F         AND 0x0F
104F  FE 01         CP 0x01
1051  28 0C         JR Z,loc_105F
1053  FE 05         CP 0x05
1055  28 08         JR Z,loc_105F
1057  FE 04         CP 0x04
1059  28 04         JR Z,loc_105F
105B  FE 06         CP 0x06
105D  20 31         JR NZ,batch_loop_tail

loc_105F:
105F  2A 68 31      LD HL,(serial_nr)
1062  3A 6C 31      LD A,(serial_cyl)
1065  5F            LD E,A
1066  16 00         LD D,0x00
1068  19            ADD HL,DE
1069  22 68 31      LD (serial_nr),HL
106C  2A 6A 31      LD HL,(serial_incr)
106F  11 00 00      LD DE,0x0000
1072  ED 5A         ADC HL,DE
1074  22 6A 31      LD (serial_incr),HL
1077  18 17         JR batch_loop_tail

loc_1079:
1079  2A 3B 31      LD HL,(pass_ctr)
107C  23            INC HL
107D  22 3B 31      LD (pass_ctr),HL
1080  47            LD B,A
1081  3A 61 31      LD A,(host_mode)
1084  B7            OR A
1085  20 29         JR NZ,loc_10B0
1087  78            LD A,B
1088  FE 01         CP 0x01
108A  CA 9C 07      JP Z,loc_079C
108D  C3 E5 0F      JP loc_0FE5

; end-of-pass tail: dec run_count, on last pass autoloader-accept, deselect, show OK/bad, wait key
batch_loop_tail:
1090  2A 3D 31      LD HL,(run_count)
1093  7D            LD A,L
1094  B4            OR H
1095  CA 9C 07      JP Z,loc_079C
1098  2B            DEC HL
1099  22 3D 31      LD (run_count),HL
109C  7D            LD A,L
109D  B4            OR H
109E  C2 9C 07      JP NZ,loc_079C
10A1  21 34 31      LD HL,op_word
10A4  3E 0F         LD A,0x0F
10A6  A6            AND (HL)
10A7  FE 09         CP 0x09
10A9  20 05         JR NZ,loc_10B0
10AB  36 00         LD (HL),0x00
10AD  CD C8 10      CALL al_gate_or_reject

loc_10B0:
10B0  CD 57 07      CALL drive_cfg_latch
10B3  3A 34 31      LD A,(op_word)
10B6  E6 0F         AND 0x0F
10B8  28 06         JR Z,loc_10C0
10BA  CD 3B 06      CALL show_ok_bad_count
10BD  CD 43 4D      CALL keypad_debounce

loc_10C0:
10C0  3A 4C 31      LD A,(fmt_mode)
10C3  21 50 31      LD HL,edit_ndigits
10C6  B6            OR (HL)
10C7  C9            RET

; if autoloader present route to accept/reject flow, else beep once (buzzer_pulse) and return A=0
al_gate_or_reject:
10C8  CD A8 11      CALL al_present_gate
10CB  20 05         JR NZ,al_accept_reject
10CD  CD FC 49      CALL buzzer_pulse
10D0  AF            XOR A
10D1  C9            RET

; autoloader ACCEPT (mode9): show "ACCEPT", eject good disk, retry build_select+verify up to 20x
al_accept_reject:
10D2  CD A0 11      CALL is_op_mode9
10D5  C8            RET Z
10D6  06 41         LD B,0x41
10D8  CD A8 11      CALL al_present_gate
10DB  20 4C         JR NZ,loc_1129
10DD  CD 70 06      CALL lcd_clear_line2
10E0  CD 59 4C      CALL lcd_print
10E3  1B C0 41 43 43 45 +  DB ESC(0xC0), "ACCEPT", 0
10EC  3E 01         LD A,0x01

loc_10EE:
10EE  21 8B 33      LD HL,retry_ctr+0x1
10F1  77            LD (HL),A
10F2  CD E3 49      CALL buzzer_beep
10F5  2B            DEC HL
10F6  36 00         LD (HL),0x00

loc_10F8:
10F8  CD 34 08      CALL fdc_build_select
10FB  38 2A         JR C,loc_1127
10FD  3A C8 52      LD A,(image_present)
1100  B7            OR A
1101  C4 BA 51      CALL NZ,verify_ram_bank
1104  28 03         JR Z,loc_1109
1106  CD 2B 12      CALL show_lost_data

loc_1109:
1109  21 8A 33      LD HL,retry_ctr
110C  34            INC (HL)
110D  3E 14         LD A,0x14
110F  BE            CP (HL)
1110  20 0A         JR NZ,loc_111C
1112  21 8B 33      LD HL,retry_ctr+0x1
1115  7E            LD A,(HL)
1116  CD E3 49      CALL buzzer_beep
1119  2B            DEC HL
111A  36 00         LD (HL),0x00

loc_111C:
111C  AF            XOR A
111D  CD 89 4D      CALL get_key
1120  28 D6         JR Z,loc_10F8
1122  3E 01         LD A,0x01
1124  CD 89 4D      CALL get_key

loc_1127:
1127  AF            XOR A
1128  C9            RET

loc_1129:
1129  06 41         LD B,0x41
112B  18 1E         JR loc_114B

; autoloader REJECT: show "REJECT", send reject cmd 0x52, await ack with "timeout" handling
al_cmd_reject:
112D  CD A8 11      CALL al_present_gate
1130  20 13         JR NZ,loc_1145
1132  CD 70 06      CALL lcd_clear_line2
1135  CD 59 4C      CALL lcd_print
1138  1B C0 52 45 4A 45 +  DB ESC(0xC0), "REJECT", 0
1141  3E 03         LD A,0x03
1143  18 A9         JR loc_10EE

loc_1145:
1145  CD A0 11      CALL is_op_mode9
1148  C8            RET Z
1149  06 52         LD B,0x52

loc_114B:
114B  CD 99 4E      CALL al_tx
114E  AF            XOR A
114F  32 4C 31      LD (fmt_mode),A
1152  21 4D 31      LD HL,al_status1
1155  36 40         LD (HL),0x40

loc_1157:
1157  CD 53 4E      CALL al_rx_ready
115A  20 2B         JR NZ,loc_1187
115C  35            DEC (HL)
115D  20 1A         JR NZ,loc_1179
115F  CD 59 4C      CALL lcd_print
1162  74 69 6D 65 6F 75 +  DB "timeout", 0

loc_116A:
116A  3E 8C         LD A,0x8C
116C  32 4C 31      LD (fmt_mode),A
116F  21 00 00      LD HL,0x0000
1172  CD 22 4C      CALL lcd_setpos
1175  3E 01         LD A,0x01
1177  B7            OR A
1178  C9            RET

loc_1179:
1179  3A C8 52      LD A,(image_present)
117C  B7            OR A
117D  28 08         JR Z,loc_1187
117F  CD BA 51      CALL verify_ram_bank
1182  28 D3         JR Z,loc_1157
1184  C3 2B 12      JP show_lost_data

loc_1187:
1187  CD E5 13      CALL al_rx_response
118A  C8            RET Z
118B  FE 02         CP 0x02
118D  20 DB         JR NZ,loc_116A
118F  CD FB 13      CALL al_cmd_status
1192  20 D6         JR NZ,loc_116A
1194  CD 86 12      CALL al_status_decode
1197  F5            PUSH AF

; send autoloader calibrate command (0x43) with ack; sets carry (error-exit tail)
al_calibrate:
1198  06 43         LD B,0x43
119A  CD D9 13      CALL al_cmd_ack
119D  F1            POP AF
119E  37            SCF
119F  C9            RET

; test whether op_word low nibble == 9 (autoloader run mode); returns Z if so
is_op_mode9:
11A0  3A 34 31      LD A,(op_word)
11A3  E6 0F         AND 0x0F
11A5  FE 09         CP 0x09
11A7  C9            RET

; gate on autoloader-present flag (al_present); returns Z if no autoloader attached
al_present_gate:
11A8  3A 62 31      LD A,(al_present)
11AB  B7            OR A
11AC  C9            RET

; enter insert/read-source flow with retry_ctr preset to 1 (single-shot insert)
al_insert_disk:
11AD  21 8A 33      LD HL,retry_ctr
11B0  36 01         LD (HL),0x01
11B2  18 09         JR loc_11BD

; read source disk (autoloader-aware): command INSERT, spin up, verify bank, retry on rpm-low/lost-data
read_source:
11B4  21 8A 33      LD HL,retry_ctr
11B7  36 00         LD (HL),0x00
11B9  CD A0 11      CALL is_op_mode9
11BC  C8            RET Z

loc_11BD:
11BD  CD A8 11      CALL al_present_gate
11C0  20 3A         JR NZ,al_insert
11C2  CD 70 06      CALL lcd_clear_line2
11C5  CD 59 4C      CALL lcd_print
11C8  1B C0 49 4E 53 45 +  DB ESC(0xC0), "INSERT", 0

loc_11D1:
11D1  CD 34 08      CALL fdc_build_select
11D4  30 22         JR NC,loc_11F8
11D6  CD 11 08      CALL show_rpm_low
11D9  3A C8 52      LD A,(image_present)
11DC  B7            OR A
11DD  C4 BA 51      CALL NZ,verify_ram_bank
11E0  28 03         JR Z,loc_11E5
11E2  CD 2B 12      CALL show_lost_data

loc_11E5:
11E5  AF            XOR A
11E6  CD 89 4D      CALL get_key
11E9  28 E6         JR Z,loc_11D1
11EB  3A 8A 33      LD A,(retry_ctr)
11EE  B7            OR A
11EF  20 07         JR NZ,loc_11F8
11F1  32 8A 33      LD (retry_ctr),A
11F4  3E 01         LD A,0x01
11F6  B7            OR A
11F7  C9            RET

loc_11F8:
11F8  C3 4C 12      JP loc_124C
11FB  C9            RET

; send autoloader insert command (0x49), wait ready; "timeout" message on no response
al_insert:
11FC  06 49         LD B,0x49
11FE  CD 99 4E      CALL al_tx
1201  21 4D 31      LD HL,al_status1
1204  36 40         LD (HL),0x40

loc_1206:
1206  CD 53 4E      CALL al_rx_ready
1209  20 3C         JR NZ,loc_1247
120B  35            DEC (HL)
120C  20 12         JR NZ,loc_1220
120E  CD 59 4C      CALL lcd_print
1211  74 69 6D 65 6F 75 +  DB "timeout", 0
1219  CD 43 4D      CALL keypad_debounce
121C  3E 01         LD A,0x01
121E  B7            OR A
121F  C9            RET

loc_1220:
1220  3A C8 52      LD A,(image_present)
1223  B7            OR A
1224  28 21         JR Z,loc_1247
1226  CD BA 51      CALL verify_ram_bank
1229  28 DB         JR Z,loc_1206

; fatal image-lost error: hex-dump 0x52C7, draw "Lost data", then halt (spin forever)
show_lost_data:
122B  21 C7 52      LD HL,menu_scratch+0x5
122E  3E 01         LD A,0x01
1230  CD 3B 4F      CALL lcd_dump_hex
1233  CD 70 06      CALL lcd_clear_line2
1236  CD 59 4C      CALL lcd_print
1239  1B C0 4C 6F 73 74 +  DB ESC(0xC0), "Lost data", 0

loc_1245:
1245  18 FE         JR loc_1245

loc_1247:
1247  CD E5 13      CALL al_rx_response
124A  20 15         JR NZ,loc_1261

loc_124C:
124C  2A 69 32      LD HL,(cycle_cnt_lo)
124F  11 01 00      LD DE,0x0001
1252  19            ADD HL,DE
1253  22 69 32      LD (cycle_cnt_lo),HL
1256  30 07         JR NC,loc_125F
1258  2A 6B 32      LD HL,(cycle_cnt_hi)
125B  23            INC HL
125C  22 6B 32      LD (cycle_cnt_hi),HL

loc_125F:
125F  AF            XOR A
1260  C9            RET

loc_1261:
1261  FE 02         CP 0x02
1263  C0            RET NZ

loc_1264:
1264  CD FB 13      CALL al_cmd_status
1267  20 F8         JR NZ,loc_1261
1269  CD 86 12      CALL al_status_decode
126C  F5            PUSH AF

; send autoloader reject(0x52)+calibrate(0x43) with ack; on ok re-insert per retry_ctr
al_reject:
126D  06 52         LD B,0x52
126F  CD D9 13      CALL al_cmd_ack
1272  06 43         LD B,0x43
1274  CD D9 13      CALL al_cmd_ack
1277  28 03         JR Z,loc_127C
1279  F1            POP AF
127A  18 E8         JR loc_1264

loc_127C:
127C  F1            POP AF
127D  FE 01         CP 0x01
127F  CA FC 11      JP Z,al_insert
1282  3E 03         LD A,0x03
1284  B7            OR A
1285  C9            RET

; decode autoloader status byte -> on-screen message (bit1 seated, hi-nibble class)
al_status_decode:
1286  F5            PUSH AF
1287  CD 70 06      CALL lcd_clear_line2
128A  F1            POP AF
128B  CB 4F         BIT 1,A
128D  CA 7D 13      JP Z,loc_137D
1290  E6 F0         AND 0xF0
1292  FE 20         CP 0x20
1294  CA 2B 13      JP Z,loc_132B
1297  FE 10         CP 0x10
1299  CA 98 13      JP Z,loc_1398
129C  FE 80         CP 0x80
129E  CA A5 13      JP Z,loc_13A5
12A1  FE 90         CP 0x90
12A3  CA C1 13      JP Z,loc_13C1
12A6  FE A0         CP 0xA0
12A8  CA 0F 13      JP Z,loc_130F
12AB  FE D0         CP 0xD0
12AD  CA F9 12      JP Z,loc_12F9
12B0  FE C0         CP 0xC0
12B2  CA E3 12      JP Z,loc_12E3
12B5  FE 00         CP 0x00
12B7  20 20         JR NZ,loc_12D9
12B9  32 4C 31      LD (fmt_mode),A
12BC  CD 70 06      CALL lcd_clear_line2
12BF  CD 59 4C      CALL lcd_print
12C2  0C 1B C0 41 4C 20 +  DB \f, ESC(0xC0), "AL status ok", 0
12D2  CD 43 4D      CALL keypad_debounce
12D5  AF            XOR A
12D6  3E 01         LD A,0x01
12D8  C9            RET

loc_12D9:
12D9  CD B0 02      CALL show_al_error
12DC  CD 43 4D      CALL keypad_debounce
12DF  3E 8A         LD A,0x8A
12E1  18 5C         JR loc_133F

loc_12E3:
12E3  CD 59 4C      CALL lcd_print
12E6  1B C0 52 65 6A 65 +  DB ESC(0xC0), "Reject error", 0
12F5  3E 8C         LD A,0x8C
12F7  18 46         JR loc_133F

loc_12F9:
12F9  CD 59 4C      CALL lcd_print
12FC  1B C0 42 61 64 20 +  DB ESC(0xC0), "Bad bin full", 0
130B  3E 8C         LD A,0x8C
130D  18 30         JR loc_133F

loc_130F:
130F  CD 59 4C      CALL lcd_print
1312  1B C0 41 63 63 65 +  DB ESC(0xC0), "Accept hopper full", 0
1327  3E 8C         LD A,0x8C
1329  18 14         JR loc_133F

loc_132B:
132B  CD 59 4C      CALL lcd_print
132E  1B C0 48 6F 70 70 +  DB ESC(0xC0), "Hopper empty", 0
133D  3E 82         LD A,0x82

loc_133F:
133F  32 4C 31      LD (fmt_mode),A
1342  47            LD B,A
1343  3A 4C 31      LD A,(fmt_mode)
1346  FE 8A         CP 0x8A
1348  3E 01         LD A,0x01
134A  C8            RET Z
134B  3A 61 31      LD A,(host_mode)
134E  A7            AND A
134F  3E 02         LD A,0x02
1351  C0            RET NZ
1352  06 64         LD B,0x64

loc_1354:
1354  AF            XOR A
1355  CD 89 4D      CALL get_key
1358  20 11         JR NZ,loc_136B
135A  2B            DEC HL
135B  7D            LD A,L
135C  B4            OR H
135D  20 F5         JR NZ,loc_1354
135F  78            LD A,B
1360  B7            OR A
1361  28 F1         JR Z,loc_1354
1363  05            DEC B
1364  3E 01         LD A,0x01
1366  CD 66 27      CALL beep
1369  18 E9         JR loc_1354

loc_136B:
136B  3A 34 31      LD A,(op_word)
136E  E6 0F         AND 0x0F
1370  28 03         JR Z,loc_1375
1372  CD 3B 06      CALL show_ok_bad_count

loc_1375:
1375  3E 01         LD A,0x01
1377  CD 89 4D      CALL get_key
137A  E6 0F         AND 0x0F
137C  C9            RET

loc_137D:
137D  CD 59 4C      CALL lcd_print
1380  1B C0 48 6F 70 70 +  DB ESC(0xC0), "Hopper not seated", 0
1394  3E 82         LD A,0x82
1396  18 A7         JR loc_133F

loc_1398:
1398  CD 59 4C      CALL lcd_print
139B  1B C0 4A 61 6D 00  DB ESC(0xC0), "Jam", 0
13A1  3E 84         LD A,0x84
13A3  18 9A         JR loc_133F

loc_13A5:
13A5  CD 59 4C      CALL lcd_print
13A8  1B C0 43 61 6C 69 +  DB ESC(0xC0), "Calibration error", 0
13BC  3E 86         LD A,0x86
13BE  C3 3F 13      JP loc_133F

loc_13C1:
13C1  CD 59 4C      CALL lcd_print
13C4  1B C0 45 6A 65 63 +  DB ESC(0xC0), "Eject timeout", 0
13D4  3E 88         LD A,0x88
13D6  C3 3F 13      JP loc_133F

; send 1-char autoloader command in B, read reply; 'X'=ok/1=timeout/2=other
al_cmd_ack:
13D9  DB D0         IN A,(0xD0)  ; al_data
13DB  DB D0         IN A,(0xD0)  ; al_data
13DD  DB D0         IN A,(0xD0)  ; al_data
13DF  CD 91 4E      CALL al_cmd_reset
13E2  CD 99 4E      CALL al_tx

; receive one autoloader response byte into fmt_mode; return 0 if 'X' ack, else error code 1/2
al_rx_response:
13E5  CD A1 4E      CALL al_rx
13E8  32 4C 31      LD (fmt_mode),A
13EB  20 06         JR NZ,loc_13F3
13ED  3E 58         LD A,0x58
13EF  B8            CP B
13F0  20 05         JR NZ,loc_13F7
13F2  C9            RET

loc_13F3:
13F3  3E 01         LD A,0x01
13F5  B7            OR A
13F6  C9            RET

loc_13F7:
13F7  3E 02         LD A,0x02
13F9  B7            OR A
13FA  C9            RET

; autoloader S(tatus): read 2 ASCII-hex chars, decode to status byte
al_cmd_status:
13FB  CD 33 14      CALL al_flush_rx
13FE  06 53         LD B,0x53
1400  CD 99 4E      CALL al_tx
1403  CD A1 4E      CALL al_rx
1406  20 20         JR NZ,loc_1428
1408  78            LD A,B
1409  32 4C 31      LD (fmt_mode),A
140C  CD A1 4E      CALL al_rx
140F  20 17         JR NZ,loc_1428
1411  78            LD A,B
1412  32 4D 31      LD (al_status1),A
1415  CD 2B 14      CALL ascii_hex_to_nibble
1418  47            LD B,A
1419  3A 4C 31      LD A,(fmt_mode)
141C  CD 2B 14      CALL ascii_hex_to_nibble
141F  87            ADD A,A
1420  87            ADD A,A
1421  87            ADD A,A
1422  87            ADD A,A
1423  B0            OR B
1424  47            LD B,A
1425  AF            XOR A
1426  78            LD A,B
1427  C9            RET

loc_1428:
1428  3E 01         LD A,0x01
142A  C9            RET

; convert one ASCII hex character in A to its 0-15 nibble value
ascii_hex_to_nibble:
142B  D6 30         SUB 0x30
142D  FE 0A         CP 0x0A
142F  D8            RET C
1430  D6 07         SUB 0x07
1432  C9            RET

; drain 3 stale bytes from autoloader USART RX (0xD0) and reset its status
al_flush_rx:
1433  DB D0         IN A,(0xD0)  ; al_data
1435  F5            PUSH AF
1436  F1            POP AF
1437  DB D0         IN A,(0xD0)  ; al_data
1439  F5            PUSH AF
143A  F1            POP AF
143B  DB D0         IN A,(0xD0)  ; al_data
143D  F5            PUSH AF
143E  F1            POP AF
143F  3E 30         LD A,0x30
1441  D3 D4         OUT (0xD4),A  ; al_stat
1443  C9            RET

phase_handler_tbl:
1444  EE 14         DW submenu_e        ; [0]
1446  EE 14         DW submenu_e        ; [1]
1448  AA 14         DW submenu_a        ; [2]
144A  B8 14         DW submenu_b        ; [3]
144C  CA 14         DW submenu_c        ; [4]
144E  EE 14         DW submenu_e        ; [5]
1450  E4 14         DW submenu_d        ; [6]
1452  EE 14         DW submenu_e        ; [7]

spfmt_menu_a:
1454  8D 15         DW spfmt_show_01    ; [8]
1456  92 15         DW spfmt_show_02    ; [9]
1458  97 15         DW spfmt_show_03    ; [10]
145A  9C 15         DW spfmt_show_04    ; [11]
145C  A1 15         DW spfmt_show_05    ; [12]
145E  A6 15         DW spfmt_show_06    ; [13]
1460  AB 15         DW spfmt_show_07    ; [14]
1462  00 00         DW 0x0000           ; [15]
1464  6B 16         DW spfmt_apply_01   ; [16]
1466  77 16         DW spfmt_apply_02   ; [17]
1468  7C 16         DW spfmt_apply_03   ; [18]
146A  81 16         DW spfmt_apply_04   ; [19]
146C  86 16         DW spfmt_apply_05   ; [20]
146E  8B 16         DW spfmt_apply_06   ; [21]
1470  90 16         DW spfmt_apply_07   ; [22]

spfmt_menu_c:
1472  8D 15         DW spfmt_show_01    ; [23]
1474  92 15         DW spfmt_show_02    ; [24]
1476  97 15         DW spfmt_show_03    ; [25]
1478  00 00         DW 0x0000           ; [26]
147A  6B 16         DW spfmt_apply_01   ; [27]
147C  77 16         DW spfmt_apply_02   ; [28]
147E  7C 16         DW spfmt_apply_03   ; [29]

spfmt_menu_d:
1480  B0 15         DW spfmt_show_08    ; [30]
1482  B5 15         DW spfmt_show_09    ; [31]
1484  BA 15         DW spfmt_show_10    ; [32]
1486  00 00         DW 0x0000           ; [33]
1488  95 16         DW spfmt_apply_08   ; [34]
148A  99 16         DW spfmt_apply_09   ; [35]
148C  9D 16         DW spfmt_apply_10   ; [36]

spfmt_menu_b:
148E  CE 15         DW spfmt_show_14    ; [37]
1490  D3 15         DW spfmt_show_15    ; [38]
1492  D8 15         DW spfmt_show_16    ; [39]
1494  00 00         DW 0x0000           ; [40]
1496  AD 16         DW spfmt_apply_14   ; [41]
1498  B1 16         DW spfmt_apply_15   ; [42]
149A  B5 16         DW spfmt_apply_16   ; [43]

spfmt_menu_e:
149C  BF 15         DW spfmt_show_11    ; [44]
149E  C4 15         DW spfmt_show_12    ; [45]
14A0  C9 15         DW spfmt_show_13    ; [46]
14A2  00 00         DW 0x0000           ; [47]
14A4  A1 16         DW spfmt_apply_11   ; [48]
14A6  A5 16         DW spfmt_apply_12   ; [49]
14A8  A9 16         DW spfmt_apply_13   ; [50]

submenu_a:
14AA  B9 16         DW fmt_35_720k      ; [51]
14AC  55 15         DW special_formats_menu ; [52]
14AE  40 15         DW hrd_menu         ; [53]
14B0  00 00         DW 0x0000           ; [54]
14B2  59 18         DW fmt_apply        ; [55]
14B4  78 15         DW menu_show_c      ; [56]
14B6  30 19         DW show_insert_model ; [57]

submenu_b:
14B8  E7 16         DW fmt_35_144m      ; [58]
14BA  B9 16         DW fmt_35_720k      ; [59]
14BC  55 15         DW special_formats_menu ; [60]
14BE  40 15         DW hrd_menu         ; [61]
14C0  00 00         DW 0x0000           ; [62]
14C2  41 18         DW fmt_apply_hd     ; [63]
14C4  29 18         DW fmt_apply_dd     ; [64]
14C6  6A 15         DW menu_show_a      ; [65]
14C8  30 19         DW show_insert_model ; [66]

submenu_c:
14CA  15 17         DW fmt_525_360k     ; [67]
14CC  43 17         DW fmt_525_180k     ; [68]
14CE  71 17         DW fmt_525_320k     ; [69]
14D0  9F 17         DW fmt_525_160k     ; [70]
14D2  55 15         DW special_formats_menu ; [71]
14D4  40 15         DW hrd_menu         ; [72]
14D6  00 00         DW 0x0000           ; [73]
14D8  59 18         DW fmt_apply        ; [74]
14DA  0D 19         DW sel_model_1      ; [75]
14DC  17 19         DW sel_model_2      ; [76]
14DE  21 19         DW sel_model_3      ; [77]
14E0  7F 15         DW menu_show_d      ; [78]
14E2  30 19         DW show_insert_model ; [79]

submenu_d:
14E4  CD 17         DW fmt_525_720k     ; [80]
14E6  55 15         DW special_formats_menu ; [81]
14E8  00 00         DW 0x0000           ; [82]
14EA  59 18         DW fmt_apply        ; [83]
14EC  86 15         DW menu_show_e      ; [84]

submenu_e:
14EE  FB 17         DW fmt_525_12m      ; [85]
14F0  55 15         DW special_formats_menu ; [86]
14F2  40 15         DW hrd_menu         ; [87]
14F4  00 00         DW 0x0000           ; [88]
14F6  59 18         DW fmt_apply        ; [89]
14F8  71 15         DW menu_show_b      ; [90]
14FA  30 19         DW show_insert_model ; [91]

ops_menu:
14FC  D2 19         DW show_read_source ; [92]
14FE  25 1A         DW show_copy_fwv    ; [93]
1500  40 1A         DW show_copy_wv     ; [94]
1502  58 1A         DW show_copy_crc    ; [95]
1504  69 1A         DW show_copy_fv     ; [96]
1506  82 1A         DW show_copy_wd     ; [97]
1508  97 1D         DW show_copy_bitverify ; [98]
150A  C1 25         DW show_batch       ; [99]
150C  B4 1D         DW show_clean_fdd   ; [100]
150E  00 00         DW 0x0000           ; [101]
1510  94 1A         DW set_error_recovery ; [102]
1512  F6 1A         DW start_copy_fwv   ; [103]
1514  C8 1C         DW start_copy_wv    ; [104]
1516  CD 1C         DW start_copy_format ; [105]
1518  DB 1C         DW start_copy_fmtverify ; [106]
151A  92 1D         DW start_copy_write ; [107]
151C  AF 1D         DW start_copy_verify ; [108]
151E  D7 25         DW start_batch      ; [109]
1520  C6 1D         DW abort_check      ; [110]

hrd_test_menu:
1522  D1 2B         DW hrd_radial_a     ; [111]
1524  DA 2B         DW hrd_radial_b     ; [112]
1526  E3 2B         DW hrd_radial_c     ; [113]
1528  35 2C         DW hrd_show_ecc     ; [114]
152A  47 2C         DW hrd_show_azimuth ; [115]
152C  59 2C         DW hrd_show_positioner ; [116]
152E  76 2C         DW hrd_show_spindle ; [117]
1530  00 00         DW 0x0000           ; [118]
1532  C1 2C         DW hrd_run_e        ; [119]
1534  B4 2C         DW hrd_run_c        ; [120]
1536  BB 2C         DW hrd_run_d        ; [121]
1538  AC 2C         DW hrd_run_a        ; [122]
153A  B0 2C         DW hrd_run_b        ; [123]
153C  25 2E         DW hrd_hysteresis   ; [124]
153E  72 2E         DW hrd_spindle_rpm  ; [125]

; print "HRD diagnostics" menu title
hrd_menu:
1540  CD 59 4C      CALL lcd_print
1543  0C 48 52 44 20 64 +  DB \f, "HRD diagnostics", 0
1554  C9            RET

; print "Special formats" menu title
special_formats_menu:
1555  CD 59 4C      CALL lcd_print
1558  0C 53 70 65 63 69 +  DB \f, "Special formats", 0
1569  C9            RET

; run special-format submenu A (spfmt_menu_a) via menu_run
menu_show_a:
156A  21 54 14      LD HL,spfmt_menu_a
156D  CD 2F 52      CALL menu_run
1570  C9            RET

; run special-format submenu B (spfmt_menu_b) via menu_run
menu_show_b:
1571  21 8E 14      LD HL,spfmt_menu_b
1574  CD 2F 52      CALL menu_run
1577  C9            RET

; run special-format submenu C (spfmt_menu_c) via menu_run
menu_show_c:
1578  21 72 14      LD HL,spfmt_menu_c
157B  CD 2F 52      CALL menu_run
157E  C9            RET

; run special-format submenu D (spfmt_menu_d) via menu_run
menu_show_d:
157F  21 80 14      LD HL,spfmt_menu_d
1582  CD 2F 52      CALL menu_run
1585  C9            RET

; run special-format submenu E (spfmt_menu_e) via menu_run
menu_show_e:
1586  21 9C 14      LD HL,spfmt_menu_e
1589  CD 2F 52      CALL menu_run
158C  C9            RET

; display "Special format No. 1" screen (selects number string, stores cyl_head to 0x3165)
spfmt_show_01:
158D  21 FB 15      LD HL,loc_15FB
1590  18 49         JR loc_15DB

; display "Special format No. 2" screen (shared No.-N display code)
spfmt_show_02:
1592  21 02 16      LD HL,loc_1602
1595  18 44         JR loc_15DB

; display "Special format No. 3" screen (shared No.-N display code)
spfmt_show_03:
1597  21 09 16      LD HL,loc_1609
159A  18 3F         JR loc_15DB

; display "Special format No. 4" screen (shared No.-N display code)
spfmt_show_04:
159C  21 10 16      LD HL,loc_1610
159F  18 3A         JR loc_15DB

; display "Special format No. 5" screen (shared No.-N display code)
spfmt_show_05:
15A1  21 17 16      LD HL,loc_1617
15A4  18 35         JR loc_15DB

; display "Special format No. 6" screen (shared No.-N display code)
spfmt_show_06:
15A6  21 1E 16      LD HL,loc_161E
15A9  18 30         JR loc_15DB

; display "Special format No. 7" screen (shared No.-N display code)
spfmt_show_07:
15AB  21 25 16      LD HL,loc_1625
15AE  18 2B         JR loc_15DB

; draw 'Special format No. 8' menu title, latch cyl_head into 0x3165 (slot 8 of 8-16 chain)
spfmt_show_08:
15B0  21 2C 16      LD HL,loc_162C
15B3  18 26         JR loc_15DB

; draw 'Special format No. 9' menu title, latch cyl_head into 0x3165
spfmt_show_09:
15B5  21 33 16      LD HL,loc_1633
15B8  18 21         JR loc_15DB

; draw 'Special format No.10' menu title, latch cyl_head into 0x3165
spfmt_show_10:
15BA  21 3A 16      LD HL,loc_163A
15BD  18 1C         JR loc_15DB

; draw 'Special format No.11' menu title, latch cyl_head into 0x3165
spfmt_show_11:
15BF  21 41 16      LD HL,loc_1641
15C2  18 17         JR loc_15DB

; draw 'Special format No.12' menu title, latch cyl_head into 0x3165
spfmt_show_12:
15C4  21 48 16      LD HL,loc_1648
15C7  18 12         JR loc_15DB

; draw 'Special format No.13' menu title, latch cyl_head into 0x3165
spfmt_show_13:
15C9  21 4F 16      LD HL,loc_164F
15CC  18 0D         JR loc_15DB

; draw 'Special format No.14' menu title, latch cyl_head into 0x3165
spfmt_show_14:
15CE  21 56 16      LD HL,loc_1656
15D1  18 08         JR loc_15DB

; draw 'Special format No.15' menu title, latch cyl_head into 0x3165
spfmt_show_15:
15D3  21 5D 16      LD HL,loc_165D
15D6  18 03         JR loc_15DB

; draw 'Special format No.16' menu title, latch cyl_head into 0x3165
spfmt_show_16:
15D8  21 64 16      LD HL,loc_1664

loc_15DB:
15DB  E5            PUSH HL
15DC  CD 59 4C      CALL lcd_print
15DF  0C 53 70 65 63 69 +  DB \f, "Special format No.", 0
15F3  3A 64 31      LD A,(cyl_head)
15F6  32 65 31      LD (spfmt_num),A
15F9  E1            POP HL
15FA  E9            JP (HL)

loc_15FB:
15FB  CD 59 4C      CALL lcd_print
15FE  20 31 00      DB " 1", 0
1601  C9            RET

loc_1602:
1602  CD 59 4C      CALL lcd_print
1605  20 32 00      DB " 2", 0
1608  C9            RET

loc_1609:
1609  CD 59 4C      CALL lcd_print
160C  20 33 00      DB " 3", 0
160F  C9            RET

loc_1610:
1610  CD 59 4C      CALL lcd_print
1613  20 34 00      DB " 4", 0
1616  C9            RET

loc_1617:
1617  CD 59 4C      CALL lcd_print
161A  20 35 00      DB " 5", 0
161D  C9            RET

loc_161E:
161E  CD 59 4C      CALL lcd_print
1621  20 36 00      DB " 6", 0
1624  C9            RET

loc_1625:
1625  CD 59 4C      CALL lcd_print
1628  20 37 00      DB " 7", 0
162B  C9            RET

loc_162C:
162C  CD 59 4C      CALL lcd_print
162F  20 38 00      DB " 8", 0
1632  C9            RET

loc_1633:
1633  CD 59 4C      CALL lcd_print
1636  20 39 00      DB " 9", 0
1639  C9            RET

loc_163A:
163A  CD 59 4C      CALL lcd_print
163D  31 30 00      DB "10", 0
1640  C9            RET

loc_1641:
1641  CD 59 4C      CALL lcd_print
1644  31 31 00      DB "11", 0
1647  C9            RET

loc_1648:
1648  CD 59 4C      CALL lcd_print
164B  31 32 00      DB "12", 0
164E  C9            RET

loc_164F:
164F  CD 59 4C      CALL lcd_print
1652  31 33 00      DB "13", 0
1655  C9            RET

loc_1656:
1656  CD 59 4C      CALL lcd_print
1659  31 34 00      DB "14", 0
165C  C9            RET

loc_165D:
165D  CD 59 4C      CALL lcd_print
1660  31 35 00      DB "15", 0
1663  C9            RET

loc_1664:
1664  CD 59 4C      CALL lcd_print
1667  31 36 00      DB "16", 0
166A  C9            RET

; apply special-format slot 1 as DD: cyl_head=1, clear density bit, run fmt_apply
spfmt_apply_01:
166B  3E 01         LD A,0x01
166D  C3 2A 18      JP loc_182A

loc_1670:
1670  21 64 31      LD HL,cyl_head
1673  77            LD (HL),A
1674  C3 5D 18      JP loc_185D

; apply special-format slot 2 as DD: cyl_head=2, clear density bit, run fmt_apply
spfmt_apply_02:
1677  3E 02         LD A,0x02
1679  C3 2A 18      JP loc_182A

; apply special-format slot 3 as DD: cyl_head=3, clear density bit, run fmt_apply
spfmt_apply_03:
167C  3E 03         LD A,0x03
167E  C3 2A 18      JP loc_182A

; apply special-format slot 4 as HD: cyl_head=4, set density bit, run fmt_apply
spfmt_apply_04:
1681  3E 04         LD A,0x04
1683  C3 42 18      JP loc_1842

; apply special-format slot 5 as HD: cyl_head=5, set density bit, run fmt_apply
spfmt_apply_05:
1686  3E 05         LD A,0x05
1688  C3 42 18      JP loc_1842

; apply special-format slot 6 as HD: cyl_head=6, set density bit, run fmt_apply
spfmt_apply_06:
168B  3E 06         LD A,0x06
168D  C3 42 18      JP loc_1842

; apply special-format slot 7 as HD: cyl_head=7, set density bit, run fmt_apply
spfmt_apply_07:
1690  3E 07         LD A,0x07
1692  C3 42 18      JP loc_1842

; apply special-format slot 8: set cyl_head=8, run fmt_apply core (no density change)
spfmt_apply_08:
1695  3E 08         LD A,0x08
1697  18 D7         JR loc_1670

; apply special-format slot 9: set cyl_head=9, run fmt_apply core (no density change)
spfmt_apply_09:
1699  3E 09         LD A,0x09
169B  18 D3         JR loc_1670

; apply special-format slot 10: set cyl_head=10, run fmt_apply core
spfmt_apply_10:
169D  3E 0A         LD A,0x0A
169F  18 CF         JR loc_1670

; apply special-format slot 11: set cyl_head=11, run fmt_apply core
spfmt_apply_11:
16A1  3E 0B         LD A,0x0B
16A3  18 CB         JR loc_1670

; apply special-format slot 12: set cyl_head=12, run fmt_apply core
spfmt_apply_12:
16A5  3E 0C         LD A,0x0C
16A7  18 C7         JR loc_1670

; apply special-format slot 13: set cyl_head=13, run fmt_apply core
spfmt_apply_13:
16A9  3E 0D         LD A,0x0D
16AB  18 C3         JR loc_1670

; apply special-format slot 14: set cyl_head=14, run fmt_apply core
spfmt_apply_14:
16AD  3E 0E         LD A,0x0E
16AF  18 BF         JR loc_1670

; apply special-format slot 15: set cyl_head=15, run fmt_apply core
spfmt_apply_15:
16B1  3E 0F         LD A,0x0F
16B3  18 BB         JR loc_1670

; apply special-format slot 16: set cyl_head=16, run fmt_apply core
spfmt_apply_16:
16B5  3E 10         LD A,0x10
16B7  18 B7         JR loc_1670

; print media spec line '3.5" 720kB 9sec 80cyl 2h' for the format-select menu
fmt_35_720k:
16B9  CD 59 4C      CALL lcd_print
16BC  0C 33 2E 35 22 20 +  DB \f, "3.5\"  720 kB 512 b/s 9 sec. 80 cyl. 2 h.", 0
16E6  C9            RET

; print media spec line '3.5" 1.44MB 18sec 80cyl 2h' for the format-select menu
fmt_35_144m:
16E7  CD 59 4C      CALL lcd_print
16EA  0C 33 2E 35 22 20 +  DB \f, "3.5\" 1.44 MB 512 b/s18 sec. 80 cyl. 2 h.", 0
1714  C9            RET

; print media spec line '5.25" 360kB 9sec 40cyl 2h'
fmt_525_360k:
1715  CD 59 4C      CALL lcd_print
1718  0C 35 2E 32 35 22 +  DB \f, "5.25\" 360 kB 512 b/s 9 sec. 40 cyl. 2 h.", 0
1742  C9            RET

; print media spec line '5.25" 180kB 9sec 40cyl 1h'
fmt_525_180k:
1743  CD 59 4C      CALL lcd_print
1746  0C 35 2E 32 35 22 +  DB \f, "5.25\" 180 kB 512 b/s 9 sec. 40 cyl. 1 h.", 0
1770  C9            RET

; print media spec line '5.25" 320kB 8sec 40cyl 2h'
fmt_525_320k:
1771  CD 59 4C      CALL lcd_print
1774  0C 35 2E 32 35 22 +  DB \f, "5.25\" 320 kB 512 b/s 8 sec. 40 cyl. 2 h.", 0
179E  C9            RET

; print media spec line '5.25" 160kB 8sec 40cyl 1h'
fmt_525_160k:
179F  CD 59 4C      CALL lcd_print
17A2  0C 35 2E 32 35 22 +  DB \f, "5.25\" 160 kB 512 b/s 8 sec. 40 cyl. 1 h.", 0
17CC  C9            RET

; print media spec line '5.25" 720kB 9sec 80cyl 2h'
fmt_525_720k:
17CD  CD 59 4C      CALL lcd_print
17D0  0C 35 2E 32 35 22 +  DB \f, "5.25\" 720 kB 512 b/s 9 sec. 80 cyl. 2 h.", 0
17FA  C9            RET

; print media spec line '5.25" 1.2MB 15sec 80cyl 2h'
fmt_525_12m:
17FB  CD 59 4C      CALL lcd_print
17FE  0C 35 2E 32 35 22 +  DB \f, "5.25\" 1.2 MB 512 b/s15 sec. 80 cyl. 2 h.", 0
1828  C9            RET

; enter fmt_apply selecting DD density: cyl_head=0, clear format_desc[11] bit7, sync image flag
fmt_apply_dd:
1829  AF            XOR A

loc_182A:
182A  32 64 31      LD (cyl_head),A
182D  DD 21 DD 52   LD IX,format_desc
1831  DD CB 0B BE   RES 7,(IX+11)
1835  3A 37 31      LD A,(unit_sel)
1838  CB 4F         BIT 1,A
183A  C4 29 19      CALL NZ,clear_image_present
183D  CB 8F         RES 1,A
183F  18 1F         JR loc_1860

; enter fmt_apply selecting HD density: cyl_head=0, set format_desc[11] bit7, sync image flag
fmt_apply_hd:
1841  AF            XOR A

loc_1842:
1842  32 64 31      LD (cyl_head),A
1845  DD 21 DD 52   LD IX,format_desc
1849  DD CB 0B FE   SET 7,(IX+11)
184D  3A 37 31      LD A,(unit_sel)
1850  CB 4F         BIT 1,A
1852  CC 29 19      CALL Z,clear_image_present
1855  CB CF         SET 1,A
1857  18 07         JR loc_1860

; format-apply core: program both FDCs, build format block + sector layout, warn on non-std max cyl, run ops_menu
fmt_apply:
1859  AF            XOR A
185A  32 64 31      LD (cyl_head),A

loc_185D:
185D  3A 37 31      LD A,(unit_sel)

loc_1860:
1860  21 85 4A      LD HL,fdc_result_buf
1863  21 DA 4A      LD HL,fdc_param_recs+0x1E
1866  21 DD 52      LD HL,format_desc
1869  21 EB 4A      LD HL,drive_blk_a
186C  32 37 31      LD (unit_sel),A
186F  CD 7B 04      CALL fdc_cmd_both_drives
1872  CD CB 4F      CALL build_format_block
1875  CD CC 50      CALL layout_sectors
1878  3A 64 31      LD A,(cyl_head)
187B  FE 04         CP 0x04
187D  28 04         JR Z,loc_1883
187F  FE 0E         CP 0x0E
1881  20 11         JR NZ,loc_1894

loc_1883:
1883  21 00 00      LD HL,0x0000
1886  CD F2 4F      CALL block_to_chs
1889  EB            EX DE,HL
188A  47            LD B,A
188B  0E 00         LD C,0x00
188D  79            LD A,C
188E  59            LD E,C
188F  16 1A         LD D,0x1A
1891  CD 1E 48      CALL dram_stack_fill

loc_1894:
1894  DD 7E 0B      LD A,(IX+11)
1897  CB 47         BIT 0,A
1899  20 0F         JR NZ,loc_18AA
189B  CD 25 27      CALL drive_block_pos
189E  06 18         LD B,0x18
18A0  21 A1 31      LD HL,hrd_hd0
18A3  3E 00         LD A,0x00
18A5  CD 35 27      CALL config_save
18A8  18 0C         JR loc_18B6

loc_18AA:
18AA  CD 07 27      CALL drive_block_ptr
18AD  11 A1 31      LD DE,hrd_hd0
18B0  06 00         LD B,0x00
18B2  0E 18         LD C,0x18
18B4  ED B0         LDIR

loc_18B6:
18B6  3A 37 31      LD A,(unit_sel)
18B9  21 38 31      LD HL,unit_sel+0x1
18BC  BE            CP (HL)
18BD  77            LD (HL),A
18BE  C4 29 19      CALL NZ,clear_image_present
18C1  3A 64 31      LD A,(cyl_head)
18C4  21 65 31      LD HL,spfmt_num
18C7  BE            CP (HL)
18C8  77            LD (HL),A
18C9  C4 29 19      CALL NZ,clear_image_present
18CC  3A 1C 31      LD A,(cfg_flags)
18CF  E6 7F         AND 0x7F
18D1  28 2E         JR Z,loc_1901
18D3  CD 59 4C      CALL lcd_print
18D6  0C 20 20 20 20 57 +  DB \f, "    WARNING !", \r, \n, "non std. max. cyl.", 0
18F9  3E 03         LD A,0x03
18FB  CD 66 27      CALL beep
18FE  CD A9 03      CALL lcd_home3

loc_1901:
1901  21 FC 14      LD HL,ops_menu
1904  CD 2F 52      CALL menu_run
1907  21 34 31      LD HL,op_word
190A  CB A6         RES 4,(HL)
190C  C9            RET

; pick drive model 1 (unit_sel low bits=01) then run fmt_apply
sel_model_1:
190D  3A 37 31      LD A,(unit_sel)
1910  E6 FC         AND 0xFC
1912  F6 01         OR 0x01
1914  C3 59 18      JP fmt_apply

; pick drive model 2 (unit_sel low bits=10) then run fmt_apply
sel_model_2:
1917  3A 37 31      LD A,(unit_sel)
191A  E6 FC         AND 0xFC
191C  F6 02         OR 0x02
191E  C3 59 18      JP fmt_apply

; pick drive model 0/3 (clear unit_sel low bits) then run fmt_apply
sel_model_3:
1921  3A 37 31      LD A,(unit_sel)
1924  E6 FC         AND 0xFC
1926  C3 59 18      JP fmt_apply

; invalidate cached RAM disk image by zeroing image_present (AF preserved)
clear_image_present:
1929  F5            PUSH AF
192A  AF            XOR A
192B  32 C8 52      LD (image_present),A
192E  F1            POP AF
192F  C9            RET

; draw 'Insert model' prompt; decode model-ID sense (0x52E8) to 528/526/325-400 handler else Not available
show_insert_model:
1930  CD 59 4C      CALL lcd_print
1933  1B C0 49 6E 73 65 +  DB ESC(0xC0), "Insert model ", 0
1943  3A E8 52      LD A,(format_desc+0xB)
1946  E6 C8         AND 0xC8
1948  FE 08         CP 0x08
194A  28 21         JR Z,loc_196D
194C  FE C8         CP 0xC8
194E  28 2E         JR Z,loc_197E
1950  E6 48         AND 0x48
1952  FE 40         CP 0x40
1954  28 39         JR Z,loc_198F

; draw 'Not available' on LCD line 2 and home cursor
show_not_available:
1956  CD 59 4C      CALL lcd_print
1959  1B C0 4E 6F 74 20 +  DB ESC(0xC0), "Not available", 0
1969  CD A9 03      CALL lcd_home3
196C  C9            RET

loc_196D:
196D  CD 59 4C      CALL lcd_print
1970  35 32 38 2D 34 30 +  DB "528-400", 0
1978  3E 00         LD A,0x00
197A  06 14         LD B,0x14
197C  18 25         JR loc_19A3

loc_197E:
197E  CD 59 4C      CALL lcd_print
1981  35 32 36 2D 34 30 +  DB "526-400", 0
1989  3E 01         LD A,0x01
198B  06 13         LD B,0x13
198D  18 14         JR loc_19A3

loc_198F:
198F  CD 59 4C      CALL lcd_print
1992  33 32 35 2D 34 30 +  DB "325-400", 0
199A  21 E8 52      LD HL,format_desc+0xB
199D  CB BE         RES 7,(HL)
199F  3E 02         LD A,0x02
19A1  06 12         LD B,0x12

loc_19A3:
19A3  32 78 31      LD (hrd_model_idx),A
19A6  78            LD A,B
19A7  32 64 31      LD (cyl_head),A
19AA  3E 01         LD A,0x01
19AC  CD 89 4D      CALL get_key
19AF  CD 4F 07      CALL set_drive_cfg
19B2  CD B4 11      CALL read_source
19B5  C0            RET NZ
19B6  CD E7 51      CALL fdc_build_unit_sel
19B9  32 37 31      LD (unit_sel),A
19BC  CD 7B 04      CALL fdc_cmd_both_drives
19BF  CD A9 03      CALL lcd_home3
19C2  CD 09 07      CALL motor_ready_wait
19C5  CD 57 07      CALL drive_cfg_latch
19C8  21 22 15      LD HL,hrd_test_menu
19CB  CD 2F 52      CALL menu_run
19CE  CD 2D 11      CALL al_cmd_reject
19D1  C9            RET

; draw 'Read source disk'; show 'data image present' or 'insert source disk' per image_present
show_read_source:
19D2  CD 59 4C      CALL lcd_print
19D5  0C 52 65 61 64 20 +  DB \f, "Read source disk", 0
19E7  3A C8 52      LD A,(image_present)
19EA  B7            OR A
19EB  28 1C         JR Z,loc_1A09
19ED  CD 70 06      CALL lcd_clear_line2
19F0  CD 59 4C      CALL lcd_print
19F3  1B C0 64 61 74 61 +  DB ESC(0xC0), "data image present", 0
1A08  C9            RET

loc_1A09:
1A09  CD 70 06      CALL lcd_clear_line2
1A0C  CD 59 4C      CALL lcd_print
1A0F  1B C0 69 6E 73 65 +  DB ESC(0xC0), "insert source disk", 0
1A24  C9            RET

; print 'Format Write Verify' copy-mode menu label
show_copy_fwv:
1A25  CD 59 4C      CALL lcd_print
1A28  0C 46 6F 72 6D 61 +  DB \f, "Format Write Verify", \n, \r, 0
1A3F  C9            RET

; print 'Write and verify' copy-mode menu label
show_copy_wv:
1A40  CD 59 4C      CALL lcd_print
1A43  0C 57 72 69 74 65 +  DB \f, "Write and verify", \n, \r, 0
1A57  C9            RET

; print 'CRC check' copy-mode menu label
show_copy_crc:
1A58  CD 59 4C      CALL lcd_print
1A5B  0C 43 52 43 20 63 +  DB \f, "CRC check", \n, \r, 0
1A68  C9            RET

; print 'Format and verify' copy-mode menu label
show_copy_fv:
1A69  CD 59 4C      CALL lcd_print
1A6C  0C 46 6F 72 6D 61 +  DB \f, "Format and verify", \n, \r, 0
1A81  C9            RET

; print 'Write disk' copy-mode menu label
show_copy_wd:
1A82  CD 59 4C      CALL lcd_print
1A85  0C 57 72 69 74 65 +  DB \f, "Write disk", \n, \r, 0
1A93  C9            RET

; force error-recovery mode (0x314A=3), run duplication then image-compare pass, restore, set image_present on success
set_error_recovery:
1A94  21 4A 31      LD HL,err_recovery
1A97  7E            LD A,(HL)
1A98  36 03         LD (HL),0x03
1A9A  23            INC HL
1A9B  77            LD (HL),A
1A9C  3E 00         LD A,0x00
1A9E  21 01 00      LD HL,0x0001
1AA1  32 C8 52      LD (image_present),A
1AA4  32 4E 31      LD (run_status),A
1AA7  CD ED 1A      CALL start_run_op
1AAA  AF            XOR A
1AAB  32 C8 52      LD (image_present),A
1AAE  3A 34 31      LD A,(op_word)
1AB1  E6 E0         AND 0xE0
1AB3  20 29         JR NZ,loc_1ADE
1AB5  CD 70 06      CALL lcd_clear_line2
1AB8  CD 59 4C      CALL lcd_print
1ABB  1B C0 69 6D 61 67 +  DB ESC(0xC0), "image comparing", 0
1ACD  3E 08         LD A,0x08
1ACF  32 4E 31      LD (run_status),A
1AD2  AF            XOR A
1AD3  21 01 00      LD HL,0x0001
1AD6  CD ED 1A      CALL start_run_op
1AD9  3A 34 31      LD A,(op_word)
1ADC  E6 E0         AND 0xE0

loc_1ADE:
1ADE  F5            PUSH AF
1ADF  21 4B 31      LD HL,err_recovery+0x1
1AE2  7E            LD A,(HL)
1AE3  2B            DEC HL
1AE4  77            LD (HL),A
1AE5  F1            POP AF
1AE6  C0            RET NZ
1AE7  3E 01         LD A,0x01
1AE9  32 C8 52      LD (image_present),A
1AEC  C9            RET

; set op_word=A and run_count=HL, then enter dup_engine_loop to run the duplication op
start_run_op:
1AED  32 34 31      LD (op_word),A
1AF0  22 3D 31      LD (run_count),HL
1AF3  C3 9E 1C      JP loc_1C9E

; start Format-Write-Verify copy (op_word=1); if no image show 'data image missing', else prompt copy count and run
start_copy_fwv:
1AF6  3E 01         LD A,0x01

loc_1AF8:
1AF8  32 34 31      LD (op_word),A
1AFB  21 00 00      LD HL,0x0000
1AFE  22 3D 31      LD (run_count),HL
1B01  3A C8 52      LD A,(image_present)
1B04  B7            OR A
1B05  20 2B         JR NZ,loc_1B32
1B07  CD 59 4C      CALL lcd_print
1B0A  0C 4E 6F 74 20 61 +  DB \f, "Not available", \r, \n, "data image missing", 0
1B2D  3E 01         LD A,0x01
1B2F  C3 89 4D      JP get_key

loc_1B32:
1B32  2A 41 31      LD HL,(copy_count)
1B35  22 3D 31      LD (run_count),HL
1B38  CD 93 04      CALL edit_num_copies
1B3B  C8            RET Z
1B3C  21 67 31      LD HL,hrd_desc_tbl
1B3F  CB 4E         BIT 1,(HL)
1B41  CA 88 07      JP Z,dup_engine_loop
1B44  3A 34 31      LD A,(op_word)
1B47  E6 0F         AND 0x0F
1B49  FE 03         CP 0x03
1B4B  CA 88 07      JP Z,dup_engine_loop
1B4E  FE 08         CP 0x08
1B50  CA 88 07      JP Z,dup_engine_loop
1B53  CD 59 4C      CALL lcd_print
1B56  0C 49 6E 69 74 69 +  DB \f, "Initial serial Nr.", 0
1B6A  2A 68 31      LD HL,(serial_nr)
1B6D  22 43 31      LD (edit_value),HL
1B70  2A 6A 31      LD HL,(serial_incr)
1B73  22 45 31      LD (edit_value_hi),HL
1B76  06 08         LD B,0x08
1B78  3E 0A         LD A,0x0A
1B7A  CD C3 04      CALL edit_num_field
1B7D  C8            RET Z
1B7E  2A 43 31      LD HL,(edit_value)
1B81  22 68 31      LD (serial_nr),HL
1B84  2A 45 31      LD HL,(edit_value_hi)
1B87  22 6A 31      LD (serial_incr),HL
1B8A  CD 59 4C      CALL lcd_print
1B8D  0C 49 6E 63 72 65 +  DB \f, "Increment", 0
1B98  3A 6C 31      LD A,(serial_cyl)
1B9B  6F            LD L,A
1B9C  26 00         LD H,0x00
1B9E  22 43 31      LD (edit_value),HL
1BA1  6C            LD L,H
1BA2  22 45 31      LD (edit_value_hi),HL
1BA5  06 02         LD B,0x02
1BA7  3E 10         LD A,0x10
1BA9  CD C3 04      CALL edit_num_field
1BAC  C8            RET Z
1BAD  3A 43 31      LD A,(edit_value)
1BB0  32 6C 31      LD (serial_cyl),A

loc_1BB3:
1BB3  CD 59 4C      CALL lcd_print
1BB6  0C 43 79 6C 69 6E +  DB \f, "Cylinder", 0
1BC0  3A 6D 31      LD A,(serial_head)
1BC3  6F            LD L,A
1BC4  26 00         LD H,0x00
1BC6  22 43 31      LD (edit_value),HL
1BC9  6C            LD L,H
1BCA  22 45 31      LD (edit_value_hi),HL
1BCD  06 02         LD B,0x02
1BCF  3E 10         LD A,0x10
1BD1  CD C3 04      CALL edit_num_field
1BD4  C8            RET Z
1BD5  21 DD 52      LD HL,format_desc
1BD8  CD A5 1C      CALL check_cyl_limit
1BDB  38 D6         JR C,loc_1BB3
1BDD  32 6D 31      LD (serial_head),A

loc_1BE0:
1BE0  CD 59 4C      CALL lcd_print
1BE3  0C 48 65 61 64 00  DB \f, "Head", 0
1BE9  3A 6E 31      LD A,(serial_sector)
1BEC  6F            LD L,A
1BED  26 00         LD H,0x00
1BEF  22 43 31      LD (edit_value),HL
1BF2  6C            LD L,H
1BF3  22 45 31      LD (edit_value_hi),HL
1BF6  06 01         LD B,0x01
1BF8  3E 11         LD A,0x11
1BFA  CD C3 04      CALL edit_num_field
1BFD  C8            RET Z
1BFE  21 DE 52      LD HL,format_desc+0x1
1C01  CD A5 1C      CALL check_cyl_limit
1C04  38 DA         JR C,loc_1BE0
1C06  32 6E 31      LD (serial_sector),A

loc_1C09:
1C09  CD 59 4C      CALL lcd_print
1C0C  0C 53 65 63 74 6F +  DB \f, "Sector", 0
1C14  3A 6F 31      LD A,(serial_offset)
1C17  6F            LD L,A
1C18  26 00         LD H,0x00
1C1A  22 43 31      LD (edit_value),HL
1C1D  6C            LD L,H
1C1E  22 45 31      LD (edit_value_hi),HL
1C21  06 02         LD B,0x02
1C23  3E 10         LD A,0x10
1C25  CD C3 04      CALL edit_num_field
1C28  C8            RET Z
1C29  21 DF 52      LD HL,format_desc+0x2
1C2C  34            INC (HL)
1C2D  CD A5 1C      CALL check_cyl_limit
1C30  35            DEC (HL)
1C31  38 D6         JR C,loc_1C09
1C33  A7            AND A
1C34  CC AC 1C      CALL Z,show_out_of_range
1C37  38 D0         JR C,loc_1C09
1C39  32 6F 31      LD (serial_offset),A

loc_1C3C:
1C3C  CD 59 4C      CALL lcd_print
1C3F  0C 4F 66 66 73 65 +  DB \f, "Offset", 0
1C47  2A 70 31      LD HL,(serial_pos)
1C4A  22 43 31      LD (edit_value),HL
1C4D  21 00 00      LD HL,0x0000
1C50  22 45 31      LD (edit_value_hi),HL
1C53  06 04         LD B,0x04
1C55  3E 0E         LD A,0x0E
1C57  CD C3 04      CALL edit_num_field
1C5A  C8            RET Z
1C5B  2A 43 31      LD HL,(edit_value)
1C5E  ED 5B E0 52   LD DE,(format_desc+0x3)
1C62  1B            DEC DE
1C63  1B            DEC DE
1C64  1B            DEC DE
1C65  1B            DEC DE
1C66  A7            AND A
1C67  E5            PUSH HL
1C68  ED 52         SBC HL,DE
1C6A  E1            POP HL
1C6B  38 05         JR C,loc_1C72
1C6D  CD AC 1C      CALL show_out_of_range
1C70  18 CA         JR loc_1C3C

loc_1C72:
1C72  22 70 31      LD (serial_pos),HL
1C75  ED 4B 6D 31   LD BC,(serial_head)
1C79  79            LD A,C
1C7A  48            LD C,B
1C7B  47            LD B,A
1C7C  CB 09         RRC C
1C7E  3A 6F 31      LD A,(serial_offset)
1C81  CD A5 2B      CALL track_buf_ptr
1C84  32 72 31      LD (serial_flag),A
1C87  ED 5B 70 31   LD DE,(serial_pos)
1C8B  19            ADD HL,DE
1C8C  22 73 31      LD (serial_addr),HL
1C8F  2A 70 31      LD HL,(serial_pos)
1C92  3A 6F 31      LD A,(serial_offset)
1C95  CD AB 2B      CALL track_ptr_scale
1C98  22 75 31      LD (serial_ptr),HL
1C9B  CD A1 1C      CALL jump_phase_handler

loc_1C9E:
1C9E  C3 88 07      JP dup_engine_loop

; indirect jump through phase_handler vector to the current duplication-phase routine
jump_phase_handler:
1CA1  2A 31 31      LD HL,(phase_handler)
1CA4  E9            JP (HL)

; test requested cyl in HL against max-cyl 0x3143; returns in-range via M flag (no carry if OK)
check_cyl_limit:
1CA5  3A 43 31      LD A,(edit_value)
1CA8  BE            CP (HL)
1CA9  37            SCF
1CAA  3F            CCF
1CAB  F8            RET M

; draw 'Out of range' on LCD line 2, home cursor, set carry to reject the value
show_out_of_range:
1CAC  E5            PUSH HL
1CAD  CD 70 06      CALL lcd_clear_line2
1CB0  CD 59 4C      CALL lcd_print
1CB3  1B C0 4F 75 74 20 +  DB ESC(0xC0), "Out of range", 0
1CC2  CD A9 03      CALL lcd_home3
1CC5  E1            POP HL
1CC6  37            SCF
1CC7  C9            RET

; start Write-and-Verify copy (op_word=2) via the shared start_copy_fwv path
start_copy_wv:
1CC8  3E 02         LD A,0x02
1CCA  C3 F8 1A      JP loc_1AF8

; start Format-only copy (op_word=3), jump to copy-count prompt and run
start_copy_format:
1CCD  3E 03         LD A,0x03

loc_1CCF:
1CCF  32 34 31      LD (op_word),A
1CD2  21 00 00      LD HL,0x0000
1CD5  22 3D 31      LD (run_count),HL
1CD8  C3 32 1B      JP loc_1B32

; FORMAT: if cyl_head!=0 skip; else build blank FAT12 image in DRAM bank 0xFE from ROM template, stamp 0x55AA, zero-fill+FAT-init every track
start_copy_fmtverify:
1CDB  3A 64 31      LD A,(cyl_head)
1CDE  B7            OR A
1CDF  C2 8D 1D      JP NZ,loc_1D8D

; FORMAT: build FAT12 boot sector from ROM template, stamp 0x55AA, format tracks
format_track:
1CE2  AF            XOR A
1CE3  32 C8 52      LD (image_present),A
1CE6  DD 21 DD 52   LD IX,format_desc
1CEA  3E FE         LD A,0xFE
1CEC  D3 B0         OUT (0xB0),A  ; dram_bank
1CEE  DD 4E 07      LD C,(IX+7)
1CF1  DD 46 08      LD B,(IX+8)
1CF4  0B            DEC BC
1CF5  21 00 80      LD HL,image_buf
1CF8  11 01 80      LD DE,image_buf+0x1
1CFB  36 00         LD (HL),0x00
1CFD  ED B0         LDIR
1CFF  21 05 33      LD HL,fat12_template
1D02  11 00 80      LD DE,image_buf
1D05  01 0B 00      LD BC,0x000B
1D08  ED B0         LDIR
1D0A  11 2B 80      LD DE,image_buf+0x2B
1D0D  01 13 00      LD BC,0x0013
1D10  ED B0         LDIR
1D12  11 50 80      LD DE,image_buf+0x50
1D15  01 2B 00      LD BC,0x002B
1D18  ED B0         LDIR
1D1A  21 55 AA      LD HL,0xAA55
1D1D  22 FE 81      LD (image_buf+0x1FE),HL
1D20  CD 83 2B      CALL fdd_geom_index
1D23  0E 00         LD C,0x00
1D25  11 13 00      LD DE,0x0013
1D28  CD 05 4F      CALL mul16
1D2B  11 6D 32      LD DE,cycle_cnt_hi+0x2
1D2E  19            ADD HL,DE
1D2F  E5            PUSH HL
1D30  11 0B 80      LD DE,image_buf+0xB
1D33  01 13 00      LD BC,0x0013
1D36  ED B0         LDIR
1D38  DD E1         POP IX
1D3A  DD 7E 06      LD A,(IX+6)
1D3D  07            RLCA
1D3E  07            RLCA
1D3F  07            RLCA
1D40  07            RLCA
1D41  DD 46 0B      LD B,(IX+11)
1D44  CB 20         SLA B
1D46  80            ADD A,B
1D47  47            LD B,A
1D48  DD 7E 03      LD A,(IX+3)

loc_1D4B:
1D4B  C5            PUSH BC
1D4C  F5            PUSH AF
1D4D  CD B7 2B      CALL geom_sector_calc
1D50  CD A5 2B      CALL track_buf_ptr
1D53  E5            PUSH HL
1D54  D1            POP DE
1D55  D3 B0         OUT (0xB0),A  ; dram_bank
1D57  13            INC DE
1D58  01 FF 01      LD BC,0x01FF
1D5B  36 00         LD (HL),0x00
1D5D  ED B0         LDIR
1D5F  F1            POP AF
1D60  3C            INC A
1D61  C1            POP BC
1D62  10 E7         DJNZ loc_1D4B
1D64  01 00 00      LD BC,0x0000
1D67  3E 02         LD A,0x02
1D69  CD A5 2B      CALL track_buf_ptr
1D6C  D3 B0         OUT (0xB0),A  ; dram_bank
1D6E  DD 7E 0A      LD A,(IX+10)
1D71  77            LD (HL),A
1D72  23            INC HL
1D73  36 FF         LD (HL),0xFF
1D75  23            INC HL
1D76  36 FF         LD (HL),0xFF
1D78  DD 7E 0B      LD A,(IX+11)
1D7B  3C            INC A
1D7C  3C            INC A
1D7D  01 00 00      LD BC,0x0000
1D80  CD A5 2B      CALL track_buf_ptr
1D83  DD 7E 0A      LD A,(IX+10)
1D86  77            LD (HL),A
1D87  23            INC HL
1D88  36 FF         LD (HL),0xFF
1D8A  23            INC HL
1D8B  36 FF         LD (HL),0xFF

loc_1D8D:
1D8D  3E 04         LD A,0x04
1D8F  C3 CF 1C      JP loc_1CCF

; start a 'Copy: write' run (start_run_op with mode 6)
start_copy_write:
1D92  3E 06         LD A,0x06
1D94  C3 F8 1A      JP loc_1AF8

; draw the 'Bit per bit verify' status line
show_copy_bitverify:
1D97  CD 59 4C      CALL lcd_print
1D9A  0C 42 69 74 20 70 +  DB \f, "Bit per bit verify", 0
1DAE  C9            RET

; start a 'Copy: verify' run (start_run_op with mode 8)
start_copy_verify:
1DAF  3E 08         LD A,0x08
1DB1  C3 F8 1A      JP loc_1AF8

; draw the 'Cleaning FDD' status line
show_clean_fdd:
1DB4  CD 59 4C      CALL lcd_print
1DB7  0C 43 6C 65 61 6E +  DB \f, "Cleaning FDD", 0
1DC5  C9            RET

; if autoloader disk present launch run op 9, else fall through to show_abort prompt
abort_check:
1DC6  CD AD 11      CALL al_insert_disk
1DC9  28 1D         JR Z,loc_1DE8

; show 'Abort' on line2, beep once, reset LCD cursor; returns fmt_mode
show_abort:
1DCB  CD 70 06      CALL lcd_clear_line2
1DCE  CD 59 4C      CALL lcd_print
1DD1  1B C0 41 62 6F 72 +  DB ESC(0xC0), "Abort", 0
1DD9  3E 01         LD A,0x01
1DDB  CD 66 27      CALL beep
1DDE  21 00 00      LD HL,0x0000
1DE1  CD 22 4C      CALL lcd_setpos
1DE4  3A 4C 31      LD A,(fmt_mode)
1DE7  C9            RET

loc_1DE8:
1DE8  CD 70 06      CALL lcd_clear_line2
1DEB  21 0A 00      LD HL,0x000A
1DEE  3E 09         LD A,0x09
1DF0  C3 ED 1A      JP start_run_op

; read 4-byte host command packet (opcode in D)
host_read_packet:
1DF3  CD 01 1E      CALL host_rx_word
1DF6  C0            RET NZ
1DF7  CD AD 4E      CALL host_rx
1DFA  68            LD L,B
1DFB  C0            RET NZ
1DFC  CD AD 4E      CALL host_rx
1DFF  60            LD H,B
1E00  C9            RET

; read a little-endian 16-bit word from host USART into E,D (abort on rx error)
host_rx_word:
1E01  CD AD 4E      CALL host_rx
1E04  58            LD E,B
1E05  C0            RET NZ
1E06  CD AD 4E      CALL host_rx
1E09  50            LD D,B
1E0A  C9            RET

; host remote-control server dispatcher (opcode table)
host_dispatch:
1E0B  3E 01         LD A,0x01
1E0D  32 61 31      LD (host_mode),A
1E10  18 19         JR loc_1E2B

loc_1E12:
1E12  B7            OR A
1E13  28 07         JR Z,loc_1E1C
1E15  06 45         LD B,0x45
1E17  CD 9D 4E      CALL host_tx
1E1A  18 EF         JR host_dispatch

loc_1E1C:
1E1C  CD 59 4C      CALL lcd_print
1E1F  1B 93 2E 00   DB ESC(0x93), ".", 0
1E23  3A 21 1E      LD A,(loc_1E1C+0x5)
1E26  EE 0F         XOR 0x0F
1E28  32 21 1E      LD (loc_1E1C+0x5),A

loc_1E2B:
1E2B  CD F3 1D      CALL host_read_packet
1E2E  20 E2         JR NZ,loc_1E12
1E30  7A            LD A,D
1E31  32 34 31      LD (op_word),A
1E34  22 3D 31      LD (run_count),HL

; host op 0x0A: download disk image over bulk channel - AA55 sync, validate geometry header, stream tracks into DRAM banks, verify checksum, set image_present
host_op_image_dl:
1E37  FE 0A         CP 0x0A
1E39  C2 9F 1F      JP NZ,host_op_enter_run
1E3C  06 58         LD B,0x58
1E3E  CD 9D 4E      CALL host_tx
1E41  21 00 00      LD HL,0x0000
1E44  22 39 31      LD (track_ctr),HL
1E47  22 47 31      LD (dl_rec_count),HL
1E4A  3E FF         LD A,0xFF
1E4C  32 33 31      LD (cur_track),A
1E4F  CD 59 4C      CALL lcd_print
1E52  1B C0 77 61 69 74 +  DB ESC(0xC0), "wait for data", 0
1E62  CD 96 21      CALL bulk_sync_aa55
1E65  C2 F6 1E      JP NZ,loc_1EF6
1E68  CD 59 4C      CALL lcd_print
1E6B  1B C8 72 65 61 64 +  DB ESC(0xC8), "read RI", 0
1E75  18 06         JR loc_1E7D

loc_1E77:
1E77  CD 96 21      CALL bulk_sync_aa55
1E7A  C2 F6 1E      JP NZ,loc_1EF6

loc_1E7D:
1E7D  21 00 00      LD HL,0x0000
1E80  22 39 31      LD (track_ctr),HL
1E83  CD 6A 21      CALL bulk_read_byte
1E86  79            LD A,C
1E87  32 4E 33      LD (fmt_buf1),A
1E8A  32 39 31      LD (track_ctr),A
1E8D  E6 7F         AND 0x7F
1E8F  FE 01         CP 0x01
1E91  28 28         JR Z,loc_1EBB
1E93  CD 70 06      CALL lcd_clear_line2
1E96  CD 59 4C      CALL lcd_print
1E99  1B C0 52 65 6D 6F +  DB ESC(0xC0), "Remote command error", 0
1EB0  CD 43 4D      CALL keypad_debounce
1EB3  06 90         LD B,0x90
1EB5  CD 9D 4E      CALL host_tx
1EB8  C3 0B 1E      JP host_dispatch

loc_1EBB:
1EBB  21 4F 33      LD HL,fmt_buf1+0x1
1EBE  06 08         LD B,0x08
1EC0  E5            PUSH HL
1EC1  CD 34 21      CALL bulk_read_bytes
1EC4  E1            POP HL
1EC5  3A 37 31      LD A,(unit_sel)
1EC8  E6 1F         AND 0x1F
1ECA  BE            CP (HL)
1ECB  28 30         JR Z,loc_1EFD
1ECD  FE 04         CP 0x04
1ECF  20 04         JR NZ,loc_1ED5
1ED1  3C            INC A
1ED2  BE            CP (HL)
1ED3  28 28         JR Z,loc_1EFD

loc_1ED5:
1ED5  CD 70 06      CALL lcd_clear_line2
1ED8  CD 59 4C      CALL lcd_print
1EDB  1B C0 4E 6F 74 20 +  DB ESC(0xC0), "Not proper image", 0
1EEE  06 B0         LD B,0xB0
1EF0  CD 9D 4E      CALL host_tx
1EF3  C3 0B 1E      JP host_dispatch

loc_1EF6:
1EF6  CD CB 1D      CALL show_abort
1EF9  C3 0B 1E      JP host_dispatch
1EFC  C9            RET

loc_1EFD:
1EFD  CD 41 21      CALL bulk_validate
1F00  28 16         JR Z,loc_1F18
1F02  DD 21 4F 33   LD IX,fmt_buf1+0x1
1F06  DD 46 01      LD B,(IX+1)
1F09  DD 7E 02      LD A,(IX+2)
1F0C  0F            RRCA
1F0D  E6 80         AND 0x80
1F0F  4F            LD C,A
1F10  CD F2 4F      CALL block_to_chs
1F13  D3 B0         OUT (0xB0),A  ; dram_bank
1F15  22 3B 31      LD (pass_ctr),HL

loc_1F18:
1F18  2A 3B 31      LD HL,(pass_ctr)
1F1B  06 00         LD B,0x00
1F1D  CD 34 21      CALL bulk_read_bytes
1F20  22 3B 31      LD (pass_ctr),HL
1F23  20 D1         JR NZ,loc_1EF6
1F25  11 00 00      LD DE,0x0000
1F28  DD 21 00 00   LD IX,0x0000
1F2C  2B            DEC HL
1F2D  43            LD B,E

loc_1F2E:
1F2E  5E            LD E,(HL)
1F2F  DD 19         ADD IX,DE
1F31  2B            DEC HL
1F32  5E            LD E,(HL)
1F33  DD 19         ADD IX,DE
1F35  2B            DEC HL
1F36  10 F6         DJNZ loc_1F2E
1F38  21 4E 33      LD HL,fmt_buf1
1F3B  06 11         LD B,0x11

loc_1F3D:
1F3D  5E            LD E,(HL)
1F3E  DD 19         ADD IX,DE
1F40  23            INC HL
1F41  10 FA         DJNZ loc_1F3D
1F43  CD 61 21      CALL bulk_read_word
1F46  DD E5         PUSH IX
1F48  E1            POP HL
1F49  B7            OR A
1F4A  ED 52         SBC HL,DE
1F4C  28 20         JR Z,loc_1F6E
1F4E  CD 70 06      CALL lcd_clear_line2
1F51  CD 59 4C      CALL lcd_print
1F54  1B C0 54 72 61 6E +  DB ESC(0xC0), "Transfer failed", 0
1F66  06 A0         LD B,0xA0
1F68  CD 9D 4E      CALL host_tx
1F6B  C3 0B 1E      JP host_dispatch

loc_1F6E:
1F6E  21 4E 33      LD HL,fmt_buf1
1F71  CB 7E         BIT 7,(HL)
1F73  20 14         JR NZ,loc_1F89
1F75  CD 70 06      CALL lcd_clear_line2
1F78  2A 47 31      LD HL,(dl_rec_count)
1F7B  23            INC HL
1F7C  22 47 31      LD (dl_rec_count),HL
1F7F  3E 00         LD A,0x00
1F81  1E 20         LD E,0x20
1F83  CD FA 05      CALL num_to_lcd_alt
1F86  C3 77 1E      JP loc_1E77

loc_1F89:
1F89  CD 61 21      CALL bulk_read_word
1F8C  3E 01         LD A,0x01
1F8E  32 C8 52      LD (image_present),A
1F91  CD 5D 51      CALL checksum_all_banks
1F94  CD 70 06      CALL lcd_clear_line2
1F97  06 00         LD B,0x00
1F99  CD 9D 4E      CALL host_tx
1F9C  C3 0B 1E      JP host_dispatch

; host op 0x0B: enter interactive run mode - install iovec callbacks (key/out/annun) and JP run_entry
host_op_enter_run:
1F9F  FE 0B         CP 0x0B
1FA1  20 23         JR NZ,host_op_disk_write
1FA3  AF            XOR A
1FA4  32 61 31      LD (host_mode),A
1FA7  06 58         LD B,0x58
1FA9  CD 9D 4E      CALL host_tx
1FAC  06 00         LD B,0x00
1FAE  CD 9D 4E      CALL host_tx
1FB1  21 8E 4D      LD HL,get_key_dispatch
1FB4  22 CB 52      LD (iovec_poll),HL
1FB7  21 4A 4C      LD HL,byte_out
1FBA  22 C9 52      LD (iovec_out),HL
1FBD  21 E3 49      LD HL,buzzer_beep
1FC0  22 CD 52      LD (iovec_beep),HL
1FC3  C3 61 01      JP run_entry

; host op 0x0D: receive format params from host (cfg_flags, unit, geometry, per-head tables), program FDC and build format block; echoes each byte
host_op_disk_write:
1FC6  FE 0D         CP 0x0D
1FC8  C2 4B 20      JP NZ,host_op_ping
1FCB  06 58         LD B,0x58
1FCD  CD 9D 4E      CALL host_tx
1FD0  AF            XOR A
1FD1  32 C8 52      LD (image_present),A
1FD4  CD 3E 20      CALL host_rx_echo
1FD7  78            LD A,B
1FD8  32 1C 31      LD (cfg_flags),A
1FDB  CD 3E 20      CALL host_rx_echo
1FDE  C2 48 20      JP NZ,loc_2048
1FE1  78            LD A,B
1FE2  32 E8 52      LD (format_desc+0xB),A
1FE5  CD E7 51      CALL fdc_build_unit_sel
1FE8  32 37 31      LD (unit_sel),A
1FEB  4F            LD C,A
1FEC  3A 1C 31      LD A,(cfg_flags)
1FEF  47            LD B,A
1FF0  79            LD A,C
1FF1  E6 0F         AND 0x0F
1FF3  FE 00         CP 0x00
1FF5  20 04         JR NZ,loc_1FFB
1FF7  79            LD A,C
1FF8  E6 FC         AND 0xFC
1FFA  B0            OR B

loc_1FFB:
1FFB  32 37 31      LD (unit_sel),A
1FFE  CD 7B 04      CALL fdc_cmd_both_drives
2001  CD CB 4F      CALL build_format_block
2004  CD CC 50      CALL layout_sectors
2007  CD 3E 20      CALL host_rx_echo
200A  78            LD A,B
200B  D3 9C         OUT (0x9C),A  ; ctrl_latch
200D  32 55 31      LD (wprot_mode),A
2010  CD 3E 20      CALL host_rx_echo
2013  78            LD A,B
2014  32 4A 31      LD (err_recovery),A
2017  CD 3E 20      CALL host_rx_echo
201A  06 18         LD B,0x18
201C  21 A1 31      LD HL,hrd_hd0

loc_201F:
201F  C5            PUSH BC
2020  CD 3E 20      CALL host_rx_echo
2023  70            LD (HL),B
2024  23            INC HL
2025  C1            POP BC
2026  10 F7         DJNZ loc_201F
2028  06 B0         LD B,0xB0
202A  21 B9 31      LD HL,param_tables

loc_202D:
202D  C5            PUSH BC
202E  CD 3E 20      CALL host_rx_echo
2031  70            LD (HL),B
2032  23            INC HL
2033  C1            POP BC
2034  10 F7         DJNZ loc_202D
2036  06 00         LD B,0x00
2038  CD 9D 4E      CALL host_tx
203B  C3 2B 1E      JP loc_1E2B

; receive one byte from host and echo it back as ack (returns byte in B, NZ on error)
host_rx_echo:
203E  CD AD 4E      CALL host_rx
2041  C0            RET NZ
2042  CD 9D 4E      CALL host_tx
2045  AF            XOR A
2046  C9            RET
2047  C1            POP BC

loc_2048:
2048  C3 2B 1E      JP loc_1E2B

; host op 0x0C: ping - ack with 0x58 then 0x00
host_op_ping:
204B  FE 0C         CP 0x0C
204D  20 0D         JR NZ,host_op_start
204F  06 58         LD B,0x58
2051  CD 9D 4E      CALL host_tx
2054  06 00         LD B,0x00
2056  CD 9D 4E      CALL host_tx
2059  C3 2B 1E      JP loc_1E2B

; host op 0x09: clear op_word, ack, run abort_check gate then execute run
host_op_start:
205C  FE 09         CP 0x09
205E  20 0F         JR NZ,host_op_load_exec
2060  AF            XOR A
2061  32 34 31      LD (op_word),A
2064  06 58         LD B,0x58
2066  CD 9D 4E      CALL host_tx
2069  CD C6 1D      CALL abort_check
206C  C3 2A 21      JP loc_212A

; host op 0x0F: ack then code_loader (download+execute code image), loop dispatch
host_op_load_exec:
206F  FE 0F         CP 0x0F
2071  20 0B         JR NZ,loc_207E
2073  06 58         LD B,0x58
2075  CD 9D 4E      CALL host_tx
2078  CD A9 21      CALL code_loader
207B  C3 0B 1E      JP host_dispatch

loc_207E:
207E  FE 0E         CP 0x0E
2080  20 61         JR NZ,host_op_begin_run

; host op 0x0E: diagnostic bridge - relay bytes between host (port DC) and autoloader USART
host_op_diag_out:
2082  06 58         LD B,0x58
2084  CD 9D 4E      CALL host_tx
2087  06 00         LD B,0x00
2089  CD 9D 4E      CALL host_tx
208C  21 00 06      LD HL,0x0600
208F  CD 22 4C      CALL lcd_setpos
2092  21 9C 20      LD HL,host_ser_blob0
2095  01 DC 0D      LD BC,0x0DDC
2098  ED B3         OTIR
209A  18 0D         JR loc_20A9

host_ser_blob0:
209C  18 03 C0 04 44 05 E0 01 80 03 C1 05 EA          |....D........|

loc_20A9:
20A9  CD 53 4E      CALL al_rx_ready
20AC  20 15         JR NZ,loc_20C3
20AE  CD 4F 4E      CALL host_rx_ready
20B1  28 F6         JR Z,loc_20A9
20B3  CD AD 4E      CALL host_rx
20B6  3E DF         LD A,0xDF
20B8  A0            AND B
20B9  FE 57         CP 0x57
20BB  CA CB 20      JP Z,loc_20CB
20BE  CD 99 4E      CALL al_tx
20C1  18 E6         JR loc_20A9

loc_20C3:
20C3  CD A1 4E      CALL al_rx
20C6  CD 9D 4E      CALL host_tx
20C9  18 DE         JR loc_20A9

loc_20CB:
20CB  21 D6 20      LD HL,host_ser_blob1
20CE  01 DC 0D      LD BC,0x0DDC
20D1  ED B3         OTIR
20D3  C3 0B 1E      JP host_dispatch

host_ser_blob1:
20D6  18 03 C0 04 45 05 E0 01 80 03 C1 05 EA          |....E........|

; start a duplication/blank-check run - ack, show 'FDD', clear fmt_mode; op 0x07 sets up blank-pass ('BP')
host_op_begin_run:
20E3  F5            PUSH AF
20E4  06 58         LD B,0x58
20E6  CD 9D 4E      CALL host_tx
20E9  CD 70 06      CALL lcd_clear_line2
20EC  CD 59 4C      CALL lcd_print
20EF  1B C0 46 44 44 00  DB ESC(0xC0), "FDD", 0
20F5  AF            XOR A
20F6  32 4C 31      LD (fmt_mode),A
20F9  32 50 31      LD (edit_ndigits),A
20FC  F1            POP AF
20FD  FE 07         CP 0x07
20FF  20 23         JR NZ,loc_2124
2101  21 00 00      LD HL,0x0000
2104  22 3D 31      LD (run_count),HL
2107  7D            LD A,L
2108  32 C8 52      LD (image_present),A
210B  3E 01         LD A,0x01
210D  32 4E 31      LD (run_status),A
2110  3E 04         LD A,0x04
2112  D3 9C         OUT (0x9C),A  ; ctrl_latch
2114  CD 70 06      CALL lcd_clear_line2
2117  CD 59 4C      CALL lcd_print
211A  1B C0 42 50 00  DB ESC(0xC0), "BP", 0
211F  CD 8B 07      CALL require_motor_ready
2122  18 06         JR loc_212A

loc_2124:
2124  32 4E 31      LD (run_status),A
2127  CD 88 07      CALL dup_engine_loop

loc_212A:
212A  47            LD B,A
212B  CD 9D 4E      CALL host_tx
212E  CD 70 06      CALL lcd_clear_line2
2131  C3 0B 1E      JP host_dispatch

; read B*2 bytes from the bulk-image channel into (HL++)
bulk_read_bytes:
2134  CD 6A 21      CALL bulk_read_byte
2137  71            LD (HL),C
2138  23            INC HL
2139  CD 6A 21      CALL bulk_read_byte
213C  71            LD (HL),C
213D  23            INC HL
213E  10 F4         DJNZ bulk_read_bytes
2140  C9            RET

; compare received image geometry header (0x334F+1/+2) with stored (0x3133/0x3135); update and return NZ if changed
bulk_validate:
2141  DD 21 4F 33   LD IX,fmt_buf1+0x1
2145  3A 33 31      LD A,(cur_track)
2148  DD BE 01      CP (IX+1)
214B  20 07         JR NZ,loc_2154
214D  3A 35 31      LD A,(datarate_idx)
2150  DD BE 02      CP (IX+2)
2153  C8            RET Z

loc_2154:
2154  DD 7E 02      LD A,(IX+2)
2157  32 35 31      LD (datarate_idx),A
215A  DD 7E 01      LD A,(IX+1)
215D  32 33 31      LD (cur_track),A
2160  C9            RET

; read a little-endian 16-bit word from the bulk-image channel into DE
bulk_read_word:
2161  CD 6A 21      CALL bulk_read_byte
2164  59            LD E,C
2165  CD 6A 21      CALL bulk_read_byte
2168  51            LD D,C
2169  C9            RET

; read one byte from host bulk-image channel (0x90/0x94/0x9C handshake)
bulk_read_byte:
216A  E5            PUSH HL
216B  21 00 00      LD HL,0x0000

loc_216E:
216E  DB 94         IN A,(0x94)  ; status_in
2170  CB 77         BIT 6,A
2172  20 07         JR NZ,loc_217B
2174  2B            DEC HL
2175  7D            LD A,L
2176  B4            OR H
2177  20 F5         JR NZ,loc_216E
2179  18 0F         JR loc_218A

loc_217B:
217B  3E 0E         LD A,0x0E
217D  D3 9C         OUT (0x9C),A  ; ctrl_latch

loc_217F:
217F  DB 94         IN A,(0x94)  ; status_in
2181  CB 77         BIT 6,A
2183  28 08         JR Z,loc_218D
2185  2B            DEC HL
2186  7D            LD A,L
2187  B4            OR H
2188  20 F5         JR NZ,loc_217F

loc_218A:
218A  3D            DEC A
218B  E1            POP HL
218C  C9            RET

loc_218D:
218D  DB 90         IN A,(0x90)  ; bulk_data
218F  4F            LD C,A
2190  3E 0F         LD A,0x0F
2192  D3 9C         OUT (0x9C),A  ; ctrl_latch
2194  E1            POP HL
2195  C9            RET

; wait for 0xAA 0x55 sync word on the bulk-image channel
bulk_sync_aa55:
2196  CD 6A 21      CALL bulk_read_byte
2199  C0            RET NZ
219A  79            LD A,C
219B  FE AA         CP 0xAA
219D  20 F7         JR NZ,bulk_sync_aa55
219F  CD 6A 21      CALL bulk_read_byte
21A2  C0            RET NZ
21A3  79            LD A,C
21A4  FE 55         CP 0x55
21A6  20 EE         JR NZ,bulk_sync_aa55
21A8  C9            RET

; code loader: copy 256-byte bootstrap to 0x7800, verify image to 0x8000, JP
code_loader:
21A9  21 4A 4C      LD HL,byte_out
21AC  22 C9 52      LD (iovec_out),HL
21AF  CD 59 4C      CALL lcd_print
21B2  0C 43 6F 64 65 20 +  DB \f, "Code loading", 0
21C0  21 CE 21      LD HL,dl_code
21C3  11 00 78      LD DE,dl_code
21C6  01 00 01      LD BC,boot_init
21C9  ED B0         LDIR
21CB  C3 00 78      JP dl_code

; downloaded-code block (copied to 0x7800 by host opcode 0x0F); runs from RAM, labeled at its ROM source
dl_code:
21CE  3E 0E         LD A,0x0E
21D0  D3 9C         OUT (0x9C),A  ; ctrl_latch

loc_21D2:
21D2  06 10         LD B,0x10
21D4  16 00         LD D,0x00

loc_21D6:
21D6  CD 68 78      CALL dl_boot_entry_b
21D9  BA            CP D
21DA  20 F6         JR NZ,loc_21D2
21DC  14            INC D
21DD  10 F7         DJNZ loc_21D6
21DF  06 10         LD B,0x10
21E1  16 0F         LD D,0x0F

loc_21E3:
21E3  CD 68 78      CALL dl_boot_entry_b
21E6  BA            CP D
21E7  20 E9         JR NZ,loc_21D2
21E9  15            DEC D
21EA  10 F7         DJNZ loc_21E3
21EC  CD 5F 78      CALL dl_boot_entry_a
21EF  22 85 78      LD (dl_code+0x85),HL
21F2  CD 5F 78      CALL dl_boot_entry_a
21F5  22 81 78      LD (dl_code+0x81),HL
21F8  CD 5F 78      CALL dl_boot_entry_a
21FB  22 83 78      LD (dl_code+0x83),HL
21FE  21 00 80      LD HL,image_buf
2201  3E FE         LD A,0xFE
2203  D3 B0         OUT (0xB0),A  ; dram_bank
2205  ED 4B 85 78   LD BC,(dl_code+0x85)
2209  16 00         LD D,0x00

loc_220B:
220B  CD 68 78      CALL dl_boot_entry_b
220E  77            LD (HL),A
220F  82            ADD A,D
2210  57            LD D,A
2211  23            INC HL
2212  0B            DEC BC
2213  78            LD A,B
2214  B1            OR C
2215  20 F4         JR NZ,loc_220B
2217  CD 68 78      CALL dl_boot_entry_b
221A  BA            CP D
221B  C0            RET NZ
221C  ED 5B 81 78   LD DE,(dl_code+0x81)
2220  21 00 80      LD HL,image_buf
2223  ED 4B 85 78   LD BC,(dl_code+0x85)
2227  ED B0         LDIR
2229  2A 83 78      LD HL,(dl_code+0x83)
222C  E9            JP (HL)

; download entry A (runs at 0x785F after relocation to 0x7800)
dl_boot_entry_a:
222D  CD 68 78      CALL dl_boot_entry_b
2230  6F            LD L,A
2231  CD 68 78      CALL dl_boot_entry_b
2234  67            LD H,A
2235  C9            RET

; download entry B (runs at 0x7868 after relocation to 0x7800)
dl_boot_entry_b:
2236  DB 94         IN A,(0x94)  ; status_in
2238  CB 77         BIT 6,A
223A  20 FA         JR NZ,dl_boot_entry_b
223C  DB 90         IN A,(0x90)  ; bulk_data
223E  F5            PUSH AF
223F  3E 0F         LD A,0x0F
2241  D3 9C         OUT (0x9C),A  ; ctrl_latch

loc_2243:
2243  DB 94         IN A,(0x94)  ; status_in
2245  CB 77         BIT 6,A
2247  28 FA         JR Z,loc_2243
2249  3E 0E         LD A,0x0E
224B  D3 9C         OUT (0x9C),A  ; ctrl_latch
224D  F1            POP AF
224E  C9            RET

padding:
224F  00 00 00 00 00 00                               |......|

; clear line2 and draw the '(curr.= ' prefix for a config current-value readout
show_curr_prefix:
2255  CD 70 06      CALL lcd_clear_line2
2258  CD 59 4C      CALL lcd_print
225B  1B C0 28 63 75 72 +  DB ESC(0xC0), "(curr.= ", 0
2266  C9            RET

; CONFIG menu top level
config_menu:
2267  CD 59 4C      CALL lcd_print
226A  0C 43 6F 6E 66 69 +  DB \f, "Config. setting", 0

loc_227B:
227B  AF            XOR A
227C  CD 89 4D      CALL get_key
227F  20 FA         JR NZ,loc_227B

loc_2281:
2281  CD B4 03      CALL dram_bank_cfg
2284  CD F8 28      CALL show_media_status
2287  3E 01         LD A,0x01
2289  CD 89 4D      CALL get_key
228C  FE 01         CP 0x01
228E  28 25         JR Z,loc_22B5
2290  21 1D 31      LD HL,cfg_byte
2293  22 1A 31      LD (cfg_ptr),HL
2296  3A 1D 31      LD A,(cfg_byte)
2299  E6 03         AND 0x03
229B  32 67 31      LD (hrd_desc_tbl),A
229E  21 F4 30      LD HL,config_fdd_menu
22A1  CD 2F 52      CALL menu_run
22A4  21 1D 31      LD HL,cfg_byte
22A7  3E FC         LD A,0xFC
22A9  A6            AND (HL)
22AA  47            LD B,A
22AB  3A 67 31      LD A,(hrd_desc_tbl)
22AE  B0            OR B
22AF  77            LD (HL),A
22B0  CD F4 28      CALL save_cfg_block
22B3  18 CC         JR loc_2281

loc_22B5:
22B5  CD 59 4C      CALL lcd_print
22B8  0C 50 72 65 63 6F +  DB \f, "Precomp. setting", 0
22CA  CD 55 22      CALL show_curr_prefix
22CD  21 1D 31      LD HL,cfg_byte
22D0  CB 46         BIT 0,(HL)
22D2  20 0D         JR NZ,loc_22E1
22D4  CD 59 4C      CALL lcd_print
22D7  75 73 65 72 27 73 +  DB "user's)", 0
22DF  18 0C         JR loc_22ED

loc_22E1:
22E1  CD 59 4C      CALL lcd_print
22E4  64 65 66 61 75 6C +  DB "default)", 0

loc_22ED:
22ED  3E 01         LD A,0x01
22EF  CD 89 4D      CALL get_key
22F2  FE 02         CP 0x02
22F4  CA 6C 26      JP Z,loc_266C
22F7  CD 9E 24      CALL config_wprotect
22FA  CD 1E 23      CALL config_err_recovery
22FD  DB 98         IN A,(0x98)  ; key_scan
22FF  21 1E 31      LD HL,drv_active_cfg
2302  CB 57         BIT 2,A
2304  3E 04         LD A,0x04
2306  28 02         JR Z,loc_230A
2308  EE 01         XOR 0x01

loc_230A:
230A  77            LD (HL),A
230B  3A 4A 31      LD A,(err_recovery)
230E  32 1F 31      LD (cfg_batch),A
2311  0E 01         LD C,0x01
2313  06 03         LD B,0x03
2315  3E 01         LD A,0x01
2317  21 1D 31      LD HL,cfg_byte
231A  CD 35 27      CALL config_save
231D  C9            RET

; config menu item: toggle data-error-recovery (0x314A=1 enable / 3 disable) via ENTER/EXIT prompt
config_err_recovery:
231E  CD 69 25      CALL show_err_recovery
2321  3E 01         LD A,0x01
2323  CD 89 4D      CALL get_key
2326  FE 02         CP 0x02
2328  C0            RET NZ
2329  CD 59 4C      CALL lcd_print
232C  0C 64 69 73 61 62 +  DB \f, "disable    ...  EXITenable     ... ENTER", 0
2356  3E 01         LD A,0x01
2358  CD 89 4D      CALL get_key
235B  FE 01         CP 0x01
235D  21 4A 31      LD HL,err_recovery
2360  3E 03         LD A,0x03
2362  28 02         JR Z,loc_2366
2364  3E 01         LD A,0x01

loc_2366:
2366  77            LD (HL),A
2367  18 B5         JR config_err_recovery

; config menu item: toggle serialization (hrd_desc_tbl bit1 & cfg_byte bit1) via ENTER/EXIT prompt
config_serialization:
2369  CD A5 25      CALL show_serial_batch
236C  3E 01         LD A,0x01
236E  CD 89 4D      CALL get_key
2371  FE 02         CP 0x02
2373  C0            RET NZ
2374  CD 59 4C      CALL lcd_print
2377  0C 64 69 73 61 62 +  DB \f, "disable    ...  EXITenable     ... ENTER", 0
23A1  3E 01         LD A,0x01
23A3  CD 89 4D      CALL get_key
23A6  FE 01         CP 0x01
23A8  21 67 31      LD HL,hrd_desc_tbl
23AB  DD 21 1D 31   LD IX,cfg_byte
23AF  CB CE         SET 1,(HL)
23B1  DD CB 00 CE   SET 1,(IX+0)
23B5  28 06         JR Z,loc_23BD
23B7  CB 8E         RES 1,(HL)
23B9  DD CB 00 8E   RES 1,(IX+0)

loc_23BD:
23BD  18 AA         JR config_serialization

; config menu item: toggle copy direction (cfg_flags bit7: in->out / out->in)
config_copy_dir:
23BF  CD 2C 25      CALL show_copy_dir
23C2  3E 01         LD A,0x01
23C4  CD 89 4D      CALL get_key
23C7  FE 02         CP 0x02
23C9  C0            RET NZ
23CA  CD 59 4C      CALL lcd_print
23CD  0C 69 6E 20 2D 3E +  DB \f, "in -> out  ...  EXITout -> in  ... ENTER", 0
23F7  3E 01         LD A,0x01
23F9  CD 89 4D      CALL get_key
23FC  FE 01         CP 0x01
23FE  21 1C 31      LD HL,cfg_flags
2401  CB FE         SET 7,(HL)
2403  28 02         JR Z,loc_2407
2405  CB BE         RES 7,(HL)

loc_2407:
2407  18 B6         JR config_copy_dir

; config menu item: edit maximal cylinder - edit_num_field, clamp to 0x55, store in cfg_flags preserving bit7
config_max_cyl:
2409  CD 53 24      CALL show_max_cyl
240C  3E 01         LD A,0x01
240E  CD 89 4D      CALL get_key
2411  FE 02         CP 0x02
2413  C0            RET NZ
2414  CD 29 19      CALL clear_image_present
2417  CD 59 4C      CALL lcd_print
241A  0C 53 65 74 20 6D +  DB \f, "Set maximal cylinder", 0
2430  3A 1C 31      LD A,(cfg_flags)
2433  E6 80         AND 0x80
2435  F5            PUSH AF
2436  AF            XOR A
2437  32 43 31      LD (edit_value),A
243A  3E 12         LD A,0x12
243C  06 02         LD B,0x02
243E  CD C3 04      CALL edit_num_field
2441  3A 43 31      LD A,(edit_value)
2444  FE 56         CP 0x56
2446  FA 4B 24      JP M,loc_244B
2449  3E 55         LD A,0x55

loc_244B:
244B  47            LD B,A
244C  F1            POP AF
244D  B0            OR B
244E  32 1C 31      LD (cfg_flags),A
2451  18 B6         JR config_max_cyl

; render 'Maximal cylinder' header + current value from 0x4AFC/cfg_flags
show_max_cyl:
2453  CD 59 4C      CALL lcd_print
2456  0C 4D 61 78 69 6D +  DB \f, "Maximal cylinder ", 0
2469  06 02         LD B,0x02
246B  2A FC 4A      LD HL,(drive_blk_a+0x11)
246E  2D            DEC L
246F  26 00         LD H,0x00
2471  5C            LD E,H
2472  54            LD D,H
2473  3E 12         LD A,0x12
2475  0E 20         LD C,0x20
2477  CD FC 05      CALL num_to_lcd
247A  CD 55 22      CALL show_curr_prefix
247D  06 02         LD B,0x02
247F  2A 1C 31      LD HL,(cfg_flags)
2482  CB BD         RES 7,L
2484  26 00         LD H,0x00
2486  5C            LD E,H
2487  54            LD D,H
2488  7D            LD A,L
2489  B7            OR A
248A  20 05         JR NZ,loc_2491
248C  3A FC 4A      LD A,(drive_blk_a+0x11)
248F  3D            DEC A
2490  6F            LD L,A

loc_2491:
2491  3E 89         LD A,0x89
2493  0E 30         LD C,0x30
2495  CD FA 05      CALL num_to_lcd_alt
2498  CD 59 4C      CALL lcd_print
249B  29 00         DB ")", 0
249D  C9            RET

; config menu item: toggle write-protect recognition (ctrl_latch bit0 / 0x3155)
config_wprotect:
249E  CD EC 24      CALL show_wprotect
24A1  3E 01         LD A,0x01
24A3  CD 89 4D      CALL get_key
24A6  FE 02         CP 0x02
24A8  C0            RET NZ
24A9  CD 59 4C      CALL lcd_print
24AC  0C 75 6E 72 65 63 +  DB \f, "unrecognize ..  EXITrecognize   .. ENTER", 0
24D6  3E 01         LD A,0x01
24D8  CD 89 4D      CALL get_key
24DB  FE 01         CP 0x01
24DD  3E 05         LD A,0x05
24DF  20 02         JR NZ,loc_24E3
24E1  EE 01         XOR 0x01

loc_24E3:
24E3  D3 9C         OUT (0x9C),A  ; ctrl_latch
24E5  32 55 31      LD (wprot_mode),A
24E8  18 B4         JR config_wprotect
24EA  F1            POP AF
24EB  C9            RET

; render 'Write protect (curr.= recognize/unrecognize)' from key_scan bit2
show_wprotect:
24EC  CD 59 4C      CALL lcd_print
24EF  0C 57 72 69 74 65 +  DB \f, "Write protect", \r, \n, 0
2500  CD 55 22      CALL show_curr_prefix
2503  DB 98         IN A,(0x98)  ; key_scan
2505  CB 57         BIT 2,A
2507  F5            PUSH AF
2508  28 12         JR Z,loc_251C
250A  CD 59 4C      CALL lcd_print
250D  75 6E 72 65 63 6F +  DB "unrecognize)", 0
251A  18 0E         JR loc_252A

loc_251C:
251C  CD 59 4C      CALL lcd_print
251F  72 65 63 6F 67 6E +  DB "recognize)", 0

loc_252A:
252A  F1            POP AF
252B  C9            RET

; render 'Copy direction (curr.= in->out/out->in)' from cfg_flags bit7
show_copy_dir:
252C  CD 59 4C      CALL lcd_print
252F  0C 43 6F 70 79 20 +  DB \f, "Copy direction", \r, \n, 0
2541  CD 55 22      CALL show_curr_prefix
2544  21 1C 31      LD HL,cfg_flags
2547  CB 7E         BIT 7,(HL)
2549  20 0F         JR NZ,loc_255A
254B  CD 59 4C      CALL lcd_print
254E  69 6E 20 2D 3E 20 +  DB "in -> out)", 0
2559  C9            RET

loc_255A:
255A  CD 59 4C      CALL lcd_print
255D  6F 75 74 20 2D 3E +  DB "out -> in)", 0
2568  C9            RET

; render 'Data error recovery (curr.= enable/disable)' from 0x314A
show_err_recovery:
2569  CD 59 4C      CALL lcd_print
256C  0C 44 61 74 61 20 +  DB \f, "Data error recovery", 0
2581  CD 55 22      CALL show_curr_prefix
2584  21 4A 31      LD HL,err_recovery
2587  3E 01         LD A,0x01
2589  BE            CP (HL)

loc_258A:
258A  28 0C         JR Z,loc_2598
258C  CD 59 4C      CALL lcd_print
258F  65 6E 61 62 6C 65 +  DB "enable)", 0
2597  C9            RET

loc_2598:
2598  CD 59 4C      CALL lcd_print
259B  64 69 73 61 62 6C +  DB "disable)", 0
25A4  C9            RET

; render 'Serialization (curr.= enable/disable)' from hrd_desc_tbl bit1
show_serial_batch:
25A5  CD 59 4C      CALL lcd_print
25A8  0C 53 65 72 69 61 +  DB \f, "Serialization", 0
25B7  CD 55 22      CALL show_curr_prefix
25BA  21 67 31      LD HL,hrd_desc_tbl
25BD  CB 4E         BIT 1,(HL)
25BF  18 C9         JR loc_258A

; draw the 'Batch processing' menu header
show_batch:
25C1  CD 59 4C      CALL lcd_print
25C4  0C 42 61 74 63 68 +  DB \f, "Batch processing", 0
25D6  C9            RET

; batch-processing entry: gate on autoloader-present, else show 'not available'
start_batch:
25D7  CD A8 11      CALL al_present_gate
25DA  20 04         JR NZ,loc_25E0
25DC  CD 56 19      CALL show_not_available
25DF  C9            RET

loc_25E0:
25E0  21 02 26      LD HL,loc_2602
25E3  C3 2F 52      JP menu_run

loc_25E6:
25E6  3E 04         LD A,0x04
25E8  D3 9C         OUT (0x9C),A  ; ctrl_latch
25EA  CD 4F 07      CALL set_drive_cfg
25ED  CD 70 06      CALL lcd_clear_line2
25F0  21 00 00      LD HL,0x0000
25F3  3E 07         LD A,0x07
25F5  32 34 31      LD (op_word),A
25F8  22 3D 31      LD (run_count),HL
25FB  7D            LD A,L
25FC  32 C8 52      LD (image_present),A
25FF  C3 8B 07      JP require_motor_ready

loc_2602:
2602  14            INC D
2603  26 26         LD H,0x26
2605  26 37         LD H,0x37
2607  26 48         LD H,0x48
2609  26 00         LD H,0x00
260B  00            NOP
260C  58            LD E,B
260D  26 60         LD H,0x60
260F  26 64         LD H,0x64
2611  26 68         LD H,0x68
2613  26 CD         LD H,0xCD
2615  70            LD (HL),B
2616  06 CD         LD B,0xCD
2618  59            LD E,C
2619  4C            LD C,H
261A  1B            DEC DE
261B  C0            RET NZ
261C  52            LD D,D
261D  44            LD B,H
261E  20 2B         JR NZ,loc_264B
2620  20 46         JR NZ,loc_2668
2622  57            LD D,A
2623  56            LD D,(HL)
2624  00            NOP
2625  C9            RET
2626  CD 70 06      CALL lcd_clear_line2
2629  CD 59 4C      CALL lcd_print
262C  1B C0 52 44 20 2B +  DB ESC(0xC0), "RD + WV", 0
2636  C9            RET
2637  CD 70 06      CALL lcd_clear_line2
263A  CD 59 4C      CALL lcd_print
263D  1B C0 52 44 20 2B +  DB ESC(0xC0), "RD + FW", 0
2647  C9            RET
2648  CD 70 06      CALL lcd_clear_line2

loc_264B:
264B  CD 59 4C      CALL lcd_print
264E  1B C0 52 44 20 2B +  DB ESC(0xC0), "RD + W", 0
2657  C9            RET
2658  3E 01         LD A,0x01

loc_265A:
265A  32 4F 31      LD (rd_submode),A
265D  C3 E6 25      JP loc_25E6
2660  3E 02         LD A,0x02
2662  18 F6         JR loc_265A
2664  3E 05         LD A,0x05
2666  18 F2         JR loc_265A

loc_2668:
2668  3E 06         LD A,0x06
266A  18 EE         JR loc_265A

loc_266C:
266C  21 5E 31      LD HL,read_addr+0x4
266F  36 00         LD (HL),0x00
2671  3A 1D 31      LD A,(cfg_byte)
2674  CD 25 27      CALL drive_block_pos
2677  79            LD A,C
2678  32 49 31      LD (op_flag_49),A
267B  06 18         LD B,0x18
267D  21 A1 31      LD HL,hrd_hd0
2680  3E 00         LD A,0x00
2682  CD 35 27      CALL config_save
2685  CD 59 4C      CALL lcd_print
2688  0C 75 73 65 72 20 +  DB \f, "user     ...    EXIT", \r, \n, "default  ...   ENTER", 0
26B4  3E 01         LD A,0x01
26B6  CD 89 4D      CALL get_key
26B9  FE 02         CP 0x02
26BB  21 5E 31      LD HL,read_addr+0x4
26BE  28 24         JR Z,loc_26E4
26C0  FE 08         CP 0x08
26C2  20 0E         JR NZ,loc_26D2
26C4  E5            PUSH HL
26C5  21 29 4B      LD HL,fmt_geom_recs
26C8  06 60         LD B,0x60
26CA  3E 01         LD A,0x01
26CC  0E 04         LD C,0x04
26CE  CD 35 27      CALL config_save
26D1  E1            POP HL

loc_26D2:
26D2  CB 46         BIT 0,(HL)
26D4  21 1C 31      LD HL,cfg_flags
26D7  20 03         JR NZ,loc_26DC
26D9  21 1D 31      LD HL,cfg_byte

loc_26DC:
26DC  CB C6         SET 0,(HL)
26DE  CD F4 28      CALL save_cfg_block
26E1  C3 B5 22      JP loc_22B5

loc_26E4:
26E4  CB 46         BIT 0,(HL)
26E6  21 1C 31      LD HL,cfg_flags
26E9  20 03         JR NZ,loc_26EE
26EB  21 1D 31      LD HL,cfg_byte

loc_26EE:
26EE  CB 86         RES 0,(HL)
26F0  CD F4 28      CALL save_cfg_block
26F3  CD 6A 27      CALL hrd_head_edit
26F6  3A 49 31      LD A,(op_flag_49)
26F9  4F            LD C,A
26FA  21 A1 31      LD HL,hrd_hd0
26FD  06 18         LD B,0x18
26FF  3E 01         LD A,0x01
2701  CD 35 27      CALL config_save
2704  C3 B5 22      JP loc_22B5

; compute pointer to a drive's 0x18-byte record in the table at 0x4B29 (index from unit-select bits)
drive_block_ptr:
2707  CD 16 27      CALL drive_index_bits
270A  3E 18         LD A,0x18
270C  0E 00         LD C,0x00
270E  CD 05 4F      CALL mul16
2711  11 29 4B      LD DE,fmt_geom_recs
2714  19            ADD HL,DE
2715  C9            RET

; map unit-select byte bits7,3 to a 0..3 drive index in E
drive_index_bits:
2716  16 00         LD D,0x00
2718  5A            LD E,D
2719  CB 7F         BIT 7,A
271B  28 02         JR Z,loc_271F
271D  CB C3         SET 0,E

loc_271F:
271F  CB 5F         BIT 3,A
2721  C0            RET NZ
2722  CB CB         SET 1,E
2724  C9            RET

; compute a drive's record offset (0x18*index + 4), returns low byte in C
drive_block_pos:
2725  CD 16 27      CALL drive_index_bits
2728  3E 18         LD A,0x18
272A  0E 00         LD C,0x00
272C  CD 05 4F      CALL mul16
272F  11 04 00      LD DE,0x0004
2732  19            ADD HL,DE
2733  4D            LD C,L
2734  C9            RET

; persist config block to serial EEPROM (bit-banged)
config_save:
2735  F5            PUSH AF
2736  C5            PUSH BC
2737  B7            OR A
2738  59            LD E,C
2739  28 10         JR Z,loc_274B

loc_273B:
273B  CD CB 2A      CALL eeprom_write
273E  7E            LD A,(HL)
273F  CD D4 2A      CALL eeprom_send_byte
2742  CD 3E 2B      CALL eeprom_io
2745  23            INC HL
2746  1C            INC E
2747  10 F2         DJNZ loc_273B
2749  18 18         JR loc_2763

loc_274B:
274B  CD 55 2B      CALL eeprom_read
274E  05            DEC B

loc_274F:
274F  CD 66 2B      CALL i2c_read_byte
2752  CD 4D 2B      CALL i2c_ack
2755  77            LD (HL),A
2756  23            INC HL
2757  10 F6         DJNZ loc_274F
2759  CD 66 2B      CALL i2c_read_byte
275C  CD EF 2A      CALL eeprom_clk_idle
275F  CD 3E 2B      CALL eeprom_io
2762  77            LD (HL),A

loc_2763:
2763  C1            POP BC
2764  F1            POP AF
2765  C9            RET

; beep via the iovec_beep vector (default buzzer_beep); beep count encodes the alert/error code
beep:
2766  2A CD 52      LD HL,(iovec_beep)
2769  E9            JP (HL)

; BC-preserving wrapper to edit the two-head cyl-0 parameter table
hrd_head_edit:
276A  C5            PUSH BC
276B  CD 00 28      CALL hrd_edit_head_pair
276E  C1            POP BC
276F  C9            RET

; render head-1 row of the head parameter table (sets prefix '1', buffer 0x31AF)
hrd_row_head1:
2770  E5            PUSH HL
2771  C5            PUSH BC
2772  3E 31         LD A,0x31
2774  21 AF 31      LD HL,hrd_test_idx+0xA
2777  32 92 27      LD (loc_2786+0xC),A
277A  18 0A         JR loc_2786

; render head-0 row: print 'H C-0' grid, format 5 cyl-0 sector values and N/L/H flag cells
hrd_row_head0:
277C  E5            PUSH HL
277D  C5            PUSH BC
277E  3E 30         LD A,0x30
2780  32 92 27      LD (loc_2786+0xC),A
2783  21 A3 31      LD HL,hrd_hd1

loc_2786:
2786  E5            PUSH HL
2787  CD 59 4C      CALL lcd_print
278A  0C 48 20 43 2D 30 +  DB \f, "H C-0", \r, \n, "0 v-", 0
2797  0E 86         LD C,0x86
2799  E1            POP HL
279A  E5            PUSH HL
279B  06 05         LD B,0x05

loc_279D:
279D  E5            PUSH HL
279E  C5            PUSH BC
279F  7E            LD A,(HL)
27A0  CD E7 27      CALL hrd_fmt_num
27A3  C1            POP BC
27A4  79            LD A,C
27A5  32 FA 27      LD (lcd_val_tmpl+0x1),A
27A8  CD F5 27      CALL hrd_emit_num
27AB  0C            INC C
27AC  0C            INC C
27AD  0C            INC C
27AE  E1            POP HL
27AF  23            INC HL
27B0  23            INC HL
27B1  10 EA         DJNZ loc_279D
27B3  E1            POP HL
27B4  2B            DEC HL
27B5  AF            XOR A
27B6  32 FC 27      LD (lcd_val_tmpl+0x3),A
27B9  0E C4         LD C,0xC4
27BB  06 06         LD B,0x06

loc_27BD:
27BD  E5            PUSH HL
27BE  C5            PUSH BC
27BF  7E            LD A,(HL)
27C0  B7            OR A
27C1  20 04         JR NZ,loc_27C7
27C3  3E 4E         LD A,0x4E
27C5  18 0A         JR loc_27D1

loc_27C7:
27C7  FE 01         CP 0x01
27C9  20 04         JR NZ,loc_27CF
27CB  3E 4C         LD A,0x4C
27CD  18 02         JR loc_27D1

loc_27CF:
27CF  3E 48         LD A,0x48

loc_27D1:
27D1  32 FB 27      LD (lcd_val_tmpl+0x2),A
27D4  79            LD A,C
27D5  32 FA 27      LD (lcd_val_tmpl+0x1),A
27D8  CD F5 27      CALL hrd_emit_num
27DB  C1            POP BC
27DC  0C            INC C
27DD  0C            INC C
27DE  0C            INC C
27DF  E1            POP HL
27E0  23            INC HL
27E1  23            INC HL
27E2  10 D9         DJNZ loc_27BD
27E4  C1            POP BC
27E5  E1            POP HL
27E6  C9            RET

; convert a byte to decimal (bin2dec_clear) and patch the digits into the head-table print buffer
hrd_fmt_num:
27E7  6F            LD L,A
27E8  26 00         LD H,0x00
27EA  5C            LD E,H
27EB  CD B2 4E      CALL bin2dec_clear
27EE  2A 37 4F      LD HL,(lcd_dec_tmpl+0x8)
27F1  22 FB 27      LD (lcd_val_tmpl+0x2),HL
27F4  C9            RET

; print a formatted head-table number cell (BC-preserving lcd_print of patched inline bytes)
hrd_emit_num:
27F5  C5            PUSH BC
27F6  CD 59 4C      CALL lcd_print

lcd_val_tmpl:
27F9  1B 00 00 00 00  DB ESC(0x00), \x00, \x00, \x00
27FE  C1            POP BC
27FF  C9            RET

; render both head rows (0 and 1) of the head parameter table with framing escapes
hrd_edit_head_pair:
2800  CD 59 4C      CALL lcd_print
2803  1B 0D 00      DB ESC(0x0D), 0
2806  21 A3 31      LD HL,hrd_hd1
2809  3E 00         LD A,0x00
280B  CD 1D 28      CALL hrd_edit_head_row
280E  21 AF 31      LD HL,hrd_test_idx+0xA
2811  3E 01         LD A,0x01
2813  CD 1D 28      CALL hrd_edit_head_row
2816  CD 59 4C      CALL lcd_print
2819  1B 0C 00      DB ESC(0x0C), 0
281C  C9            RET

; render one head row (0 or 1) computing per-column LCD cursor positions
hrd_edit_head_row:
281D  06 00         LD B,0x00
281F  0E 87         LD C,0x87

loc_2821:
2821  F5            PUSH AF
2822  B7            OR A
2823  20 05         JR NZ,loc_282A
2825  CD 7C 27      CALL hrd_row_head0
2828  18 03         JR loc_282D

loc_282A:
282A  CD 70 27      CALL hrd_row_head1

loc_282D:
282D  E5            PUSH HL
282E  C5            PUSH BC
282F  78            LD A,B
2830  07            RLCA
2831  5F            LD E,A
2832  80            ADD A,B
2833  81            ADD A,C
2834  16 00         LD D,0x00
2836  19            ADD HL,DE
2837  47            LD B,A
2838  AF            XOR A
2839  32 FB 27      LD (lcd_val_tmpl+0x2),A
283C  32 FC 27      LD (lcd_val_tmpl+0x3),A
283F  78            LD A,B
2840  32 FA 27      LD (lcd_val_tmpl+0x1),A
2843  CD F5 27      CALL hrd_emit_num
2846  3E 01         LD A,0x01
2848  CD 89 4D      CALL get_key
284B  FE 08         CP 0x08
284D  20 09         JR NZ,loc_2858
284F  34            INC (HL)
2850  7E            LD A,(HL)
2851  D6 51         SUB 0x51
2853  38 1F         JR C,loc_2874
2855  77            LD (HL),A
2856  18 1C         JR loc_2874

loc_2858:
2858  FE 04         CP 0x04
285A  20 0B         JR NZ,loc_2867
285C  35            DEC (HL)
285D  7E            LD A,(HL)
285E  FE FF         CP 0xFF
2860  20 12         JR NZ,loc_2874
2862  3E 50         LD A,0x50
2864  77            LD (HL),A
2865  18 0D         JR loc_2874

loc_2867:
2867  FE 01         CP 0x01
2869  20 0E         JR NZ,loc_2879
286B  C1            POP BC
286C  04            INC B
286D  78            LD A,B
286E  D6 05         SUB 0x05
2870  20 01         JR NZ,loc_2873
2872  47            LD B,A

loc_2873:
2873  C5            PUSH BC

loc_2874:
2874  C1            POP BC
2875  E1            POP HL
2876  F1            POP AF
2877  18 A8         JR loc_2821

loc_2879:
2879  C1            POP BC
287A  E1            POP HL
287B  F1            POP AF
287C  B7            OR A
287D  20 05         JR NZ,loc_2884
287F  21 A2 31      LD HL,hrd_hd0+0x1
2882  18 03         JR loc_2887

loc_2884:
2884  21 AE 31      LD HL,hrd_test_idx+0x9

loc_2887:
2887  0E C4         LD C,0xC4
2889  06 00         LD B,0x00

loc_288B:
288B  F5            PUSH AF
288C  B7            OR A
288D  20 05         JR NZ,loc_2894
288F  CD 7C 27      CALL hrd_row_head0
2892  18 03         JR loc_2897

loc_2894:
2894  CD 70 27      CALL hrd_row_head1

loc_2897:
2897  E5            PUSH HL
2898  C5            PUSH BC
2899  78            LD A,B
289A  07            RLCA
289B  5F            LD E,A
289C  80            ADD A,B
289D  81            ADD A,C
289E  16 00         LD D,0x00
28A0  19            ADD HL,DE
28A1  47            LD B,A
28A2  AF            XOR A
28A3  32 FB 27      LD (lcd_val_tmpl+0x2),A
28A6  32 FC 27      LD (lcd_val_tmpl+0x3),A
28A9  78            LD A,B
28AA  32 FA 27      LD (lcd_val_tmpl+0x1),A
28AD  CD F5 27      CALL hrd_emit_num
28B0  3E 01         LD A,0x01
28B2  CD 89 4D      CALL get_key
28B5  FE 08         CP 0x08
28B7  20 09         JR NZ,loc_28C2
28B9  34            INC (HL)
28BA  7E            LD A,(HL)
28BB  D6 03         SUB 0x03
28BD  20 1F         JR NZ,loc_28DE
28BF  77            LD (HL),A
28C0  18 1C         JR loc_28DE

loc_28C2:
28C2  FE 04         CP 0x04
28C4  20 0B         JR NZ,loc_28D1
28C6  35            DEC (HL)
28C7  7E            LD A,(HL)
28C8  FE FF         CP 0xFF
28CA  20 12         JR NZ,loc_28DE
28CC  3E 02         LD A,0x02
28CE  77            LD (HL),A
28CF  18 0D         JR loc_28DE

loc_28D1:
28D1  FE 01         CP 0x01
28D3  20 0E         JR NZ,loc_28E3
28D5  C1            POP BC
28D6  04            INC B
28D7  78            LD A,B
28D8  D6 06         SUB 0x06
28DA  20 01         JR NZ,loc_28DD
28DC  47            LD B,A

loc_28DD:
28DD  C5            PUSH BC

loc_28DE:
28DE  C1            POP BC
28DF  E1            POP HL
28E0  F1            POP AF
28E1  18 A8         JR loc_288B

loc_28E3:
28E3  C1            POP BC
28E4  E1            POP HL
28E5  F1            POP AF
28E6  C9            RET
28E7  3E 00         LD A,0x00

loc_28E9:
28E9  21 1C 31      LD HL,cfg_flags
28EC  0E 00         LD C,0x00
28EE  06 02         LD B,0x02
28F0  CD 35 27      CALL config_save
28F3  C9            RET

; persist the 2-byte cfg_flags block to serial EEPROM (config_save write mode)
save_cfg_block:
28F4  3E 01         LD A,0x01
28F6  18 F1         JR loc_28E9

; render media summary from cfg_byte: size, density, S/N and HS/NS/DS; self-patches LCD cursor
show_media_status:
28F8  3A 1D 31      LD A,(cfg_byte)
28FB  4F            LD C,A
28FC  3E 8C         LD A,0x8C
28FE  32 4E 29      LD (show_size_density+0x8),A
2901  32 5B 29      LD (loc_2957+0x4),A
2904  3E CA         LD A,0xCA
2906  32 69 29      LD (loc_2961+0x8),A
2909  32 77 29      LD (loc_2973+0x4),A
290C  32 85 29      LD (loc_297D+0x8),A
290F  CD 59 4C      CALL lcd_print
2912  0C 00         DB \f, 0
2914  CD 46 29      CALL show_size_density
2917  CB 61         BIT 4,C
2919  28 08         JR Z,loc_2923
291B  CD 59 4C      CALL lcd_print
291E  53 20 00      DB "S ", 0
2921  18 06         JR loc_2929

loc_2923:
2923  CD 59 4C      CALL lcd_print
2926  4E 20 00      DB "N ", 0

loc_2929:
2929  CB 51         BIT 2,C
292B  20 12         JR NZ,loc_293F
292D  CB 69         BIT 5,C
292F  28 07         JR Z,loc_2938
2931  CD 59 4C      CALL lcd_print
2934  48 53 00      DB "HS", 0
2937  C9            RET

loc_2938:
2938  CD 59 4C      CALL lcd_print
293B  4E 53 00      DB "NS", 0
293E  C9            RET

loc_293F:
293F  CD 59 4C      CALL lcd_print
2942  44 53 00      DB "DS", 0
2945  C9            RET

; print size+density portion of media summary (5.25"/3.5", HD/DD/QD) from cfg_byte bits3,7,6
show_size_density:
2946  CB 59         BIT 3,C
2948  28 0D         JR Z,loc_2957
294A  CD 59 4C      CALL lcd_print
294D  1B 00 35 2E 32 35 +  DB ESC(0x00), "5.25\"", 0
2955  18 0A         JR loc_2961

loc_2957:
2957  CD 59 4C      CALL lcd_print
295A  1B 00 33 2E 35 22 +  DB ESC(0x00), "3.5\"", 0

loc_2961:
2961  CB 79         BIT 7,C
2963  28 0A         JR Z,loc_296F
2965  CD 59 4C      CALL lcd_print
2968  1B 80 48 44 20 00  DB ESC(0x80), "HD ", 0
296E  C9            RET

loc_296F:
296F  CB 71         BIT 6,C
2971  20 0A         JR NZ,loc_297D

loc_2973:
2973  CD 59 4C      CALL lcd_print
2976  1B 80 44 44 20 00  DB ESC(0x80), "DD ", 0
297C  C9            RET

loc_297D:
297D  CB 59         BIT 3,C
297F  28 F2         JR Z,loc_2973
2981  CD 59 4C      CALL lcd_print
2984  1B 80 51 44 20 00  DB ESC(0x80), "QD ", 0
298A  C9            RET

; draw 'Form factor 3.5"' menu header
show_ff_35:
298B  CD 59 4C      CALL lcd_print
298E  0C 46 6F 72 6D 20 +  DB \f, "Form factor 3.5\"", 0
29A0  C9            RET

; draw 'Form factor 5.25"' menu header
show_ff_525:
29A1  CD 59 4C      CALL lcd_print
29A4  0C 46 6F 72 6D 20 +  DB \f, "Form factor 5.25\"", 0
29B7  C9            RET

; draw 'Double density' menu header
show_density_dd:
29B8  CD 59 4C      CALL lcd_print
29BB  0C 44 6F 75 62 6C +  DB \f, "Double density", 0
29CB  C9            RET

; draw 'High density' menu header
show_density_hd:
29CC  CD 59 4C      CALL lcd_print
29CF  0C 48 69 67 68 20 +  DB \f, "High density", 0
29DD  C9            RET

; draw 'Simultaneous mode' menu header
show_mode_simul:
29DE  CD 59 4C      CALL lcd_print
29E1  0C 53 69 6D 75 6C +  DB \f, "Simultaneous mode", 0
29F4  C9            RET

; draw 'Normal mode' menu header
show_mode_normal:
29F5  CD 59 4C      CALL lcd_print
29F8  0C 4E 6F 72 6D 61 +  DB \f, "Normal mode", 0
2A05  C9            RET

; draw 'High spindle speed' menu header
show_spindle_high:
2A06  CD 59 4C      CALL lcd_print
2A09  0C 48 69 67 68 20 +  DB \f, "High spindle speed", 0
2A1D  C9            RET

; draw 'Normal spindle speed' menu header
show_spindle_normal:
2A1E  CD 59 4C      CALL lcd_print
2A21  0C 4E 6F 72 6D 61 +  DB \f, "Normal spindle speed", 0
2A37  C9            RET

; draw 'Double spindle speed' menu header
show_spindle_double:
2A38  CD 59 4C      CALL lcd_print
2A3B  0C 44 6F 75 62 6C +  DB \f, "Double spindle speed", 0
2A51  C9            RET
2A52  CD 59 4C      CALL lcd_print
2A55  0C 4E 6F 20 46 44 +  DB \f, "No FDD", 0
2A5D  C9            RET

; set config form factor to 3.5" (cfg_ptr: RES bit3, SET bit6, clear bit1)
set_ff_35:
2A5E  2A 1A 31      LD HL,(cfg_ptr)
2A61  CB 9E         RES 3,(HL)
2A63  CB F6         SET 6,(HL)
2A65  18 07         JR loc_2A6E

; media-config toggle: select 5.25" form-factor (cfg flags SET3/RES6/RES1), then refresh LCD
set_ff_525:
2A67  2A 1A 31      LD HL,(cfg_ptr)
2A6A  CB DE         SET 3,(HL)
2A6C  CB B6         RES 6,(HL)

loc_2A6E:
2A6E  CB 8E         RES 1,(HL)
2A70  18 44         JR loc_2AB6
2A72  C9            RET

; media-config toggle: select DD/double density (cfg flags RES7), then refresh LCD
set_density_dd:
2A73  2A 1A 31      LD HL,(cfg_ptr)
2A76  CB BE         RES 7,(HL)
2A78  18 3C         JR loc_2AB6
2A7A  C9            RET

; media-config toggle: select HD/high density (cfg flags SET7/SET6), then refresh LCD
set_density_hd:
2A7B  2A 1A 31      LD HL,(cfg_ptr)
2A7E  CB FE         SET 7,(HL)
2A80  CB F6         SET 6,(HL)
2A82  18 32         JR loc_2AB6
2A84  C9            RET

; media-config toggle: enable simultaneous copy mode (cfg flags SET4), refresh LCD
set_mode_simul:
2A85  2A 1A 31      LD HL,(cfg_ptr)
2A88  CB E6         SET 4,(HL)
2A8A  18 2A         JR loc_2AB6
2A8C  C9            RET

; media-config toggle: select normal copy mode (cfg flags RES4), refresh LCD
set_mode_normal:
2A8D  2A 1A 31      LD HL,(cfg_ptr)
2A90  CB A6         RES 4,(HL)
2A92  18 22         JR loc_2AB6
2A94  C9            RET

; media-config toggle: high spindle speed (cfg flags RES2/SET5), refresh LCD
set_spindle_high:
2A95  2A 1A 31      LD HL,(cfg_ptr)
2A98  CB 96         RES 2,(HL)
2A9A  CB EE         SET 5,(HL)
2A9C  18 18         JR loc_2AB6
2A9E  C9            RET

; media-config toggle: normal spindle speed (cfg flags RES2/RES5), refresh LCD
set_spindle_normal:
2A9F  2A 1A 31      LD HL,(cfg_ptr)
2AA2  CB 96         RES 2,(HL)
2AA4  CB AE         RES 5,(HL)
2AA6  18 0E         JR loc_2AB6

; media-config toggle: double spindle speed (cfg flags SET2/RES5), refresh LCD
set_spindle_double:
2AA8  2A 1A 31      LD HL,(cfg_ptr)
2AAB  CB D6         SET 2,(HL)
2AAD  CB AE         RES 5,(HL)
2AAF  18 05         JR loc_2AB6
2AB1  2A 1A 31      LD HL,(cfg_ptr)
2AB4  CB CE         SET 1,(HL)

loc_2AB6:
2AB6  CD 59 4C      CALL lcd_print
2AB9  1B C5 73 65 6C 65 +  DB ESC(0xC5), "selected", 0
2AC4  21 00 00      LD HL,0x0000
2AC7  CD 22 4C      CALL lcd_setpos
2ACA  C9            RET

; bit-bang serial EEPROM: I2C start, control 0xA0 (write), then clock data byte E out MSB-first
eeprom_write:
2ACB  CD 39 2B      CALL i2c_start
2ACE  3E A0         LD A,0xA0
2AD0  CD D4 2A      CALL eeprom_send_byte
2AD3  7B            LD A,E

; bit-bang one byte to the serial config EEPROM
eeprom_send_byte:
2AD4  C5            PUSH BC
2AD5  06 08         LD B,0x08

loc_2AD7:
2AD7  CD 09 2B      CALL i2c_scl_lo
2ADA  17            RLA
2ADB  38 05         JR C,loc_2AE2
2ADD  CD 2B 2B      CALL i2c_sda_lo
2AE0  18 03         JR loc_2AE5

loc_2AE2:
2AE2  CD 1D 2B      CALL i2c_sda_hi

loc_2AE5:
2AE5  CD F5 2A      CALL eeprom_clk_high
2AE8  10 ED         DJNZ loc_2AD7
2AEA  CD EF 2A      CALL eeprom_clk_idle
2AED  C1            POP BC
2AEE  C9            RET

; return bit-banged I2C bus to idle: SCL low, SDA released high, then pulse SCL high w/ settle
eeprom_clk_idle:
2AEF  CD 09 2B      CALL i2c_scl_lo
2AF2  CD 1D 2B      CALL i2c_sda_hi

; drive I2C SCL high on panel latch (bit5 of 0x4A58/port F0) with a short settle delay
eeprom_clk_high:
2AF5  F5            PUSH AF
2AF6  E5            PUSH HL
2AF7  21 58 4A      LD HL,panel_shadow
2AFA  7E            LD A,(HL)
2AFB  F6 20         OR 0x20
2AFD  77            LD (HL),A
2AFE  D3 F0         OUT (0xF0),A  ; panel
2B00  21 0A 00      LD HL,0x000A
2B03  CD 22 4C      CALL lcd_setpos
2B06  E1            POP HL
2B07  F1            POP AF
2B08  C9            RET

; drive I2C SCL low (clear bit5 of panel latch 0x4A58, OUT port F0)
i2c_scl_lo:
2B09  F5            PUSH AF
2B0A  E5            PUSH HL
2B0B  21 58 4A      LD HL,panel_shadow
2B0E  7E            LD A,(HL)
2B0F  E6 DF         AND 0xDF
2B11  77            LD (HL),A
2B12  D3 F0         OUT (0xF0),A  ; panel
2B14  21 0A 00      LD HL,0x000A
2B17  CD 22 4C      CALL lcd_setpos
2B1A  E1            POP HL
2B1B  F1            POP AF
2B1C  C9            RET

; release I2C SDA high (set bit4 of panel latch 0x4A58, OUT port F0)
i2c_sda_hi:
2B1D  F5            PUSH AF
2B1E  E5            PUSH HL
2B1F  21 58 4A      LD HL,panel_shadow
2B22  7E            LD A,(HL)
2B23  F6 10         OR 0x10
2B25  77            LD (HL),A
2B26  D3 F0         OUT (0xF0),A  ; panel
2B28  E1            POP HL
2B29  F1            POP AF
2B2A  C9            RET

; pull I2C SDA low (clear bit4 of panel latch 0x4A58, OUT port F0)
i2c_sda_lo:
2B2B  F5            PUSH AF
2B2C  E5            PUSH HL
2B2D  21 58 4A      LD HL,panel_shadow
2B30  7E            LD A,(HL)
2B31  E6 EF         AND 0xEF
2B33  77            LD (HL),A
2B34  D3 F0         OUT (0xF0),A  ; panel
2B36  E1            POP HL
2B37  F1            POP AF
2B38  C9            RET

; I2C start condition (config EEPROM)
i2c_start:
2B39  CD EF 2A      CALL eeprom_clk_idle
2B3C  18 ED         JR i2c_sda_lo

; finish an EEPROM byte transfer: emit ACK clock, release SDA, then delay
eeprom_io:
2B3E  CD 4D 2B      CALL i2c_ack
2B41  CD 1D 2B      CALL i2c_sda_hi
2B44  E5            PUSH HL
2B45  21 E8 03      LD HL,0x03E8
2B48  CD 22 4C      CALL lcd_setpos
2B4B  E1            POP HL
2B4C  C9            RET

; generate I2C ACK bit: SCL low, SDA low, then pulse SCL high
i2c_ack:
2B4D  CD 09 2B      CALL i2c_scl_lo
2B50  CD 2B 2B      CALL i2c_sda_lo
2B53  18 A0         JR eeprom_clk_high

; EEPROM random read: send word address via eeprom_write, then repeated-start read (0xA1)
eeprom_read:
2B55  C5            PUSH BC
2B56  CD CB 2A      CALL eeprom_write
2B59  CD 5E 2B      CALL i2c_read_start
2B5C  C1            POP BC
2B5D  C9            RET

; issue I2C (re)start and send control byte 0xA1 to address EEPROM for reading
i2c_read_start:
2B5E  CD 39 2B      CALL i2c_start
2B61  3E A1         LD A,0xA1
2B63  C3 D4 2A      JP eeprom_send_byte

; read one byte from the I2C config EEPROM
i2c_read_byte:
2B66  C5            PUSH BC
2B67  3E 00         LD A,0x00
2B69  06 08         LD B,0x08

loc_2B6B:
2B6B  CD 09 2B      CALL i2c_scl_lo
2B6E  CD 1D 2B      CALL i2c_sda_hi
2B71  CD F5 2A      CALL eeprom_clk_high
2B74  4F            LD C,A
2B75  DB F0         IN A,(0xF0)  ; panel
2B77  37            SCF
2B78  CB 67         BIT 4,A
2B7A  20 01         JR NZ,loc_2B7D
2B7C  3F            CCF

loc_2B7D:
2B7D  79            LD A,C
2B7E  17            RLA
2B7F  10 EA         DJNZ loc_2B6B
2B81  C1            POP BC
2B82  C9            RET

; map media/geometry config to a drive-geom table index; for cfg==4 add unit 0-3, else code 7/6/3
fdd_geom_index:
2B83  CD 0A 52      CALL media_cfg_index
2B86  FE 04         CP 0x04
2B88  20 08         JR NZ,loc_2B92
2B8A  47            LD B,A
2B8B  3A 37 31      LD A,(unit_sel)
2B8E  E6 03         AND 0x03
2B90  80            ADD A,B
2B91  C9            RET

loc_2B92:
2B92  06 03         LD B,0x03
2B94  FE 07         CP 0x07
2B96  28 0B         JR Z,loc_2BA3
2B98  05            DEC B
2B99  FE 06         CP 0x06
2B9B  28 06         JR Z,loc_2BA3
2B9D  05            DEC B
2B9E  FE 03         CP 0x03
2BA0  28 01         JR Z,loc_2BA3
2BA2  05            DEC B

loc_2BA3:
2BA3  78            LD A,B
2BA4  C9            RET

; compute track-image buffer pointer: derive head via block_to_chs, then scale by track size
track_buf_ptr:
2BA5  F5            PUSH AF
2BA6  CD F2 4F      CALL block_to_chs
2BA9  4F            LD C,A
2BAA  F1            POP AF

; advance HL by (A-1)*track_size (0x52E0) to reach a track's image slot; returns head in A
track_ptr_scale:
2BAB  3D            DEC A
2BAC  47            LD B,A
2BAD  79            LD A,C
2BAE  C8            RET Z
2BAF  ED 5B E0 52   LD DE,(format_desc+0x3)

loc_2BB3:
2BB3  19            ADD HL,DE
2BB4  10 FD         DJNZ loc_2BB3
2BB6  C9            RET

; from format_desc geometry (IX+13/+15) compute sectors-per-track/interleave via div32_16
geom_sector_calc:
2BB7  6F            LD L,A
2BB8  26 00         LD H,0x00
2BBA  5C            LD E,H
2BBB  54            LD D,H
2BBC  DD 4E 0D      LD C,(IX+13)
2BBF  06 00         LD B,0x00
2BC1  CD CE 4E      CALL div32_16
2BC4  0C            INC C
2BC5  79            LD A,C
2BC6  45            LD B,L
2BC7  DD 4E 0F      LD C,(IX+15)
2BCA  0D            DEC C
2BCB  CB 09         RRC C
2BCD  C8            RET Z
2BCE  CB 08         RRC B
2BD0  C9            RET

; HRD radial-alignment test (head variant a)
hrd_radial_a:
2BD1  CD EC 2B      CALL show_radial_align
2BD4  3E 00         LD A,0x00
2BD6  CD 04 2C      CALL hrd_show_radial
2BD9  C9            RET

; HRD radial-alignment diag: show header, then display drive-B radial reading (index 1)
hrd_radial_b:
2BDA  CD EC 2B      CALL show_radial_align
2BDD  3E 01         LD A,0x01
2BDF  CD 04 2C      CALL hrd_show_radial
2BE2  C9            RET

; HRD radial-alignment diag: show header, then display radial reading index 2
hrd_radial_c:
2BE3  CD EC 2B      CALL show_radial_align
2BE6  3E 02         LD A,0x02
2BE8  CD 04 2C      CALL hrd_show_radial
2BEB  C9            RET

; print the radial-alignment test header line on the LCD
show_radial_align:
2BEC  CD 59 4C      CALL lcd_print
2BEF  0C 52 61 64 69 61 +  DB \f, "Radial alignment T", 0
2C03  C9            RET

; read radial measurement byte (via hrd_radial_ptr[B]) and format it to the LCD
hrd_show_radial:
2C04  C5            PUSH BC
2C05  DD E5         PUSH IX
2C07  47            LD B,A
2C08  CD 1E 2C      CALL hrd_radial_ptr
2C0B  6E            LD L,(HL)
2C0C  26 00         LD H,0x00
2C0E  11 00 00      LD DE,0x0000
2C11  06 02         LD B,0x02
2C13  0E 30         LD C,0x30
2C15  3E 12         LD A,0x12
2C17  CD FC 05      CALL num_to_lcd
2C1A  DD E1         POP IX
2C1C  C1            POP BC
2C1D  C9            RET

; return pointer to the radial-measurement record for index B (index 0 -> 0x3179)
hrd_radial_ptr:
2C1E  78            LD A,B
2C1F  B7            OR A
2C20  20 04         JR NZ,loc_2C26
2C22  21 79 31      LD HL,hrd_model_idx+0x1
2C25  C9            RET

loc_2C26:
2C26  05            DEC B
2C27  3A 78 31      LD A,(hrd_model_idx)
2C2A  87            ADD A,A
2C2B  87            ADD A,A
2C2C  80            ADD A,B
2C2D  6F            LD L,A
2C2E  26 00         LD H,0x00
2C30  11 7A 31      LD DE,hrd_model_idx+0x2
2C33  19            ADD HL,DE
2C34  C9            RET

; print the ECC diagnostic test header line on the LCD
hrd_show_ecc:
2C35  CD 59 4C      CALL lcd_print
2C38  0C 45 63 63 65 6E +  DB \f, "Eccentricity", 0
2C46  C9            RET

; print the azimuth-alignment test header line on the LCD
hrd_show_azimuth:
2C47  CD 59 4C      CALL lcd_print
2C4A  0C 48 65 61 64 20 +  DB \f, "Head azimuth", 0
2C58  C9            RET

; print the head-positioner test header line on the LCD
hrd_show_positioner:
2C59  CD 59 4C      CALL lcd_print
2C5C  0C 50 6F 73 69 74 +  DB \f, "Positioner", \r, \n, "hystheresis", 0
2C75  C9            RET

; print the spindle-speed test header line on the LCD
hrd_show_spindle:
2C76  CD 59 4C      CALL lcd_print
2C79  0C 53 70 69 6E 64 +  DB \f, "Spindle motor speed", 0
2C8E  C9            RET

loc_2C8F:
2C8F  CD 59 4C      CALL lcd_print
2C92  1B C0 48 52 44 20 +  DB ESC(0xC0), "HRD unreadable", 0
2CA3  CD 57 07      CALL drive_cfg_latch
2CA6  3E 01         LD A,0x01
2CA8  CD 43 4D      CALL keypad_debounce
2CAB  C9            RET

; HRD alignment-run entry (variant A): set test index 1, fall into measure+display tail
hrd_run_a:
2CAC  3E 01         LD A,0x01
2CAE  18 13         JR loc_2CC3

; HRD alignment-run entry (variant B): set test index 2, fall into measure+display tail
hrd_run_b:
2CB0  3E 02         LD A,0x02
2CB2  18 0F         JR loc_2CC3

; HRD alignment-run entry (variant C): set test index 0/flag 1, fall into measure+display tail
hrd_run_c:
2CB4  3E 00         LD A,0x00
2CB6  06 01         LD B,0x01
2CB8  C3 C3 2C      JP loc_2CC3

; HRD alignment-run entry (variant D): set test index 0/flag 2, fall into measure+display tail
hrd_run_d:
2CBB  3E 00         LD A,0x00
2CBD  06 02         LD B,0x02
2CBF  18 02         JR loc_2CC3

; HRD alignment run: measure radial, print head0/head1 scaled values, then jump to test's handler
hrd_run_e:
2CC1  AF            XOR A
2CC2  47            LD B,A

loc_2CC3:
2CC3  CD 5B 2D      CALL hrd_radial_measure
2CC6  DA 8F 2C      JP C,loc_2C8F
2CC9  CD 70 06      CALL lcd_clear_line2
2CCC  2A A1 31      LD HL,(hrd_hd0)
2CCF  3E 44         LD A,0x44
2CD1  CD EE 2C      CALL hrd_show_scaled
2CD4  3A A5 31      LD A,(hrd_test_idx)
2CD7  FE 01         CP 0x01
2CD9  28 08         JR Z,loc_2CE3
2CDB  2A A3 31      LD HL,(hrd_hd1)

loc_2CDE:
2CDE  3E 4F         LD A,0x4F
2CE0  CD EE 2C      CALL hrd_show_scaled

loc_2CE3:
2CE3  21 88 31      LD HL,hrd_test_tbl+0x2
2CE6  CD 2C 2D      CALL hrd_rec_ptr
2CE9  5E            LD E,(HL)
2CEA  23            INC HL
2CEB  56            LD D,(HL)
2CEC  D5            PUSH DE
2CED  C9            RET

; scale a signed measurement to display units: value * K / 10000, K = hrd_test_tbl[test].scale (ROM const: 422 radial/ecc/positioner um, 696 azimuth, 1 spindle-RPM); print preserving sign
hrd_show_scaled:
2CEE  F5            PUSH AF
2CEF  E5            PUSH HL
2CF0  21 86 31      LD HL,hrd_test_tbl
2CF3  CD 2C 2D      CALL hrd_rec_ptr
2CF6  7E            LD A,(HL)
2CF7  23            INC HL
2CF8  4E            LD C,(HL)
2CF9  D1            POP DE
2CFA  CB 7A         BIT 7,D
2CFC  CB BA         RES 7,D
2CFE  F5            PUSH AF
2CFF  CD 05 4F      CALL mul16
2D02  01 10 27      LD BC,0x2710
2D05  CD CE 4E      CALL div32_16
2D08  C1            POP BC
2D09  F1            POP AF
2D0A  F5            PUSH AF
2D0B  C5            PUSH BC
2D0C  0E 20         LD C,0x20
2D0E  06 03         LD B,0x03
2D10  CD FC 05      CALL num_to_lcd
2D13  C1            POP BC
2D14  F1            POP AF
2D15  3D            DEC A
2D16  CB 71         BIT 6,C
2D18  C0            RET NZ
2D19  F6 80         OR 0x80
2D1B  32 28 2D      LD (hrd_show_scaled+0x3A),A
2D1E  3A A5 31      LD A,(hrd_test_idx)
2D21  FE 01         CP 0x01
2D23  C8            RET Z
2D24  CD 59 4C      CALL lcd_print
2D27  1B 00 2D 00   DB ESC(0x00), "-", 0
2D2B  C9            RET

; index into the per-test result record table (stride 5) selected by hrd_test_idx
hrd_rec_ptr:
2D2C  3A A5 31      LD A,(hrd_test_idx)
2D2F  4F            LD C,A
2D30  87            ADD A,A
2D31  87            ADD A,A
2D32  81            ADD A,C
2D33  5F            LD E,A
2D34  16 00         LD D,0x00
2D36  19            ADD HL,DE
2D37  C9            RET
2D38  C9            RET
2D39  F5            PUSH AF
2D3A  CD 70 06      CALL lcd_clear_line2
2D3D  CD 59 4C      CALL lcd_print
2D40  1B C0 48 52 44 20 +  DB ESC(0xC0), "HRD reading error", 0
2D54  3E 05         LD A,0x05
2D56  CD E3 49      CALL buzzer_beep
2D59  F1            POP AF
2D5A  C9            RET

; HRD alignment measure: seek+capture 4 windows (hd0 A/B @ image_buf+0/+0x2000, hd1 A/B @ +0x4000/+0x6000); per-head result = burst-position difference (hrd_find_burst, SBC); 10 samples -> hrd_median_filter -> hrd_hd0/hd1
hrd_radial_measure:
2D5B  21 A5 31      LD HL,hrd_test_idx
2D5E  77            LD (HL),A
2D5F  23            INC HL
2D60  70            LD (HL),B
2D61  3E 04         LD A,0x04
2D63  32 49 31      LD (op_flag_49),A
2D66  DD 21 A7 31   LD IX,hrd_test_idx+0x2
2D6A  3E 64         LD A,0x64
2D6C  D3 AC         OUT (0xAC),A  ; pit_ctrl
2D6E  3E 00         LD A,0x00
2D70  D3 A4         OUT (0xA4),A  ; pit_c1
2D72  3E 0E         LD A,0x0E
2D74  D3 9C         OUT (0x9C),A  ; ctrl_latch
2D76  CD 4F 07      CALL set_drive_cfg
2D79  CD 57 0C      CALL show_in_progress
2D7C  CD A9 03      CALL lcd_home3
2D7F  06 0A         LD B,0x0A

loc_2D81:
2D81  C5            PUSH BC

loc_2D82:
2D82  21 A5 31      LD HL,hrd_test_idx
2D85  7E            LD A,(HL)
2D86  23            INC HL

loc_2D87:
2D87  B7            OR A
2D88  20 07         JR NZ,loc_2D91
2D8A  46            LD B,(HL)

loc_2D8B:
2D8B  CD 1E 2C      CALL hrd_radial_ptr
2D8E  7E            LD A,(HL)
2D8F  18 0E         JR loc_2D9F

loc_2D91:
2D91  FE 01         CP 0x01
2D93  20 04         JR NZ,loc_2D99
2D95  06 03         LD B,0x03
2D97  18 F2         JR loc_2D8B

loc_2D99:
2D99  FE 02         CP 0x02
2D9B  06 04         LD B,0x04
2D9D  18 EC         JR loc_2D8B

loc_2D9F:
2D9F  CD BA 2E      CALL hrd_seek_read
2DA2  47            LD B,A
2DA3  21 8A 31      LD HL,hrd_test_tbl+0x4
2DA6  CD 2C 2D      CALL hrd_rec_ptr
2DA9  4E            LD C,(HL)
2DAA  78            LD A,B
2DAB  A1            AND C
2DAC  B9            CP C
2DAD  28 09         JR Z,loc_2DB8
2DAF  21 49 31      LD HL,op_flag_49
2DB2  35            DEC (HL)
2DB3  20 CD         JR NZ,loc_2D82
2DB5  C1            POP BC
2DB6  37            SCF
2DB7  C9            RET

loc_2DB8:
2DB8  21 00 80      LD HL,image_buf
2DBB  CD 08 30      CALL hrd_find_burst
2DBE  22 A1 31      LD (hrd_hd0),HL
2DC1  21 00 A0      LD HL,image_buf+0x2000
2DC4  CD 08 30      CALL hrd_find_burst
2DC7  54            LD D,H
2DC8  5D            LD E,L
2DC9  2A A1 31      LD HL,(hrd_hd0)
2DCC  B7            OR A
2DCD  ED 52         SBC HL,DE
2DCF  22 A1 31      LD (hrd_hd0),HL
2DD2  21 00 C0      LD HL,image_buf+0x4000
2DD5  CD 08 30      CALL hrd_find_burst
2DD8  22 A3 31      LD (hrd_hd1),HL
2DDB  21 00 E0      LD HL,image_buf+0x6000
2DDE  CD 08 30      CALL hrd_find_burst
2DE1  54            LD D,H
2DE2  5D            LD E,L
2DE3  2A A3 31      LD HL,(hrd_hd1)
2DE6  B7            OR A
2DE7  ED 52         SBC HL,DE
2DE9  22 A3 31      LD (hrd_hd1),HL
2DEC  DD 75 14      LD (IX+20),L
2DEF  DD 74 15      LD (IX+21),H
2DF2  2A A1 31      LD HL,(hrd_hd0)
2DF5  DD 75 00      LD (IX+0),L
2DF8  DD 74 01      LD (IX+1),H
2DFB  DD 23         INC IX
2DFD  DD 23         INC IX
2DFF  C1            POP BC
2E00  10 02         DJNZ loc_2E04
2E02  18 03         JR loc_2E07

loc_2E04:
2E04  C3 81 2D      JP loc_2D81

loc_2E07:
2E07  CD 09 07      CALL motor_ready_wait
2E0A  CD 57 07      CALL drive_cfg_latch
2E0D  21 A7 31      LD HL,hrd_test_idx+0x2
2E10  06 0A         LD B,0x0A
2E12  CD 84 30      CALL hrd_median_filter
2E15  22 A1 31      LD (hrd_hd0),HL
2E18  21 BB 31      LD HL,param_tables+0x2
2E1B  06 0A         LD B,0x0A
2E1D  CD 84 30      CALL hrd_median_filter
2E20  22 A3 31      LD (hrd_hd1),HL
2E23  B7            OR A
2E24  C9            RET

; HRD positioner hysteresis: step in/out, difference of approach positions (um)
hrd_hysteresis:
2E25  AF            XOR A
2E26  06 01         LD B,0x01
2E28  CD 5B 2D      CALL hrd_radial_measure
2E2B  2A A1 31      LD HL,(hrd_hd0)
2E2E  DA 8F 2C      JP C,loc_2C8F
2E31  E5            PUSH HL
2E32  CD 4F 07      CALL set_drive_cfg
2E35  06 02         LD B,0x02
2E37  CD 1E 2C      CALL hrd_radial_ptr
2E3A  7E            LD A,(HL)
2E3B  CD E2 06      CALL fdc_step_to_track
2E3E  AF            XOR A
2E3F  06 01         LD B,0x01
2E41  CD 5B 2D      CALL hrd_radial_measure
2E44  2A A1 31      LD HL,(hrd_hd0)
2E47  D1            POP DE
2E48  DA 8F 2C      JP C,loc_2C8F
2E4B  ED 53 A3 31   LD (hrd_hd1),DE
2E4F  CB 7C         BIT 7,H
2E51  CB BC         RES 7,H
2E53  C4 EB 30      CALL NZ,neg16
2E56  E5            PUSH HL
2E57  2A A3 31      LD HL,(hrd_hd1)
2E5A  CB 7C         BIT 7,H
2E5C  CB BC         RES 7,H
2E5E  C4 EB 30      CALL NZ,neg16
2E61  D1            POP DE
2E62  B7            OR A
2E63  ED 52         SBC HL,DE
2E65  CB 7C         BIT 7,H
2E67  C4 EB 30      CALL NZ,neg16
2E6A  3E 03         LD A,0x03
2E6C  32 A5 31      LD (hrd_test_idx),A
2E6F  C3 DE 2C      JP loc_2CDE

; HRD spindle RPM: time index period (8253 c1/c2), RPM = 9230769/ticks
hrd_spindle_rpm:
2E72  CD 4F 07      CALL set_drive_cfg
2E75  CD 57 0C      CALL show_in_progress

loc_2E78:
2E78  3A 37 31      LD A,(unit_sel)
2E7B  47            LD B,A
2E7C  3E 01         LD A,0x01
2E7E  CD DB 37      CALL index_period_timer
2E81  CD 70 06      CALL lcd_clear_line2
2E84  30 08         JR NC,loc_2E8E
2E86  B7            OR A
2E87  21 00 00      LD HL,0x0000
2E8A  54            LD D,H
2E8B  5C            LD E,H
2E8C  28 11         JR Z,loc_2E9F

loc_2E8E:
2E8E  2A 9F 31      LD HL,(rpm_residual)
2E91  CD EB 30      CALL neg16
2E94  4D            LD C,L
2E95  44            LD B,H
2E96  11 8C 00      LD DE,0x008C
2E99  21 B1 D9      LD HL,0xD9B1
2E9C  CD CE 4E      CALL div32_16

loc_2E9F:
2E9F  0E 20         LD C,0x20
2EA1  06 03         LD B,0x03
2EA3  3E 47         LD A,0x47
2EA5  CD FC 05      CALL num_to_lcd
2EA8  CD 7A 30      CALL show_rpm_suffix
2EAB  AF            XOR A
2EAC  CD 89 4D      CALL get_key
2EAF  28 C7         JR Z,loc_2E78
2EB1  3E 01         LD A,0x01
2EB3  CD 89 4D      CALL get_key
2EB6  CD 57 07      CALL drive_cfg_latch
2EB9  C9            RET

; HRD read-back: step both heads to cyl 0x3133, arm per-drive DMA, read all sides, CRC-verify, build 4-bit success mask in op_word
hrd_seek_read:
2EBA  DD E5         PUSH IX
2EBC  21 33 31      LD HL,cur_track
2EBF  47            LD B,A
2EC0  96            SUB (HL)
2EC1  78            LD A,B
2EC2  28 17         JR Z,loc_2EDB
2EC4  FA D4 2E      JP M,loc_2ED4
2EC7  3D            DEC A
2EC8  CD E2 06      CALL fdc_step_to_track
2ECB  3C            INC A

loc_2ECC:
2ECC  CD A9 03      CALL lcd_home3
2ECF  CD E2 06      CALL fdc_step_to_track
2ED2  18 07         JR loc_2EDB

loc_2ED4:
2ED4  3C            INC A
2ED5  CD E2 06      CALL fdc_step_to_track
2ED8  3D            DEC A
2ED9  18 F1         JR loc_2ECC

loc_2EDB:
2EDB  DD 21 EB 4A   LD IX,drive_blk_a
2EDF  FD 21 06 4B   LD IY,drive_blk_b
2EE3  DD 77 00      LD (IX+0),A
2EE6  FD 77 00      LD (IY+0),A
2EE9  3E FE         LD A,0xFE
2EEB  DD 77 07      LD (IX+7),A
2EEE  FD 77 07      LD (IY+7),A
2EF1  AF            XOR A
2EF2  DD 77 01      LD (IX+1),A
2EF5  3A 63 31      LD A,(side_sel)
2EF8  FD 77 01      LD (IY+1),A
2EFB  21 00 80      LD HL,image_buf
2EFE  DD 75 0C      LD (IX+12),L
2F01  DD 74 0D      LD (IX+13),H
2F04  21 00 C0      LD HL,image_buf+0x4000
2F07  FD 75 0C      LD (IY+12),L
2F0A  FD 74 0D      LD (IY+13),H
2F0D  AF            XOR A
2F0E  32 34 31      LD (op_word),A
2F11  3A E8 52      LD A,(format_desc+0xB)
2F14  CB 67         BIT 4,A
2F16  28 41         JR Z,loc_2F59
2F18  CD 83 3A      CALL fdc_read_dual
2F1B  CD C0 2F      CALL hrd_read_verify
2F1E  38 31         JR C,loc_2F51
2F20  CB C6         SET 0,(HL)
2F22  CD D4 2F      CALL hrd_result_verify
2F25  38 2A         JR C,loc_2F51
2F27  CB CE         SET 1,(HL)
2F29  3E 02         LD A,0x02
2F2B  CD F1 2F      CALL fdc_set_xfer_cnt
2F2E  21 00 A0      LD HL,image_buf+0x2000
2F31  DD 75 0C      LD (IX+12),L
2F34  DD 74 0D      LD (IX+13),H
2F37  21 00 E0      LD HL,image_buf+0x6000
2F3A  FD 75 0C      LD (IY+12),L
2F3D  FD 74 0D      LD (IY+13),H
2F40  CD 83 3A      CALL fdc_read_dual
2F43  CD C0 2F      CALL hrd_read_verify
2F46  38 09         JR C,loc_2F51
2F48  CB D6         SET 2,(HL)
2F4A  CD D4 2F      CALL hrd_result_verify
2F4D  38 02         JR C,loc_2F51
2F4F  CB DE         SET 3,(HL)

loc_2F51:
2F51  DD E1         POP IX
2F53  3A 34 31      LD A,(op_word)
2F56  E6 0F         AND 0x0F
2F58  C9            RET

loc_2F59:
2F59  3E 01         LD A,0x01
2F5B  CD F1 2F      CALL fdc_set_xfer_cnt
2F5E  3E 01         LD A,0x01
2F60  CD 18 3A      CALL fdc_send_dma
2F63  CD C0 2F      CALL hrd_read_verify
2F66  38 E9         JR C,loc_2F51
2F68  CB C6         SET 0,(HL)
2F6A  3E 02         LD A,0x02
2F6C  CD F1 2F      CALL fdc_set_xfer_cnt
2F6F  21 00 A0      LD HL,image_buf+0x2000
2F72  DD 75 0C      LD (IX+12),L
2F75  DD 74 0D      LD (IX+13),H
2F78  3E 01         LD A,0x01
2F7A  CD 18 3A      CALL fdc_send_dma
2F7D  CD C0 2F      CALL hrd_read_verify
2F80  38 CF         JR C,loc_2F51
2F82  CB CE         SET 1,(HL)
2F84  3E 01         LD A,0x01
2F86  CD F1 2F      CALL fdc_set_xfer_cnt
2F89  3A 63 31      LD A,(side_sel)
2F8C  32 EC 4A      LD (drive_blk_a+0x1),A
2F8F  21 00 C0      LD HL,image_buf+0x4000
2F92  DD 75 0C      LD (IX+12),L
2F95  DD 74 0D      LD (IX+13),H
2F98  3E 01         LD A,0x01
2F9A  CD 18 3A      CALL fdc_send_dma
2F9D  CD C0 2F      CALL hrd_read_verify
2FA0  38 AF         JR C,loc_2F51
2FA2  CB D6         SET 2,(HL)
2FA4  3E 02         LD A,0x02
2FA6  CD F1 2F      CALL fdc_set_xfer_cnt
2FA9  21 00 E0      LD HL,image_buf+0x6000
2FAC  DD 75 0C      LD (IX+12),L
2FAF  DD 74 0D      LD (IX+13),H
2FB2  3E 01         LD A,0x01
2FB4  CD 18 3A      CALL fdc_send_dma
2FB7  CD C0 2F      CALL hrd_read_verify
2FBA  38 95         JR C,loc_2F51
2FBC  CB DE         SET 3,(HL)
2FBE  18 91         JR loc_2F51

; wait for FDC read to complete, then CRC/status-check fdc0_result via chk_fdc_crc
hrd_read_verify:
2FC0  DD E5         PUSH IX
2FC2  DD 21 DD 52   LD IX,format_desc
2FC6  CD 8C 0E      CALL wait_read_done
2FC9  E5            PUSH HL
2FCA  21 85 4A      LD HL,fdc_result_buf

loc_2FCD:
2FCD  CD DC 2F      CALL chk_fdc_crc
2FD0  E1            POP HL
2FD1  DD E1         POP IX
2FD3  C9            RET

; verify fdc0_result: normal termination (ST0&0xC0==0x40) plus sector/data-mark bits set
hrd_result_verify:
2FD4  DD E5         PUSH IX
2FD6  E5            PUSH HL
2FD7  21 85 4A      LD HL,fdc_result_buf
2FDA  18 F1         JR loc_2FCD

; validate FDC 7-byte result: ST0 top bits==0x40 and bit5 of ST1/ST2 set (good termination)
chk_fdc_crc:
2FDC  7E            LD A,(HL)
2FDD  E6 C0         AND 0xC0
2FDF  FE 40         CP 0x40
2FE1  20 0C         JR NZ,loc_2FEF
2FE3  23            INC HL
2FE4  CB 6E         BIT 5,(HL)
2FE6  28 07         JR Z,loc_2FEF
2FE8  23            INC HL
2FE9  CB 6E         BIT 5,(HL)
2FEB  28 02         JR Z,loc_2FEF
2FED  B7            OR A
2FEE  C9            RET

loc_2FEF:
2FEF  37            SCF
2FF0  C9            RET

; store transfer sector count A into per-drive blocks and derived end-count (0x4AFF-1) fields
fdc_set_xfer_cnt:
2FF1  32 05 4B      LD (drive_blk_a+0x1A),A
2FF4  32 20 4B      LD (drive_blk_b+0x1A),A
2FF7  32 EE 4A      LD (drive_blk_a+0x3),A
2FFA  32 09 4B      LD (drive_blk_b+0x3),A
2FFD  2A FF 4A      LD HL,(drive_blk_a+0x14)
3000  2B            DEC HL
3001  22 F9 4A      LD (drive_blk_a+0xE),HL
3004  22 14 4B      LD (drive_blk_b+0xE),HL
3007  C9            RET

; scan captured read data for alignment sync bursts, return byte offset
hrd_find_burst:
3008  3E FE         LD A,0xFE
300A  D3 B0         OUT (0xB0),A  ; dram_bank
300C  06 00         LD B,0x00

loc_300E:
300E  7E            LD A,(HL)
300F  23            INC HL
3010  86            ADD A,(HL)
3011  23            INC HL
3012  86            ADD A,(HL)
3013  23            INC HL
3014  FE FF         CP 0xFF
3016  28 F6         JR Z,loc_300E
3018  04            INC B
3019  2B            DEC HL
301A  2B            DEC HL
301B  78            LD A,B
301C  FE 07         CP 0x07
301E  20 EE         JR NZ,loc_300E
3020  7C            LD A,H
3021  E6 1F         AND 0x1F
3023  67            LD H,A
3024  C9            RET
3025  CD 59 4C      CALL lcd_print
3028  1B C0 48 64 30 1B +  DB ESC(0xC0), "Hd0", ESC(0xC7), \x01, "m", ESC(0xCB), "Hd1", ESC(0xD2), \x01, "m", 0

loc_303B:
303B  3E 01         LD A,0x01
303D  C3 89 4D      JP get_key
3040  CD 59 4C      CALL lcd_print
3043  1B C7 01 6D 00  DB ESC(0xC7), \x01, "m", 0
3048  18 F1         JR loc_303B
304A  CD 59 4C      CALL lcd_print
304D  1B C0 48 64 30 1B +  DB ESC(0xC0), "Hd0", ESC(0xC7), "'", ESC(0xCB), "Hd1", ESC(0xD2), "'", 0
305E  18 DB         JR loc_303B
3060  CD 59 4C      CALL lcd_print
3063  1B C0 68 79 73 74 +  DB ESC(0xC0), "hystheresis   ", ESC(0xD2), \x01, "m", 0
3078  18 C1         JR loc_303B

; print the RPM units suffix string on the LCD
show_rpm_suffix:
307A  CD 59 4C      CALL lcd_print
307D  1B CA 72 70 6D 00  DB ESC(0xCA), "rpm", 0
3083  C9            RET

; median filter: bubble-sort B signed 16-bit samples, sum the middle ones and divide (sign-preserved)
hrd_median_filter:
3084  48            LD C,B
3085  0D            DEC C

loc_3086:
3086  C5            PUSH BC
3087  E5            PUSH HL
3088  E5            PUSH HL
3089  DD E1         POP IX
308B  41            LD B,C

loc_308C:
308C  DD 7E 00      LD A,(IX+0)
308F  DD 96 02      SUB (IX+2)
3092  DD 7E 01      LD A,(IX+1)
3095  DD 9E 03      SBC A,(IX+3)
3098  FA B3 30      JP M,loc_30B3
309B  DD 5E 00      LD E,(IX+0)
309E  DD 56 02      LD D,(IX+2)
30A1  DD 72 00      LD (IX+0),D
30A4  DD 73 02      LD (IX+2),E
30A7  DD 5E 01      LD E,(IX+1)
30AA  DD 56 03      LD D,(IX+3)
30AD  DD 72 01      LD (IX+1),D
30B0  DD 73 03      LD (IX+3),E

loc_30B3:
30B3  DD 23         INC IX
30B5  DD 23         INC IX
30B7  10 D3         DJNZ loc_308C
30B9  E1            POP HL
30BA  C1            POP BC
30BB  10 C9         DJNZ loc_3086
30BD  41            LD B,C
30BE  05            DEC B
30BF  48            LD C,B
30C0  05            DEC B
30C1  E5            PUSH HL
30C2  DD E1         POP IX
30C4  DD 6E 02      LD L,(IX+2)
30C7  DD 66 03      LD H,(IX+3)

loc_30CA:
30CA  DD 5E 04      LD E,(IX+4)
30CD  DD 56 05      LD D,(IX+5)
30D0  19            ADD HL,DE
30D1  DD 23         INC IX
30D3  DD 23         INC IX
30D5  10 F3         DJNZ loc_30CA
30D7  CB 7C         BIT 7,H
30D9  F5            PUSH AF
30DA  28 03         JR Z,loc_30DF
30DC  CD EB 30      CALL neg16

loc_30DF:
30DF  11 00 00      LD DE,0x0000
30E2  43            LD B,E
30E3  CD CE 4E      CALL div32_16
30E6  F1            POP AF
30E7  C8            RET Z
30E8  CB FC         SET 7,H
30EA  C9            RET

; negate 16-bit value in HL (compute 0 - HL)
neg16:
30EB  5D            LD E,L
30EC  54            LD D,H
30ED  21 00 00      LD HL,0x0000
30F0  B7            OR A
30F1  ED 52         SBC HL,DE
30F3  C9            RET

config_fdd_menu:
30F4  8B 29         DW show_ff_35       ; [0]
30F6  A1 29         DW show_ff_525      ; [1]
30F8  B8 29         DW show_density_dd  ; [2]
30FA  CC 29         DW show_density_hd  ; [3]
30FC  DE 29         DW show_mode_simul  ; [4]
30FE  F5 29         DW show_mode_normal ; [5]
3100  1E 2A         DW show_spindle_normal ; [6]
3102  06 2A         DW show_spindle_high ; [7]
3104  38 2A         DW show_spindle_double ; [8]
3106  00 00         DW 0x0000           ; [9]
3108  5E 2A         DW set_ff_35        ; [10]
310A  67 2A         DW set_ff_525       ; [11]
310C  73 2A         DW set_density_dd   ; [12]
310E  7B 2A         DW set_density_hd   ; [13]
3110  85 2A         DW set_mode_simul   ; [14]
3112  8D 2A         DW set_mode_normal  ; [15]
3114  9F 2A         DW set_spindle_normal ; [16]
3116  95 2A         DW set_spindle_high ; [17]
3118  A8 2A         DW set_spindle_double ; [18]

cfg_ptr:
311A  00 00         DW 0x0000           ; [19]

; config flags word: form-factor/density/mode/spindle + max-cyl (bit7 = copy direction)
cfg_flags:
311C  00                                              |.|
; config byte: density/size + serialization mirror bits
cfg_byte:
311D  00                                              |.|
; drive-active control constant (hardcoded 0x2D @0x01B7; NOT precomp). bit0 (always 1) is the shared enable fanned to drive latches 0x40/0x60 and 0x9C line 6; real write-precomp is FDC port 0xC2
drv_active_cfg:
311E  00                                              |.|
; config: batch-processing / serialization flag
cfg_batch:
311F  00                                              |.|
; geometry pointer stored by each disk-format select handler
fmt_geom_ptr:
3120  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
; number of installed 32KB DRAM banks (counted by dram_test)
dram_bank_count:
3130  00                                              |.|
; pointer to the current duplication-phase / menu handler (JP target)
phase_handler:
3131  00 00                                           |..|
; current cylinder (stepped during seek; also host image geometry)
cur_track:
3133  00                                              |.|
; operation word: phase code (bits3-0), error flags (bit6/5), advance (bit7)
op_word:
3134  00                                              |.|
; media geometry word; low byte indexes the data-rate table (datarate_tbl)
datarate_idx:
3135  00                                              |.|
; index into the write-precomp table (precomp_tbl)
precomp_idx:
3136  00                                              |.|
; drive/unit + head select byte
unit_sel:
3137  00 00                                           |..|
; per-disk track/pass counter (good tally)
track_ctr:
3139  00 00                                           |..|
; completed-pass counter
pass_ctr:
313B  00 00                                           |..|
; remaining count for this run (tracks or copies)
run_count:
313D  00 00 00 00                                     |....|
; saved copy count for the current run
copy_count:
3141  00 00                                           |..|
; 32-bit numeric edit-field accumulator (low); also holds max-cyl / copy count
edit_value:
3143  00 00                                           |..|
; numeric edit-field accumulator (high word)
edit_value_hi:
3145  00 00                                           |..|
; host image-download record counter
dl_rec_count:
3147  00 00                                           |..|
; op/diag flag set by fdc_build_select & start_batch, read by HRD [purpose uncertain]
op_flag_49:
3149  00                                              |.|
; data-error-recovery mode (1=enable, 3=disable); init 3
err_recovery:
314A  03 00                                           |..|
; FDD format/mode index; also holds the autoloader reply/status byte
fmt_mode:
314C  08                                              |.|
; autoloader status low nibble (2nd hex char of S reply)
al_status1:
314D  00                                              |.|
; run status code (8 = comparing, etc.)
run_status:
314E  00                                              |.|
; RD+ copy sub-mode (1=FWV, 2=WV, 5=FW, 6=W)
rd_submode:
314F  00                                              |.|
; numeric edit-field digit count; also an operation/side flag
edit_ndigits:
3150  00                                              |.|
; numeric edit-field width (init 8)
edit_width:
3151  08                                              |.|
; numeric edit-field LCD column
edit_col:
3152  00                                              |.|
; numeric edit-field minimum value
edit_min:
3153  00                                              |.|
; numeric edit-field maximum value
edit_max:
3154  00                                              |.|
; write-protect recognition flag (config); init 4
wprot_mode:
3155  04                                              |.|
; DRAM image bank for the current track, drive group A
track_bank_a:
3156  00                                              |.|
; DRAM image bank for the current track, drive group B
track_bank_b:
3157  00                                              |.|
; byte offset of the current track within its DRAM bank
track_off:
3158  00 00                                           |..|
; image read/copy address pointer
read_addr:
315A  00 00 00 00 00                                  |.....|
; FDC data-rate register value, drive group A
fdc_rate_a:
315F  00                                              |.|
; FDC data-rate register value, drive group B
fdc_rate_b:
3160  00                                              |.|
; host remote-control mode flag (set when host drives the machine)
host_mode:
3161  00                                              |.|
; autoloader-present flag (1 = attached)
al_present:
3162  01                                              |.|
; head/side select byte (init 0x81)
side_sel:
3163  81                                              |.|
; current cylinder/head + format-select code
cyl_head:
3164  00                                              |.|
; selected special-format number (1-16)
spfmt_num:
3165  00                                              |.|
; precomp selection index
precomp_sel:
3166  00                                              |.|

; precomp menu value + serialization-enable bit
hrd_desc_tbl:
3167  02                                              |.|
; serialization: current serial number (word)
serial_nr:
3168  00 00                                           |..|
; serialization: increment added per disk (word)
serial_incr:
316A  00 00                                           |..|
; serialization: target cylinder for the stamp
serial_cyl:
316C  00                                              |.|
; serialization: target head for the stamp
serial_head:
316D  00                                              |.|
; serialization: target sector for the stamp
serial_sector:
316E  00                                              |.|
; serialization: byte offset within the sector (init 1)
serial_offset:
316F  01                                              |.|
; serialization: computed write position (word)
serial_pos:
3170  00 00                                           |..|
; serialization: sub-flag / bit-verify toggle
serial_flag:
3172  00                                              |.|
; serialization: write-buffer address (word)
serial_addr:
3173  00 00                                           |..|
; serialization: image pointer for the serial stamp (word)
serial_ptr:
3175  00 00 00                                        |...|
; HRD head/model index
hrd_model_idx:
3178  00 00 10 27 14 22 20 4F 2C 4C 28 4F 2C 4C       |...'." O,L(O,L|
; HRD test descriptor records, 5 bytes each (limits + string ptr)
hrd_test_tbl:
3186  A6 01 25 30 0F                                  |..%0.|
318B  A6 01 40 30 03                                  |..@0.|
3190  B8 02 4A 30 0F                                  |..J0.|
3195  A6 01 60 30 0F                                  |..`0.|
319A  01 00 7A 30 0F                                  |..z0.|

; spindle index-period timer residual (read back from 8253)
rpm_residual:
319F  00 00                                           |..|
; HRD measured value for head 0 (um)
hrd_hd0:
31A1  00 00                                           |..|

; HRD measured value for head 1 (um)
hrd_hd1:
31A3  0A 01                                           |..|
; selected HRD diagnostic test index
hrd_test_idx:
31A5  14 00 28 02 14 00 28 02 00 01 0C 02 19 01 1E 02 |..(...(.........|
31B5  14 00 28 02                                     |..(.|

param_tables:
31B9  00 00 00 00 00 00 00 00                         |........|
; per-format FDC data-rate register values (indexed by datarate_idx)
datarate_tbl:
31C1  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
31D1  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
31E1  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
31F1  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
3201  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
3211  00 00 00 00 00 00 00 00                         |........|
; per-format write-precomp register values (indexed by precomp_idx)
precomp_tbl:
3219  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
3229  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
3239  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
3249  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
3259  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
; 32-bit lifetime copy/insert cycle counter (low word)
cycle_cnt_lo:
3269  00 00                                           |..|
; cycle counter (high word)
cycle_cnt_hi:
326B  00 00 00                                        |...|

; 8x built-in disk-format BPB records (rec0 = 720K 3.5" DD: F9, 1440 sec, 9 spt, 2 heads, 112 root, 3 sec/FAT). NOTE: table is UNREFERENCED by firmware code
fmt_param_tbl:
326E  02 02 01 00 02 70 00 A0 05 F9 03 00 09 00 02 00 00 00 00 |.....p.............|
; 1.44M 3.5" HD: F0, 2880 sec, 18 spt, 2 heads, 224 root, 9 sec/FAT
fmt_1440k:
3281  02 01 01 00 02 E0 00 40 0B F0 09 00 12 00 02 00 00 00 00 |.......@...........|
; 720K variant: F9, 1440 sec, 9 spt, 2 heads, 144 root, 3 sec/FAT
fmt_720k_b:
3294  02 02 01 00 02 90 00 A0 05 F9 03 00 09 00 02 00 00 00 00 |...................|
; 1.2M 5.25" HD: F9, 2400 sec, 15 spt, 2 heads, 224 root, 7 sec/FAT
fmt_1200k:
32A7  02 01 01 00 02 E0 00 60 09 F9 07 00 0F 00 02 00 00 00 00 |.......`...........|
; 160K 5.25" SS DD: FE, 320 sec, 8 spt, 1 head, 64 root, 1 sec/FAT
fmt_160k:
32BA  02 01 01 00 02 40 00 40 01 FE 01 00 08 00 01 00 00 00 00 |.....@.@...........|
; 180K 5.25" SS DD: FC, 360 sec, 9 spt, 1 head, 64 root, 2 sec/FAT
fmt_180k:
32CD  02 01 01 00 02 40 00 68 01 FC 02 00 09 00 01 00 00 00 00 |.....@.h...........|
; 320K 5.25" DS DD: FF, 640 sec, 8 spt, 2 heads, 112 root, 1 sec/FAT
fmt_320k:
32E0  02 02 01 00 02 70 00 80 02 FF 01 00 08 00 02 00 00 00 00 |.....p.............|
; 360K 5.25" DS DD: FD, 720 sec, 9 spt, 2 heads, 112 root, 2 sec/FAT
fmt_360k:
32F3  02 02 01 00 02 70 00 D0 02 FD 02 00 09 00 02 00 00 00 |.....p............|

fat12_template:
3305  EB 4E 90 4A 75 6D 62 6F 20 20 20                |.N.Jumbo   |
3310  20 20 20 20 20 20 20 20 20 20 20 46 41 54 31 32 20 20 20 |           FAT12   |
3323  E8 10 00 4E 6F 6E 20 73 79 73 74 65 6D 20 64 69 73 6B 00 5B B4 0E 2E 8A 07 3C 00 74 05 CD 10 43 EB F2 30 E4 CD 16 EA 00 00 FF FF |...Non system disk.[.....<.t...C..0........|

fmt_buf1:
334E  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
335E  00                                              |.|
335F  F5            PUSH AF
3360  C5            PUSH BC
3361  D5            PUSH DE
3362  E5            PUSH HL
3363  DD E5         PUSH IX
3365  FD E5         PUSH IY
3367  32 87 33      LD (fmt_buf2),A
336A  22 88 33      LD (fmt_buf2+0x1),HL
336D  21 87 33      LD HL,fmt_buf2
3370  3E 03         LD A,0x03
3372  CD 3B 4F      CALL lcd_dump_hex
3375  CD 43 4D      CALL keypad_debounce
3378  CD 8D 06      CALL lcd_clear_line1
337B  32 4C 31      LD (fmt_mode),A
337E  FD E1         POP IY
3380  DD E1         POP IX
3382  E1            POP HL
3383  D1            POP DE
3384  C1            POP BC
3385  F1            POP AF
3386  C9            RET

fmt_buf2:
3387  00 00 00                                        |...|
retry_ctr:
338A  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
339A  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
33AA  00 00 00 00 00 00 00 00                         |........|

; top-level FDC op dispatcher: mask op (A&0x7F), pick drive block A/B from B.bit0, decode class B&0xE0 to a handler and JP
fdc_op_dispatch:
33B2  DD E5         PUSH IX
33B4  E5            PUSH HL
33B5  FD E5         PUSH IY
33B7  C5            PUSH BC
33B8  E6 7F         AND 0x7F
33BA  F5            PUSH AF
33BB  08            EX AF,AF'
33BC  3E 01         LD A,0x01
33BE  32 05 4B      LD (drive_blk_a+0x1A),A
33C1  32 20 4B      LD (drive_blk_b+0x1A),A
33C4  78            LD A,B
33C5  E6 1F         AND 0x1F
33C7  08            EX AF,AF'
33C8  FD 21 06 4B   LD IY,drive_blk_b
33CC  FE 01         CP 0x01
33CE  20 04         JR NZ,loc_33D4
33D0  FD 21 EB 4A   LD IY,drive_blk_a

loc_33D4:
33D4  08            EX AF,AF'
33D5  F5            PUSH AF
33D6  78            LD A,B
33D7  E6 E0         AND 0xE0
33D9  21 06 34      LD HL,fdc_format_build
33DC  28 26         JR Z,loc_3404
33DE  21 A2 34      LD HL,fdc_build_20
33E1  FE 20         CP 0x20
33E3  28 1F         JR Z,loc_3404
33E5  21 AA 34      LD HL,fdc_build_40
33E8  FE 40         CP 0x40
33EA  28 18         JR Z,loc_3404
33EC  21 F9 34      LD HL,fdc_build_60
33EF  FE 60         CP 0x60
33F1  28 11         JR Z,loc_3404
33F3  21 FD 34      LD HL,fdc_build_80
33F6  FE 80         CP 0x80
33F8  28 0A         JR Z,loc_3404
33FA  21 7C 35      LD HL,fdc_build_A0
33FD  FE A0         CP 0xA0
33FF  28 03         JR Z,loc_3404
3401  21 80 35      LD HL,fdc_build_C0

loc_3404:
3404  F1            POP AF
3405  E9            JP (HL)

; build FDC format command parameters (rate/precomp/sector fields)
fdc_format_build:
3406  CD 23 37      CALL set_fdc_pending
3409  FE 02         CP 0x02
340B  26 02         LD H,0x02
340D  30 02         JR NC,loc_3411
340F  26 01         LD H,0x01

loc_3411:
3411  FD 74 12      LD (IY+18),H
3414  CD 0E 37      CALL panel_bit6_on
3417  FE 06         CP 0x06
3419  26 00         LD H,0x00
341B  F5            PUSH AF
341C  C5            PUSH BC
341D  3E 02         LD A,0x02
341F  06 28         LD B,0x28
3421  CD 66 48      CALL store_rate_precomp
3424  C1            POP BC
3425  F1            POP AF
3426  30 0D         JR NC,loc_3435
3428  26 02         LD H,0x02
342A  F5            PUSH AF
342B  C5            PUSH BC
342C  3E 00         LD A,0x00
342E  06 00         LD B,0x00
3430  CD 66 48      CALL store_rate_precomp
3433  C1            POP BC
3434  F1            POP AF

loc_3435:
3435  FD 74 16      LD (IY+22),H
3438  26 01         LD H,0x01
343A  FD 74 17      LD (IY+23),H
343D  FE 05         CP 0x05
343F  26 2A         LD H,0x2A
3441  2E 45         LD L,0x45
3443  38 12         JR C,loc_3457
3445  26 1B         LD H,0x1B
3447  2E 4A         LD L,0x4A
3449  28 0C         JR Z,loc_3457
344B  FE 07         CP 0x07
344D  26 2A         LD H,0x2A
344F  2E 44         LD L,0x44
3451  38 04         JR C,loc_3457
3453  26 1B         LD H,0x1B
3455  2E 50         LD L,0x50

loc_3457:
3457  FD 74 04      LD (IY+4),H
345A  FD 75 10      LD (IY+16),L
345D  DD 21 B4 4A   LD IX,fdc_gap_tbl
3461  D9            EXX
3462  06 00         LD B,0x00
3464  4F            LD C,A
3465  DD 09         ADD IX,BC
3467  D9            EXX
3468  DD 66 00      LD H,(IX+0)
346B  FD 74 03      LD (IY+3),H
346E  FD 74 13      LD (IY+19),H
3471  FE 04         CP 0x04
3473  26 50         LD H,0x50
3475  30 02         JR NC,loc_3479
3477  26 28         LD H,0x28

loc_3479:
3479  FD 74 11      LD (IY+17),H
347C  21 01 02      LD HL,0x0201
347F  FD 74 02      LD (IY+2),H
3482  FD 75 05      LD (IY+5),L
3485  21 00 02      LD HL,0x0200
3488  FD 75 14      LD (IY+20),L
348B  FD 74 15      LD (IY+21),H
348E  21 01 0F      LD HL,0x0F01
3491  FD 74 18      LD (IY+24),H
3494  FD 75 19      LD (IY+25),L
3497  26 01         LD H,0x01
3499  FD 74 06      LD (IY+6),H
349C  CD 51 37      CALL fdc_dma_from_blk
349F  C3 83 35      JP loc_3583

; op-word bits7-5=0x20 handler: set FDC pending, H=2, rejoin build at loc_3411
fdc_build_20:
34A2  CD 23 37      CALL set_fdc_pending
34A5  26 02         LD H,0x02
34A7  C3 11 34      JP loc_3411

; op-word bits7-5=0x40 handler: build write/verify FDC rate+precomp+gap params
fdc_build_40:
34AA  FE 02         CP 0x02
34AC  26 02         LD H,0x02
34AE  30 02         JR NC,loc_34B2
34B0  26 01         LD H,0x01

loc_34B2:
34B2  FD 74 12      LD (IY+18),H
34B5  FE 06         CP 0x06
34B7  26 01         LD H,0x01
34B9  F5            PUSH AF
34BA  C5            PUSH BC
34BB  3E 01         LD A,0x01
34BD  06 00         LD B,0x00
34BF  CD 66 48      CALL store_rate_precomp
34C2  C1            POP BC
34C3  F1            POP AF
34C4  30 05         JR NC,loc_34CB
34C6  CD 0E 37      CALL panel_bit6_on
34C9  38 13         JR C,loc_34DE

loc_34CB:
34CB  CD 23 37      CALL set_fdc_pending
34CE  CD 0E 37      CALL panel_bit6_on
34D1  26 00         LD H,0x00
34D3  F5            PUSH AF
34D4  C5            PUSH BC
34D5  3E 02         LD A,0x02
34D7  06 28         LD B,0x28
34D9  CD 66 48      CALL store_rate_precomp
34DC  C1            POP BC
34DD  F1            POP AF

loc_34DE:
34DE  FD 74 16      LD (IY+22),H
34E1  CD 23 37      CALL set_fdc_pending
34E4  26 01         LD H,0x01
34E6  FD 74 17      LD (IY+23),H
34E9  FE 05         CP 0x05
34EB  26 2A         LD H,0x2A
34ED  2E 40         LD L,0x40
34EF  DA 57 34      JP C,loc_3457
34F2  26 1B         LD H,0x1B
34F4  2E 4C         LD L,0x4C
34F6  C3 57 34      JP loc_3457

; op-word bits7-5=0x60 handler: H=2, enter the 0x40 build body at loc_34B2
fdc_build_60:
34F9  26 02         LD H,0x02
34FB  18 B5         JR loc_34B2

; op-word bits7-5=0x80 handler: build params with unit_sel-dependent pending, alt density
fdc_build_80:
34FD  FE 02         CP 0x02
34FF  26 02         LD H,0x02
3501  30 02         JR NC,loc_3505
3503  26 01         LD H,0x01

loc_3505:
3505  FD 74 12      LD (IY+18),H
3508  F5            PUSH AF
3509  3A 37 31      LD A,(unit_sel)
350C  FE 83         CP 0x83
350E  28 1A         JR Z,loc_352A
3510  FE 87         CP 0x87
3512  28 16         JR Z,loc_352A
3514  FE 86         CP 0x86
3516  28 12         JR Z,loc_352A
3518  FE A3         CP 0xA3
351A  28 0E         JR Z,loc_352A
351C  FE A7         CP 0xA7
351E  28 0A         JR Z,loc_352A
3520  FE A6         CP 0xA6
3522  28 06         JR Z,loc_352A
3524  F1            POP AF
3525  CD 23 37      CALL set_fdc_pending
3528  18 04         JR loc_352E

loc_352A:
352A  F1            POP AF
352B  CD 2B 37      CALL clr_fdc_pending

loc_352E:
352E  FE 06         CP 0x06
3530  26 00         LD H,0x00
3532  F5            PUSH AF
3533  C5            PUSH BC
3534  3E 02         LD A,0x02
3536  06 28         LD B,0x28
3538  CD 66 48      CALL store_rate_precomp
353B  C1            POP BC
353C  F1            POP AF
353D  30 05         JR NC,loc_3544
353F  CD 0E 37      CALL panel_bit6_on
3542  38 10         JR C,loc_3554

loc_3544:
3544  26 00         LD H,0x00
3546  CD 1B 37      CALL clr_ctrl_bit6
3549  F5            PUSH AF
354A  C5            PUSH BC
354B  3E 03         LD A,0x03
354D  06 A3         LD B,0xA3
354F  CD 66 48      CALL store_rate_precomp
3552  C1            POP BC
3553  F1            POP AF

loc_3554:
3554  FD 74 16      LD (IY+22),H
3557  26 01         LD H,0x01
3559  FD 74 17      LD (IY+23),H
355C  FE 05         CP 0x05
355E  26 2A         LD H,0x2A
3560  2E 50         LD L,0x50
3562  DA 57 34      JP C,loc_3457
3565  26 1B         LD H,0x1B
3567  2E 41         LD L,0x41
3569  CA 57 34      JP Z,loc_3457
356C  FE 06         CP 0x06
356E  26 2A         LD H,0x2A
3570  2E 50         LD L,0x50
3572  CA 57 34      JP Z,loc_3457
3575  26 1B         LD H,0x1B
3577  2E 5A         LD L,0x5A
3579  C3 57 34      JP loc_3457

; op-word bits7-5=0xA0 handler: H=2, enter the 0x80 build body at loc_3505
fdc_build_A0:
357C  26 02         LD H,0x02
357E  18 85         JR loc_3505

; op-word bits7-5=0xC0/0xE0 handler: JP fdc_format_build
fdc_build_C0:
3580  C3 06 34      JP fdc_format_build

loc_3583:
3583  F1            POP AF
3584  C1            POP BC
3585  08            EX AF,AF'
3586  79            LD A,C
3587  B7            OR A
3588  CA FE 36      JP Z,loc_36FE
358B  08            EX AF,AF'
358C  FD 21 06 4B   LD IY,drive_blk_b
3590  FE 01         CP 0x01
3592  20 04         JR NZ,loc_3598
3594  FD 21 EB 4A   LD IY,drive_blk_a

loc_3598:
3598  26 02         LD H,0x02
359A  FD 74 12      LD (IY+18),H
359D  26 00         LD H,0x00
359F  69            LD L,C
35A0  2D            DEC L
35A1  E5            PUSH HL
35A2  D1            POP DE
35A3  29            ADD HL,HL
35A4  19            ADD HL,DE
35A5  11 AA 35      LD DE,fdc_sub_jmptbl
35A8  19            ADD HL,DE
35A9  E9            JP (HL)

; JP jump-table indexed by sub-command (C-1): 3-byte JP entries dispatched by JP (HL) @0x35A9
fdc_sub_jmptbl:
35AA  C3 E6 35      JP loc_35E6
35AD  C3 07 36      JP loc_3607
35B0  C3 0A 36      JP loc_360A
35B3  C3 21 36      JP loc_3621
35B6  C3 38 36      JP loc_3638
35B9  C3 4F 36      JP loc_364F
35BC  C3 66 36      JP loc_3666
35BF  C3 69 36      JP loc_3669
35C2  C3 80 36      JP loc_3680
35C5  C3 83 36      JP loc_3683
35C8  C3 9A 36      JP loc_369A
35CB  C3 B1 36      JP loc_36B1
35CE  C3 B4 36      JP loc_36B4
35D1  C3 B7 36      JP loc_36B7
35D4  C3 BA 36      JP loc_36BA
35D7  C3 C2 36      JP loc_36C2
35DA  C3 C5 36      JP loc_36C5
35DD  C3 D7 36      JP loc_36D7
35E0  C3 E9 36      JP loc_36E9
35E3  C3 FB 36      JP loc_36FB

loc_35E6:
35E6  C5            PUSH BC
35E7  DD 21 C6 4A   LD IX,fdc_param_recs+0xA
35EB  CD 2F 37      CALL copy_fdc_params
35EE  CD 2B 37      CALL clr_fdc_pending
35F1  26 50         LD H,0x50
35F3  FD 74 11      LD (IY+17),H
35F6  26 0E         LD H,0x0E
35F8  2E 36         LD L,0x36

loc_35FA:
35FA  FD 74 04      LD (IY+4),H
35FD  FD 75 10      LD (IY+16),L
3600  CD 51 37      CALL fdc_dma_from_blk
3603  C1            POP BC
3604  C3 FE 36      JP loc_36FE

loc_3607:
3607  C3 FE 36      JP loc_36FE

loc_360A:
360A  C5            PUSH BC
360B  DD 21 D5 4A   LD IX,fdc_param_recs+0x19
360F  CD 2F 37      CALL copy_fdc_params
3612  CD 2B 37      CALL clr_fdc_pending
3615  26 50         LD H,0x50
3617  FD 74 11      LD (IY+17),H
361A  26 35         LD H,0x35
361C  2E 74         LD L,0x74
361E  C3 FA 35      JP loc_35FA

loc_3621:
3621  C5            PUSH BC
3622  DD 21 C1 4A   LD IX,fdc_param_recs+0x5
3626  CD 2F 37      CALL copy_fdc_params
3629  CD 2B 37      CALL clr_fdc_pending
362C  26 4D         LD H,0x4D
362E  FD 74 11      LD (IY+17),H
3631  26 0E         LD H,0x0E
3633  2E 36         LD L,0x36
3635  C3 FA 35      JP loc_35FA

loc_3638:
3638  C5            PUSH BC
3639  DD 21 CB 4A   LD IX,fdc_param_recs+0xF
363D  CD 2F 37      CALL copy_fdc_params
3640  CD 2B 37      CALL clr_fdc_pending
3643  26 4D         LD H,0x4D
3645  FD 74 11      LD (IY+17),H
3648  26 1B         LD H,0x1B
364A  2E 54         LD L,0x54
364C  C3 FA 35      JP loc_35FA

loc_364F:
364F  C5            PUSH BC
3650  DD 21 D0 4A   LD IX,fdc_param_recs+0x14
3654  CD 2F 37      CALL copy_fdc_params
3657  CD 2B 37      CALL clr_fdc_pending
365A  26 4D         LD H,0x4D
365C  FD 74 11      LD (IY+17),H
365F  26 35         LD H,0x35
3661  2E 74         LD L,0x74
3663  C3 FA 35      JP loc_35FA

loc_3666:
3666  C3 FE 36      JP loc_36FE

loc_3669:
3669  C5            PUSH BC
366A  DD 21 C6 4A   LD IX,fdc_param_recs+0xA
366E  CD 2F 37      CALL copy_fdc_params
3671  CD 2B 37      CALL clr_fdc_pending
3674  26 28         LD H,0x28
3676  FD 74 11      LD (IY+17),H
3679  26 0E         LD H,0x0E
367B  2E 36         LD L,0x36
367D  C3 FA 35      JP loc_35FA

loc_3680:
3680  C3 FE 36      JP loc_36FE

loc_3683:
3683  C5            PUSH BC
3684  DD 21 D5 4A   LD IX,fdc_param_recs+0x19
3688  CD 2F 37      CALL copy_fdc_params
368B  CD 2B 37      CALL clr_fdc_pending
368E  26 28         LD H,0x28
3690  FD 74 11      LD (IY+17),H
3693  26 35         LD H,0x35
3695  2E 74         LD L,0x74
3697  C3 FA 35      JP loc_35FA

loc_369A:
369A  C5            PUSH BC
369B  DD 21 C6 4A   LD IX,fdc_param_recs+0xA
369F  CD 2F 37      CALL copy_fdc_params
36A2  CD 2B 37      CALL clr_fdc_pending
36A5  26 50         LD H,0x50
36A7  FD 74 11      LD (IY+17),H
36AA  26 0E         LD H,0x0E
36AC  2E 36         LD L,0x36
36AE  C3 FA 35      JP loc_35FA

loc_36B1:
36B1  C3 FE 36      JP loc_36FE

loc_36B4:
36B4  C3 0A 36      JP loc_360A

loc_36B7:
36B7  C3 21 36      JP loc_3621

loc_36BA:
36BA  26 4D         LD H,0x4D
36BC  FD 74 11      LD (IY+17),H
36BF  C3 FE 36      JP loc_36FE

loc_36C2:
36C2  C3 4F 36      JP loc_364F

loc_36C5:
36C5  C5            PUSH BC
36C6  DD 21 BC 4A   LD IX,fdc_param_recs
36CA  CD 2F 37      CALL copy_fdc_params
36CD  CD 2B 37      CALL clr_fdc_pending
36D0  26 07         LD H,0x07
36D2  2E 1B         LD L,0x1B
36D4  C3 FA 35      JP loc_35FA

loc_36D7:
36D7  C5            PUSH BC
36D8  DD 21 DF 4A   LD IX,fdc_param_recs+0x23
36DC  CD 2F 37      CALL copy_fdc_params
36DF  CD 2B 37      CALL clr_fdc_pending
36E2  26 C8         LD H,0xC8
36E4  2E FF         LD L,0xFF
36E6  C3 FA 35      JP loc_35FA

loc_36E9:
36E9  C5            PUSH BC
36EA  DD 21 E4 4A   LD IX,fdc_param_recs+0x28
36EE  CD 2F 37      CALL copy_fdc_params
36F1  CD 2B 37      CALL clr_fdc_pending
36F4  26 C8         LD H,0xC8
36F6  2E FF         LD L,0xFF
36F8  C3 FA 35      JP loc_35FA

loc_36FB:
36FB  C3 D7 36      JP loc_36D7

loc_36FE:
36FE  3A 01 4B      LD A,(drive_blk_a+0x16)
3701  D3 50         OUT (0x50),A  ; drv_lat1
3703  3A 1C 4B      LD A,(drive_blk_b+0x16)
3706  D3 70         OUT (0x70),A  ; drv_lat3
3708  FD E1         POP IY
370A  E1            POP HL
370B  DD E1         POP IX
370D  C9            RET

; assert panel latch bit6 (0x40) via port F0 (drive/head control line)
panel_bit6_on:
370E  F5            PUSH AF
370F  3A 58 4A      LD A,(panel_shadow)
3712  F6 40         OR 0x40

loc_3714:
3714  D3 F0         OUT (0xF0),A  ; panel
3716  32 58 4A      LD (panel_shadow),A
3719  F1            POP AF
371A  C9            RET

; clear panel latch bit6 (0x40) via port F0
clr_ctrl_bit6:
371B  F5            PUSH AF
371C  3A 58 4A      LD A,(panel_shadow)
371F  E6 BF         AND 0xBF
3721  18 F1         JR loc_3714

; set the FDC-command-pending flag (0x4AE9 = 1)
set_fdc_pending:
3723  F5            PUSH AF
3724  3E 01         LD A,0x01

loc_3726:
3726  32 E9 4A      LD (fdc_op_flags),A
3729  F1            POP AF
372A  C9            RET

; clear the FDC-command-pending flag (0x4AE9 = 0)
clr_fdc_pending:
372B  F5            PUSH AF
372C  AF            XOR A
372D  18 F7         JR loc_3726

; copy geometry params (sector/size fields) from IX format descriptor into IY drive block
copy_fdc_params:
372F  DD 6E 00      LD L,(IX+0)
3732  FD 75 05      LD (IY+5),L
3735  DD 6E 01      LD L,(IX+1)
3738  DD 66 02      LD H,(IX+2)
373B  FD 75 14      LD (IY+20),L
373E  FD 74 15      LD (IY+21),H
3741  DD 6E 03      LD L,(IX+3)
3744  FD 75 03      LD (IY+3),L
3747  FD 75 13      LD (IY+19),L
374A  DD 6E 04      LD L,(IX+4)
374D  FD 75 02      LD (IY+2),L
3750  C9            RET

; arm DMA for a track: compute byte count from block sector range, call fdc_dma_setup, store count and count*4-1 back
fdc_dma_from_blk:
3751  D5            PUSH DE
3752  FD 5E 03      LD E,(IY+3)
3755  16 00         LD D,0x00
3757  E5            PUSH HL
3758  EB            EX DE,HL
3759  FD 5E 1A      LD E,(IY+26)
375C  16 00         LD D,0x00
375E  37            SCF
375F  3F            CCF
3760  ED 52         SBC HL,DE
3762  23            INC HL
3763  EB            EX DE,HL
3764  E1            POP HL
3765  D5            PUSH DE
3766  FD 7E 02      LD A,(IY+2)
3769  CD 89 44      CALL fdc_dma_setup
376C  FD 73 0E      LD (IY+14),E
376F  FD 72 0F      LD (IY+15),D
3772  D1            POP DE
3773  CB 23         SLA E
3775  CB 12         RL D
3777  CB 23         SLA E
3779  CB 12         RL D
377B  1B            DEC DE
377C  FD 73 0A      LD (IY+10),E
377F  FD 72 0B      LD (IY+11),D
3782  D1            POP DE
3783  C9            RET

; home head to track 0: pulse ~10 single-steps then step until track-0 sense, confirm via fdc_sense_ready
fdc_home_head:
3784  C5            PUSH BC
3785  D5            PUSH DE
3786  E5            PUSH HL
3787  CD 6E 48      CALL panel_bus_on
378A  CD 0E 37      CALL panel_bit6_on
378D  CD 90 49      CALL fdc_sense_ready
3790  20 2F         JR NZ,loc_37C1
3792  06 0A         LD B,0x0A

loc_3794:
3794  3E 0A         LD A,0x0A
3796  90            SUB B
3797  C5            PUSH BC
3798  06 00         LD B,0x00
379A  4F            LD C,A
379B  CD C6 37      CALL fdc_step_pulse
379E  C1            POP BC
379F  10 F3         DJNZ loc_3794
37A1  06 09         LD B,0x09

loc_37A3:
37A3  48            LD C,B
37A4  C5            PUSH BC

loc_37A5:
37A5  06 00         LD B,0x00
37A7  CD C6 37      CALL fdc_step_pulse
37AA  CD 90 49      CALL fdc_sense_ready
37AD  C1            POP BC
37AE  28 11         JR Z,loc_37C1
37B0  10 F1         DJNZ loc_37A3
37B2  01 00 00      LD BC,0x0000
37B5  CD C6 37      CALL fdc_step_pulse
37B8  CD 90 49      CALL fdc_sense_ready
37BB  20 04         JR NZ,loc_37C1
37BD  37            SCF
37BE  3F            CCF
37BF  18 01         JR loc_37C2

loc_37C1:
37C1  37            SCF

loc_37C2:
37C2  E1            POP HL
37C3  D1            POP DE
37C4  C1            POP BC
37C5  C9            RET

; issue one FDC step/seek pulse (fdc_send_seek A=1) and poll for completion
fdc_step_pulse:
37C6  3E 01         LD A,0x01
37C8  CD 3A 43      CALL fdc_send_seek

loc_37CB:
37CB  3E 01         LD A,0x01
37CD  CD 2D 47      CALL fdc_poll_complete
37D0  28 F9         JR Z,loc_37CB
37D2  E5            PUSH HL
37D3  21 D0 07      LD HL,0x07D0
37D6  CD 22 4C      CALL lcd_setpos
37D9  E1            POP HL
37DA  C9            RET

; measure spindle index period via index sensor + PIT c1/c2, compare vs min/max (0x4AA2/0x4AA4) to validate RPM
index_period_timer:
37DB  C5            PUSH BC
37DC  D5            PUSH DE
37DD  E5            PUSH HL
37DE  F5            PUSH AF
37DF  CD 6E 48      CALL panel_bus_on
37E2  78            LD A,B
37E3  E6 C0         AND 0xC0
37E5  FE 00         CP 0x00
37E7  28 6D         JR Z,loc_3856
37E9  FE 40         CP 0x40
37EB  28 3A         JR Z,loc_3827
37ED  FE 80         CP 0x80
37EF  28 00         JR Z,loc_37F1

loc_37F1:
37F1  79            LD A,C
37F2  B7            OR A
37F3  28 1C         JR Z,loc_3811
37F5  FE 04         CP 0x04
37F7  28 1D         JR Z,loc_3816
37F9  FE 05         CP 0x05
37FB  28 19         JR Z,loc_3816
37FD  FE 06         CP 0x06
37FF  28 15         JR Z,loc_3816
3801  FE 0E         CP 0x0E
3803  28 11         JR Z,loc_3816
3805  FE 0F         CP 0x0F
3807  28 0D         JR Z,loc_3816
3809  FE 10         CP 0x10
380B  28 09         JR Z,loc_3816
380D  FE 11         CP 0x11
380F  18 05         JR loc_3816

loc_3811:
3811  78            LD A,B
3812  E6 1F         AND 0x1F
3814  FE 06         CP 0x06

loc_3816:
3816  11 A5 37      LD DE,loc_37A5
3819  21 87 2D      LD HL,loc_2D87
381C  28 6B         JR Z,loc_3889
381E  11 C6 42      LD DE,loc_42C6
3821  21 16 36      LD HL,0x3616
3824  C3 89 38      JP loc_3889

loc_3827:
3827  79            LD A,C
3828  B7            OR A
3829  28 23         JR Z,loc_384E
382B  FE 04         CP 0x04
382D  28 16         JR Z,loc_3845
382F  FE 05         CP 0x05
3831  28 12         JR Z,loc_3845
3833  FE 06         CP 0x06
3835  28 0E         JR Z,loc_3845
3837  FE 0E         CP 0x0E
3839  28 0A         JR Z,loc_3845
383B  FE 0F         CP 0x0F
383D  28 06         JR Z,loc_3845
383F  FE 10         CP 0x10
3841  28 02         JR Z,loc_3845
3843  FE 11         CP 0x11

loc_3845:
3845  11 BE 5C      LD DE,0x5CBE
3848  21 E1 4B      LD HL,loc_4BE1
384B  CA 89 38      JP Z,loc_3889

loc_384E:
384E  11 4A 6F      LD DE,0x6F4A
3851  21 0E 5B      LD HL,0x5B0E
3854  18 33         JR loc_3889

loc_3856:
3856  79            LD A,C
3857  B7            OR A
3858  28 1C         JR Z,loc_3876
385A  FE 04         CP 0x04
385C  28 1D         JR Z,loc_387B
385E  FE 05         CP 0x05
3860  28 19         JR Z,loc_387B
3862  FE 06         CP 0x06
3864  28 15         JR Z,loc_387B
3866  FE 0E         CP 0x0E
3868  28 11         JR Z,loc_387B
386A  FE 0F         CP 0x0F
386C  28 0D         JR Z,loc_387B
386E  FE 10         CP 0x10
3870  28 09         JR Z,loc_387B
3872  FE 11         CP 0x11
3874  18 05         JR loc_387B

loc_3876:
3876  78            LD A,B
3877  E6 1F         AND 0x1F
3879  FE 06         CP 0x06

loc_387B:
387B  11 4A 6F      LD DE,0x6F4A
387E  21 0E 5B      LD HL,0x5B0E
3881  28 06         JR Z,loc_3889
3883  11 8C 85      LD DE,0x858C
3886  21 2C 6C      LD HL,0x6C2C

loc_3889:
3889  F1            POP AF
388A  08            EX AF,AF'
388B  ED 53 A2 4A   LD (fdc_result_save+0x1),DE
388F  22 A4 4A      LD (fdc_result_save+0x3),HL
3892  F5            PUSH AF
3893  3E 04         LD A,0x04
3895  32 59 4A      LD (fdc_drv_state),A
3898  F1            POP AF

loc_3899:
3899  01 FF FF      LD BC,0xFFFF

loc_389C:
389C  DB F0         IN A,(0xF0)  ; panel
389E  08            EX AF,AF'
389F  CB 47         BIT 0,A
38A1  28 08         JR Z,loc_38AB
38A3  08            EX AF,AF'
38A4  CB 47         BIT 0,A
38A6  28 10         JR Z,loc_38B8
38A8  C3 B0 38      JP loc_38B0

loc_38AB:
38AB  08            EX AF,AF'
38AC  CB 4F         BIT 1,A
38AE  28 08         JR Z,loc_38B8

loc_38B0:
38B0  0B            DEC BC
38B1  79            LD A,C
38B2  B0            OR B
38B3  CA 45 39      JP Z,loc_3945
38B6  18 E4         JR loc_389C

loc_38B8:
38B8  08            EX AF,AF'
38B9  47            LD B,A
38BA  CB 47         BIT 0,A
38BC  28 0C         JR Z,loc_38CA
38BE  3E 74         LD A,0x74
38C0  D3 AC         OUT (0xAC),A  ; pit_ctrl
38C2  3E FF         LD A,0xFF
38C4  D3 A4         OUT (0xA4),A  ; pit_c1
38C6  D3 A4         OUT (0xA4),A  ; pit_c1
38C8  18 0A         JR loc_38D4

loc_38CA:
38CA  3E B4         LD A,0xB4
38CC  D3 AC         OUT (0xAC),A  ; pit_ctrl
38CE  3E FF         LD A,0xFF
38D0  D3 A8         OUT (0xA8),A  ; pit_c2
38D2  D3 A8         OUT (0xA8),A  ; pit_c2

loc_38D4:
38D4  57            LD D,A
38D5  5F            LD E,A

loc_38D6:
38D6  DB F0         IN A,(0xF0)  ; panel
38D8  CB 40         BIT 0,B
38DA  28 06         JR Z,loc_38E2
38DC  CB 47         BIT 0,A
38DE  28 F6         JR Z,loc_38D6
38E0  18 04         JR loc_38E6

loc_38E2:
38E2  CB 4F         BIT 1,A
38E4  28 F0         JR Z,loc_38D6

loc_38E6:
38E6  21 00 4B      LD HL,drive_blk_a+0x15

loc_38E9:
38E9  2B            DEC HL
38EA  7D            LD A,L
38EB  B4            OR H
38EC  CA 45 39      JP Z,loc_3945
38EF  DB F0         IN A,(0xF0)  ; panel
38F1  CB 40         BIT 0,B
38F3  28 06         JR Z,loc_38FB
38F5  CB 47         BIT 0,A
38F7  20 F0         JR NZ,loc_38E9
38F9  18 04         JR loc_38FF

loc_38FB:
38FB  CB 4F         BIT 1,A
38FD  20 EA         JR NZ,loc_38E9

loc_38FF:
38FF  CB 40         BIT 0,B
3901  28 05         JR Z,loc_3908
3903  CD DE 48      CALL read_timer_c1
3906  18 0A         JR loc_3912

loc_3908:
3908  3E 84         LD A,0x84
390A  D3 AC         OUT (0xAC),A  ; pit_ctrl
390C  DB A8         IN A,(0xA8)  ; pit_c2
390E  6F            LD L,A
390F  DB A8         IN A,(0xA8)  ; pit_c2
3911  67            LD H,A

loc_3912:
3912  EB            EX DE,HL
3913  ED 53 9F 31   LD (rpm_residual),DE
3917  ED 52         SBC HL,DE
3919  ED 5B A2 4A   LD DE,(fdc_result_save+0x1)
391D  E5            PUSH HL
391E  ED 52         SBC HL,DE
3920  E1            POP HL
3921  30 0C         JR NC,loc_392F
3923  ED 5B A4 4A   LD DE,(fdc_result_save+0x3)
3927  ED 52         SBC HL,DE
3929  30 1D         JR NC,loc_3948
392B  3E 02         LD A,0x02
392D  18 18         JR loc_3947

loc_392F:
392F  3A 59 4A      LD A,(fdc_drv_state)
3932  3D            DEC A
3933  32 59 4A      LD (fdc_drv_state),A
3936  28 05         JR Z,loc_393D
3938  78            LD A,B
3939  08            EX AF,AF'
393A  C3 99 38      JP loc_3899

loc_393D:
393D  3E 01         LD A,0x01
393F  18 06         JR loc_3947
3941  3E 02         LD A,0x02
3943  18 02         JR loc_3947

loc_3945:
3945  3E 00         LD A,0x00

loc_3947:
3947  37            SCF

loc_3948:
3948  E1            POP HL
3949  D1            POP DE
394A  C1            POP BC
394B  C9            RET

; prep recal/seek step params: pick step-rate C by drive index (unit_sel) & 0x4A58 cfg, DE=target track per side
fdc_recal_seek:
394C  C5            PUSH BC
394D  D5            PUSH DE
394E  E5            PUSH HL
394F  E6 7F         AND 0x7F
3951  08            EX AF,AF'
3952  3A 37 31      LD A,(unit_sel)
3955  E6 0F         AND 0x0F
3957  FE 04         CP 0x04
3959  0E 05         LD C,0x05
395B  38 0D         JR C,loc_396A
395D  4F            LD C,A
395E  3A 58 4A      LD A,(panel_shadow)
3961  CB 77         BIT 6,A
3963  79            LD A,C
3964  0E 06         LD C,0x06
3966  28 02         JR Z,loc_396A
3968  0E 03         LD C,0x03

loc_396A:
396A  ED 5B 1E 4B   LD DE,(drive_blk_b+0x18)
396E  08            EX AF,AF'
396F  FE 01         CP 0x01
3971  20 04         JR NZ,loc_3977
3973  ED 5B 03 4B   LD DE,(drive_blk_a+0x18)

loc_3977:
3977  D5            PUSH DE
3978  F5            PUSH AF
3979  CD 9E 39      CALL fdc_recal_wrap
397C  F1            POP AF
397D  F5            PUSH AF

loc_397E:
397E  CD 2D 47      CALL fdc_poll_complete
3981  28 FB         JR Z,loc_397E
3983  F1            POP AF
3984  D1            POP DE
3985  FE 01         CP 0x01
3987  20 06         JR NZ,loc_398F
3989  08            EX AF,AF'
398A  3A 02 4B      LD A,(drive_blk_a+0x17)
398D  18 04         JR loc_3993

loc_398F:
398F  08            EX AF,AF'
3990  3A 1D 4B      LD A,(drive_blk_b+0x17)

loc_3993:
3993  4F            LD C,A
3994  08            EX AF,AF'
3995  06 00         LD B,0x00
3997  CD D5 44      CALL fdc_set_steprate
399A  E1            POP HL
399B  D1            POP DE
399C  C1            POP BC
399D  C9            RET

; FDC specify wrapper: set step rate, issue specify (0x07); folds in bit0 of drv_active_cfg (const enable, not precomp — real write-precomp is FDC port 0xC2)
fdc_recal_wrap:
399E  C5            PUSH BC
399F  E5            PUSH HL

; build+issue FDC RECALIBRATE (opcode 0x07) to both drives of a pair
fdc_recalibrate:
39A0  CD 6E 48      CALL panel_bus_on
39A3  06 01         LD B,0x01
39A5  CD 90 45      CALL key_decode
39A8  06 00         LD B,0x00
39AA  F5            PUSH AF
39AB  CD D5 44      CALL fdc_set_steprate
39AE  F1            POP AF
39AF  CB 47         BIT 0,A
39B1  28 1D         JR Z,loc_39D0
39B3  0E 10         LD C,0x10
39B5  21 6A 4A      LD HL,fdc_cmd_buf1
39B8  06 02         LD B,0x02
39BA  36 07         LD (HL),0x07
39BC  23            INC HL
39BD  3A 1E 31      LD A,(drv_active_cfg)
39C0  E6 01         AND 0x01
39C2  CB C7         SET 0,A
39C4  77            LD (HL),A
39C5  2B            DEC HL
39C6  CD 7F 45      CALL fdc_write_bytes
39C9  0E 00         LD C,0x00
39CB  21 61 4A      LD HL,fdc_cmd_buf
39CE  18 1B         JR loc_39EB

loc_39D0:
39D0  0E 30         LD C,0x30
39D2  21 7C 4A      LD HL,fdc_cmd_buf3
39D5  06 02         LD B,0x02
39D7  36 07         LD (HL),0x07
39D9  23            INC HL
39DA  3A 1E 31      LD A,(drv_active_cfg)
39DD  E6 01         AND 0x01
39DF  CB C7         SET 0,A
39E1  77            LD (HL),A
39E2  2B            DEC HL
39E3  CD 7F 45      CALL fdc_write_bytes
39E6  0E 20         LD C,0x20
39E8  21 73 4A      LD HL,fdc_cmd_buf2

loc_39EB:
39EB  06 02         LD B,0x02
39ED  36 07         LD (HL),0x07
39EF  23            INC HL
39F0  3A 1E 31      LD A,(drv_active_cfg)
39F3  E6 01         AND 0x01
39F5  CB C7         SET 0,A
39F7  77            LD (HL),A
39F8  2B            DEC HL
39F9  CD 7F 45      CALL fdc_write_bytes
39FC  FB            EI
39FD  E1            POP HL
39FE  C1            POP BC
39FF  C9            RET
3A00  F5            PUSH AF
3A01  CD 18 3A      CALL fdc_send_dma

loc_3A04:
3A04  F1            POP AF
3A05  CD 48 48      CALL timeout_start

loc_3A08:
3A08  F5            PUSH AF
3A09  CD 2D 47      CALL fdc_poll_complete
3A0C  20 07         JR NZ,loc_3A15
3A0E  F1            POP AF
3A0F  CD 57 48      CALL timeout_check
3A12  30 F4         JR NC,loc_3A08
3A14  C9            RET

loc_3A15:
3A15  33            INC SP
3A16  33            INC SP
3A17  C9            RET

; arm single-FDC DMA read (4 desc, cnt 0x0C): pick blk A/B by A==1, set bank/drive latch, exec via SP-swap
fdc_send_dma:
3A18  C5            PUSH BC
3A19  D5            PUSH DE
3A1A  E5            PUSH HL
3A1B  E6 7F         AND 0x7F

loc_3A1D:
3A1D  DD E5         PUSH IX
3A1F  F5            PUSH AF
3A20  DD 21 06 4B   LD IX,drive_blk_b
3A24  0E C6         LD C,0xC6
3A26  FE 01         CP 0x01
3A28  20 06         JR NZ,loc_3A30
3A2A  DD 21 EB 4A   LD IX,drive_blk_a
3A2E  0E B0         LD C,0xB0

loc_3A30:
3A30  DD 46 07      LD B,(IX+7)
3A33  ED 41         OUT (C),B
3A35  06 04         LD B,0x04
3A37  21 0C 00      LD HL,0x000C
3A3A  CD EC 43      CALL dma_arm_desc
3A3D  F1            POP AF
3A3E  F3            DI
3A3F  ED 73 54 4A   LD (fdc_saved_sp),SP
3A43  DD F9         LD SP,IX
3A45  C1            POP BC
3A46  D1            POP DE
3A47  E1            POP HL
3A48  08            EX AF,AF'
3A49  DD 7E 1A      LD A,(IX+26)
3A4C  CB 27         SLA A
3A4E  B4            OR H
3A4F  67            LD H,A
3A50  08            EX AF,AF'
3A51  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3A55  FB            EI
3A56  DD E1         POP IX
3A58  CD 04 3B      CALL fdc_read_cmd
3A5B  E1            POP HL
3A5C  D1            POP DE
3A5D  C1            POP BC
3A5E  C9            RET
3A5F  CD 83 3A      CALL fdc_read_dual

loc_3A62:
3A62  CD 48 48      CALL timeout_start

loc_3A65:
3A65  3E 01         LD A,0x01
3A67  CD 2D 47      CALL fdc_poll_complete
3A6A  20 06         JR NZ,loc_3A72
3A6C  CD 57 48      CALL timeout_check
3A6F  30 F4         JR NC,loc_3A65
3A71  C9            RET

loc_3A72:
3A72  08            EX AF,AF'

loc_3A73:
3A73  3E 02         LD A,0x02
3A75  CD 2D 47      CALL fdc_poll_complete
3A78  20 06         JR NZ,loc_3A80
3A7A  CD 57 48      CALL timeout_check
3A7D  30 F4         JR NC,loc_3A73
3A7F  C9            RET

loc_3A80:
3A80  D8            RET C
3A81  08            EX AF,AF'
3A82  C9            RET

; read both drives at once: set dram_bank+drive_sel_b, arm DMA ch1(blkA)/ch2(blkB) reads, exec via SP-swap
fdc_read_dual:
3A83  C5            PUSH BC
3A84  D5            PUSH DE
3A85  E5            PUSH HL

loc_3A86:
3A86  3A 0D 4B      LD A,(drive_blk_b+0x7)
3A89  D3 C6         OUT (0xC6),A  ; drive_sel_b
3A8B  3A F2 4A      LD A,(drive_blk_a+0x7)
3A8E  D3 B0         OUT (0xB0),A  ; dram_bank
3A90  DD E5         PUSH IX
3A92  DD 21 EB 4A   LD IX,drive_blk_a
3A96  06 04         LD B,0x04
3A98  21 0C 00      LD HL,0x000C
3A9B  3E 01         LD A,0x01
3A9D  CD EC 43      CALL dma_arm_desc
3AA0  DD 21 06 4B   LD IX,drive_blk_b
3AA4  06 04         LD B,0x04
3AA6  21 0C 00      LD HL,0x000C
3AA9  3E 02         LD A,0x02
3AAB  CD EC 43      CALL dma_arm_desc
3AAE  F3            DI
3AAF  ED 73 54 4A   LD (fdc_saved_sp),SP
3AB3  DD F9         LD SP,IX
3AB5  C1            POP BC
3AB6  D1            POP DE
3AB7  E1            POP HL
3AB8  08            EX AF,AF'
3AB9  DD 7E 1A      LD A,(IX+26)
3ABC  CB 27         SLA A
3ABE  B4            OR H
3ABF  67            LD H,A
3AC0  08            EX AF,AF'
3AC1  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3AC5  C5            PUSH BC
3AC6  D5            PUSH DE
3AC7  E5            PUSH HL
3AC8  DD 21 EB 4A   LD IX,drive_blk_a
3ACC  ED 73 54 4A   LD (fdc_saved_sp),SP
3AD0  DD F9         LD SP,IX
3AD2  C1            POP BC
3AD3  D1            POP DE
3AD4  E1            POP HL
3AD5  08            EX AF,AF'
3AD6  DD 7E 1A      LD A,(IX+26)
3AD9  CB 27         SLA A
3ADB  B4            OR H
3ADC  67            LD H,A
3ADD  08            EX AF,AF'
3ADE  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3AE2  FB            EI
3AE3  3E 01         LD A,0x01
3AE5  CD 04 3B      CALL fdc_read_cmd
3AE8  3E 02         LD A,0x02
3AEA  E1            POP HL
3AEB  D1            POP DE
3AEC  C1            POP BC
3AED  CD 04 3B      CALL fdc_read_cmd
3AF0  DD E1         POP IX
3AF2  E1            POP HL
3AF3  D1            POP DE
3AF4  C1            POP BC
3AF5  C9            RET

; entry into fdc_send_dma (single-FDC DMA read) with command bit (0x80) masked off A
fdc_dma_read2:
3AF6  C5            PUSH BC
3AF7  D5            PUSH DE
3AF8  E5            PUSH HL
3AF9  E6 7F         AND 0x7F
3AFB  C3 1D 3A      JP loc_3A1D

; dual-drive DMA read entry: jumps into fdc_read_dual body (both FDCs simultaneously)
fdc_read_dual2:
3AFE  C5            PUSH BC
3AFF  D5            PUSH DE
3B00  E5            PUSH HL
3B01  C3 86 3A      JP loc_3A86

; begin FDC read: enable panel bus, select side1, set cmd tag 0x26 (read-data MFM) in 0x4AEA, build R/W cmd block
fdc_read_cmd:
3B04  CD 6E 48      CALL panel_bus_on
3B07  CD 8B 48      CALL panel_sel_hi
3B0A  08            EX AF,AF'
3B0B  3E 26         LD A,0x26
3B0D  32 EA 4A      LD (fdc_opcode_base),A
3B10  08            EX AF,AF'
3B11  C3 FB 3B      JP fdc_build_rw_cmd
3B14  CD 6E 48      CALL panel_bus_on
3B17  CD 8B 48      CALL panel_sel_hi
3B1A  08            EX AF,AF'
3B1B  3E 0A         LD A,0x0A
3B1D  32 EA 4A      LD (fdc_opcode_base),A
3B20  08            EX AF,AF'
3B21  C3 FB 3B      JP fdc_build_rw_cmd

; issue FDC write via DMA then wait for completion
fdc_write_poll:
3B24  F5            PUSH AF
3B25  CD 2B 3B      CALL fdc_write_dma
3B28  C3 04 3A      JP loc_3A04

; arm single-FDC DMA write (8 desc): pick blk A/B by A==1, set bank/drive latch, exec via SP-swap
fdc_write_dma:
3B2B  C5            PUSH BC
3B2C  D5            PUSH DE
3B2D  E5            PUSH HL
3B2E  E6 7F         AND 0x7F
3B30  DD E5         PUSH IX
3B32  F5            PUSH AF
3B33  DD 21 06 4B   LD IX,drive_blk_b
3B37  0E C6         LD C,0xC6
3B39  FE 01         CP 0x01
3B3B  20 06         JR NZ,loc_3B43
3B3D  DD 21 EB 4A   LD IX,drive_blk_a
3B41  0E B0         LD C,0xB0

loc_3B43:
3B43  DD 46 07      LD B,(IX+7)
3B46  ED 41         OUT (C),B
3B48  06 08         LD B,0x08
3B4A  21 0C 00      LD HL,0x000C
3B4D  CD EC 43      CALL dma_arm_desc
3B50  F1            POP AF
3B51  F3            DI
3B52  ED 73 54 4A   LD (fdc_saved_sp),SP
3B56  DD F9         LD SP,IX
3B58  C1            POP BC
3B59  D1            POP DE
3B5A  E1            POP HL
3B5B  08            EX AF,AF'
3B5C  DD 7E 1A      LD A,(IX+26)
3B5F  CB 27         SLA A
3B61  B4            OR H
3B62  67            LD H,A
3B63  08            EX AF,AF'
3B64  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3B68  FB            EI
3B69  DD E1         POP IX
3B6B  CD EE 3B      CALL fdc_wr_side1
3B6E  E1            POP HL
3B6F  D1            POP DE
3B70  C1            POP BC
3B71  C9            RET

; write both drives via DMA then wait for completion
fdc_write_dual:
3B72  CD 78 3B      CALL fdc_write_both
3B75  C3 62 3A      JP loc_3A62

; write both drives at once: set dram_bank+drive_sel_b, arm DMA ch1(blkA)/ch2(blkB) writes (8 desc), exec
fdc_write_both:
3B78  C5            PUSH BC
3B79  D5            PUSH DE
3B7A  E5            PUSH HL
3B7B  DD E5         PUSH IX
3B7D  3A F2 4A      LD A,(drive_blk_a+0x7)
3B80  D3 B0         OUT (0xB0),A  ; dram_bank
3B82  3A 0D 4B      LD A,(drive_blk_b+0x7)
3B85  D3 C6         OUT (0xC6),A  ; drive_sel_b
3B87  DD 21 EB 4A   LD IX,drive_blk_a
3B8B  06 08         LD B,0x08
3B8D  21 0C 00      LD HL,0x000C
3B90  E5            PUSH HL
3B91  3E 01         LD A,0x01
3B93  CD EC 43      CALL dma_arm_desc
3B96  DD 21 06 4B   LD IX,drive_blk_b
3B9A  06 08         LD B,0x08
3B9C  E1            POP HL
3B9D  3E 02         LD A,0x02
3B9F  CD EC 43      CALL dma_arm_desc
3BA2  F3            DI
3BA3  ED 73 54 4A   LD (fdc_saved_sp),SP
3BA7  DD F9         LD SP,IX
3BA9  C1            POP BC
3BAA  D1            POP DE
3BAB  E1            POP HL
3BAC  08            EX AF,AF'
3BAD  DD 7E 1A      LD A,(IX+26)
3BB0  CB 27         SLA A
3BB2  B4            OR H
3BB3  67            LD H,A
3BB4  08            EX AF,AF'
3BB5  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3BB9  C5            PUSH BC
3BBA  D5            PUSH DE
3BBB  E5            PUSH HL
3BBC  DD 21 EB 4A   LD IX,drive_blk_a
3BC0  ED 73 54 4A   LD (fdc_saved_sp),SP
3BC4  DD F9         LD SP,IX
3BC6  C1            POP BC
3BC7  D1            POP DE
3BC8  E1            POP HL
3BC9  08            EX AF,AF'
3BCA  DD 7E 1A      LD A,(IX+26)
3BCD  CB 27         SLA A
3BCF  B4            OR H
3BD0  67            LD H,A
3BD1  08            EX AF,AF'
3BD2  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3BD6  3E 01         LD A,0x01
3BD8  CD EE 3B      CALL fdc_wr_side1
3BDB  E1            POP HL
3BDC  D1            POP DE
3BDD  C1            POP BC
3BDE  3E 02         LD A,0x02
3BE0  CD EE 3B      CALL fdc_wr_side1
3BE3  DD E1         POP IX
3BE5  E1            POP HL
3BE6  D1            POP DE
3BE7  C1            POP BC
3BE8  C9            RET

; begin FDC write side0: select side lo, set cmd tag 0x05 (write-data), decode drive to result buf, save SP
fdc_wr_side0:
3BE9  CD 83 48      CALL panel_sel_lo
3BEC  18 03         JR loc_3BF1

; begin FDC write side1: select side hi, set cmd tag 0x05 (write-data), decode drive to result buf
fdc_wr_side1:
3BEE  CD 8B 48      CALL panel_sel_hi

loc_3BF1:
3BF1  CD 6E 48      CALL panel_bus_on
3BF4  08            EX AF,AF'

; FDC write-command core: set cmd tag 0x05, decode drive via key_decode, select fdc0/1/2/3 result buffer
fdc_write_cmd:
3BF5  3E 05         LD A,0x05
3BF7  32 EA 4A      LD (fdc_opcode_base),A
3BFA  08            EX AF,AF'

; build 9-byte FDC READ/WRITE command {cmd,HD,C,H,R,N,EOT,GPL,DTL} and stream it
fdc_build_rw_cmd:
3BFB  F5            PUSH AF
3BFC  C5            PUSH BC
3BFD  06 01         LD B,0x01
3BFF  CD 90 45      CALL key_decode
3C02  C1            POP BC
3C03  F3            DI
3C04  ED 73 54 4A   LD (fdc_saved_sp),SP
3C08  CB 7F         BIT 7,A
3C0A  28 0D         JR Z,loc_3C19
3C0C  FE 81         CP 0x81
3C0E  D9            EXX
3C0F  21 85 4A      LD HL,fdc_result_buf
3C12  20 10         JR NZ,loc_3C24
3C14  21 73 4A      LD HL,fdc_cmd_buf2
3C17  18 0B         JR loc_3C24

loc_3C19:
3C19  FE 01         CP 0x01
3C1B  D9            EXX
3C1C  21 7C 4A      LD HL,fdc_cmd_buf3
3C1F  20 03         JR NZ,loc_3C24
3C21  21 6A 4A      LD HL,fdc_cmd_buf1

loc_3C24:
3C24  F9            LD SP,HL
3C25  D9            EXX
3C26  7C            LD A,H
3C27  26 FF         LD H,0xFF
3C29  E5            PUSH HL
3C2A  67            LD H,A
3C2B  08            EX AF,AF'
3C2C  CB 3C         SRL H
3C2E  7C            LD A,H
3C2F  15            DEC D
3C30  82            ADD A,D
3C31  57            LD D,A
3C32  D5            PUSH DE
3C33  78            LD A,B
3C34  E6 7F         AND 0x7F
3C36  6F            LD L,A
3C37  E5            PUSH HL
3C38  78            LD A,B
3C39  E6 80         AND 0x80
3C3B  CB 07         RLC A
3C3D  CB 07         RLC A
3C3F  CB 07         RLC A
3C41  41            LD B,C
3C42  4F            LD C,A
3C43  3A 1E 31      LD A,(drv_active_cfg)
3C46  E6 01         AND 0x01
3C48  CB C7         SET 0,A
3C4A  B1            OR C
3C4B  4F            LD C,A
3C4C  C5            PUSH BC
3C4D  08            EX AF,AF'
3C4E  E6 01         AND 0x01
3C50  0F            RRCA
3C51  0F            RRCA
3C52  6F            LD L,A
3C53  3A EA 4A      LD A,(fdc_opcode_base)
3C56  B5            OR L
3C57  21 00 00      LD HL,0x0000
3C5A  39            ADD HL,SP
3C5B  2B            DEC HL
3C5C  77            LD (HL),A
3C5D  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3C61  FB            EI
3C62  06 09         LD B,0x09

loc_3C64:
3C64  F1            POP AF
3C65  CB 7F         BIT 7,A
3C67  28 0A         JR Z,loc_3C73
3C69  FE 81         CP 0x81
3C6B  0E 30         LD C,0x30
3C6D  20 0C         JR NZ,loc_3C7B
3C6F  0E 10         LD C,0x10
3C71  18 08         JR loc_3C7B

loc_3C73:
3C73  0E 20         LD C,0x20
3C75  FE 01         CP 0x01
3C77  20 02         JR NZ,loc_3C7B
3C79  0E 00         LD C,0x00

loc_3C7B:
3C7B  CD 7F 45      CALL fdc_write_bytes
3C7E  C9            RET

; format-command entry for drive-pair (B=2), falls into fdc_format_cmd
fdc_format_cmd2:
3C7F  F5            PUSH AF
3C80  C5            PUSH BC
3C81  06 02         LD B,0x02
3C83  C3 8A 3C      JP loc_3C8A

; issue FDC format-track: decode drive (B), enable bus+select side0, exec via SP-swap into result buf
fdc_format_cmd:
3C86  F5            PUSH AF
3C87  C5            PUSH BC
3C88  06 01         LD B,0x01

loc_3C8A:
3C8A  CD 90 45      CALL key_decode
3C8D  C1            POP BC
3C8E  CD 6E 48      CALL panel_bus_on
3C91  CD 83 48      CALL panel_sel_lo
3C94  F3            DI
3C95  ED 73 54 4A   LD (fdc_saved_sp),SP
3C99  CB 47         BIT 0,A
3C9B  D9            EXX
3C9C  21 79 4A      LD HL,fdc_cmd_buf2+0x6
3C9F  28 03         JR Z,loc_3CA4
3CA1  21 67 4A      LD HL,fdc_cmd_buf+0x6

loc_3CA4:
3CA4  F9            LD SP,HL
3CA5  D9            EXX
3CA6  7C            LD A,H
3CA7  61            LD H,C
3CA8  E5            PUSH HL
3CA9  D5            PUSH DE
3CAA  08            EX AF,AF'
3CAB  78            LD A,B
3CAC  E6 80         AND 0x80
3CAE  CB 07         RLC A
3CB0  CB 07         RLC A
3CB2  CB 07         RLC A
3CB4  47            LD B,A
3CB5  08            EX AF,AF'
3CB6  0F            RRCA
3CB7  0F            RRCA
3CB8  F6 0D         OR 0x0D
3CBA  4F            LD C,A
3CBB  3A 1E 31      LD A,(drv_active_cfg)
3CBE  E6 01         AND 0x01
3CC0  CB C7         SET 0,A
3CC2  B0            OR B
3CC3  47            LD B,A
3CC4  C5            PUSH BC
3CC5  21 00 00      LD HL,0x0000
3CC8  39            ADD HL,SP
3CC9  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3CCD  FB            EI
3CCE  06 06         LD B,0x06
3CD0  C3 64 3C      JP loc_3C64

; build FDC specify/step params for both drives from step-rate/HUT state into per-side cmd blocks, set irq bits 0x0F
fdc_specify_dor:
3CD3  FD E5         PUSH IY
3CD5  CD 6E 48      CALL panel_bus_on
3CD8  CD 83 48      CALL panel_sel_lo
3CDB  3E 0F         LD A,0x0F
3CDD  32 A1 4A      LD (fdc_result_save),A
3CE0  ED 5B ED 4A   LD DE,(drive_blk_a+0x2)
3CE4  3A FB 4A      LD A,(drive_blk_a+0x10)
3CE7  6F            LD L,A
3CE8  3A F0 4A      LD A,(drive_blk_a+0x5)
3CEB  D9            EXX
3CEC  08            EX AF,AF'
3CED  ED 5B 08 4B   LD DE,(drive_blk_b+0x2)
3CF1  3A 16 4B      LD A,(drive_blk_b+0x10)
3CF4  6F            LD L,A
3CF5  3A 0B 4B      LD A,(drive_blk_b+0x5)
3CF8  DD 21 61 4A   LD IX,fdc_cmd_buf
3CFC  FD 21 73 4A   LD IY,fdc_cmd_buf2
3D00  F6 34         OR 0x34
3D02  0F            RRCA
3D03  0F            RRCA
3D04  FD 77 00      LD (IY+0),A
3D07  22 77 4A      LD (fdc_cmd_buf2+0x4),HL
3D0A  ED 53 75 4A   LD (fdc_cmd_buf2+0x2),DE
3D0E  D9            EXX
3D0F  08            EX AF,AF'
3D10  F6 34         OR 0x34
3D12  0F            RRCA
3D13  0F            RRCA
3D14  DD 77 00      LD (IX+0),A
3D17  22 65 4A      LD (fdc_cmd_buf+0x4),HL
3D1A  ED 53 63 4A   LD (fdc_cmd_buf+0x2),DE
3D1E  3A 1E 31      LD A,(drv_active_cfg)
3D21  E6 01         AND 0x01
3D23  CB C7         SET 0,A
3D25  DD 77 01      LD (IX+1),A
3D28  F6 04         OR 0x04
3D2A  FD 77 01      LD (IY+1),A
3D2D  21 61 4A      LD HL,fdc_cmd_buf
3D30  06 06         LD B,0x06
3D32  0E 00         LD C,0x00
3D34  CD 7F 45      CALL fdc_write_bytes
3D37  21 73 4A      LD HL,fdc_cmd_buf2
3D3A  06 06         LD B,0x06
3D3C  0E 20         LD C,0x20
3D3E  CD 7F 45      CALL fdc_write_bytes
3D41  FD E1         POP IY
3D43  C9            RET

; issue seek via DMA then wait for completion
fdc_seek_write_wrap:
3D44  F5            PUSH AF
3D45  CD 4B 3D      CALL fdc_seek_dma
3D48  C3 04 3A      JP loc_3A04

; arm FDC seek via DMA (8 desc): pick blk A/B by A bit0, set bank/drive latch, exec via SP-swap
fdc_seek_dma:
3D4B  C5            PUSH BC
3D4C  D5            PUSH DE
3D4D  E5            PUSH HL
3D4E  E6 7F         AND 0x7F
3D50  DD E5         PUSH IX
3D52  CB 47         BIT 0,A
3D54  DD 21 06 4B   LD IX,drive_blk_b
3D58  0E C6         LD C,0xC6
3D5A  28 06         JR Z,loc_3D62
3D5C  DD 21 EB 4A   LD IX,drive_blk_a
3D60  0E B0         LD C,0xB0

loc_3D62:
3D62  DD 46 07      LD B,(IX+7)
3D65  ED 41         OUT (C),B
3D67  F5            PUSH AF
3D68  21 08 00      LD HL,0x0008
3D6B  45            LD B,L
3D6C  CD EC 43      CALL dma_arm_desc
3D6F  F3            DI
3D70  ED 73 54 4A   LD (fdc_saved_sp),SP
3D74  DD F9         LD SP,IX
3D76  C1            POP BC
3D77  D1            POP DE
3D78  E1            POP HL
3D79  3A 16 4B      LD A,(drive_blk_b+0x10)
3D7C  6F            LD L,A
3D7D  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3D81  FB            EI
3D82  F1            POP AF
3D83  F5            PUSH AF
3D84  FE 01         CP 0x01
3D86  C2 8F 3D      JP NZ,loc_3D8F
3D89  08            EX AF,AF'
3D8A  3A FB 4A      LD A,(drive_blk_a+0x10)
3D8D  6F            LD L,A
3D8E  08            EX AF,AF'

loc_3D8F:
3D8F  CD 86 3C      CALL fdc_format_cmd
3D92  C3 E7 3E      JP loc_3EE7

; read a full track: prep DMA read then poll completion in a timeout-guarded loop
fdc_read_track:
3D95  CD B9 3D      CALL fdc_read_dma_prep

loc_3D98:
3D98  CD 48 48      CALL timeout_start

loc_3D9B:
3D9B  3E 01         LD A,0x01
3D9D  CD 2D 47      CALL fdc_poll_complete
3DA0  20 06         JR NZ,loc_3DA8
3DA2  CD 57 48      CALL timeout_check
3DA5  30 F4         JR NC,loc_3D9B
3DA7  C9            RET

loc_3DA8:
3DA8  08            EX AF,AF'

loc_3DA9:
3DA9  3E 02         LD A,0x02
3DAB  CD 04 47      CALL fdc_poll_result
3DAE  20 06         JR NZ,loc_3DB6
3DB0  CD 57 48      CALL timeout_check
3DB3  30 F4         JR NC,loc_3DA9
3DB5  C9            RET

loc_3DB6:
3DB6  D8            RET C
3DB7  08            EX AF,AF'
3DB8  C9            RET

; prep FDC DMA read: verify drive ready, OR-in irq bits 0xF0, reset all 4 fdc result buffers
fdc_read_dma_prep:
3DB9  C5            PUSH BC
3DBA  D5            PUSH DE
3DBB  E5            PUSH HL
3DBC  CD 74 49      CALL fdc_drive_ready
3DBF  28 30         JR Z,loc_3DF1

loc_3DC1:
3DC1  DD E5         PUSH IX
3DC3  DD 21 A1 4A   LD IX,fdc_result_save
3DC7  DD 7E 00      LD A,(IX+0)
3DCA  F6 F0         OR 0xF0
3DCC  DD 77 00      LD (IX+0),A
3DCF  DD 21 85 4A   LD IX,fdc_result_buf
3DD3  CD D2 49      CALL fdc_result_reset
3DD6  DD 21 93 4A   LD IX,fdc_result_buf2
3DDA  CD D2 49      CALL fdc_result_reset
3DDD  DD 21 8C 4A   LD IX,fdc_result_buf1
3DE1  CD D2 49      CALL fdc_result_reset
3DE4  DD 21 9A 4A   LD IX,fdc_result_buf3
3DE8  CD D2 49      CALL fdc_result_reset
3DEB  DD E1         POP IX
3DED  E1            POP HL
3DEE  D1            POP DE
3DEF  C1            POP BC
3DF0  C9            RET

loc_3DF1:
3DF1  3A F2 4A      LD A,(drive_blk_a+0x7)
3DF4  D3 B0         OUT (0xB0),A  ; dram_bank
3DF6  3A 0D 4B      LD A,(drive_blk_b+0x7)
3DF9  D3 C6         OUT (0xC6),A  ; drive_sel_b
3DFB  DD E5         PUSH IX
3DFD  CD 57 44      CALL dma_setup

; seek+write both drives: send specify, arm DMA ch1(0x81)/ch2(0x82) 8 desc, exec via SP-swap
fdc_seek_write_dma:
3E00  CD D3 3C      CALL fdc_specify_dor
3E03  DD 21 EB 4A   LD IX,drive_blk_a
3E07  3E 81         LD A,0x81
3E09  21 0C 00      LD HL,0x000C
3E0C  06 08         LD B,0x08
3E0E  CD EC 43      CALL dma_arm_desc
3E11  DD 21 06 4B   LD IX,drive_blk_b
3E15  3E 82         LD A,0x82
3E17  21 0C 00      LD HL,0x000C
3E1A  06 08         LD B,0x08
3E1C  CD EC 43      CALL dma_arm_desc
3E1F  F3            DI
3E20  ED 73 54 4A   LD (fdc_saved_sp),SP
3E24  DD F9         LD SP,IX
3E26  C1            POP BC
3E27  D1            POP DE
3E28  E1            POP HL
3E29  08            EX AF,AF'
3E2A  DD 7E 1A      LD A,(IX+26)
3E2D  CB 27         SLA A
3E2F  B4            OR H
3E30  67            LD H,A
3E31  08            EX AF,AF'
3E32  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3E36  C5            PUSH BC
3E37  D5            PUSH DE
3E38  E5            PUSH HL
3E39  DD 21 EB 4A   LD IX,drive_blk_a
3E3D  ED 73 54 4A   LD (fdc_saved_sp),SP
3E41  DD F9         LD SP,IX
3E43  C1            POP BC
3E44  D1            POP DE
3E45  E1            POP HL
3E46  08            EX AF,AF'
3E47  DD 7E 1A      LD A,(IX+26)
3E4A  CB 27         SLA A
3E4C  B4            OR H
3E4D  67            LD H,A
3E4E  08            EX AF,AF'
3E4F  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3E53  FB            EI
3E54  3E 81         LD A,0x81
3E56  CD E9 3B      CALL fdc_wr_side0
3E59  E1            POP HL
3E5A  D1            POP DE
3E5B  C1            POP BC
3E5C  3E 82         LD A,0x82
3E5E  CD E9 3B      CALL fdc_wr_side0
3E61  C3 E8 3E      JP loc_3EE8

; arm FDC DMA read then wait for completion
fdc_dma_exec:
3E64  F5            PUSH AF
3E65  CD 6B 3E      CALL fdc_dma_arm2
3E68  C3 04 3A      JP loc_3A04

; arm FDC DMA read: check drive ready, if ready reset result buffers then proceed
fdc_dma_arm2:
3E6B  C5            PUSH BC
3E6C  D5            PUSH DE
3E6D  E5            PUSH HL
3E6E  F5            PUSH AF
3E6F  CD 74 49      CALL fdc_drive_ready
3E72  28 04         JR Z,loc_3E78
3E74  F1            POP AF
3E75  C3 C1 3D      JP loc_3DC1

loc_3E78:
3E78  F1            POP AF
3E79  E6 7F         AND 0x7F
3E7B  DD E5         PUSH IX
3E7D  CB 47         BIT 0,A
3E7F  DD 21 06 4B   LD IX,drive_blk_b
3E83  0E C6         LD C,0xC6
3E85  28 06         JR Z,loc_3E8D
3E87  DD 21 EB 4A   LD IX,drive_blk_a
3E8B  0E B0         LD C,0xB0

loc_3E8D:
3E8D  DD 46 07      LD B,(IX+7)
3E90  ED 41         OUT (C),B
3E92  F5            PUSH AF
3E93  21 08 00      LD HL,0x0008
3E96  45            LD B,L
3E97  CD EC 43      CALL dma_arm_desc
3E9A  F1            POP AF
3E9B  F5            PUSH AF
3E9C  F6 80         OR 0x80
3E9E  21 0C 00      LD HL,0x000C
3EA1  06 08         LD B,0x08
3EA3  CD EC 43      CALL dma_arm_desc
3EA6  F1            POP AF
3EA7  F5            PUSH AF
3EA8  F6 80         OR 0x80
3EAA  F3            DI
3EAB  ED 73 54 4A   LD (fdc_saved_sp),SP
3EAF  DD F9         LD SP,IX
3EB1  C1            POP BC
3EB2  D1            POP DE
3EB3  E1            POP HL
3EB4  08            EX AF,AF'
3EB5  DD 7E 1A      LD A,(IX+26)
3EB8  CB 27         SLA A
3EBA  B4            OR H
3EBB  67            LD H,A
3EBC  08            EX AF,AF'
3EBD  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3EC1  FB            EI
3EC2  CD E9 3B      CALL fdc_wr_side0
3EC5  F3            DI
3EC6  ED 73 54 4A   LD (fdc_saved_sp),SP
3ECA  DD F9         LD SP,IX
3ECC  C1            POP BC
3ECD  D1            POP DE
3ECE  E1            POP HL
3ECF  3A 16 4B      LD A,(drive_blk_b+0x10)
3ED2  6F            LD L,A
3ED3  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3ED7  FB            EI
3ED8  F1            POP AF
3ED9  F5            PUSH AF
3EDA  FE 01         CP 0x01
3EDC  20 06         JR NZ,loc_3EE4
3EDE  08            EX AF,AF'
3EDF  3A FB 4A      LD A,(drive_blk_a+0x10)
3EE2  6F            LD L,A
3EE3  08            EX AF,AF'

loc_3EE4:
3EE4  CD 7F 3C      CALL fdc_format_cmd2

loc_3EE7:
3EE7  F1            POP AF

loc_3EE8:
3EE8  DD E1         POP IX
3EEA  E1            POP HL
3EEB  D1            POP DE
3EEC  C1            POP BC
3EED  C9            RET

; write both drives via DMA then poll completion with timeout
fdc_write_both_wrap:
3EEE  CD F4 3E      CALL fdc_write_dma_both
3EF1  C3 98 3D      JP loc_3D98

; write both drives via DMA: set dram_bank+drive_sel_b, arm ch1/ch2 8-desc writes, exec via SP-swap
fdc_write_dma_both:
3EF4  C5            PUSH BC
3EF5  D5            PUSH DE
3EF6  E5            PUSH HL
3EF7  3A F2 4A      LD A,(drive_blk_a+0x7)
3EFA  D3 B0         OUT (0xB0),A  ; dram_bank
3EFC  3A 0D 4B      LD A,(drive_blk_b+0x7)
3EFF  D3 C6         OUT (0xC6),A  ; drive_sel_b
3F01  DD E5         PUSH IX
3F03  DD 21 EB 4A   LD IX,drive_blk_a
3F07  21 08 00      LD HL,0x0008
3F0A  45            LD B,L
3F0B  3E 01         LD A,0x01
3F0D  CD EC 43      CALL dma_arm_desc
3F10  DD 21 06 4B   LD IX,drive_blk_b
3F14  21 08 00      LD HL,0x0008
3F17  45            LD B,L
3F18  3E 02         LD A,0x02
3F1A  CD EC 43      CALL dma_arm_desc
3F1D  F3            DI
3F1E  ED 73 54 4A   LD (fdc_saved_sp),SP
3F22  DD F9         LD SP,IX
3F24  C1            POP BC
3F25  D1            POP DE
3F26  E1            POP HL
3F27  3A 16 4B      LD A,(drive_blk_b+0x10)
3F2A  6F            LD L,A
3F2B  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3F2F  3E 02         LD A,0x02
3F31  CD 86 3C      CALL fdc_format_cmd
3F34  DD 21 EB 4A   LD IX,drive_blk_a
3F38  ED 73 54 4A   LD (fdc_saved_sp),SP
3F3C  DD F9         LD SP,IX
3F3E  C1            POP BC
3F3F  D1            POP DE
3F40  E1            POP HL
3F41  ED 7B 54 4A   LD SP,(fdc_saved_sp)
3F45  FB            EI
3F46  3A FB 4A      LD A,(drive_blk_a+0x10)
3F49  6F            LD L,A
3F4A  3E 01         LD A,0x01
3F4C  F5            PUSH AF
3F4D  CD 86 3C      CALL fdc_format_cmd
3F50  C3 E7 3E      JP loc_3EE7

; read from source drive then latch its bank/track pointers from format_desc (0x52E9..0x52ED) for copy
fdc_read_src:
3F53  E5            PUSH HL
3F54  E6 7F         AND 0x7F
3F56  F5            PUSH AF
3F57  CD 64 3E      CALL fdc_dma_exec

loc_3F5A:
3F5A  38 4A         JR C,loc_3FA6
3F5C  F1            POP AF
3F5D  6F            LD L,A
3F5E  08            EX AF,AF'
3F5F  7D            LD A,L
3F60  FE 01         CP 0x01
3F62  28 0E         JR Z,loc_3F72
3F64  2A ED 52      LD HL,(format_desc+0x10)
3F67  3A EC 52      LD A,(format_desc+0xF)
3F6A  32 0D 4B      LD (drive_blk_b+0x7),A
3F6D  22 12 4B      LD (drive_blk_b+0xC),HL
3F70  18 0C         JR loc_3F7E

loc_3F72:
3F72  2A EA 52      LD HL,(format_desc+0xD)
3F75  3A E9 52      LD A,(format_desc+0xC)
3F78  32 F2 4A      LD (drive_blk_a+0x7),A
3F7B  22 F7 4A      LD (drive_blk_a+0xC),HL

loc_3F7E:
3F7E  08            EX AF,AF'
3F7F  F5            PUSH AF
3F80  3A E9 4A      LD A,(fdc_op_flags)
3F83  B7            OR A
3F84  28 02         JR Z,loc_3F88
3F86  18 07         JR loc_3F8F

loc_3F88:
3F88  F1            POP AF
3F89  CD AA 3F      CALL fdc_src_dma
3F8C  C3 A8 3F      JP loc_3FA8

loc_3F8F:
3F8F  F1            POP AF
3F90  F5            PUSH AF
3F91  CD F6 3A      CALL fdc_dma_read2
3F94  F1            POP AF
3F95  CD 48 48      CALL timeout_start

loc_3F98:
3F98  F5            PUSH AF
3F99  CD 2D 47      CALL fdc_poll_complete
3F9C  20 08         JR NZ,loc_3FA6
3F9E  F1            POP AF
3F9F  CD 57 48      CALL timeout_check
3FA2  30 F4         JR NC,loc_3F98
3FA4  18 02         JR loc_3FA8

loc_3FA6:
3FA6  33            INC SP
3FA7  33            INC SP

loc_3FA8:
3FA8  E1            POP HL
3FA9  C9            RET

; arm source-drive DMA: set bank or drive latch by A==1, load ptr, compute byte length
fdc_src_dma:
3FAA  C5            PUSH BC
3FAB  D5            PUSH DE
3FAC  E5            PUSH HL
3FAD  DD E5         PUSH IX
3FAF  F5            PUSH AF
3FB0  FE 01         CP 0x01
3FB2  20 0D         JR NZ,loc_3FC1
3FB4  3A F2 4A      LD A,(drive_blk_a+0x7)
3FB7  D3 B0         OUT (0xB0),A  ; dram_bank
3FB9  2A F7 4A      LD HL,(drive_blk_a+0xC)
3FBC  22 21 4B      LD (dma_ptr_save),HL
3FBF  18 0B         JR loc_3FCC

loc_3FC1:
3FC1  3A 0D 4B      LD A,(drive_blk_b+0x7)
3FC4  D3 C6         OUT (0xC6),A  ; drive_sel_b
3FC6  2A 12 4B      LD HL,(drive_blk_b+0xC)
3FC9  22 25 4B      LD (dma_ptr_save+0x4),HL

loc_3FCC:
3FCC  F1            POP AF
3FCD  2A F9 4A      LD HL,(drive_blk_a+0xE)
3FD0  ED 5B FF 4A   LD DE,(drive_blk_a+0x14)
3FD4  08            EX AF,AF'
3FD5  AF            XOR A
3FD6  ED 52         SBC HL,DE
3FD8  08            EX AF,AF'
3FD9  FE 01         CP 0x01
3FDB  C2 EA 3F      JP NZ,loc_3FEA
3FDE  F5            PUSH AF
3FDF  22 23 4B      LD (dma_ptr_save+0x2),HL
3FE2  DD 21 21 4B   LD IX,dma_ptr_save
3FE6  3E 01         LD A,0x01
3FE8  18 0A         JR loc_3FF4

loc_3FEA:
3FEA  F5            PUSH AF
3FEB  22 27 4B      LD (dma_ptr_save+0x6),HL
3FEE  DD 21 25 4B   LD IX,dma_ptr_save+0x4
3FF2  3E 02         LD A,0x02

loc_3FF4:
3FF4  06 04         LD B,0x04
3FF6  21 00 00      LD HL,0x0000
3FF9  CD EC 43      CALL dma_arm_desc
3FFC  F1            POP AF
3FFD  F5            PUSH AF
3FFE  FE 01         CP 0x01
4000  C2 0B 40      JP NZ,loc_400B
4003  DD 21 EB 4A   LD IX,drive_blk_a
4007  3E 01         LD A,0x01
4009  18 06         JR loc_4011

loc_400B:
400B  DD 21 06 4B   LD IX,drive_blk_b
400F  3E 02         LD A,0x02

loc_4011:
4011  F3            DI
4012  ED 73 54 4A   LD (fdc_saved_sp),SP
4016  DD F9         LD SP,IX
4018  C1            POP BC
4019  D1            POP DE
401A  E1            POP HL
401B  08            EX AF,AF'
401C  DD 7E 1A      LD A,(IX+26)
401F  3C            INC A
4020  CB 27         SLA A
4022  B4            OR H
4023  67            LD H,A
4024  08            EX AF,AF'
4025  ED 7B 54 4A   LD SP,(fdc_saved_sp)
4029  FB            EI
402A  CD 04 3B      CALL fdc_read_cmd
402D  CD 48 48      CALL timeout_start
4030  F1            POP AF
4031  FE 01         CP 0x01
4033  26 01         LD H,0x01
4035  28 02         JR Z,loc_4039
4037  26 02         LD H,0x02

loc_4039:
4039  7C            LD A,H
403A  E5            PUSH HL
403B  CD 2D 47      CALL fdc_poll_complete
403E  E1            POP HL
403F  20 08         JR NZ,loc_4049
4041  7C            LD A,H
4042  CD 57 48      CALL timeout_check
4045  30 F2         JR NC,loc_4039
4047  18 74         JR loc_40BD

loc_4049:
4049  7C            LD A,H
404A  38 71         JR C,loc_40BD
404C  2A FF 4A      LD HL,(drive_blk_a+0x14)
404F  2B            DEC HL
4050  22 23 4B      LD (dma_ptr_save+0x2),HL
4053  22 27 4B      LD (dma_ptr_save+0x6),HL
4056  F5            PUSH AF
4057  FE 01         CP 0x01
4059  20 08         JR NZ,loc_4063
405B  DD 21 21 4B   LD IX,dma_ptr_save
405F  3E 01         LD A,0x01
4061  18 06         JR loc_4069

loc_4063:
4063  DD 21 25 4B   LD IX,dma_ptr_save+0x4
4067  3E 02         LD A,0x02

loc_4069:
4069  06 04         LD B,0x04
406B  21 00 00      LD HL,0x0000
406E  CD EC 43      CALL dma_arm_desc
4071  F1            POP AF
4072  F5            PUSH AF
4073  FE 01         CP 0x01
4075  20 08         JR NZ,loc_407F
4077  DD 21 EB 4A   LD IX,drive_blk_a
407B  3E 01         LD A,0x01
407D  18 06         JR loc_4085

loc_407F:
407F  DD 21 06 4B   LD IX,drive_blk_b
4083  3E 02         LD A,0x02

loc_4085:
4085  F3            DI
4086  ED 73 54 4A   LD (fdc_saved_sp),SP
408A  DD F9         LD SP,IX
408C  C1            POP BC
408D  D1            POP DE
408E  16 01         LD D,0x01
4090  E1            POP HL
4091  08            EX AF,AF'
4092  DD 7E 1A      LD A,(IX+26)
4095  CB 27         SLA A
4097  B4            OR H
4098  67            LD H,A
4099  08            EX AF,AF'
409A  ED 7B 54 4A   LD SP,(fdc_saved_sp)
409E  FB            EI
409F  CD 04 3B      CALL fdc_read_cmd
40A2  CD 48 48      CALL timeout_start
40A5  F1            POP AF
40A6  FE 01         CP 0x01
40A8  26 01         LD H,0x01
40AA  28 02         JR Z,loc_40AE
40AC  26 02         LD H,0x02

loc_40AE:
40AE  7C            LD A,H
40AF  E5            PUSH HL
40B0  CD 2D 47      CALL fdc_poll_complete
40B3  E1            POP HL
40B4  20 07         JR NZ,loc_40BD
40B6  CD 57 48      CALL timeout_check
40B9  30 F3         JR NC,loc_40AE
40BB  18 00         JR loc_40BD

loc_40BD:
40BD  DD E1         POP IX
40BF  E1            POP HL
40C0  D1            POP DE
40C1  C1            POP BC
40C2  C9            RET

; copy one track: read source track, latch dest geometry from format_desc, write to dest drive if enabled
fdc_copy_track:
40C3  E5            PUSH HL
40C4  CD 95 3D      CALL fdc_read_track

loc_40C7:
40C7  38 4C         JR C,loc_4115
40C9  2A ED 52      LD HL,(format_desc+0x10)
40CC  3A EC 52      LD A,(format_desc+0xF)
40CF  32 0D 4B      LD (drive_blk_b+0x7),A
40D2  22 12 4B      LD (drive_blk_b+0xC),HL
40D5  2A EA 52      LD HL,(format_desc+0xD)
40D8  3A E9 52      LD A,(format_desc+0xC)
40DB  32 F2 4A      LD (drive_blk_a+0x7),A
40DE  22 F7 4A      LD (drive_blk_a+0xC),HL
40E1  3A E9 4A      LD A,(fdc_op_flags)
40E4  B7            OR A
40E5  28 02         JR Z,loc_40E9
40E7  18 06         JR loc_40EF

loc_40E9:
40E9  CD 17 41      CALL fdc_write_track
40EC  C3 15 41      JP loc_4115

loc_40EF:
40EF  CD FE 3A      CALL fdc_read_dual2
40F2  CD 48 48      CALL timeout_start

loc_40F5:
40F5  3E 01         LD A,0x01
40F7  CD 2D 47      CALL fdc_poll_complete
40FA  20 07         JR NZ,loc_4103
40FC  CD 57 48      CALL timeout_check
40FF  30 F4         JR NC,loc_40F5
4101  18 12         JR loc_4115

loc_4103:
4103  08            EX AF,AF'

loc_4104:
4104  3E 02         LD A,0x02
4106  CD 04 47      CALL fdc_poll_result
4109  20 07         JR NZ,loc_4112
410B  CD 57 48      CALL timeout_check
410E  30 F4         JR NC,loc_4104
4110  18 03         JR loc_4115

loc_4112:
4112  38 01         JR C,loc_4115
4114  08            EX AF,AF'

loc_4115:
4115  E1            POP HL
4116  C9            RET

; write full track to dest drive: set latches, copy DMA base ptrs, compute length, arm 4-desc DMA descriptors
fdc_write_track:
4117  C5            PUSH BC
4118  D5            PUSH DE
4119  E5            PUSH HL
411A  3A 0D 4B      LD A,(drive_blk_b+0x7)
411D  D3 C6         OUT (0xC6),A  ; drive_sel_b
411F  3A F2 4A      LD A,(drive_blk_a+0x7)
4122  D3 B0         OUT (0xB0),A  ; dram_bank
4124  CD 61 42      CALL dma_set_ptrs
4127  2A F9 4A      LD HL,(drive_blk_a+0xE)
412A  ED 5B FF 4A   LD DE,(drive_blk_a+0x14)
412E  AF            XOR A
412F  ED 52         SBC HL,DE
4131  22 23 4B      LD (dma_ptr_save+0x2),HL
4134  22 27 4B      LD (dma_ptr_save+0x6),HL
4137  DD E5         PUSH IX
4139  DD 21 21 4B   LD IX,dma_ptr_save
413D  06 04         LD B,0x04
413F  21 00 00      LD HL,0x0000
4142  3E 01         LD A,0x01
4144  CD EC 43      CALL dma_arm_desc
4147  DD 21 25 4B   LD IX,dma_ptr_save+0x4
414B  06 04         LD B,0x04
414D  21 00 00      LD HL,0x0000
4150  3E 02         LD A,0x02
4152  CD EC 43      CALL dma_arm_desc
4155  DD 21 06 4B   LD IX,drive_blk_b
4159  F3            DI
415A  ED 73 54 4A   LD (fdc_saved_sp),SP
415E  DD F9         LD SP,IX
4160  C1            POP BC
4161  D1            POP DE
4162  E1            POP HL
4163  08            EX AF,AF'
4164  DD 7E 1A      LD A,(IX+26)
4167  3C            INC A
4168  CB 27         SLA A
416A  B4            OR H
416B  67            LD H,A
416C  08            EX AF,AF'
416D  ED 7B 54 4A   LD SP,(fdc_saved_sp)
4171  C5            PUSH BC
4172  D5            PUSH DE
4173  E5            PUSH HL
4174  DD 21 EB 4A   LD IX,drive_blk_a
4178  ED 73 54 4A   LD (fdc_saved_sp),SP
417C  DD F9         LD SP,IX
417E  C1            POP BC
417F  D1            POP DE
4180  E1            POP HL
4181  08            EX AF,AF'
4182  DD 7E 1A      LD A,(IX+26)
4185  3C            INC A
4186  CB 27         SLA A
4188  B4            OR H
4189  67            LD H,A
418A  08            EX AF,AF'
418B  ED 7B 54 4A   LD SP,(fdc_saved_sp)
418F  FB            EI
4190  3E 01         LD A,0x01
4192  CD 04 3B      CALL fdc_read_cmd
4195  3E 02         LD A,0x02
4197  E1            POP HL
4198  D1            POP DE
4199  C1            POP BC
419A  CD 04 3B      CALL fdc_read_cmd
419D  CD 48 48      CALL timeout_start

loc_41A0:
41A0  3E 01         LD A,0x01
41A2  CD 2D 47      CALL fdc_poll_complete
41A5  20 08         JR NZ,loc_41AF
41A7  CD 57 48      CALL timeout_check
41AA  30 F4         JR NC,loc_41A0
41AC  C3 5B 42      JP loc_425B

loc_41AF:
41AF  08            EX AF,AF'

loc_41B0:
41B0  3E 02         LD A,0x02
41B2  CD 04 47      CALL fdc_poll_result
41B5  20 08         JR NZ,loc_41BF
41B7  CD 57 48      CALL timeout_check
41BA  30 F4         JR NC,loc_41B0
41BC  C3 5B 42      JP loc_425B

loc_41BF:
41BF  DA 5B 42      JP C,loc_425B
41C2  08            EX AF,AF'
41C3  DA 5B 42      JP C,loc_425B
41C6  2A FF 4A      LD HL,(drive_blk_a+0x14)
41C9  2B            DEC HL
41CA  22 23 4B      LD (dma_ptr_save+0x2),HL
41CD  22 27 4B      LD (dma_ptr_save+0x6),HL
41D0  DD 21 21 4B   LD IX,dma_ptr_save
41D4  06 04         LD B,0x04
41D6  21 00 00      LD HL,0x0000
41D9  3E 01         LD A,0x01
41DB  CD EC 43      CALL dma_arm_desc
41DE  DD 21 25 4B   LD IX,dma_ptr_save+0x4
41E2  06 04         LD B,0x04
41E4  21 00 00      LD HL,0x0000
41E7  3E 02         LD A,0x02
41E9  CD EC 43      CALL dma_arm_desc
41EC  DD 21 06 4B   LD IX,drive_blk_b
41F0  F3            DI
41F1  ED 73 54 4A   LD (fdc_saved_sp),SP
41F5  DD F9         LD SP,IX
41F7  C1            POP BC
41F8  D1            POP DE
41F9  16 01         LD D,0x01
41FB  E1            POP HL
41FC  08            EX AF,AF'
41FD  DD 7E 1A      LD A,(IX+26)
4200  CB 27         SLA A
4202  B4            OR H
4203  67            LD H,A
4204  08            EX AF,AF'
4205  ED 7B 54 4A   LD SP,(fdc_saved_sp)
4209  C5            PUSH BC
420A  D5            PUSH DE
420B  E5            PUSH HL
420C  DD 21 EB 4A   LD IX,drive_blk_a
4210  ED 73 54 4A   LD (fdc_saved_sp),SP
4214  DD F9         LD SP,IX
4216  C1            POP BC
4217  D1            POP DE
4218  16 01         LD D,0x01
421A  E1            POP HL
421B  08            EX AF,AF'
421C  DD 7E 1A      LD A,(IX+26)
421F  CB 27         SLA A
4221  B4            OR H
4222  67            LD H,A
4223  08            EX AF,AF'
4224  ED 7B 54 4A   LD SP,(fdc_saved_sp)
4228  FB            EI
4229  3E 01         LD A,0x01
422B  CD 04 3B      CALL fdc_read_cmd
422E  3E 02         LD A,0x02
4230  E1            POP HL
4231  D1            POP DE
4232  C1            POP BC
4233  CD 04 3B      CALL fdc_read_cmd
4236  CD 48 48      CALL timeout_start

loc_4239:
4239  3E 01         LD A,0x01
423B  CD 2D 47      CALL fdc_poll_complete
423E  20 08         JR NZ,loc_4248
4240  CD 57 48      CALL timeout_check
4243  30 F4         JR NC,loc_4239
4245  C3 5B 42      JP loc_425B

loc_4248:
4248  08            EX AF,AF'

loc_4249:
4249  3E 02         LD A,0x02
424B  CD 04 47      CALL fdc_poll_result
424E  20 08         JR NZ,loc_4258
4250  CD 57 48      CALL timeout_check
4253  30 F4         JR NC,loc_4249
4255  C3 5B 42      JP loc_425B

loc_4258:
4258  38 01         JR C,loc_425B
425A  08            EX AF,AF'

loc_425B:
425B  DD E1         POP IX
425D  E1            POP HL
425E  D1            POP DE
425F  C1            POP BC
4260  C9            RET

; copy source(0x4AF7)/dest(0x4B12) DMA base pointers into active descriptor slots 0x4B21/0x4B25
dma_set_ptrs:
4261  2A F7 4A      LD HL,(drive_blk_a+0xC)
4264  22 21 4B      LD (dma_ptr_save),HL
4267  2A 12 4B      LD HL,(drive_blk_b+0xC)
426A  22 25 4B      LD (dma_ptr_save+0x4),HL
426D  C9            RET
426E  E5            PUSH HL
426F  CD EE 3E      CALL fdc_write_both_wrap
4272  C3 C7 40      JP loc_40C7
4275  E5            PUSH HL
4276  E6 7F         AND 0x7F
4278  F5            PUSH AF
4279  CD 44 3D      CALL fdc_seek_write_wrap
427C  C3 5A 3F      JP loc_3F5A

; write side via DMA (fdc_write_poll) then latch source geometry
fdc_read_src_b:
427F  E5            PUSH HL
4280  E6 7F         AND 0x7F
4282  F5            PUSH AF
4283  CD 24 3B      CALL fdc_write_poll
4286  C3 5A 3F      JP loc_3F5A

loc_4289:
4289  E5            PUSH HL
428A  CD 72 3B      CALL fdc_write_dual
428D  C3 C7 40      JP loc_40C7
4290  ED 4B 06 4B   LD BC,(drive_blk_b)
4294  FE 01         CP 0x01
4296  20 04         JR NZ,loc_429C
4298  ED 4B EB 4A   LD BC,(drive_blk_a)

loc_429C:
429C  CD A0 42      CALL fdc_op_poll_keys
429F  C9            RET

; set FDC step rate from per-side track state (A selects side: 0x4B03 vs 0x4B1E), enable panel bus
fdc_op_poll_keys:
42A0  CD 6E 48      CALL panel_bus_on
42A3  F5            PUSH AF
42A4  C5            PUSH BC
42A5  D5            PUSH DE
42A6  E5            PUSH HL
42A7  FE 01         CP 0x01
42A9  20 14         JR NZ,loc_42BF
42AB  08            EX AF,AF'
42AC  ED 5B 03 4B   LD DE,(drive_blk_a+0x18)
42B0  3A 02 4B      LD A,(drive_blk_a+0x17)
42B3  4F            LD C,A
42B4  18 0C         JR loc_42C2
42B6  08            EX AF,AF'
42B7  ED 5B 1E 4B   LD DE,(drive_blk_b+0x18)
42BB  3A 1D 4B      LD A,(drive_blk_b+0x17)
42BE  4F            LD C,A

loc_42BF:
42BF  06 00         LD B,0x00
42C1  08            EX AF,AF'

loc_42C2:
42C2  CD D5 44      CALL fdc_set_steprate
42C5  E1            POP HL

loc_42C6:
42C6  D1            POP DE
42C7  C1            POP BC
42C8  F1            POP AF
42C9  E6 7F         AND 0x7F
42CB  DD E5         PUSH IX
42CD  C5            PUSH BC
42CE  06 01         LD B,0x01
42D0  CD 90 45      CALL key_decode
42D3  C1            POP BC
42D4  08            EX AF,AF'
42D5  78            LD A,B
42D6  E6 80         AND 0x80
42D8  07            RLCA
42D9  07            RLCA
42DA  07            RLCA
42DB  47            LD B,A
42DC  08            EX AF,AF'

; build+issue FDC SEEK (opcode 0x0F, target cyl in C)
fdc_seek:
42DD  DD 21 73 4A   LD IX,fdc_cmd_buf2
42E1  FE 01         CP 0x01
42E3  20 04         JR NZ,loc_42E9
42E5  DD 21 61 4A   LD IX,fdc_cmd_buf

loc_42E9:
42E9  DD 36 00 0F   LD (IX+0),0x0F
42ED  3A 1E 31      LD A,(drv_active_cfg)
42F0  E6 01         AND 0x01
42F2  CB C7         SET 0,A
42F4  B0            OR B
42F5  47            LD B,A
42F6  DD 70 01      LD (IX+1),B
42F9  DD 71 02      LD (IX+2),C
42FC  DD E5         PUSH IX
42FE  E1            POP HL
42FF  DD E1         POP IX
4301  06 03         LD B,0x03
4303  0E 20         LD C,0x20
4305  FE 01         CP 0x01
4307  F5            PUSH AF
4308  20 02         JR NZ,loc_430C
430A  0E 00         LD C,0x00

loc_430C:
430C  CD 7F 45      CALL fdc_write_bytes
430F  F1            POP AF
4310  C5            PUSH BC
4311  D5            PUSH DE
4312  E5            PUSH HL
4313  FE 01         CP 0x01
4315  ED 5B 1E 4B   LD DE,(drive_blk_b+0x18)
4319  20 04         JR NZ,loc_431F
431B  ED 5B 03 4B   LD DE,(drive_blk_a+0x18)

loc_431F:
431F  06 00         LD B,0x00
4321  0E 01         LD C,0x01
4323  CD D5 44      CALL fdc_set_steprate
4326  E1            POP HL
4327  D1            POP DE
4328  C1            POP BC
4329  C9            RET

; select FDC block (A==1->blkA else blkB) into BC and issue seek command
fdc_seek_sel:
432A  ED 4B 06 4B   LD BC,(drive_blk_b)
432E  FE 01         CP 0x01
4330  20 04         JR NZ,loc_4336
4332  ED 4B EB 4A   LD BC,(drive_blk_a)

loc_4336:
4336  CD 3A 43      CALL fdc_send_seek
4339  C9            RET

; issue FDC seek: enable bus, decode drive, write specify (0x0F)+precomp into cmd block, select result buf
fdc_send_seek:
433A  CD 6E 48      CALL panel_bus_on
433D  E6 7F         AND 0x7F
433F  DD E5         PUSH IX
4341  C5            PUSH BC
4342  06 01         LD B,0x01
4344  CD 90 45      CALL key_decode
4347  C1            POP BC
4348  08            EX AF,AF'
4349  78            LD A,B
434A  E6 80         AND 0x80
434C  07            RLCA
434D  07            RLCA
434E  07            RLCA
434F  47            LD B,A
4350  08            EX AF,AF'
4351  DD 21 73 4A   LD IX,fdc_cmd_buf2
4355  FE 01         CP 0x01
4357  20 04         JR NZ,loc_435D
4359  DD 21 61 4A   LD IX,fdc_cmd_buf

loc_435D:
435D  DD 36 00 0F   LD (IX+0),0x0F
4361  3A 1E 31      LD A,(drv_active_cfg)
4364  E6 01         AND 0x01
4366  CB C7         SET 0,A
4368  B0            OR B
4369  47            LD B,A
436A  DD 70 01      LD (IX+1),B
436D  DD 71 02      LD (IX+2),C
4370  DD E5         PUSH IX
4372  E1            POP HL
4373  DD E1         POP IX
4375  06 03         LD B,0x03
4377  C3 73 3C      JP loc_3C73

; seek both drives to track 45 (0x2D) for alignment test: write specify+seek to FDC 0x10/0x30, wait panel ready
fdc_seek45_both:
437A  F5            PUSH AF
437B  C5            PUSH BC
437C  E5            PUSH HL
437D  DD E5         PUSH IX
437F  DD 21 6A 4A   LD IX,fdc_cmd_buf1
4383  DD 36 00 0F   LD (IX+0),0x0F
4387  DD 36 01 01   LD (IX+1),0x01
438B  DD 36 02 2D   LD (IX+2),0x2D
438F  0E 10         LD C,0x10
4391  06 03         LD B,0x03
4393  DD E5         PUSH IX
4395  E1            POP HL
4396  CD 7F 45      CALL fdc_write_bytes
4399  0E 30         LD C,0x30
439B  06 03         LD B,0x03
439D  DD E5         PUSH IX
439F  E1            POP HL
43A0  CD 7F 45      CALL fdc_write_bytes

loc_43A3:
43A3  DB F0         IN A,(0xF0)  ; panel
43A5  E6 0C         AND 0x0C
43A7  FE 0C         CP 0x0C
43A9  20 F8         JR NZ,loc_43A3
43AB  3E 08         LD A,0x08
43AD  21 6A 4A      LD HL,fdc_cmd_buf1
43B0  77            LD (HL),A
43B1  0E 10         LD C,0x10
43B3  06 01         LD B,0x01
43B5  CD 7F 45      CALL fdc_write_bytes
43B8  3E 08         LD A,0x08
43BA  21 7C 4A      LD HL,fdc_cmd_buf3
43BD  0E 30         LD C,0x30
43BF  77            LD (HL),A
43C0  06 01         LD B,0x01
43C2  CD 7F 45      CALL fdc_write_bytes
43C5  0E 10         LD C,0x10
43C7  06 07         LD B,0x07
43C9  21 8C 4A      LD HL,fdc_result_buf1
43CC  CD F1 46      CALL fdc_read_result
43CF  0E 30         LD C,0x30
43D1  06 07         LD B,0x07
43D3  21 9A 4A      LD HL,fdc_result_buf3
43D6  CD F1 46      CALL fdc_read_result
43D9  DD E1         POP IX
43DB  E1            POP HL
43DC  C1            POP BC
43DD  F1            POP AF
43DE  C9            RET
43DF  F5            PUSH AF
43E0  3E 0F         LD A,0x0F
43E2  D3 8D         OUT (0x8D),A  ; dma_mclr
43E4  D3 8F         OUT (0x8F),A  ; dma_wrmask
43E6  3E A0         LD A,0xA0
43E8  D3 88         OUT (0x88),A  ; dma_cmd
43EA  F1            POP AF
43EB  C9            RET

; read {addr,count} descriptor from low-RAM table, arm the DMA channel (0x4401)
dma_arm_desc:
43EC  F3            DI
43ED  ED 73 54 4A   LD (fdc_saved_sp),SP
43F1  DD E5         PUSH IX
43F3  D1            POP DE
43F4  19            ADD HL,DE
43F5  F9            LD SP,HL
43F6  E1            POP HL
43F7  D1            POP DE
43F8  ED 7B 54 4A   LD SP,(fdc_saved_sp)
43FC  FB            EI
43FD  CD 01 44      CALL dma_arm_channel
4400  C9            RET

; program one 8237 DMA channel (addr/count/mode) from a descriptor
dma_arm_channel:
4401  C5            PUSH BC
4402  F5            PUSH AF
4403  CB 7F         BIT 7,A
4405  CA 1B 44      JP Z,loc_441B
4408  0E 86         LD C,0x86
440A  FE 81         CP 0x81
440C  C2 16 44      JP NZ,loc_4416
440F  3E 02         LD A,0x02
4411  0E 84         LD C,0x84
4413  C3 2E 44      JP loc_442E

loc_4416:
4416  3E 03         LD A,0x03
4418  C3 2E 44      JP loc_442E

loc_441B:
441B  0E 82         LD C,0x82
441D  FE 01         CP 0x01
441F  D3 8C         OUT (0x8C),A  ; dma_clrff
4421  C2 2A 44      JP NZ,loc_442A
4424  AF            XOR A
4425  0E 80         LD C,0x80
4427  C3 2E 44      JP loc_442E

loc_442A:
442A  3E 01         LD A,0x01
442C  0E 82         LD C,0x82

loc_442E:
442E  B0            OR B
442F  D3 8A         OUT (0x8A),A  ; dma_mask1
4431  D3 8B         OUT (0x8B),A  ; dma_mode
4433  7D            LD A,L
4434  ED 79         OUT (C),A
4436  7C            LD A,H
4437  ED 79         OUT (C),A
4439  0C            INC C
443A  7B            LD A,E
443B  ED 79         OUT (C),A
443D  7A            LD A,D
443E  ED 79         OUT (C),A
4440  C1            POP BC
4441  CB 78         BIT 7,B
4443  CA 4F 44      JP Z,loc_444F
4446  CB 40         BIT 0,B
4448  06 03         LD B,0x03
444A  CA 51 44      JP Z,loc_4451
444D  06 04         LD B,0x04

loc_444F:
444F  CB 38         SRL B

loc_4451:
4451  AF            XOR A
4452  B0            OR B
4453  D3 8A         OUT (0x8A),A  ; dma_mask1
4455  C1            POP BC
4456  C9            RET

; reset+reload 8237 channels 0/1 from the drive-block DMA descriptors
dma_setup:
4457  C5            PUSH BC
4458  3E 0F         LD A,0x0F
445A  D3 8F         OUT (0x8F),A  ; dma_wrmask
445C  3E 08         LD A,0x08
445E  D3 8B         OUT (0x8B),A  ; dma_mode
4460  3C            INC A
4461  D3 8B         OUT (0x8B),A  ; dma_mode
4463  D3 8C         OUT (0x8C),A  ; dma_clrff
4465  21 F3 4A      LD HL,drive_blk_a+0x8
4468  0E 80         LD C,0x80
446A  06 02         LD B,0x02
446C  ED B3         OTIR
446E  0C            INC C
446F  06 02         LD B,0x02
4471  ED B3         OTIR
4473  D3 8C         OUT (0x8C),A  ; dma_clrff
4475  21 0E 4B      LD HL,drive_blk_b+0x8
4478  0E 82         LD C,0x82
447A  06 02         LD B,0x02
447C  ED B3         OTIR
447E  0C            INC C
447F  06 02         LD B,0x02
4481  ED B3         OTIR
4483  3E 0C         LD A,0x0C
4485  D3 8F         OUT (0x8F),A  ; dma_wrmask
4487  C1            POP BC
4488  C9            RET

; compute DMA transfer count: index sector-size table 0x4AA6[A*2], 16-bit multiply by BC, return count-1 in DE
fdc_dma_setup:
4489  F5            PUSH AF
448A  DD E5         PUSH IX
448C  C5            PUSH BC
448D  E5            PUSH HL
448E  D5            PUSH DE
448F  DD 21 A6 4A   LD IX,sector_size_tbl
4493  07            RLCA
4494  5F            LD E,A
4495  16 00         LD D,0x00
4497  DD 19         ADD IX,DE
4499  DD 6E 00      LD L,(IX+0)
449C  DD 66 01      LD H,(IX+1)
449F  D1            POP DE
44A0  06 10         LD B,0x10
44A2  4A            LD C,D
44A3  7B            LD A,E
44A4  EB            EX DE,HL
44A5  21 00 00      LD HL,0x0000

loc_44A8:
44A8  CB 39         SRL C
44AA  CB 1F         RR A
44AC  30 01         JR NC,loc_44AF
44AE  19            ADD HL,DE

loc_44AF:
44AF  EB            EX DE,HL
44B0  29            ADD HL,HL
44B1  EB            EX DE,HL
44B2  10 F4         DJNZ loc_44A8
44B4  2B            DEC HL
44B5  54            LD D,H
44B6  5D            LD E,L
44B7  E1            POP HL
44B8  C1            POP BC
44B9  DD E1         POP IX
44BB  F1            POP AF
44BC  C9            RET
44BD  F5            PUSH AF
44BE  C5            PUSH BC
44BF  3E 0A         LD A,0x0A
44C1  D3 40         OUT (0x40),A  ; drv_lat0
44C3  D3 60         OUT (0x60),A  ; drv_lat2
44C5  F5            PUSH AF
44C6  06 0C         LD B,0x0C
44C8  CD DB 48      CALL delay_djnz
44CB  F1            POP AF
44CC  F6 04         OR 0x04
44CE  D3 40         OUT (0x40),A  ; drv_lat0
44D0  D3 60         OUT (0x60),A  ; drv_lat2
44D2  C1            POP BC
44D3  F1            POP AF
44D4  C9            RET

; pack FDC specify bytes: SRT|E->0x4A5C, D<<1|B bit0->0x4A5D; A bit0 selects alt path
fdc_set_steprate:
44D5  F5            PUSH AF
44D6  79            LD A,C
44D7  ED 44         NEG
44D9  E6 0F         AND 0x0F
44DB  4F            LD C,A
44DC  CB 21         SLA C
44DE  CB 21         SLA C
44E0  CB 21         SLA C
44E2  CB 21         SLA C
44E4  7B            LD A,E
44E5  E6 0F         AND 0x0F
44E7  B1            OR C
44E8  32 5C 4A      LD (fdc_drv_state+0x3),A
44EB  CB 22         SLA D
44ED  78            LD A,B
44EE  E6 01         AND 0x01
44F0  B2            OR D
44F1  32 5D 4A      LD (fdc_drv_state+0x4),A
44F4  F1            POP AF
44F5  CB 47         BIT 0,A
44F7  28 1A         JR Z,loc_4513
44F9  0E 00         LD C,0x00
44FB  21 5B 4A      LD HL,fdc_drv_state+0x2
44FE  06 03         LD B,0x03
4500  C5            PUSH BC
4501  E5            PUSH HL
4502  CD 7F 45      CALL fdc_write_bytes
4505  E1            POP HL
4506  C1            POP BC
4507  0E 10         LD C,0x10
4509  CD 7F 45      CALL fdc_write_bytes
450C  3A 01 4B      LD A,(drive_blk_a+0x16)
450F  D3 50         OUT (0x50),A  ; drv_lat1
4511  18 18         JR loc_452B

loc_4513:
4513  0E 20         LD C,0x20
4515  21 5B 4A      LD HL,fdc_drv_state+0x2
4518  06 03         LD B,0x03
451A  C5            PUSH BC
451B  E5            PUSH HL
451C  CD 7F 45      CALL fdc_write_bytes
451F  E1            POP HL
4520  C1            POP BC
4521  0E 30         LD C,0x30
4523  CD 7F 45      CALL fdc_write_bytes
4526  3A 1C 4B      LD A,(drive_blk_b+0x16)
4529  D3 70         OUT (0x70),A  ; drv_lat3

loc_452B:
452B  C9            RET

; issue Sense-Interrupt-Status (0x08) to all 4 FDCs and read their 7-byte result phases
fdc_senseint_all:
452C  C5            PUSH BC
452D  E5            PUSH HL
452E  0E 00         LD C,0x00
4530  21 61 4A      LD HL,fdc_cmd_buf
4533  CD 71 45      CALL fdc_senseint_send
4536  0E 10         LD C,0x10
4538  21 6A 4A      LD HL,fdc_cmd_buf1
453B  CD 71 45      CALL fdc_senseint_send
453E  0E 20         LD C,0x20
4540  21 73 4A      LD HL,fdc_cmd_buf2
4543  CD 71 45      CALL fdc_senseint_send
4546  0E 30         LD C,0x30
4548  21 7C 4A      LD HL,fdc_cmd_buf3
454B  CD 71 45      CALL fdc_senseint_send
454E  0E 00         LD C,0x00
4550  21 85 4A      LD HL,fdc_result_buf
4553  CD 79 45      CALL fdc_result_read7
4556  0E 10         LD C,0x10
4558  21 8C 4A      LD HL,fdc_result_buf1
455B  CD 79 45      CALL fdc_result_read7
455E  0E 20         LD C,0x20
4560  21 93 4A      LD HL,fdc_result_buf2
4563  CD 79 45      CALL fdc_result_read7
4566  0E 30         LD C,0x30
4568  21 9A 4A      LD HL,fdc_result_buf3
456B  CD 79 45      CALL fdc_result_read7
456E  E1            POP HL
456F  C1            POP BC
4570  C9            RET

; write Sense-Interrupt (0x08) command byte to FDC at port C
fdc_senseint_send:
4571  06 01         LD B,0x01
4573  36 08         LD (HL),0x08
4575  CD 7F 45      CALL fdc_write_bytes
4578  C9            RET

; read 7 result-phase bytes from an FDC into buffer HL
fdc_result_read7:
4579  06 07         LD B,0x07
457B  CD F1 46      CALL fdc_read_result
457E  C9            RET

; stream B command/data bytes to an FDC (poll MSR RQM/DIO before each)
fdc_write_bytes:
457F  ED 78         IN A,(C)
4581  E6 C0         AND 0xC0
4583  FE 80         CP 0x80
4585  C2 7F 45      JP NZ,fdc_write_bytes
4588  0C            INC C
4589  ED A3         OUTI
458B  0D            DEC C
458C  04            INC B
458D  10 F0         DJNZ fdc_write_bytes
458F  C9            RET

; build FDC IRQ/DMA enable mask in fdc_irq_bits from drive-select (A bit0, B bit0, side L bit7)
key_decode:
4590  F5            PUSH AF
4591  E5            PUSH HL
4592  CB 47         BIT 0,A
4594  6F            LD L,A
4595  3A A1 4A      LD A,(fdc_result_save)
4598  28 1F         JR Z,loc_45B9
459A  CB 18         RR B
459C  CB 7D         BIT 7,L
459E  28 09         JR Z,loc_45A9
45A0  30 10         JR NC,loc_45B2
45A2  F6 02         OR 0x02
45A4  E6 DF         AND 0xDF
45A6  C3 D5 45      JP loc_45D5

loc_45A9:
45A9  30 07         JR NC,loc_45B2
45AB  F6 08         OR 0x08
45AD  E6 7D         AND 0x7D
45AF  C3 D5 45      JP loc_45D5

loc_45B2:
45B2  F6 0A         OR 0x0A
45B4  E6 5F         AND 0x5F
45B6  C3 D5 45      JP loc_45D5

loc_45B9:
45B9  CB 18         RR B
45BB  CB 7D         BIT 7,L
45BD  28 09         JR Z,loc_45C8
45BF  30 10         JR NC,loc_45D1
45C1  F6 01         OR 0x01
45C3  E6 EF         AND 0xEF
45C5  C3 D5 45      JP loc_45D5

loc_45C8:
45C8  30 07         JR NC,loc_45D1
45CA  F6 04         OR 0x04
45CC  E6 BE         AND 0xBE
45CE  C3 D5 45      JP loc_45D5

loc_45D1:
45D1  F6 05         OR 0x05
45D3  E6 AF         AND 0xAF

loc_45D5:
45D5  32 A1 4A      LD (fdc_result_save),A
45D8  E1            POP HL
45D9  F1            POP AF
45DA  C9            RET

; IM1 handler: read which FDC interrupted (0x94/0xF0), pull 4x 7-byte result phases
fdc_isr:
45DB  F5            PUSH AF
45DC  C5            PUSH BC
45DD  D5            PUSH DE
45DE  E5            PUSH HL
45DF  DD E5         PUSH IX
45E1  DD 21 A1 4A   LD IX,fdc_result_save
45E5  DB 94         IN A,(0x94)  ; status_in
45E7  E6 30         AND 0x30
45E9  FE 30         CP 0x30
45EB  C2 29 46      JP NZ,loc_4629
45EE  DB F0         IN A,(0xF0)  ; panel
45F0  E6 0C         AND 0x0C
45F2  FE 0C         CP 0x0C
45F4  28 33         JR Z,loc_4629
45F6  0E 20         LD C,0x20
45F8  06 07         LD B,0x07
45FA  21 93 4A      LD HL,fdc_result_buf2
45FD  CD F1 46      CALL fdc_read_result
4600  0E 30         LD C,0x30
4602  06 07         LD B,0x07
4604  21 9A 4A      LD HL,fdc_result_buf3
4607  CD F1 46      CALL fdc_read_result
460A  0E 00         LD C,0x00
460C  06 07         LD B,0x07
460E  21 85 4A      LD HL,fdc_result_buf
4611  CD F1 46      CALL fdc_read_result
4614  0E 10         LD C,0x10
4616  06 07         LD B,0x07
4618  21 8C 4A      LD HL,fdc_result_buf1
461B  CD F1 46      CALL fdc_read_result
461E  DD 7E 00      LD A,(IX+0)
4621  F6 F0         OR 0xF0
4623  DD 77 00      LD (IX+0),A
4626  C3 E9 46      JP loc_46E9

loc_4629:
4629  CB 67         BIT 4,A
462B  20 60         JR NZ,loc_468D

; ISR seek-complete path: if FDC2 result pending re-issue Sense-Int to 0x20 (and 0x30 if panel bit3), read results
fdc_isr_sense_int:
462D  3A 73 4A      LD A,(fdc_cmd_buf2)
4630  FE 07         CP 0x07
4632  28 04         JR Z,loc_4638
4634  FE 0F         CP 0x0F
4636  20 2F         JR NZ,loc_4667

loc_4638:
4638  3E 08         LD A,0x08
463A  21 73 4A      LD HL,fdc_cmd_buf2
463D  77            LD (HL),A
463E  0E 20         LD C,0x20
4640  06 01         LD B,0x01
4642  CD 7F 45      CALL fdc_write_bytes
4645  DB F0         IN A,(0xF0)  ; panel
4647  CB 5F         BIT 3,A
4649  CA 67 46      JP Z,loc_4667
464C  3E 08         LD A,0x08
464E  21 7C 4A      LD HL,fdc_cmd_buf3
4651  77            LD (HL),A
4652  0E 30         LD C,0x30
4654  06 01         LD B,0x01
4656  CD 7F 45      CALL fdc_write_bytes
4659  0E 30         LD C,0x30
465B  06 07         LD B,0x07
465D  21 9A 4A      LD HL,fdc_result_buf3
4660  CD F1 46      CALL fdc_read_result
4663  DD CB 00 E6   SET 4,(IX+0)

loc_4667:
4667  0E 20         LD C,0x20
4669  06 07         LD B,0x07
466B  21 93 4A      LD HL,fdc_result_buf2
466E  CD F1 46      CALL fdc_read_result
4671  DD CB 00 F6   SET 6,(IX+0)
4675  DD CB 00 46   BIT 0,(IX+0)
4679  CA E9 46      JP Z,loc_46E9
467C  0E 30         LD C,0x30
467E  06 07         LD B,0x07
4680  21 9A 4A      LD HL,fdc_result_buf3
4683  CD F1 46      CALL fdc_read_result
4686  DD CB 00 E6   SET 4,(IX+0)
468A  C3 E9 46      JP loc_46E9

loc_468D:
468D  3A 61 4A      LD A,(fdc_cmd_buf)
4690  FE 07         CP 0x07
4692  28 04         JR Z,loc_4698
4694  FE 0F         CP 0x0F
4696  20 2F         JR NZ,loc_46C7

loc_4698:
4698  3E 08         LD A,0x08
469A  21 61 4A      LD HL,fdc_cmd_buf
469D  77            LD (HL),A
469E  0E 00         LD C,0x00
46A0  06 01         LD B,0x01
46A2  CD 7F 45      CALL fdc_write_bytes
46A5  DB F0         IN A,(0xF0)  ; panel
46A7  CB 57         BIT 2,A
46A9  CA C7 46      JP Z,loc_46C7
46AC  3E 08         LD A,0x08
46AE  21 6A 4A      LD HL,fdc_cmd_buf1
46B1  77            LD (HL),A
46B2  0E 10         LD C,0x10
46B4  06 01         LD B,0x01
46B6  CD 7F 45      CALL fdc_write_bytes
46B9  0E 10         LD C,0x10
46BB  06 07         LD B,0x07
46BD  21 8C 4A      LD HL,fdc_result_buf1
46C0  CD F1 46      CALL fdc_read_result
46C3  DD CB 00 EE   SET 5,(IX+0)

loc_46C7:
46C7  0E 00         LD C,0x00
46C9  06 07         LD B,0x07
46CB  21 85 4A      LD HL,fdc_result_buf
46CE  CD F1 46      CALL fdc_read_result
46D1  DD CB 00 FE   SET 7,(IX+0)
46D5  DD CB 00 4E   BIT 1,(IX+0)
46D9  28 0E         JR Z,loc_46E9
46DB  0E 10         LD C,0x10
46DD  06 07         LD B,0x07
46DF  21 8C 4A      LD HL,fdc_result_buf1
46E2  CD F1 46      CALL fdc_read_result
46E5  DD CB 00 EE   SET 5,(IX+0)

loc_46E9:
46E9  DD E1         POP IX
46EB  E1            POP HL
46EC  D1            POP DE
46ED  C1            POP BC
46EE  F1            POP AF
46EF  FB            EI
46F0  C9            RET

; read FDC result phase (poll RQM/DIO), up to B bytes
fdc_read_result:
46F1  ED 78         IN A,(C)
46F3  CB 7F         BIT 7,A
46F5  CA F1 46      JP Z,fdc_read_result
46F8  CB 77         BIT 6,A
46FA  28 07         JR Z,loc_4703
46FC  0C            INC C
46FD  ED A2         INI
46FF  0D            DEC C
4700  04            INC B
4701  10 EE         DJNZ fdc_read_result

loc_4703:
4703  C9            RET

; poll FDC done flag (irq_bits bit7 drive0 / bit6 drive2 per A bit0), dispatch to result read
fdc_poll_result:
4704  DD E5         PUSH IX
4706  FD E5         PUSH IY
4708  E5            PUSH HL
4709  DD 21 A1 4A   LD IX,fdc_result_save
470D  CB 47         BIT 0,A
470F  28 0E         JR Z,loc_471F
4711  FD 21 85 4A   LD IY,fdc_result_buf
4715  DD CB 00 7E   BIT 7,(IX+0)
4719  CA 18 48      JP Z,loc_4818
471C  C3 87 47      JP loc_4787

loc_471F:
471F  FD 21 93 4A   LD IY,fdc_result_buf2
4723  DD CB 00 76   BIT 6,(IX+0)
4727  CA 18 48      JP Z,loc_4818
472A  C3 F6 47      JP loc_47F6

; poll for FDC operation complete (or timeout)
fdc_poll_complete:
472D  DD E5         PUSH IX
472F  FD E5         PUSH IY
4731  E5            PUSH HL
4732  DD 21 A1 4A   LD IX,fdc_result_save
4736  CB 47         BIT 0,A
4738  28 70         JR Z,loc_47AA
473A  FD 21 85 4A   LD IY,fdc_result_buf
473E  DD CB 00 4E   BIT 1,(IX+0)
4742  CA 80 47      JP Z,loc_4780
4745  DB F0         IN A,(0xF0)  ; panel
4747  CB 57         BIT 2,A
4749  CA 18 48      JP Z,loc_4818
474C  21 5A 4A      LD HL,fdc_drv_state+0x1
474F  CB 56         BIT 2,(HL)
4751  20 07         JR NZ,loc_475A
4753  3E 19         LD A,0x19
4755  CD F5 4B      CALL error_report
4758  18 04         JR loc_475E

loc_475A:
475A  CB 46         BIT 0,(HL)
475C  20 0E         JR NZ,loc_476C

loc_475E:
475E  3E 0E         LD A,0x0E
4760  D3 9C         OUT (0x9C),A  ; ctrl_latch
4762  00            NOP
4763  00            NOP
4764  00            NOP
4765  00            NOP
4766  00            NOP
4767  00            NOP
4768  3E 0F         LD A,0x0F
476A  D3 9C         OUT (0x9C),A  ; ctrl_latch

loc_476C:
476C  DD CB 00 7E   BIT 7,(IX+0)
4770  C2 9D 47      JP NZ,loc_479D
4773  CD 57 48      CALL timeout_check
4776  38 02         JR C,loc_477A
4778  18 F2         JR loc_476C

loc_477A:
477A  AF            XOR A
477B  D6 01         SUB 0x01
477D  C3 09 48      JP loc_4809

loc_4780:
4780  DD CB 00 7E   BIT 7,(IX+0)
4784  CA 18 48      JP Z,loc_4818

loc_4787:
4787  DD CB 00 4E   BIT 1,(IX+0)
478B  20 0A         JR NZ,loc_4797

loc_478D:
478D  FD 7E 00      LD A,(IY+0)
4790  07            RLCA
4791  DA 09 48      JP C,loc_4809
4794  07            RLCA
4795  18 72         JR loc_4809

loc_4797:
4797  DD CB 00 6E   BIT 5,(IX+0)
479B  28 7B         JR Z,loc_4818

loc_479D:
479D  3A 8C 4A      LD A,(fdc_result_buf1)

loc_47A0:
47A0  FD B6 00      OR (IY+0)
47A3  07            RLCA
47A4  38 63         JR C,loc_4809
47A6  07            RLCA
47A7  C3 09 48      JP loc_4809

loc_47AA:
47AA  FD 21 93 4A   LD IY,fdc_result_buf2
47AE  DD CB 00 46   BIT 0,(IX+0)
47B2  CA F0 47      JP Z,loc_47F0
47B5  DB F0         IN A,(0xF0)  ; panel
47B7  CB 5F         BIT 3,A
47B9  CA 18 48      JP Z,loc_4818
47BC  21 5A 4A      LD HL,fdc_drv_state+0x1
47BF  CB 5E         BIT 3,(HL)
47C1  20 07         JR NZ,loc_47CA
47C3  3E 19         LD A,0x19
47C5  CD F5 4B      CALL error_report
47C8  18 04         JR loc_47CE

loc_47CA:
47CA  CB 4E         BIT 1,(HL)
47CC  20 0D         JR NZ,loc_47DB

loc_47CE:
47CE  3E 0E         LD A,0x0E
47D0  D3 9C         OUT (0x9C),A  ; ctrl_latch
47D2  00            NOP
47D3  00            NOP
47D4  00            NOP
47D5  00            NOP
47D6  00            NOP
47D7  00            NOP
47D8  3C            INC A
47D9  D3 9C         OUT (0x9C),A  ; ctrl_latch

loc_47DB:
47DB  DD CB 00 76   BIT 6,(IX+0)
47DF  C2 04 48      JP NZ,loc_4804
47E2  CD 57 48      CALL timeout_check
47E5  38 03         JR C,loc_47EA
47E7  C3 DB 47      JP loc_47DB

loc_47EA:
47EA  AF            XOR A
47EB  D6 01         SUB 0x01
47ED  C3 09 48      JP loc_4809

loc_47F0:
47F0  DD CB 00 76   BIT 6,(IX+0)
47F4  28 22         JR Z,loc_4818

loc_47F6:
47F6  DD CB 00 46   BIT 0,(IX+0)
47FA  20 02         JR NZ,loc_47FE
47FC  18 8F         JR loc_478D

loc_47FE:
47FE  DD CB 00 66   BIT 4,(IX+0)
4802  28 14         JR Z,loc_4818

loc_4804:
4804  3A 9A 4A      LD A,(fdc_result_buf3)
4807  18 97         JR loc_47A0

loc_4809:
4809  3E 01         LD A,0x01
480B  3C            INC A
480C  3E 00         LD A,0x00
480E  30 08         JR NC,loc_4818
4810  D5            PUSH DE
4811  F5            PUSH AF
4812  CD 93 48      CALL fdc_error_decode
4815  F1            POP AF
4816  7B            LD A,E
4817  D1            POP DE

loc_4818:
4818  E1            POP HL
4819  FD E1         POP IY
481B  DD E1         POP IX
481D  C9            RET

; fast-fill banked DRAM (bank B via 0xB0, addr 0x8000|HL+4*D) via SP-swap block writes, count A&0x7F
dram_stack_fill:
481E  C5            PUSH BC
481F  0E B0         LD C,0xB0
4821  ED 41         OUT (C),B
4823  4A            LD C,D
4824  CB 21         SLA C
4826  CB 21         SLA C
4828  06 00         LD B,0x00
482A  09            ADD HL,BC
482B  CB FC         SET 7,H
482D  C1            POP BC
482E  E6 7F         AND 0x7F
4830  47            LD B,A
4831  7B            LD A,E
4832  5A            LD E,D
4833  57            LD D,A
4834  F3            DI
4835  ED 73 54 4A   LD (fdc_saved_sp),SP
4839  F9            LD SP,HL
483A  60            LD H,B
483B  69            LD L,C
483C  43            LD B,E

loc_483D:
483D  D5            PUSH DE
483E  E5            PUSH HL
483F  1D            DEC E
4840  10 FB         DJNZ loc_483D
4842  ED 7B 54 4A   LD SP,(fdc_saved_sp)
4846  FB            EI
4847  C9            RET

; start command timeout timer (8253 counter 2)
timeout_start:
4848  F5            PUSH AF
4849  3E B4         LD A,0xB4
484B  D3 AC         OUT (0xAC),A  ; pit_ctrl
484D  3E FF         LD A,0xFF
484F  D3 A8         OUT (0xA8),A  ; pit_c2
4851  3E FF         LD A,0xFF
4853  D3 A8         OUT (0xA8),A  ; pit_c2
4855  F1            POP AF
4856  C9            RET

; check/tick the command timeout timer
timeout_check:
4857  C5            PUSH BC
4858  47            LD B,A
4859  3E 80         LD A,0x80
485B  D3 AC         OUT (0xAC),A  ; pit_ctrl
485D  DB A8         IN A,(0xA8)  ; pit_c2
485F  DB A8         IN A,(0xA8)  ; pit_c2
4861  D6 01         SUB 0x01
4863  78            LD A,B
4864  C1            POP BC
4865  C9            RET

; save data-rate (A) and precomp (B) values to 0x4B89/0x4B8A
store_rate_precomp:
4866  32 89 4B      LD (fdc_rate_reg),A
4869  78            LD A,B
486A  32 8A 4B      LD (fdc_precomp_reg),A
486D  C9            RET

; enable FDC data bus: set panel port 0xF0 bit0, update shadow 0x4A58
panel_bus_on:
486E  F5            PUSH AF
486F  3A 58 4A      LD A,(panel_shadow)
4872  F6 01         OR 0x01

loc_4874:
4874  32 58 4A      LD (panel_shadow),A
4877  D3 F0         OUT (0xF0),A  ; panel
4879  F1            POP AF
487A  C9            RET
487B  F5            PUSH AF
487C  3A 58 4A      LD A,(panel_shadow)
487F  E6 FE         AND 0xFE
4881  18 F1         JR loc_4874

; select head/side 0: clear panel bit7 (0x4A58), output to 0xF0
panel_sel_lo:
4883  F5            PUSH AF
4884  3A 58 4A      LD A,(panel_shadow)
4887  E6 7F         AND 0x7F
4889  18 E9         JR loc_4874

; select head/side 1: set panel bit7 (0x4A58), output to 0xF0
panel_sel_hi:
488B  F5            PUSH AF
488C  3A 58 4A      LD A,(panel_shadow)
488F  F6 80         OR 0x80
4891  18 E1         JR loc_4874

; decode ST0/ST1/ST2 -> error class (CRC/writeprot/seek/notready/overrun)
fdc_error_decode:
4893  1E 80         LD E,0x80
4895  FD CB 01 6E   BIT 5,(IY+1)
4899  C0            RET NZ
489A  FD CB 01 56   BIT 2,(IY+1)
489E  C0            RET NZ
489F  FD CB 01 46   BIT 0,(IY+1)
48A3  C0            RET NZ
48A4  FD CB 02 6E   BIT 5,(IY+2)
48A8  C0            RET NZ
48A9  CB 3B         SRL E
48AB  FD CB 02 76   BIT 6,(IY+2)
48AF  C0            RET NZ
48B0  CB 3B         SRL E
48B2  FD CB 01 66   BIT 4,(IY+1)
48B6  C0            RET NZ
48B7  CB 3B         SRL E
48B9  FD CB 01 4E   BIT 1,(IY+1)
48BD  C0            RET NZ
48BE  CB 3B         SRL E
48C0  FD CB 02 66   BIT 4,(IY+2)
48C4  C0            RET NZ
48C5  FD CB 02 4E   BIT 1,(IY+2)
48C9  C0            RET NZ
48CA  CB 3B         SRL E
48CC  FD CB 01 7E   BIT 7,(IY+1)
48D0  C0            RET NZ
48D1  CB 3B         SRL E
48D3  FD CB 00 66   BIT 4,(IY+0)
48D7  C0            RET NZ
48D8  1E FF         LD E,0xFF
48DA  C9            RET

; busy-wait delay: DJNZ loop for B iterations
delay_djnz:
48DB  10 FE         DJNZ delay_djnz
48DD  C9            RET

; read 8253 counter-1 16-bit (latch cmd 0x44 to 0xAC, read lo/hi from 0xA4), returns HL
read_timer_c1:
48DE  F5            PUSH AF
48DF  3E 44         LD A,0x44
48E1  D3 AC         OUT (0xAC),A  ; pit_ctrl
48E3  DB A4         IN A,(0xA4)  ; pit_c1
48E5  6F            LD L,A
48E6  DB A4         IN A,(0xA4)  ; pit_c1
48E8  67            LD H,A
48E9  F1            POP AF
48EA  C9            RET

; set FDC command-mode flags in 0x4A5A bits0-3 from op_word nibble & rd_submode/unit_sel
fdc_set_cmdmode:
48EB  E5            PUSH HL
48EC  21 5A 4A      LD HL,fdc_drv_state+0x1
48EF  CB D6         SET 2,(HL)
48F1  CB DE         SET 3,(HL)
48F3  08            EX AF,AF'
48F4  3A 34 31      LD A,(op_word)
48F7  E6 0F         AND 0x0F
48F9  08            EX AF,AF'
48FA  FE 01         CP 0x01
48FC  38 22         JR C,loc_4920
48FE  28 3E         JR Z,loc_493E
4900  08            EX AF,AF'
4901  F5            PUSH AF
4902  3A 37 31      LD A,(unit_sel)
4905  E6 C0         AND 0xC0
4907  FE 80         CP 0x80
4909  20 00         JR NZ,loc_490B

loc_490B:
490B  F1            POP AF
490C  FE 07         CP 0x07
490E  C2 14 49      JP NZ,loc_4914
4911  3A 4F 31      LD A,(rd_submode)

loc_4914:
4914  FE 05         CP 0x05
4916  CB C6         SET 0,(HL)
4918  CB CE         SET 1,(HL)
491A  20 3E         JR NZ,loc_495A
491C  CB 86         RES 0,(HL)
491E  18 38         JR loc_4958

loc_4920:
4920  08            EX AF,AF'
4921  F5            PUSH AF
4922  3A 37 31      LD A,(unit_sel)
4925  E6 C0         AND 0xC0
4927  FE 80         CP 0x80
4929  20 00         JR NZ,loc_492B

loc_492B:
492B  F1            POP AF
492C  FE 07         CP 0x07
492E  C2 34 49      JP NZ,loc_4934
4931  3A 4F 31      LD A,(rd_submode)

loc_4934:
4934  FE 05         CP 0x05
4936  CB C6         SET 0,(HL)
4938  20 20         JR NZ,loc_495A
493A  CB 86         RES 0,(HL)
493C  18 1C         JR loc_495A

loc_493E:
493E  08            EX AF,AF'
493F  F5            PUSH AF
4940  3A 37 31      LD A,(unit_sel)
4943  E6 C0         AND 0xC0
4945  FE 80         CP 0x80
4947  20 00         JR NZ,loc_4949

loc_4949:
4949  F1            POP AF
494A  FE 07         CP 0x07
494C  C2 52 49      JP NZ,loc_4952
494F  3A 4F 31      LD A,(rd_submode)

loc_4952:
4952  FE 05         CP 0x05
4954  CB CE         SET 1,(HL)
4956  20 02         JR NZ,loc_495A

loc_4958:
4958  CB 8E         RES 1,(HL)

loc_495A:
495A  E1            POP HL
495B  C9            RET
495C  37            SCF
495D  3F            CCF
495E  ED 42         SBC HL,BC
4960  E5            PUSH HL
4961  30 08         JR NC,loc_496B

loc_4963:
4963  CD DE 48      CALL read_timer_c1
4966  3F            CCF
4967  ED 52         SBC HL,DE
4969  38 F8         JR C,loc_4963

loc_496B:
496B  D1            POP DE

loc_496C:
496C  CD DE 48      CALL read_timer_c1
496F  ED 52         SBC HL,DE
4971  30 F9         JR NC,loc_496C
4973  C9            RET

; check drive ready: sense drive status, test status bit6 (ready line)
fdc_drive_ready:
4974  E5            PUSH HL
4975  C5            PUSH BC
4976  D5            PUSH DE
4977  CD 9E 49      CALL fdc_sense_drive
497A  CB 77         BIT 6,A
497C  7B            LD A,E
497D  D1            POP DE
497E  C1            POP BC
497F  E1            POP HL
4980  C9            RET

; report drive-not-ready error (code 0x96) then re-sense drive status
fdc_err_notready:
4981  E5            PUSH HL
4982  D5            PUSH DE
4983  C5            PUSH BC
4984  3E 96         LD A,0x96
4986  CD F5 4B      CALL error_report
4989  CD 90 49      CALL fdc_sense_ready
498C  C1            POP BC
498D  D1            POP DE
498E  E1            POP HL
498F  C9            RET

; sense drive ready: read status, XOR 0x10, test bit4; Z=ready
fdc_sense_ready:
4990  E5            PUSH HL
4991  C5            PUSH BC
4992  D5            PUSH DE
4993  CD 9E 49      CALL fdc_sense_drive
4996  EE 10         XOR 0x10
4998  CB 67         BIT 4,A
499A  D1            POP DE
499B  C1            POP BC
499C  E1            POP HL
499D  C9            RET

; FDC Sense Drive Status (cmd 0x04): build unit byte from bit0 of drv_active_cfg, exec, read ST3
fdc_sense_drive:
499E  5F            LD E,A
499F  3A 1E 31      LD A,(drv_active_cfg)
49A2  E6 01         AND 0x01
49A4  CB 47         BIT 0,A
49A6  20 04         JR NZ,loc_49AC
49A8  CB C7         SET 0,A
49AA  CB 27         SLA A

loc_49AC:
49AC  0E 00         LD C,0x00
49AE  CB 47         BIT 0,A
49B0  20 02         JR NZ,loc_49B4
49B2  0E 20         LD C,0x20

loc_49B4:
49B4  C5            PUSH BC
49B5  32 5F 4A      LD (fdc_drv_state+0x6),A
49B8  3E 04         LD A,0x04
49BA  32 5E 4A      LD (fdc_drv_state+0x5),A
49BD  21 5E 4A      LD HL,fdc_drv_state+0x5
49C0  06 02         LD B,0x02
49C2  CD 7F 45      CALL fdc_write_bytes
49C5  C1            POP BC
49C6  06 07         LD B,0x07
49C8  21 60 4A      LD HL,fdc_drv_state+0x7
49CB  CD F1 46      CALL fdc_read_result
49CE  3A 60 4A      LD A,(fdc_drv_state+0x7)
49D1  C9            RET

; init 4-byte FDC cmd/DMA descriptor at IX to {0x41,0x02,0x00,0x00}
fdc_result_reset:
49D2  DD 36 00 41   LD (IX+0),0x41
49D6  DD 36 01 02   LD (IX+1),0x02
49DA  DD 36 02 00   LD (IX+2),0x00
49DE  DD 36 03 00   LD (IX+3),0x00
49E2  C9            RET

; beep the piezo buzzer A times (port 0xF0 bit3, active-low), ~13ms delay between (via buzzer_pulse)
buzzer_beep:
49E3  F5            PUSH AF
49E4  C5            PUSH BC
49E5  47            LD B,A

loc_49E6:
49E6  CD FC 49      CALL buzzer_pulse
49E9  10 02         DJNZ loc_49ED
49EB  18 0C         JR loc_49F9

loc_49ED:
49ED  C5            PUSH BC
49EE  01 00 68      LD BC,0x6800

loc_49F1:
49F1  0B            DEC BC
49F2  79            LD A,C
49F3  B0            OR B
49F4  20 FB         JR NZ,loc_49F1
49F6  C1            POP BC
49F7  18 ED         JR loc_49E6

loc_49F9:
49F9  C1            POP BC
49FA  F1            POP AF
49FB  C9            RET

; one buzzer pulse: drive 0xF0 bit3 low ~13ms then high (audible click), keep shadow 0x4A58 in sync
buzzer_pulse:
49FC  C5            PUSH BC
49FD  F5            PUSH AF
49FE  CD 16 4A      CALL buzzer_off
4A01  E6 F7         AND 0xF7
4A03  D3 F0         OUT (0xF0),A  ; panel
4A05  32 58 4A      LD (panel_shadow),A
4A08  01 00 68      LD BC,0x6800

loc_4A0B:
4A0B  0B            DEC BC
4A0C  79            LD A,C
4A0D  B0            OR B
4A0E  20 FB         JR NZ,loc_4A0B
4A10  CD 16 4A      CALL buzzer_off
4A13  F1            POP AF
4A14  C1            POP BC
4A15  C9            RET

; set panel port F0 bit3 high, keeping 0x4A58 shadow in sync
buzzer_off:
4A16  3A 58 4A      LD A,(panel_shadow)
4A19  F6 08         OR 0x08
4A1B  D3 F0         OUT (0xF0),A  ; panel
4A1D  32 58 4A      LD (panel_shadow),A
4A20  C9            RET
4A21  F5            PUSH AF
4A22  3A 58 4A      LD A,(panel_shadow)
4A25  E6 FD         AND 0xFD

loc_4A27:
4A27  D3 F0         OUT (0xF0),A  ; panel
4A29  32 58 4A      LD (panel_shadow),A
4A2C  F1            POP AF
4A2D  C9            RET
4A2E  F5            PUSH AF
4A2F  3A 58 4A      LD A,(panel_shadow)
4A32  E6 FB         AND 0xFB
4A34  18 F1         JR loc_4A27
4A36  F5            PUSH AF
4A37  3A 58 4A      LD A,(panel_shadow)
4A3A  F6 02         OR 0x02
4A3C  18 E9         JR loc_4A27
4A3E  F5            PUSH AF
4A3F  3A 58 4A      LD A,(panel_shadow)
4A42  F6 04         OR 0x04
4A44  18 E1         JR loc_4A27
4A46  E5            PUSH HL
4A47  F5            PUSH AF
4A48  21 58 4A      LD HL,panel_shadow
4A4B  7E            LD A,(HL)
4A4C  EE 02         XOR 0x02
4A4E  D3 F0         OUT (0xF0),A  ; panel
4A50  77            LD (HL),A
4A51  F1            POP AF
4A52  E1            POP HL
4A53  C9            RET

; saved SP for the LD SP,IX rapid command loader (LD (..),SP / LD SP,(..)); +2 reserved
fdc_saved_sp:
4A54  00 00 00 00                                     |....|

; port-0xF0 output shadow: panel key-column drive, buzzer bit3 (active-low), status LEDs
panel_shadow:
4A58  00                                              |.|

; FDC driver state: current mode/side byte, scratch pointers and misc flags (0x4A59-0x4A60)
fdc_drv_state:
4A59  00 00 03 00 00 00 00 00                         |........|

; 4 command buffers, one per FDC, 9 bytes each; byte0 = last opcode (seek/recal marker for the ISR)
fdc_cmd_buf:
4A61  00 00 00 00 00 00 00 00 00                      |.........|
; FDC1 command buffer
fdc_cmd_buf1:
4A6A  00 00 00 00 00 00 00 00 00                      |.........|
; FDC2 command buffer
fdc_cmd_buf2:
4A73  00 00 00 00 00 00 00 00 00                      |.........|
; FDC3 command buffer
fdc_cmd_buf3:
4A7C  00 00 00 00 00 00 00 00 00                      |.........|

; 4 result-phase buffers, one per FDC, 7 bytes each: ST0,ST1,ST2,C,H,R,N from the FDC result phase
fdc_result_buf:
4A85  00 00 00 00 00 00 00                            |.......|
; FDC1 result phase
fdc_result_buf1:
4A8C  00 00 00 00 00 00 00                            |.......|
; FDC2 result phase
fdc_result_buf2:
4A93  00 00 00 00 00 00 00                            |.......|
; FDC3 result phase
fdc_result_buf3:
4A9A  00 00 00 00 00 00 00                            |.......|

; 0x4AA1 per-FDC "result captured" bits; 0x4AA2/0x4AA4 saved DE/HL across the result-read path
fdc_result_save:
4AA1  00 00 00 00 00                                  |.....|

; sector-size lookup: 7 words 128<<N (128,256,512,1024,2048,4096,8192); fdc_dma_setup indexes [N*2]
sector_size_tbl:
4AA6  80 00 00 01 00 02 00 04 00 08 00 10 00 20       |............. |

; format -> gap3/length byte table (8 entries), indexed by format id
fdc_gap_tbl:
4AB4  08 09 08 09 09 09 0F 12                         |........|

; 9x 5-byte FDC parameter records {b0, rate:word, b3, b4} streamed into an FDC block by copy_fdc_params
fdc_param_recs:
4ABC  00 80 00 1A 00                                  |.....|
4AC1  01 00 01 1A 01                                  |.....|
4AC6  01 00 01 10 01                                  |.....|
4ACB  01 00 02 0F 02                                  |.....|
4AD0  01 00 04 08 03                                  |.....|
4AD5  01 00 04 05 03                                  |.....|
4ADA  01 00 08 02 04                                  |.....|
4ADF  01 00 10 02 05                                  |.....|
4AE4  01 00 20 02 06                                  |.. ..|

; FDC command-build flags byte
fdc_op_flags:
4AE9  00                                              |.|

; READ/WRITE command opcode base (ORed with 0x40 for MFM before issue)
fdc_opcode_base:
4AEA  00                                              |.|

; drive-pair block A (27 bytes): +7 DOR/motor, +8/9 DMA start address (8237 ch0x80), +10/11 DMA count
drive_blk_a:
4AEB  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
4AFB  00 00 00 00 00 00 02 06 0F 32 01                |.........2.|

; drive-pair block B (27 bytes): same layout, 8237 channel 0x82
drive_blk_b:
4B06  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
4B16  00 00 00 00 00 00 02 06 0F 32 01                |.........2.|

; 4 words: per-FDC DMA start-address / transfer-count save slots
dma_ptr_save:
4B21  00 00 00 00 00 00 00 00                         |........|

; 8x 12-byte format geometry records (sectors/track per zone); accessed in 24-byte (2-record) format pairs
fmt_geom_recs:
4B29  00 00 21 01 28 00 28 00 28 00 28 00             |..!.(.(.(.(.|
4B35  00 00 1E 01 28 00 28 00 28 00 28 00             |....(.(.(.(.|
4B41  00 00 12 01 2C 00 36 01 4B 02 50 00             |....,.6.K.P.|
4B4D  00 00 12 01 27 02 2C 01 43 02 50 00             |....'.,.C.P.|
4B59  00 00 50 00 50 00 50 00 50 00 50 00             |..P.P.P.P.P.|
4B65  00 00 50 00 50 00 50 00 50 00 50 00             |..P.P.P.P.P.|
4B71  00 00 37 01 47 02 50 00 50 00 50 00             |..7.G.P.P.P.|
4B7D  00 00 33 01 46 02 50 00 50 00 50 00             |..3.F.P.P.P.|

; current FDC data-rate register bits (ORed then OUT to 0xB1)
fdc_rate_reg:
4B89  00                                              |.|

; current FDC write-precompensation value (OUT to 0xC2)
fdc_precomp_reg:
4B8A  00                                              |.|

ver_loader:
4B8B  53 54 49 42 47 31 31 20 39 35 30 35 30 33       |STIBG11 950503|

; HD44780 LCD init: function set 0x38, display/clear/entry/on, presence check
lcd_init:
4B99  3E 30         LD A,0x30
4B9B  D3 E0         OUT (0xE0),A  ; lcd_cmd
4B9D  21 00 03      LD HL,0x0300
4BA0  CD 22 4C      CALL lcd_setpos
4BA3  D3 E0         OUT (0xE0),A  ; lcd_cmd
4BA5  21 40 00      LD HL,ptr_ver_firmware
4BA8  CD 22 4C      CALL lcd_setpos
4BAB  D3 E0         OUT (0xE0),A  ; lcd_cmd
4BAD  0E E0         LD C,0xE0
4BAF  3E 38         LD A,0x38
4BB1  CD 43 4C      CALL lcd_byte_out
4BB4  3E 08         LD A,0x08
4BB6  CD 43 4C      CALL lcd_byte_out
4BB9  3E 01         LD A,0x01
4BBB  CD 43 4C      CALL lcd_byte_out
4BBE  3E 06         LD A,0x06
4BC0  CD 43 4C      CALL lcd_byte_out
4BC3  3E 0C         LD A,0x0C
4BC5  CD 43 4C      CALL lcd_byte_out
4BC8  3E 02         LD A,0x02
4BCA  18 77         JR lcd_byte_out
4BCC  0E E8         LD C,0xE8
4BCE  3E 55         LD A,0x55
4BD0  CD 43 4C      CALL lcd_byte_out
4BD3  0E E0         LD C,0xE0
4BD5  3E 02         LD A,0x02
4BD7  CD 43 4C      CALL lcd_byte_out
4BDA  CD 2A 4C      CALL lcd_wait_busy
4BDD  DB E8         IN A,(0xE8)  ; lcd_data
4BDF  FE 55         CP 0x55

loc_4BE1:
4BE1  C8            RET Z

; mute local I/O: disable input poll and point iovec_out at no-op stub (0x4C4F)
io_mute_local:
4BE2  CD EC 4B      CALL io_disable_poll
4BE5  21 4F 4C      LD HL,loc_4C4F
4BE8  22 C9 52      LD (iovec_out),HL
4BEB  C9            RET

; disable input polling: point iovec_poll at stub that returns A=0xFF
io_disable_poll:
4BEC  21 F2 4B      LD HL,loc_4BF2
4BEF  22 CB 52      LD (iovec_poll),HL

loc_4BF2:
4BF2  3E FF         LD A,0xFF
4BF4  C9            RET

; error beep: A*200/13 -> PIT ch1 (0xA4/0xAC) tone, pitch/duration encodes error code
error_report:
4BF5  5F            LD E,A
4BF6  16 00         LD D,0x00
4BF8  4A            LD C,D
4BF9  3E C8         LD A,0xC8
4BFB  CD 05 4F      CALL mul16
4BFE  0E 0D         LD C,0x0D
4C00  06 00         LD B,0x00
4C02  CD CE 4E      CALL div32_16
4C05  2D            DEC L
4C06  3E 70         LD A,0x70
4C08  D3 AC         OUT (0xAC),A  ; pit_ctrl
4C0A  0E A4         LD C,0xA4
4C0C  ED 69         OUT (C),L
4C0E  ED 61         OUT (C),H

loc_4C10:
4C10  3E 40         LD A,0x40
4C12  D3 AC         OUT (0xAC),A  ; pit_ctrl
4C14  DB A4         IN A,(0xA4)  ; pit_c1
4C16  47            LD B,A
4C17  DB A4         IN A,(0xA4)  ; pit_c1
4C19  FE FF         CP 0xFF
4C1B  20 F3         JR NZ,loc_4C10
4C1D  3E 50         LD A,0x50
4C1F  D3 AC         OUT (0xAC),A  ; pit_ctrl
4C21  C9            RET

; busy-loop delay (HL iterations)
lcd_setpos:
4C22  F5            PUSH AF

loc_4C23:
4C23  2B            DEC HL
4C24  7C            LD A,H
4C25  B5            OR L
4C26  20 FB         JR NZ,loc_4C23
4C28  F1            POP AF
4C29  C9            RET

; wait for LCD busy flag clear (IN 0xE0 bit7)
lcd_wait_busy:
4C2A  F5            PUSH AF

loc_4C2B:
4C2B  DB E0         IN A,(0xE0)  ; lcd_cmd
4C2D  CB 7F         BIT 7,A
4C2F  20 FA         JR NZ,loc_4C2B
4C31  F1            POP AF
4C32  DD E5         PUSH IX
4C34  DD E5         PUSH IX
4C36  DD E5         PUSH IX
4C38  DD E5         PUSH IX
4C3A  DD E1         POP IX
4C3C  DD E1         POP IX
4C3E  DD E1         POP IX
4C40  DD E1         POP IX
4C42  C9            RET

; write A to LCD via iovec_out (busy-wait then OUT (C),A; C=cmd/data reg)
lcd_byte_out:
4C43  22 57 4C      LD (lcd_byte_hl),HL
4C46  2A C9 52      LD HL,(iovec_out)
4C49  E9            JP (HL)

; default iovec_out: wait LCD busy then OUT (C),A; 0x4C4F entry is muted no-op restoring HL
byte_out:
4C4A  CD 2A 4C      CALL lcd_wait_busy
4C4D  ED 79         OUT (C),A

loc_4C4F:
4C4F  2A 57 4C      LD HL,(lcd_byte_hl)
4C52  C9            RET

; saved caller HL across lcd_print (restored at 0x4CCB)
lcd_print_hl:
4C53  00 00         DW 0x0000

; saved caller BC across lcd_print (restored at 0x4CCE)
lcd_print_bc:
4C55  00 00         DW 0x0000

; saved caller HL across lcd_byte_out (restored at 0x4C4F)
lcd_byte_hl:
4C57  00 00         DW 0x0000

; print inline string to LCD (control bytes 0x0C clr/0x0D nl/0x1B pos/0x00 end)
lcd_print:
4C59  22 53 4C      LD (lcd_print_hl),HL
4C5C  ED 43 55 4C   LD (lcd_print_bc),BC
4C60  E1            POP HL

loc_4C61:
4C61  7E            LD A,(HL)
4C62  0E E0         LD C,0xE0
4C64  23            INC HL
4C65  B7            OR A
4C66  28 62         JR Z,loc_4CCA
4C68  FE 0B         CP 0x0B
4C6A  20 07         JR NZ,loc_4C73
4C6C  3E 02         LD A,0x02

loc_4C6E:
4C6E  CD 43 4C      CALL lcd_byte_out
4C71  18 EE         JR loc_4C61

loc_4C73:
4C73  FE 0C         CP 0x0C
4C75  20 04         JR NZ,loc_4C7B
4C77  3E 01         LD A,0x01
4C79  18 F3         JR loc_4C6E

loc_4C7B:
4C7B  FE 0D         CP 0x0D
4C7D  20 0B         JR NZ,loc_4C8A
4C7F  CD 2A 4C      CALL lcd_wait_busy
4C82  DB E0         IN A,(0xE0)  ; lcd_cmd
4C84  E6 40         AND 0x40
4C86  F6 80         OR 0x80
4C88  18 E4         JR loc_4C6E

loc_4C8A:
4C8A  FE 0A         CP 0x0A
4C8C  20 10         JR NZ,loc_4C9E
4C8E  CD 2A 4C      CALL lcd_wait_busy
4C91  DB E0         IN A,(0xE0)  ; lcd_cmd
4C93  CB 77         BIT 6,A
4C95  C4 D3 4C      CALL NZ,lcd_scroll_up
4C98  F6 C0         OR 0xC0
4C9A  0E E0         LD C,0xE0
4C9C  18 D0         JR loc_4C6E

loc_4C9E:
4C9E  FE 1B         CP 0x1B
4CA0  20 04         JR NZ,loc_4CA6
4CA2  7E            LD A,(HL)
4CA3  23            INC HL
4CA4  18 C8         JR loc_4C6E

loc_4CA6:
4CA6  F5            PUSH AF
4CA7  CD 2A 4C      CALL lcd_wait_busy
4CAA  DB E0         IN A,(0xE0)  ; lcd_cmd
4CAC  E6 7F         AND 0x7F
4CAE  FE 14         CP 0x14
4CB0  20 0F         JR NZ,loc_4CC1

loc_4CB2:
4CB2  3E C0         LD A,0xC0
4CB4  0E E0         LD C,0xE0
4CB6  CD 43 4C      CALL lcd_byte_out

loc_4CB9:
4CB9  F1            POP AF
4CBA  0E E8         LD C,0xE8
4CBC  CD 43 4C      CALL lcd_byte_out
4CBF  18 A0         JR loc_4C61

loc_4CC1:
4CC1  FE 54         CP 0x54
4CC3  CC D3 4C      CALL Z,lcd_scroll_up
4CC6  20 F1         JR NZ,loc_4CB9
4CC8  18 E8         JR loc_4CB2

loc_4CCA:
4CCA  E5            PUSH HL
4CCB  2A 53 4C      LD HL,(lcd_print_hl)
4CCE  ED 4B 55 4C   LD BC,(lcd_print_bc)
4CD2  C9            RET

; scroll LCD display up one line: read line-2 chars and rewrite shifted, blank last
lcd_scroll_up:
4CD3  F5            PUSH AF
4CD4  D5            PUSH DE
4CD5  16 00         LD D,0x00

loc_4CD7:
4CD7  7A            LD A,D
4CD8  F6 C0         OR 0xC0
4CDA  0E E0         LD C,0xE0
4CDC  CD 43 4C      CALL lcd_byte_out
4CDF  CD 2A 4C      CALL lcd_wait_busy
4CE2  DB E8         IN A,(0xE8)  ; lcd_data
4CE4  F5            PUSH AF
4CE5  7A            LD A,D
4CE6  F6 C0         OR 0xC0
4CE8  0E E0         LD C,0xE0
4CEA  CD 43 4C      CALL lcd_byte_out
4CED  3E 20         LD A,0x20
4CEF  0E E8         LD C,0xE8
4CF1  CD 43 4C      CALL lcd_byte_out
4CF4  7A            LD A,D
4CF5  F6 80         OR 0x80
4CF7  0E E0         LD C,0xE0
4CF9  CD 43 4C      CALL lcd_byte_out
4CFC  F1            POP AF
4CFD  0E E8         LD C,0xE8
4CFF  CD 43 4C      CALL lcd_byte_out
4D02  14            INC D
4D03  7A            LD A,D
4D04  FE 14         CP 0x14
4D06  20 CF         JR NZ,loc_4CD7
4D08  D1            POP DE
4D09  F1            POP AF
4D0A  C9            RET

; scan the 4-key keypad matrix (ports 0x98/0x94)
keypad_scan:
4D0B  CD 9B 4D      CALL poll_host_remote
4D0E  DB 98         IN A,(0x98)  ; key_scan
4D10  E6 FC         AND 0xFC
4D12  F6 02         OR 0x02
4D14  D3 98         OUT (0x98),A  ; key_scan
4D16  CD 29 4D      CALL keypad_row_read
4D19  28 01         JR Z,loc_4D1C
4D1B  C9            RET

loc_4D1C:
4D1C  DB 98         IN A,(0x98)  ; key_scan
4D1E  EE 03         XOR 0x03
4D20  D3 98         OUT (0x98),A  ; key_scan
4D22  CD 29 4D      CALL keypad_row_read
4D25  C8            RET Z
4D26  C6 80         ADD A,0x80
4D28  C9            RET

; read keypad row: IN status 0x94, invert low nibble, return single-key code or 0
keypad_row_read:
4D29  DB 94         IN A,(0x94)  ; status_in
4D2B  2F            CPL
4D2C  E6 0F         AND 0x0F
4D2E  C8            RET Z
4D2F  FE 01         CP 0x01
4D31  28 0E         JR Z,loc_4D41
4D33  FE 02         CP 0x02
4D35  28 0A         JR Z,loc_4D41
4D37  FE 04         CP 0x04
4D39  28 06         JR Z,loc_4D41
4D3B  FE 08         CP 0x08
4D3D  28 02         JR Z,loc_4D41
4D3F  AF            XOR A
4D40  C9            RET

loc_4D41:
4D41  B7            OR A
4D42  C9            RET

; debounced key read with auto-repeat + key-click beep
keypad_debounce:
4D43  CD 49 4D      CALL keypad_wait
4D46  E6 7F         AND 0x7F
4D48  C9            RET

; wait for a debounced keypress: poll keypad_scan with LCD-timed delays and panel busy pulse
keypad_wait:
4D49  E5            PUSH HL
4D4A  DD E5         PUSH IX
4D4C  DD 21 58 4A   LD IX,panel_shadow

loc_4D50:
4D50  CD 0B 4D      CALL keypad_scan
4D53  28 FB         JR Z,loc_4D50
4D55  21 64 00      LD HL,0x0064
4D58  CD 22 4C      CALL lcd_setpos
4D5B  CD 0B 4D      CALL keypad_scan
4D5E  28 F0         JR Z,loc_4D50
4D60  F5            PUSH AF
4D61  DD CB 00 9E   RES 3,(IX+0)
4D65  DD 7E 00      LD A,(IX+0)
4D68  D3 F0         OUT (0xF0),A  ; panel
4D6A  21 E8 03      LD HL,0x03E8
4D6D  CD 22 4C      CALL lcd_setpos
4D70  DD CB 00 DE   SET 3,(IX+0)
4D74  DD 7E 00      LD A,(IX+0)
4D77  D3 F0         OUT (0xF0),A  ; panel

loc_4D79:
4D79  CD 0B 4D      CALL keypad_scan
4D7C  20 FB         JR NZ,loc_4D79
4D7E  F1            POP AF
4D7F  21 00 40      LD HL,0x4000
4D82  CD 22 4C      CALL lcd_setpos
4D85  DD E1         POP IX
4D87  E1            POP HL
4D88  C9            RET

; get key / dispatch input (indirect via iovec_poll 0x52CB: keypad or host)
get_key:
4D89  E5            PUSH HL
4D8A  2A CB 52      LD HL,(iovec_poll)
4D8D  E9            JP (HL)

; poll-input tail: if A=0 scan keypad and discard caller return; else return current value
get_key_dispatch:
4D8E  B7            OR A
4D8F  20 05         JR NZ,loc_4D96
4D91  CD 0B 4D      CALL keypad_scan
4D94  E1            POP HL
4D95  C9            RET

loc_4D96:
4D96  CD 43 4D      CALL keypad_debounce
4D99  E1            POP HL
4D9A  C9            RET

; poll host UART (0xDC) during key scan; if byte ready fetch remote word, flag cmd 0x0C
poll_host_remote:
4D9B  DB DC         IN A,(0xDC)  ; host_stat
4D9D  CB 47         BIT 0,A
4D9F  C8            RET Z
4DA0  CD 01 1E      CALL host_rx_word
4DA3  C0            RET NZ
4DA4  7A            LD A,D
4DA5  FE 0C         CP 0x0C
4DA7  28 02         JR Z,loc_4DAB
4DA9  AF            XOR A
4DAA  C9            RET

loc_4DAB:
4DAB  CD AD 4E      CALL host_rx
4DAE  CD AD 4E      CALL host_rx
4DB1  06 58         LD B,0x58
4DB3  CD 9D 4E      CALL host_tx
4DB6  06 00         LD B,0x00
4DB8  CD 9D 4E      CALL host_tx
4DBB  CD 59 4C      CALL lcd_print
4DBE  0C 52 65 6D 6F 74 +  DB \f, "Remote controll", 0
4DCF  CD E2 4B      CALL io_mute_local
4DD2  C3 0B 1E      JP host_dispatch

padding:
4DD5  00 00 00 00                                     |....|

; init 8253 (baud c0, timers c1/c2) and both USARTs; drain receivers
timer_uart_init:
4DD9  ED 56         IM 1
4DDB  3E 16         LD A,0x16
4DDD  D3 AC         OUT (0xAC),A  ; pit_ctrl
4DDF  3E 0D         LD A,0x0D
4DE1  D3 A0         OUT (0xA0),A  ; pit_c0
4DE3  3E 50         LD A,0x50
4DE5  D3 AC         OUT (0xAC),A  ; pit_ctrl
4DE7  3E 90         LD A,0x90
4DE9  D3 AC         OUT (0xAC),A  ; pit_ctrl
4DEB  F5            PUSH AF
4DEC  D3 A4         OUT (0xA4),A  ; pit_c1
4DEE  F1            POP AF
4DEF  D3 A8         OUT (0xA8),A  ; pit_c2
4DF1  3E 0F         LD A,0x0F
4DF3  D3 9C         OUT (0x9C),A  ; ctrl_latch
4DF5  3E 0E         LD A,0x0E
4DF7  D3 40         OUT (0x40),A  ; drv_lat0
4DF9  D3 60         OUT (0x60),A  ; drv_lat2
4DFB  21 28 4E      LD HL,al_ser_blob
4DFE  01 D4 0D      LD BC,0x0DD4
4E01  ED B3         OTIR
4E03  21 35 4E      LD HL,host_ser_blob2
4E06  01 DC 0D      LD BC,0x0DDC
4E09  ED B3         OTIR
4E0B  DB D0         IN A,(0xD0)  ; al_data
4E0D  DB D0         IN A,(0xD0)  ; al_data
4E0F  DB D0         IN A,(0xD0)  ; al_data
4E11  DB D0         IN A,(0xD0)  ; al_data
4E13  DB D8         IN A,(0xD8)  ; host_data
4E15  DB D8         IN A,(0xD8)  ; host_data
4E17  DB D8         IN A,(0xD8)  ; host_data
4E19  DB D8         IN A,(0xD8)  ; host_data
4E1B  CD 91 4E      CALL al_cmd_reset
4E1E  CD 95 4E      CALL host_cmd_reset
4E21  CD 99 4B      CALL lcd_init
4E24  CD 2C 45      CALL fdc_senseint_all
4E27  C9            RET

al_ser_blob:
4E28  18 03 C0 04 44 05 E0 01 80 03 C1 05 EA          |....D........|

host_ser_blob2:
4E35  18 03 C0 04 45 05 E0 01 80 03 C1 05 EA          |....E........|

; USART TX: wait TxRDY (status bit2), OUT data
uart_tx:
4E42  ED 78         IN A,(C)
4E44  CB 57         BIT 2,A
4E46  28 FA         JR Z,uart_tx
4E48  CB 91         RES 2,C
4E4A  ED 41         OUT (C),B
4E4C  CB D1         SET 2,C
4E4E  C9            RET

; test host USART RxRDY: C=0xDC, IN B, bit0 = byte available
host_rx_ready:
4E4F  0E DC         LD C,0xDC
4E51  18 02         JR loc_4E55

; test autoloader USART RxRDY: C=0xD4, IN B, bit0 = byte available
al_rx_ready:
4E53  0E D4         LD C,0xD4

loc_4E55:
4E55  ED 40         IN B,(C)
4E57  CB 40         BIT 0,B
4E59  C9            RET

; USART RX with timeout: wait RxRDY (bit0); return Z=byte / NZ=timeout|err
uart_rx:
4E5A  E5            PUSH HL
4E5B  D5            PUSH DE
4E5C  1E 14         LD E,0x14
4E5E  3E DC         LD A,0xDC
4E60  B9            CP C
4E61  20 02         JR NZ,loc_4E65
4E63  1E 01         LD E,0x01

loc_4E65:
4E65  21 00 00      LD HL,0x0000

loc_4E68:
4E68  ED 40         IN B,(C)
4E6A  CB 40         BIT 0,B
4E6C  20 0D         JR NZ,loc_4E7B
4E6E  2B            DEC HL
4E6F  7D            LD A,L
4E70  B4            OR H
4E71  20 F5         JR NZ,loc_4E68
4E73  1D            DEC E
4E74  20 F2         JR NZ,loc_4E68
4E76  F6 01         OR 0x01
4E78  7D            LD A,L
4E79  18 0E         JR loc_4E89

loc_4E7B:
4E7B  CB 91         RES 2,C
4E7D  ED 40         IN B,(C)
4E7F  CB D1         SET 2,C
4E81  3E 01         LD A,0x01
4E83  ED 79         OUT (C),A
4E85  ED 78         IN A,(C)
4E87  E6 70         AND 0x70

loc_4E89:
4E89  D1            POP DE
4E8A  E1            POP HL
4E8B  C9            RET

; send USART command 0x30 to port C (reset error flags / enter hunt)
uart_send_reset:
4E8C  3E 30         LD A,0x30
4E8E  ED 79         OUT (C),A
4E90  C9            RET

; reset autoloader USART (C=0xD4) via command 0x30
al_cmd_reset:
4E91  0E D4         LD C,0xD4
4E93  18 F7         JR uart_send_reset

; reset host USART (C=0xDC) via command 0x30
host_cmd_reset:
4E95  0E DC         LD C,0xDC
4E97  18 F3         JR uart_send_reset

; transmit byte A to autoloader USART (C=0xD4, via uart_tx)
al_tx:
4E99  0E D4         LD C,0xD4
4E9B  18 A5         JR uart_tx

; transmit byte A to host USART (C=0xDC, via uart_tx)
host_tx:
4E9D  0E DC         LD C,0xDC
4E9F  18 A1         JR uart_tx

; receive byte from autoloader USART (C=0xD4); on data, clear USART errors
al_rx:
4EA1  0E D4         LD C,0xD4

loc_4EA3:
4EA3  CD 5A 4E      CALL uart_rx
4EA6  C8            RET Z
4EA7  F5            PUSH AF
4EA8  CD 8C 4E      CALL uart_send_reset
4EAB  F1            POP AF
4EAC  C9            RET

; receive byte from host USART (C=0xDC); on data, clear USART errors
host_rx:
4EAD  0E DC         LD C,0xDC
4EAF  18 F2         JR loc_4EA3
4EB1  C9            RET

; 32-bit binary (DE:HL) -> decimal ASCII, right-justified in buffer at 0x4F38 down
bin2dec_clear:
4EB2  CD 1D 4F      CALL clear_dec_buf

; binary -> decimal ASCII conversion
bin2dec:
4EB5  DD 21 38 4F   LD IX,lcd_dec_tmpl+0x9

loc_4EB9:
4EB9  CD CB 4E      CALL div_by_10
4EBC  79            LD A,C
4EBD  C6 30         ADD A,0x30
4EBF  DD 77 00      LD (IX+0),A
4EC2  DD 2B         DEC IX
4EC4  7D            LD A,L
4EC5  B4            OR H
4EC6  B3            OR E
4EC7  B2            OR D
4EC8  20 EF         JR NZ,loc_4EB9
4ECA  C9            RET

; divide 32-bit DE:HL by 10 (BC=10 wrapper over div32_16), remainder in C for digits
div_by_10:
4ECB  01 0A 00      LD BC,0x000A

; 32/16 unsigned divide (DE:HL / BC)
div32_16:
4ECE  DD E5         PUSH IX
4ED0  DD 21 00 00   LD IX,0x0000
4ED4  3E 21         LD A,0x21
4ED6  B7            OR A

loc_4ED7:
4ED7  ED 6A         ADC HL,HL
4ED9  EB            EX DE,HL
4EDA  ED 6A         ADC HL,HL
4EDC  EB            EX DE,HL
4EDD  3D            DEC A
4EDE  28 1F         JR Z,loc_4EFF
4EE0  E5            PUSH HL
4EE1  DD E5         PUSH IX
4EE3  E1            POP HL
4EE4  ED 6A         ADC HL,HL
4EE6  E5            PUSH HL
4EE7  DD E1         POP IX
4EE9  30 08         JR NC,loc_4EF3
4EEB  A7            AND A
4EEC  ED 42         SBC HL,BC
4EEE  E5            PUSH HL
4EEF  DD E1         POP IX
4EF1  18 09         JR loc_4EFC

loc_4EF3:
4EF3  A7            AND A
4EF4  ED 42         SBC HL,BC
4EF6  38 03         JR C,loc_4EFB
4EF8  E5            PUSH HL
4EF9  DD E1         POP IX

loc_4EFB:
4EFB  3F            CCF

loc_4EFC:
4EFC  E1            POP HL
4EFD  18 D8         JR loc_4ED7

loc_4EFF:
4EFF  DD E5         PUSH IX
4F01  C1            POP BC
4F02  DD E1         POP IX
4F04  C9            RET

; 16x16 unsigned multiply
mul16:
4F05  06 10         LD B,0x10
4F07  21 00 00      LD HL,0x0000

loc_4F0A:
4F0A  CB 25         SLA L
4F0C  CB 14         RL H
4F0E  CB 17         RL A
4F10  CB 11         RL C
4F12  30 04         JR NC,loc_4F18
4F14  19            ADD HL,DE
4F15  30 01         JR NC,loc_4F18
4F17  3C            INC A

loc_4F18:
4F18  10 F0         DJNZ loc_4F0A
4F1A  51            LD D,C
4F1B  5F            LD E,A
4F1C  C9            RET

; fill 8-byte decimal-conversion buffer at 0x4F31 with spaces
clear_dec_buf:
4F1D  DD 21 31 4F   LD IX,lcd_dec_tmpl+0x2
4F21  06 08         LD B,0x08

loc_4F23:
4F23  DD 36 00 20   LD (IX+0),0x20
4F27  DD 23         INC IX
4F29  10 F8         DJNZ loc_4F23
4F2B  C9            RET

; print the decimal-conversion buffer string to LCD (via lcd_print)
lcd_print_number:
4F2C  CD 59 4C      CALL lcd_print

lcd_dec_tmpl:
4F2F  1B C0 2E 2E 2E 2E +  DB ESC(0xC0), "........", 0
4F3A  C9            RET

; monitor hex-dump: clear LCD (cmd 0x01) then print a hex row of bytes from (HL)
lcd_dump_hex:
4F3B  F5            PUSH AF
4F3C  C5            PUSH BC
4F3D  47            LD B,A
4F3E  3E 01         LD A,0x01
4F40  0E E0         LD C,0xE0
4F42  CD 43 4C      CALL lcd_byte_out
4F45  78            LD A,B
4F46  A7            AND A
4F47  20 06         JR NZ,loc_4F4F
4F49  CD 5C 4F      CALL mon_hexrow

loc_4F4C:
4F4C  C1            POP BC
4F4D  F1            POP AF
4F4E  C9            RET

loc_4F4F:
4F4F  47            LD B,A

loc_4F50:
4F50  C5            PUSH BC
4F51  CD 7A 4F      CALL mon_hexbyte
4F54  CD 6F 4F      CALL mon_hex_space
4F57  C1            POP BC
4F58  10 F6         DJNZ loc_4F50
4F5A  18 F0         JR loc_4F4C

; print a full 2-line monitor hex row (mon_hex4 group + line-2 home)
mon_hexrow:
4F5C  CD 5F 4F      CALL mon_hexrow_b

; print monitor hex group then home to LCD line 2
mon_hexrow_b:
4F5F  CD 66 4F      CALL mon_hex4
4F62  CD C4 4F      CALL lcd_line2_home
4F65  C9            RET

; monitor hex-row segment: print 4 hex bytes from (HL) plus trailing space
mon_hex4:
4F66  CD 69 4F      CALL mon_hex3

; monitor hex-row segment: print 3 hex bytes from (HL) plus trailing space
mon_hex3:
4F69  CD 6C 4F      CALL mon_hex2

; monitor hex-row segment: print 2 hex bytes from (HL) plus trailing space
mon_hex2:
4F6C  CD 77 4F      CALL mon_hex2b

; print a single space char to LCD data (0xE8) - monitor field separator
mon_hex_space:
4F6F  3E 20         LD A,0x20
4F71  0E E8         LD C,0xE8
4F73  CD 43 4C      CALL lcd_byte_out
4F76  C9            RET

; print 2 hex bytes from (HL) to LCD, advancing HL (monitor)
mon_hex2b:
4F77  CD 7A 4F      CALL mon_hexbyte

; print byte at (HL) as 2 hex digits to LCD, advance HL (monitor)
mon_hexbyte:
4F7A  7E            LD A,(HL)
4F7B  E5            PUSH HL
4F7C  21 AB 4F      LD HL,mon_hexbuf+0x2
4F7F  32 AB 4F      LD (mon_hexbuf+0x2),A
4F82  CD AC 4F      CALL mon_hexpair
4F85  E1            POP HL
4F86  23            INC HL
4F87  C9            RET
4F88  F5            PUSH AF
4F89  E5            PUSH HL
4F8A  CD 59 4C      CALL lcd_print
4F8D  0C 41 64 72 65 73 +  DB \f, "Adresa = ", 0
4F98  E1            POP HL
4F99  E5            PUSH HL
4F9A  7C            LD A,H
4F9B  65            LD H,L
4F9C  6F            LD L,A
4F9D  22 A9 4F      LD (mon_hexbuf),HL
4FA0  21 A9 4F      LD HL,mon_hexbuf
4FA3  CD 77 4F      CALL mon_hex2b
4FA6  E1            POP HL
4FA7  F1            POP AF
4FA8  C9            RET

mon_hexbuf:
4FA9  00 00 01                                        |...|

; print two hex nibbles of buffered byte (0x4FAB) via RLD, ASCII-adjust, to LCD
mon_hexpair:
4FAC  CD AF 4F      CALL mon_hexnib

; print one hex nibble via RLD to ASCII (0-9/A-F) to LCD data (0xE8)
mon_hexnib:
4FAF  ED 6F         RLD
4FB1  F5            PUSH AF
4FB2  E6 0F         AND 0x0F
4FB4  C6 30         ADD A,0x30
4FB6  FE 3A         CP 0x3A
4FB8  FA BD 4F      JP M,loc_4FBD
4FBB  C6 07         ADD A,0x07

loc_4FBD:
4FBD  0E E8         LD C,0xE8
4FBF  CD 43 4C      CALL lcd_byte_out
4FC2  F1            POP AF
4FC3  C9            RET

; home LCD to line 2 (via lcd_print control sequence)
lcd_line2_home:
4FC4  CD 59 4C      CALL lcd_print
4FC7  1B C0 00      DB ESC(0xC0), 0
4FCA  C9            RET

; assemble FDC format command block: geometry + sector map + interleave + DMA/bank params from 0x3130
build_format_block:
4FCB  CD 01 51      CALL init_format_geom
4FCE  CD 43 50      CALL format_sector_map
4FD1  FD 22 F2 52   LD (cksum_ref+0x2),IY
4FD5  CD 7E 50      CALL build_interleave_tbl
4FD8  3A 30 31      LD A,(dram_bank_count)
4FDB  DD 77 0C      LD (IX+12),A
4FDE  DD 36 0D 00   LD (IX+13),0x00
4FE2  DD 36 0E 80   LD (IX+14),0x80
4FE6  DD 77 0F      LD (IX+15),A
4FE9  DD 36 10 00   LD (IX+16),0x00
4FED  DD 36 11 C0   LD (IX+17),0xC0
4FF1  C9            RET

; logical block -> CHS + DMA descriptor (uses format_desc geometry)
block_to_chs:
4FF2  C5            PUSH BC
4FF3  DD E5         PUSH IX
4FF5  79            LD A,C
4FF6  07            RLCA
4FF7  E6 01         AND 0x01
4FF9  4F            LD C,A
4FFA  DD 21 DD 52   LD IX,format_desc
4FFE  DD 7E 01      LD A,(IX+1)
5001  3D            DEC A
5002  28 02         JR Z,loc_5006
5004  CB 20         SLA B

loc_5006:
5006  78            LD A,B
5007  81            ADD A,C
5008  4F            LD C,A
5009  06 56         LD B,0x56
500B  DD 7E 01      LD A,(IX+1)
500E  3D            DEC A
500F  05            DEC B
5010  A7            AND A
5011  28 02         JR Z,loc_5015
5013  CB 20         SLA B

loc_5015:
5015  80            ADD A,B
5016  91            SUB C
5017  DD 2A F2 52   LD IX,(cksum_ref+0x2)
501B  6F            LD L,A
501C  26 00         LD H,0x00
501E  29            ADD HL,HL
501F  EB            EX DE,HL
5020  DD 19         ADD IX,DE
5022  DD 7E 01      LD A,(IX+1)
5025  87            ADD A,A
5026  87            ADD A,A
5027  5F            LD E,A
5028  16 00         LD D,0x00
502A  FD 21 F4 52   LD IY,cksum_ref+0x4
502E  FD 19         ADD IY,DE
5030  FD 6E 00      LD L,(IY+0)
5033  FD 66 01      LD H,(IY+1)
5036  FD 5E 02      LD E,(IY+2)
5039  FD 56 03      LD D,(IY+3)
503C  DD 7E 00      LD A,(IX+0)
503F  DD E1         POP IX
5041  C1            POP BC
5042  C9            RET

; generate per-track sector-ID (interleave) list for FORMAT
format_sector_map:
5043  FD 21 F4 52   LD IY,cksum_ref+0x4
5047  DD 21 DD 52   LD IX,format_desc
504B  21 00 80      LD HL,image_buf
504E  DD 5E 07      LD E,(IX+7)
5051  DD 7E 08      LD A,(IX+8)
5054  F6 80         OR 0x80
5056  57            LD D,A
5057  DD 46 05      LD B,(IX+5)

loc_505A:
505A  FD 75 00      LD (IY+0),L
505D  FD 74 01      LD (IY+1),H
5060  FD 73 02      LD (IY+2),E
5063  FD 72 03      LD (IY+3),D
5066  DD 6E 06      LD L,(IX+6)
5069  26 00         LD H,0x00
506B  19            ADD HL,DE
506C  E5            PUSH HL
506D  DD 5E 09      LD E,(IX+9)
5070  DD 56 0A      LD D,(IX+10)
5073  19            ADD HL,DE
5074  11 04 00      LD DE,0x0004
5077  FD 19         ADD IY,DE
5079  EB            EX DE,HL
507A  E1            POP HL
507B  10 DD         DJNZ loc_505A
507D  C9            RET

; build sector interleave table at IY (0x52F2): fill physical->logical sector ids via sector_lba
build_interleave_tbl:
507E  DD 21 DD 52   LD IX,format_desc
5082  FD 2A F2 52   LD IY,(cksum_ref+0x2)
5086  06 56         LD B,0x56

loc_5088:
5088  C5            PUSH BC
5089  DD 46 01      LD B,(IX+1)

loc_508C:
508C  78            LD A,B
508D  68            LD L,B
508E  3D            DEC A
508F  C1            POP BC
5090  C5            PUSH BC
5091  05            DEC B
5092  4D            LD C,L
5093  CD AB 50      CALL sector_lba
5096  41            LD B,C
5097  FD 77 01      LD (IY+1),A
509A  7D            LD A,L
509B  3C            INC A
509C  2F            CPL
509D  FD 77 00      LD (IY+0),A
50A0  11 02 00      LD DE,0x0002
50A3  FD 19         ADD IY,DE
50A5  10 E5         DJNZ loc_508C
50A7  C1            POP BC
50A8  10 DE         DJNZ loc_5088
50AA  C9            RET

; compute interleaved logical sector id from position: div32_16 by sectors-per-track (format_desc+5)
sector_lba:
50AB  C5            PUSH BC
50AC  DD E5         PUSH IX
50AE  DD 21 DD 52   LD IX,format_desc
50B2  DD 4E 01      LD C,(IX+1)
50B5  0D            DEC C
50B6  28 02         JR Z,loc_50BA
50B8  CB 20         SLA B

loc_50BA:
50BA  80            ADD A,B
50BB  6F            LD L,A
50BC  26 00         LD H,0x00
50BE  5C            LD E,H
50BF  54            LD D,H
50C0  44            LD B,H
50C1  DD 4E 05      LD C,(IX+5)
50C4  CD CE 4E      CALL div32_16
50C7  79            LD A,C
50C8  DD E1         POP IX
50CA  C1            POP BC
50CB  C9            RET

; lay out per-sector format descriptors (C/H/R/N) for whole track via block_to_chs
layout_sectors:
50CC  DD 21 DD 52   LD IX,format_desc
50D0  06 56         LD B,0x56

loc_50D2:
50D2  C5            PUSH BC
50D3  DD 46 01      LD B,(IX+1)

loc_50D6:
50D6  78            LD A,B
50D7  68            LD L,B
50D8  3D            DEC A
50D9  0F            RRCA
50DA  C1            POP BC
50DB  C5            PUSH BC
50DC  05            DEC B
50DD  4F            LD C,A
50DE  E5            PUSH HL
50DF  3E 00         LD A,0x00
50E1  30 03         JR NC,loc_50E6
50E3  3A 63 31      LD A,(side_sel)

loc_50E6:
50E6  F5            PUSH AF
50E7  CD F2 4F      CALL block_to_chs
50EA  EB            EX DE,HL
50EB  57            LD D,A
50EC  3A ED 4A      LD A,(drive_blk_a+0x2)
50EF  5F            LD E,A
50F0  48            LD C,B
50F1  42            LD B,D
50F2  DD 56 02      LD D,(IX+2)
50F5  F1            POP AF
50F6  CD 1E 48      CALL dram_stack_fill
50F9  E1            POP HL
50FA  45            LD B,L
50FB  10 D9         DJNZ loc_50D6
50FD  C1            POP BC
50FE  10 D2         DJNZ loc_50D2
5100  C9            RET

; init format_desc geometry: copy 5 disk params from 0x4AFC, compute sectors-per-track and totals
init_format_geom:
5101  21 FC 4A      LD HL,drive_blk_a+0x11
5104  11 DD 52      LD DE,format_desc
5107  D5            PUSH DE
5108  DD E1         POP IX
510A  01 05 00      LD BC,0x0005
510D  ED B0         LDIR
510F  DD 5E 03      LD E,(IX+3)
5112  DD 56 04      LD D,(IX+4)
5115  21 04 00      LD HL,0x0004
5118  19            ADD HL,DE
5119  DD 7E 02      LD A,(IX+2)
511C  0E 00         LD C,0x00
511E  EB            EX DE,HL
511F  CD 05 4F      CALL mul16
5122  44            LD B,H
5123  4D            LD C,L
5124  21 00 80      LD HL,image_buf
5127  CD CE 4E      CALL div32_16
512A  DD 75 05      LD (IX+5),L
512D  DD 7E 02      LD A,(IX+2)
5130  0E 00         LD C,0x00
5132  DD 56 04      LD D,(IX+4)
5135  DD 5E 03      LD E,(IX+3)
5138  CD 05 4F      CALL mul16
513B  DD 75 09      LD (IX+9),L
513E  DD 74 0A      LD (IX+10),H
5141  DD 75 07      LD (IX+7),L
5144  DD 74 08      LD (IX+8),H
5147  DD 7E 02      LD A,(IX+2)
514A  CB 27         SLA A
514C  CB 27         SLA A
514E  DD 77 06      LD (IX+6),A
5151  3E 0C         LD A,0x0C
5153  DD CB 0B 66   BIT 4,(IX+11)
5157  20 01         JR NZ,loc_515A
5159  3C            INC A

loc_515A:
515A  D3 9C         OUT (0x9C),A  ; ctrl_latch
515C  C9            RET

; checksum every loaded DRAM image bank: set image_present, LCD progress, loop banks via set_bank_checksum
checksum_all_banks:
515D  3E 01         LD A,0x01
515F  32 C8 52      LD (image_present),A
5162  3A 34 31      LD A,(op_word)
5165  E6 0F         AND 0x0F
5167  FE 07         CP 0x07
5169  28 21         JR Z,loc_518C
516B  CD 70 06      CALL lcd_clear_line2
516E  CD 59 4C      CALL lcd_print
5171  1B C0 52 41 4D 20 +  DB ESC(0xC0), "RAM checking - wait", 0
5187  3E FF         LD A,0xFF
5189  32 C7 52      LD (menu_scratch+0x5),A

loc_518C:
518C  DD 21 DD 52   LD IX,format_desc
5190  DD 7E 0C      LD A,(IX+12)

loc_5193:
5193  3C            INC A
5194  FE FF         CP 0xFF
5196  C8            RET Z
5197  CD 9C 51      CALL set_bank_checksum
519A  18 F7         JR loc_5193

; select DRAM bank A (OUT 0xB0), compute image_checksum, store two's-complement at 0xFFFF so bank sums to 0
set_bank_checksum:
519C  D3 B0         OUT (0xB0),A  ; dram_bank
519E  47            LD B,A
519F  CD A9 51      CALL image_checksum
51A2  ED 44         NEG
51A4  32 FF FF      LD (image_buf+0x7FFF),A
51A7  78            LD A,B
51A8  C9            RET

; checksum the whole DRAM image (sum 0x8000..0xFFFF)
image_checksum:
51A9  3E 00         LD A,0x00
51AB  21 00 80      LD HL,image_buf

loc_51AE:
51AE  86            ADD A,(HL)
51AF  2C            INC L
51B0  C2 AE 51      JP NZ,loc_51AE
51B3  24            INC H
51B4  C2 AE 51      JP NZ,loc_51AE
51B7  2B            DEC HL
51B8  96            SUB (HL)
51B9  C9            RET

; verify next DRAM bank checksum (bank counter 0x52C7): add image_checksum, expect 0; pulses panel busy + LCD
verify_ram_bank:
51BA  E5            PUSH HL
51BB  21 58 4A      LD HL,panel_shadow
51BE  7E            LD A,(HL)
51BF  CB 9F         RES 3,A
51C1  D3 F0         OUT (0xF0),A  ; panel
51C3  21 01 00      LD HL,0x0001
51C6  CD 22 4C      CALL lcd_setpos
51C9  CB DF         SET 3,A
51CB  D3 F0         OUT (0xF0),A  ; panel
51CD  21 C7 52      LD HL,menu_scratch+0x5
51D0  7E            LD A,(HL)
51D1  FE FF         CP 0xFF
51D3  20 09         JR NZ,loc_51DE
51D5  DD 21 DD 52   LD IX,format_desc
51D9  DD 7E 0C      LD A,(IX+12)
51DC  3C            INC A
51DD  77            LD (HL),A

loc_51DE:
51DE  34            INC (HL)
51DF  D3 B0         OUT (0xB0),A  ; dram_bank
51E1  CD A9 51      CALL image_checksum
51E4  86            ADD A,(HL)
51E5  E1            POP HL
51E6  C9            RET

; build FDC unit-select byte: index cfg table 0x5227 then OR option bits from format_desc IX+11; result stored to unit_sel by callers
fdc_build_unit_sel:
51E7  CD 0A 52      CALL media_cfg_index
51EA  5F            LD E,A
51EB  16 00         LD D,0x00
51ED  21 27 52      LD HL,fdc_flag_tbl
51F0  19            ADD HL,DE
51F1  7E            LD A,(HL)
51F2  DD CB 0B 66   BIT 4,(IX+11)
51F6  28 02         JR Z,loc_51FA
51F8  CB EF         SET 5,A

loc_51FA:
51FA  DD CB 0B 6E   BIT 5,(IX+11)
51FE  28 02         JR Z,loc_5202
5200  CB F7         SET 6,A

loc_5202:
5202  DD CB 0B 56   BIT 2,(IX+11)
5206  C8            RET Z
5207  CB FF         SET 7,A
5209  C9            RET

; compute media-config table index from format_desc IX+11 density/side/option bits
media_cfg_index:
520A  AF            XOR A
520B  DD 21 DD 52   LD IX,format_desc
520F  DD CB 0B 5E   BIT 3,(IX+11)
5213  28 02         JR Z,loc_5217
5215  CB D7         SET 2,A

loc_5217:
5217  DD CB 0B 76   BIT 6,(IX+11)
521B  28 02         JR Z,loc_521F
521D  CB CF         SET 1,A

loc_521F:
521F  DD CB 0B 7E   BIT 7,(IX+11)
5223  C8            RET Z
5224  CB C7         SET 0,A
5226  C9            RET

fdc_flag_tbl:
5227  00 00 05 07 03 00 04 06                         |........|

; generic 4-key menu driver (HL=draw+action ptr lists); see docs
menu_run:
522F  06 00         LD B,0x00
5231  E5            PUSH HL

loc_5232:
5232  7E            LD A,(HL)
5233  23            INC HL
5234  04            INC B
5235  B6            OR (HL)
5236  23            INC HL
5237  20 F9         JR NZ,loc_5232
5239  E5            PUSH HL
523A  DD E1         POP IX
523C  FD E1         POP IY
523E  DD 22 C2 52   LD (menu_scratch),IX
5242  FD 22 C4 52   LD (menu_scratch+0x2),IY

loc_5246:
5246  0E 01         LD C,0x01

loc_5248:
5248  21 56 52      LD HL,loc_5256
524B  E5            PUSH HL
524C  FD 6E 00      LD L,(IY+0)
524F  FD 66 01      LD H,(IY+1)
5252  22 31 31      LD (phase_handler),HL
5255  E9            JP (HL)

loc_5256:
5256  CD 43 4D      CALL keypad_debounce
5259  FE 08         CP 0x08
525B  20 19         JR NZ,loc_5276
525D  DD 23         INC IX
525F  DD 23         INC IX
5261  FD 23         INC IY
5263  FD 23         INC IY
5265  0C            INC C
5266  78            LD A,B
5267  B9            CP C
5268  C2 48 52      JP NZ,loc_5248
526B  DD 2A C2 52   LD IX,(menu_scratch)
526F  FD 2A C4 52   LD IY,(menu_scratch+0x2)
5273  C3 46 52      JP loc_5246

loc_5276:
5276  FE 04         CP 0x04
5278  20 1B         JR NZ,loc_5295
527A  DD 2B         DEC IX
527C  DD 2B         DEC IX
527E  FD 2B         DEC IY
5280  FD 2B         DEC IY
5282  0D            DEC C
5283  20 C3         JR NZ,loc_5248
5285  48            LD C,B
5286  05            DEC B

loc_5287:
5287  DD 23         INC IX
5289  DD 23         INC IX
528B  FD 23         INC IY
528D  FD 23         INC IY
528F  10 F6         DJNZ loc_5287
5291  41            LD B,C
5292  0D            DEC C
5293  18 B3         JR loc_5248

loc_5295:
5295  FE 02         CP 0x02
5297  20 01         JR NZ,loc_529A
5299  C9            RET

loc_529A:
529A  DD E5         PUSH IX
529C  FD E5         PUSH IY
529E  C5            PUSH BC
529F  2A C2 52      LD HL,(menu_scratch)
52A2  E5            PUSH HL
52A3  2A C4 52      LD HL,(menu_scratch+0x2)
52A6  E5            PUSH HL
52A7  21 B2 52      LD HL,loc_52B2
52AA  E5            PUSH HL
52AB  DD 6E 00      LD L,(IX+0)
52AE  DD 66 01      LD H,(IX+1)
52B1  E9            JP (HL)

loc_52B2:
52B2  E1            POP HL
52B3  22 C4 52      LD (menu_scratch+0x2),HL
52B6  E1            POP HL
52B7  22 C2 52      LD (menu_scratch),HL
52BA  C1            POP BC
52BB  FD E1         POP IY
52BD  DD E1         POP IX
52BF  C3 48 52      JP loc_5248

menu_scratch:
52C2  02 00 02 00 00 FF                               |......|
image_present:
52C8  00                                              |.|

iovec_out:
52C9  4A 4C         DW byte_out   ; -> 0x4C4A

iovec_poll:
52CB  8E 4D         DW get_key_dispatch   ; -> 0x4D8E

iovec_beep:
52CD  E3 49         DW buzzer_beep   ; -> 0x49E3

ver_bootloader:
52CF  52 36 52 31 41 20 20 20 39 34 30 33 32 39       |R6R1A   940329|

format_desc:
52DD  50 02 0F 00 02 04 3C 00 78 00 1E 00 00 00 00 00 |P.....<.x.......|
52ED  00 00                                           |..|
cksum_calc:
52EF  00                                              |.|
cksum_ref:
52F0  C7 AA 00 00 00 00 00 00 00 00 00 00 00 00 98 21 |...............!|

; === equates: banked DRAM window >= 0x8000 (no ROM home; refined later) ===
image_buf    = 0x8000
