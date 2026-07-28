0000  3E 0F         LD A,0x0F  ; DMA master-clear / reset value for the uPD8237A
0002  D3 8D         OUT (0x8D),A  ; dma_mclr — reset all 4 DMA channels (master clear)
0004  D3 8F         OUT (0x8F),A  ; dma_wrmask — clear the DMA write-mask register
0006  3E A0         LD A,0xA0  ; DMA command word: enable controller, normal timing
0008  D3 88         OUT (0x88),A  ; dma_cmd — program the DMA command register
000A  21 00 80      LD HL,image_buf  ; point HL at image_buf (0x8000) for stack base
000D  F9            LD SP,HL  ; set SP just below image buffer (grows down from 0x8000)
000E  3E FF         LD A,0xFF  ; bank value 0xFF = program-RAM mirror
0010  D3 B0         OUT (0xB0),A  ; dram_bank — set DRAM bank low byte = 0xFF (program-RAM mirror)
0012  D3 C0         OUT (0xC0),A  ; dram_bank_hi — set DRAM bank high byte = 0xFF (the {0xC0,0xB0} bank pair) [probed]
0014  01 FF 5F      LD BC,0x5FFF  ; copy count 0x5FFF bytes (EPROM->DRAM relocation)
0017  21 22 00      LD HL,boot_cont  ; source = boot_cont in EPROM
001A  11 22 80      LD DE,image_buf+0x22  ; dest = image_buf+0x22 in shadow DRAM bank
001D  ED B0         LDIR  ; block-copy EPROM image into DRAM bank 0xFF
001F  C3 22 80      JP image_buf+0x22  ; jump into the relocated copy to continue from RAM

; boot continuation: also copied to DRAM 0x8022 and re-entered there after banking
boot_cont:
0022  3E 92         LD A,0x92  ; ctrl_latch value: map RAM over 0x0000-0x7FFF, set flags
0024  D3 9C         OUT (0x9C),A  ; ctrl_latch — drive the 0x9C addressable latch (switch to shadowed RAM)
0026  C3 00 01      JP boot_init  ; enter main boot_init now running from DRAM

padding:
0029  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00    |...............|
0038  C3 DB 45      JP fdc_isr  ; RST 38h / IM1 interrupt vector -> FDC interrupt service

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
0050  CD 59 4C      CALL lcd_print  ; print the model/date banner, then fall through to show cycle count

ver_firmware:
0053  0C 4D 36 54 39 49 +  DB \f, "M6T9I2F 961002", 0  ; form-feed + LCD model/date string 'M6T9I2F 961002'
0063  21 69 32      LD HL,cycle_cnt_lo  ; point HL at cycle_cnt_lo in EEPROM shadow
0066  06 04         LD B,0x04  ; transfer 4 bytes (32-bit cycle counter)
0068  0E FC         LD C,0xFC  ; EEPROM sub-address 0xFC for cycle counter
006A  AF            XOR A  ; A=0 -> read direction for eeprom_transfer
006B  CD 35 27      CALL eeprom_transfer  ; load 32-bit lifetime cycle count from EEPROM
006E  2A 69 32      LD HL,(cycle_cnt_lo)  ; fetch cycle counter low word
0071  ED 5B 6B 32   LD DE,(cycle_cnt_hi)  ; fetch cycle counter high word into DE
0075  06 08         LD B,0x08  ; 8 digits field width for the number
0077  0E 20         LD C,0x20  ; 0x20 = space pad / LCD column control
0079  AF            XOR A  ; A=0 decimal formatting flag
007A  CD FA 05      CALL num_to_lcd_alt  ; render the cycle count to the LCD
007D  3E 01         LD A,0x01  ; request 1 keypress
007F  CD 89 4D      CALL get_key  ; wait for a key acknowledging the model screen
0082  00            NOP  ; no-op (patch/alignment slot)
0083  C9            RET  ; return to caller

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
0100  F3            DI  ; disable interrupts for boot init
0101  21 00 80      LD HL,image_buf  ; point HL at image_buf (0x8000)
0104  F9            LD SP,HL  ; reset stack pointer below image buffer

; sum bytes 0x0100..0x52EF; compare to cksum_ref; mismatch -> CODE TRANSFER ERROR loop
boot_checksum:
0105  3E 00         LD A,0x00  ; seed running checksum accumulator = 0
0107  21 EF 52      LD HL,cksum_calc  ; start sum at top of code region (cksum_calc, 0x52EF)

loc_010A:
010A  86            ADD A,(HL)  ; add current byte to running 8-bit checksum
010B  2B            DEC HL  ; walk downward through code image
010C  47            LD B,A  ; stash sum in B across the H-test
010D  7C            LD A,H  ; load high byte of pointer to test for wrap past 0
010E  B7            OR A  ; set flags on H (loop until HL underflows below 0)
010F  78            LD A,B  ; restore accumulated sum into A
0110  C2 0A 01      JP NZ,loc_010A  ; keep summing while pointer hasn't reached 0
0113  32 EF 52      LD (cksum_calc),A  ; store computed checksum into cksum_calc
0116  CD D9 4D      CALL timer_uart_init  ; init PIT timers and SIO UARTs
0119  CD 3E 2B      CALL eeprom_io  ; prime EEPROM I2C bus lines
011C  CD 5E 2B      CALL i2c_read_start  ; issue I2C start for EEPROM read
011F  CD 66 2B      CALL i2c_read_byte  ; read one byte over I2C from EEPROM
0122  CD EF 2A      CALL eeprom_clk_idle  ; return EEPROM clock line to idle
0125  CD 3E 2B      CALL eeprom_io  ; re-init EEPROM I2C bus after access
0128  3A EF 52      LD A,(cksum_calc)  ; reload computed checksum
012B  21 F0 52      LD HL,cksum_ref  ; point at stored reference checksum
012E  BE            CP (HL)  ; compare computed vs reference checksum
012F  28 30         JR Z,run_entry  ; match -> proceed to run_entry
0131  CD D9 4D      CALL timer_uart_init  ; mismatch: re-init timers/UART before error screen

loc_0134:
0134  CD 59 4C      CALL lcd_print  ; print the error banner
0137  0C 43 4F 44 45 20 +  DB \f, "CODE TRANSFER", \r, \n, "ERROR", 0  ; form-feed + 'CODE TRANSFER / ERROR' LCD text
014D  3E 05         LD A,0x05  ; beep pattern length 5
014F  CD 66 27      CALL beep  ; sound the error beep
0152  3E 02         LD A,0x02  ; dump 2 bytes of hex
0154  21 EF 52      LD HL,cksum_calc  ; point at the (bad) checksum value
0157  CD 3B 4F      CALL lcd_dump_hex  ; show computed checksum in hex on LCD
015A  3E 05         LD A,0x05  ; beep pattern length 5
015C  CD 66 27      CALL beep  ; sound the error beep again
015F  18 D3         JR loc_0134  ; loop the CODE TRANSFER ERROR screen forever

; run/duplication mode entry (also target of host 0x0B run vector install)
run_entry:
0161  F3            DI  ; disable interrupts entering run mode
0162  21 00 80      LD HL,image_buf  ; point HL at image_buf (0x8000)
0165  F9            LD SP,HL  ; reset stack below image buffer
0166  3E FF         LD A,0xFF  ; all-ones panel state (LEDs off / idle)
0168  32 58 4A      LD (panel_shadow),A  ; save panel state to panel_shadow
016B  D3 F0         OUT (0xF0),A  ; panel — drive the front-panel latch
016D  CD 57 07      CALL drive_cfg_latch  ; apply per-drive datarate/enable config latch
0170  AF            XOR A  ; A=0 -> non-blocking key poll
0171  CD 89 4D      CALL get_key  ; poll for a held key at power-up
0174  E6 0F         AND 0x0F  ; mask to key code nibble
0176  FE 02         CP 0x02  ; key code 2 = enter config menu?
0178  CC 67 22      CALL Z,config_menu  ; if key 2 held, open config_menu
017B  CD DD 03      CALL dram_test  ; run the DRAM sizing/self-test
017E  DB D0         IN A,(0xD0)  ; al_data — flush stale byte from autoloader SIO (chan A)
0180  DB D0         IN A,(0xD0)  ; al_data — flush autoloader SIO RX
0182  DB D0         IN A,(0xD0)  ; al_data — flush autoloader SIO RX
0184  DB D0         IN A,(0xD0)  ; al_data — flush autoloader SIO RX
0186  DB D0         IN A,(0xD0)  ; al_data — flush autoloader SIO RX
0188  DB D8         IN A,(0xD8)  ; host_data — flush stale byte from host SIO (chan B)
018A  DB D8         IN A,(0xD8)  ; host_data — flush host SIO RX
018C  DB D8         IN A,(0xD8)  ; host_data — flush host SIO RX
018E  DB D8         IN A,(0xD8)  ; host_data — flush host SIO RX
0190  DB D8         IN A,(0xD8)  ; host_data — flush host SIO RX
0192  0E E0         LD C,0xE0  ; LCD command port register
0194  3E 48         LD A,0x48  ; 0x48 = LCD control/DDRAM command
0196  CD 43 4C      CALL lcd_byte_out  ; send byte to the LCD controller
0199  CD 59 4C      CALL lcd_print  ; print status glyph line
019C  20 20 11 11 11 13 +  DB "  ", \x11, \x11, \x11, \x13, \x1D, \x10, 0  ; LCD text: two spaces + arrow/status control glyphs
01A5  AF            XOR A  ; A=0 -> non-blocking key poll
01A6  CD 89 4D      CALL get_key  ; poll for a key
01A9  C4 50 00      CALL NZ,show_model_cycles  ; if a key was pressed, show model/cycle screen

loc_01AC:
01AC  AF            XOR A  ; A=0 -> non-blocking key poll
01AD  CD 89 4D      CALL get_key  ; poll for key release
01B0  20 FA         JR NZ,loc_01AC  ; spin until all keys released
01B2  CD B4 03      CALL dram_bank_cfg  ; configure DRAM banking for image buffer
01B5  3E 2D         LD A,0x2D  ; 0x2D initial active-drive config value
01B7  32 1E 31      LD (drv_active_cfg),A  ; store initial drv_active_cfg
01BA  C3 35 02      JP wait_autoloader_loop  ; enter the top idle loop (wait for autoloader)

; draw "FDD seek error", deselect drives, beep code 5, home LCD, then reset seek/format state
show_fdd_seek_error:
01BD  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
01C0  CD 59 4C      CALL lcd_print  ; print the error banner
01C3  0C 46 44 44 20 73 +  DB \f, "FDD seek error", 0  ; form-feed + 'FDD seek error' LCD text
01D3  CD 57 07      CALL drive_cfg_latch  ; de-select drives via config latch
01D6  3E 05         LD A,0x05  ; beep pattern length 5
01D8  CD 66 27      CALL beep  ; sound the seek-error beep
01DB  21 00 00      LD HL,0x0000  ; LCD cursor position 0,0
01DE  CD 22 4C      CALL lcd_setpos  ; home the LCD cursor

; reset seek/format state after error: fmt_mode=0x90, clear flag at 0x3150
reset_seek_state:
01E1  3E 90         LD A,0x90  ; 0x90 = default format-mode value
01E3  32 4C 31      LD (fmt_mode),A  ; reset fmt_mode after error
01E6  AF            XOR A  ; A=0
01E7  32 50 31      LD (edit_ndigits),A  ; clear edit_ndigits flag
01EA  C9            RET  ; return

loc_01EB:
01EB  CD EC 24      CALL show_wprotect  ; display write-protect status
01EE  CD A9 03      CALL lcd_home3  ; reposition LCD (line 3/home helper)
01F1  CD 69 25      CALL show_err_recovery  ; display error-recovery setting
01F4  CD A9 03      CALL lcd_home3  ; reposition LCD
01F7  CD A5 25      CALL show_serial_batch  ; display serial-batch setting
01FA  CD A9 03      CALL lcd_home3  ; reposition LCD
01FD  CD 2C 25      CALL show_copy_dir  ; display copy-direction setting
0200  CD A9 03      CALL lcd_home3  ; reposition LCD
0203  CD F8 28      CALL show_media_status  ; display media/drive status
0206  CD A9 03      CALL lcd_home3  ; reposition LCD
0209  AF            XOR A  ; A=0 -> non-blocking key poll
020A  CD 89 4D      CALL get_key  ; poll for a key
020D  28 26         JR Z,wait_autoloader_loop  ; no key -> back to wait_autoloader_loop
020F  3E 01         LD A,0x01  ; A=1 -> blocking key read
0211  CD 89 4D      CALL get_key  ; wait for a key
0214  E6 0F         AND 0x0F  ; mask key code nibble
0216  FE 02         CP 0x02  ; key code 2 = enter settings?
0218  20 1B         JR NZ,wait_autoloader_loop  ; not key 2 -> back to idle loop
021A  CD 9E 24      CALL config_wprotect  ; edit write-protect setting
021D  CD 1E 23      CALL config_err_recovery  ; edit error-recovery setting
0220  CD 69 23      CALL config_serialization  ; edit serialization setting
0223  CD BF 23      CALL config_copy_dir  ; edit copy-direction setting
0226  CD 09 24      CALL config_max_cyl  ; edit max-cylinder setting
0229  0E 00         LD C,0x00  ; EEPROM sub-address 0x00 for cfg_flags
022B  06 02         LD B,0x02  ; write 2 config bytes
022D  3E 01         LD A,0x01  ; A=1 -> write direction
022F  21 1C 31      LD HL,cfg_flags  ; point at cfg_flags block
0232  CD 35 27      CALL eeprom_transfer  ; persist config flags back to EEPROM

; top idle loop: 'Wait for autoloader', poll autoloader + host serial commands
wait_autoloader_loop:
0235  CD 59 4C      CALL lcd_print  ; print the idle banner
0238  0C 57 61 69 74 20 +  DB \f, "Wait for autoloader", 0  ; form-feed + 'Wait for autoloader' LCD text

; probe autoloader (ping via R); classify NOT CONNECTED vs COMMUNICATION ERROR
al_connect_probe:
024D  3E 01         LD A,0x01  ; assume autoloader present (flag=1)
024F  32 62 31      LD (al_present),A  ; set al_present
0252  06 52         LD B,0x52  ; autoloader 'R' (0x52) = reject, used here as a presence ping
0254  CD D9 13      CALL al_cmd_ack  ; send 'R' and await autoloader ACK
0257  28 40         JR Z,loc_0299  ; ACK ok -> continue to 'C' command probe
0259  FE 01         CP 0x01  ; compare result code to 1
025B  20 30         JR NZ,loc_028D  ; result != 1 -> handle other reply at loc_028D
025D  3A 4C 31      LD A,(fmt_mode)  ; load format-mode state
0260  B7            OR A  ; test fmt_mode for zero
0261  CA D9 02      JP Z,loc_02D9  ; fmt_mode=0 -> AUTOLOADER NOT CONNECTED screen
0264  CD 59 4C      CALL lcd_print  ; print the error banner
0267  0C 43 4F 4D 4D 55 +  DB \f, "COMMUNICATION ERROR", 0  ; form-feed + 'COMMUNICATION ERROR' LCD text
027C  3E 05         LD A,0x05  ; beep pattern length 5
027E  CD 66 27      CALL beep  ; sound the comms-error beep
0281  DB D0         IN A,(0xD0)  ; al_data — flush autoloader SIO RX
0283  DB D0         IN A,(0xD0)  ; al_data — flush autoloader SIO RX
0285  DB D0         IN A,(0xD0)  ; al_data — flush autoloader SIO RX
0287  CD 43 4D      CALL keypad_debounce  ; debounce/drain the keypad
028A  C3 35 02      JP wait_autoloader_loop  ; restart the idle loop

loc_028D:
028D  3E 52         LD A,0x52  ; expected echo 'R' (0x52)
028F  B8            CP B  ; compare returned byte in B to 'R'
0290  C2 99 02      JP NZ,loc_0299  ; echo mismatch -> retry via loc_0299
0293  CD 3D 03      CALL manual_mode  ; matched -> enter front-panel manual_mode
0296  C3 5C 03      JP loc_035C  ; continue at loc_035C after manual mode

loc_0299:
0299  06 43         LD B,0x43  ; autoloader 'C' (0x43) = calibrate/clear
029B  CD D9 13      CALL al_cmd_ack  ; send 'C' and await autoloader ACK
029E  CA 60 03      JP Z,loc_0360  ; ACK ok -> proceed to loc_0360
02A1  78            LD A,B  ; get returned reply byte from B
02A2  FE 45         CP 0x45  ; reply 'E' (0x45) = error?
02A4  20 33         JR NZ,loc_02D9  ; not an error reply -> NOT CONNECTED screen
02A6  CD FB 13      CALL al_cmd_status  ; query detailed autoloader status
02A9  20 2E         JR NZ,loc_02D9  ; status non-zero -> NOT CONNECTED screen
02AB  CD B0 02      CALL show_al_error  ; show autoloader error/status line
02AE  18 61         JR loc_0311  ; continue at loc_0311

; draw "AL error / Status" line, wait keypress; preserves A across the message (autoloader fault)
show_al_error:
02B0  F5            PUSH AF  ; preserve A (status code) across the message
02B1  2A 4C 31      LD HL,(fmt_mode)  ; load fmt_mode word
02B4  22 D1 02      LD (show_al_error+0x21),HL  ; self-modify: write fmt_mode word into the 'Status ..' text field
02B7  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
02BA  CD 59 4C      CALL lcd_print  ; print the status line
02BD  1B C0 41 4C 20 65 +  DB ESC(0xC0), "AL error   Status ..", 0  ; ESC 0xC0 (line 2) + 'AL error   Status ..' text
02D4  CD 43 4D      CALL keypad_debounce  ; debounce/drain the keypad while waiting
02D7  F1            POP AF  ; restore saved status code
02D8  C9            RET  ; return

loc_02D9:
02D9  CD 59 4C      CALL lcd_print  ; print the error banner
02DC  0C 41 55 54 4F 4C +  DB \f, "AUTOLOADER", \r, \n, "NOT CONNECTED", 0  ; form-feed + 'AUTOLOADER / NOT CONNECTED' LCD text
02F7  21 8A 33      LD HL,retry_ctr  ; point at retry_ctr
02FA  AF            XOR A  ; A=0
02FB  77            LD (HL),A  ; clear the retry counter
02FC  CD 0B 4D      CALL keypad_scan  ; scan keypad for input
02FF  20 02         JR NZ,loc_0303  ; key pressed -> loc_0303
0301  CB C6         SET 0,(HL)  ; no key: set bit0 of retry_ctr (mark retry pending)

loc_0303:
0303  E5            PUSH HL  ; save key-flag pointer across beep
0304  3E 05         LD A,0x05  ; beep code 5 (key-feedback tone)
0306  CD 66 27      CALL beep  ; short beep acknowledging keypress
0309  E1            POP HL  ; restore key-flag pointer
030A  CD 0B 4D      CALL keypad_scan  ; poll keypad; Z if no key pressed
030D  28 02         JR Z,loc_0311  ; no key -> skip flag set
030F  CB CE         SET 1,(HL)  ; mark bit1 (key-pressed flag)

loc_0311:
0311  E5            PUSH HL  ; save key-flag pointer
0312  CD 3D 03      CALL manual_mode  ; show MANUAL operation-mode banner
0315  3E 05         LD A,0x05  ; beep code 5
0317  CD 66 27      CALL beep  ; beep feedback
031A  E1            POP HL  ; restore key-flag pointer
031B  CD 0B 4D      CALL keypad_scan  ; poll keypad; NZ if key pressed
031E  20 3C         JR NZ,loc_035C  ; key pressed -> serial/host path
0320  3E 03         LD A,0x03  ; expected key code 3
0322  BE            CP (HL)  ; compare stored key vs 3
0323  20 37         JR NZ,loc_035C  ; not key 3 -> exit to loc_035C
0325  21 00 00      LD HL,0x0000  ; zero value
0328  22 69 32      LD (cycle_cnt_lo),HL  ; clear cycle counter low word
032B  22 6B 32      LD (cycle_cnt_hi),HL  ; clear cycle counter high word
032E  21 69 32      LD HL,cycle_cnt_lo  ; src = cycle counter block
0331  06 04         LD B,0x04  ; 4 bytes to transfer
0333  0E FC         LD C,0xFC  ; EEPROM address/cmd 0xFC
0335  3E 01         LD A,0x01  ; direction = write to EEPROM
0337  CD 35 27      CALL eeprom_transfer  ; persist cycle counter to CAT24C02
033A  C3 61 01      JP run_entry  ; enter run/copy loop

; MANUAL operation mode top level
manual_mode:
033D  CD 59 4C      CALL lcd_print  ; print inline LCD banner
0340  0C 4D 41 4E 55 41 +  DB \f, "MANUAL", \r, \n, "OPERATION MODE", 0  ; banner text: MANUAL / OPERATION MODE
0358  CD A9 03      CALL lcd_home3  ; reset LCD cursor to home
035B  C9            RET  ; return

loc_035C:
035C  AF            XOR A  ; zero
035D  32 62 31      LD (al_present),A  ; clear autoloader-present flag

loc_0360:
0360  06 00         LD B,0x00  ; status code 0
0362  CD 9D 4E      CALL host_tx  ; notify host of current status
0365  CD 09 07      CALL motor_ready_wait  ; spin up motor and wait until ready
0368  CD 84 37      CALL fdc_home_head  ; recalibrate head to track 0
036B  DC BD 01      CALL C,show_fdd_seek_error  ; on seek error show fault message
036E  CD 57 07      CALL drive_cfg_latch  ; latch drive configuration
0371  3A 1D 31      LD A,(cfg_byte)  ; load current config byte
0374  DD 21 DD 52   LD IX,format_desc  ; point IX at format descriptor
0378  DD BE 0B      CP (IX+11)  ; compare vs stored format field 11
037B  DD 77 0B      LD (IX+11),A  ; store new config into descriptor field 11
037E  32 4C 31      LD (fmt_mode),A  ; save as current format mode
0381  28 04         JR Z,loc_0387  ; config unchanged -> keep image valid
0383  AF            XOR A  ; zero
0384  32 C8 52      LD (image_present),A  ; config changed -> invalidate loaded image

loc_0387:
0387  3E FE         LD A,0xFE  ; scratch init value 0xFE
0389  32 C7 52      LD (menu_scratch+0x5),A  ; init menu scratch flag
038C  CD 32 04      CALL fdd_detect  ; detect FDDs, select phase handler
038F  CD E7 51      CALL fdc_build_unit_sel  ; build FDC unit-select byte
0392  32 37 31      LD (unit_sel),A  ; save unit-select byte
0395  3E 81         LD A,0x81  ; side/head select value 0x81
0397  32 63 31      LD (side_sel),A  ; save side-select
039A  3A 37 31      LD A,(unit_sel)  ; reload unit-select byte
039D  CD 7B 04      CALL fdc_cmd_both_drives  ; issue command to both drives
03A0  2A 31 31      LD HL,(phase_handler)  ; load installed phase-handler ptr
03A3  CD 2F 52      CALL menu_run  ; run menu with phase handler
03A6  C3 EB 01      JP loc_01EB  ; return to main loop

; reset LCD cursor to home (0,0), repeated 3x (multi-line addressing workaround)
lcd_home3:
03A9  06 03         LD B,0x03  ; repeat home 3 times
03AB  21 00 00      LD HL,0x0000  ; cursor position (0,0)

loc_03AE:
03AE  CD 22 4C      CALL lcd_setpos  ; set LCD cursor to home
03B1  10 FB         DJNZ loc_03AE  ; loop remaining home repeats
03B3  C9            RET  ; return

; select DRAM image bank + latch drive config from cfg block
dram_bank_cfg:
03B4  21 1C 31      LD HL,cfg_flags  ; src = cfg flags block
03B7  0E 00         LD C,0x00  ; EEPROM address 0
03B9  06 04         LD B,0x04  ; 4 bytes
03BB  AF            XOR A  ; direction = read from EEPROM
03BC  CD 35 27      CALL eeprom_transfer  ; load cfg block from CAT24C02
03BF  3A 1E 31      LD A,(drv_active_cfg)  ; active drive-config latch value
03C2  D3 9C         OUT (0x9C),A  ; ctrl_latch — write drive config to ctrl latch
03C4  32 55 31      LD (wprot_mode),A  ; save latch/write-protect value
03C7  3A 1F 31      LD A,(cfg_batch)  ; config batch byte
03CA  32 4A 31      LD (err_recovery),A  ; save error-recovery setting
03CD  3A 1D 31      LD A,(cfg_byte)  ; load config byte
03D0  E6 03         AND 0x03  ; keep low 2 bits (datarate index)
03D2  21 67 31      LD HL,hrd_desc_tbl  ; point at hardware-descriptor table
03D5  77            LD (HL),A  ; store datarate index
03D6  C9            RET  ; return

; restore active DRAM bank (OUT 0x9C) from saved value
ctrl_latch_load:
03D7  3A 55 31      LD A,(wprot_mode)  ; saved latch/write-protect value
03DA  D3 9C         OUT (0x9C),A  ; ctrl_latch — restore ctrl latch
03DC  C9            RET  ; return

; size installed DRAM banks (walk via OUT 0xB0, test @0x8000) -> 'Test dram: N kB'
dram_test:
03DD  CD 59 4C      CALL lcd_print  ; print header
03E0  0C 54 65 73 74 20 +  DB \f, "Test dram:", 0  ; header text: Test dram:
03EC  3E FE         LD A,0xFE  ; start at top bank 0xFE, walk down

loc_03EE:
03EE  D3 B0         OUT (0xB0),A  ; dram_bank — select DRAM bank under test
03F0  21 00 80      LD HL,image_buf  ; test address 0x8000 (image_buf)
03F3  77            LD (HL),A  ; write bank id as test pattern
03F4  BE            CP (HL)  ; read back and verify
03F5  20 29         JR NZ,loc_0420  ; mismatch -> past last installed bank
03F7  E5            PUSH HL  ; HL -> stack
03F8  D1            POP DE  ; DE = HL
03F9  E5            PUSH HL  ; HL -> stack
03FA  C1            POP BC  ; BC = HL (fill count 0x8000)
03FB  13            INC DE  ; DE = HL+1 for overlap fill
03FC  ED B0         LDIR  ; fill whole bank with pattern (exercise DRAM)
03FE  F5            PUSH AF  ; save bank id
03FF  ED 44         NEG  ; A = -bank = banks tested so far
0401  6F            LD L,A  ; HL low = count
0402  26 00         LD H,0x00  ; HL high = 0
0404  5C            LD E,H  ; clear E (24-bit accumulator)
0405  06 05         LD B,0x05  ; shift 5 times (x32 -> kB size)

loc_0407:
0407  CB 25         SLA L  ; shift low byte left
0409  CB 14         RL H  ; carry into high byte
040B  CB 13         RL E  ; carry into top byte
040D  10 F8         DJNZ loc_0407  ; repeat shift x5
040F  CD B2 4E      CALL bin2dec_clear  ; convert binary to decimal
0412  CD 2C 4F      CALL lcd_print_number  ; print kB count
0415  CD 59 4C      CALL lcd_print  ; print units string
0418  20 6B 42 00   DB " kB", 0  ; units text: kB
041C  F1            POP AF  ; restore bank id
041D  3D            DEC A  ; step to next lower bank
041E  18 CE         JR loc_03EE  ; loop to test next bank

loc_0420:
0420  3C            INC A  ; adjust to installed-bank count
0421  32 30 31      LD (dram_bank_count),A  ; save DRAM bank count
0424  CD 59 4C      CALL lcd_print  ; print status
0427  20 6F 6B 00   DB " ok", 0  ; status text: ok
042B  21 00 00      LD HL,0x0000  ; cursor home
042E  CD 22 4C      CALL lcd_setpos  ; set LCD cursor to home
0431  C9            RET  ; return

; detect FDDs, derive media-config index, install phase_handler from phase_handler_tbl
fdd_detect:
0432  3A 4C 31      LD A,(fmt_mode)  ; load format mode
0435  CD 0A 52      CALL media_cfg_index  ; derive media-config index
0438  FE 00         CP 0x00  ; index 0?
043A  28 18         JR Z,loc_0454  ; index 0 -> unsupported
043C  FE 01         CP 0x01  ; index 1?
043E  28 14         JR Z,loc_0454  ; index 1 -> unsupported
0440  FE 05         CP 0x05  ; index 5?
0442  28 10         JR Z,loc_0454  ; index 5 -> unsupported
0444  6F            LD L,A  ; HL low = index
0445  26 00         LD H,0x00  ; HL high = 0
0447  29            ADD HL,HL  ; x2 for word-sized table entries
0448  11 44 14      LD DE,phase_handler_tbl  ; phase-handler table base
044B  19            ADD HL,DE  ; index into table
044C  5E            LD E,(HL)  ; handler ptr low
044D  23            INC HL  ; advance to high byte
044E  56            LD D,(HL)  ; handler ptr high
044F  ED 53 31 31   LD (phase_handler),DE  ; install selected phase handler
0453  C9            RET  ; return

loc_0454:
0454  CD 59 4C      CALL lcd_print  ; print error
0457  0C 55 6E 73 75 70 +  DB \f, "Unsupported FDD", \r, \n, "Run config again", 0  ; error text: Unsupported FDD / run config
047A  76            HALT  ; halt on unsupported media

; issue FDC command A to both drives via fdc_op_dispatch; head-select byte from cyl_head bit7
fdc_cmd_both_drives:
047B  47            LD B,A  ; save FDC command byte
047C  3A 64 31      LD A,(cyl_head)  ; load cyl/head byte
047F  CB 7F         BIT 7,A  ; test head/side bit7
0481  0E 11         LD C,0x11  ; default head-select byte 0x11
0483  20 01         JR NZ,loc_0486  ; bit7 set -> use default
0485  4F            LD C,A  ; else use cyl_head value

loc_0486:
0486  C5            PUSH BC  ; save command/head bytes
0487  3E 01         LD A,0x01  ; select drive 1
0489  CD B2 33      CALL fdc_op_dispatch  ; dispatch command to drive 1
048C  C1            POP BC  ; restore command/head bytes
048D  3E 02         LD A,0x02  ; select drive 2
048F  CD B2 33      CALL fdc_op_dispatch  ; dispatch command to drive 2
0492  C9            RET  ; return

; 'No. of copies' editor
edit_num_copies:
0493  CD 59 4C      CALL lcd_print  ; print prompt
0496  1B C0 4E 6F 2E 20 +  DB ESC(0xC0), "No. of copies", 0  ; prompt text: No. of copies
04A6  2A 3D 31      LD HL,(run_count)  ; current copy count
04A9  22 43 31      LD (edit_value),HL  ; seed editor value
04AC  21 00 00      LD HL,0x0000  ; zero
04AF  22 45 31      LD (edit_value_hi),HL  ; clear editor high word
04B2  06 04         LD B,0x04  ; 4-digit field
04B4  3E 0E         LD A,0x0E  ; cursor column/mode 0x0E
04B6  CD C3 04      CALL edit_num_field  ; run numeric field editor
04B9  2A 43 31      LD HL,(edit_value)  ; read edited value
04BC  22 3D 31      LD (run_count),HL  ; store as run count
04BF  22 41 31      LD (copy_count),HL  ; store as copy count
04C2  C9            RET  ; return

; edit a numeric field on the LCD (cursor on, +/- keys, Enter)
edit_num_field:
04C3  4F            LD C,A  ; stash field-mode param (0x0E) in C
04C4  C5            PUSH BC  ; save B/C
04C5  3E 0E         LD A,0x0E  ; LCD display-on + cursor cmd 0x0E
04C7  0E E0         LD C,0xE0  ; LCD command register port 0xE0
04C9  CD 43 4C      CALL lcd_byte_out  ; send cursor-on command to LCD
04CC  AF            XOR A  ; zero
04CD  32 4C 31      LD (fmt_mode),A  ; clear edit/format state

loc_04D0:
04D0  ED 5B 45 31   LD DE,(edit_value_hi)  ; load editor high word
04D4  2A 43 31      LD HL,(edit_value)  ; load editor low word
04D7  C1            POP BC  ; restore B/C
04D8  C5            PUSH BC  ; re-save B/C
04D9  79            LD A,C  ; A = field mode param (0x0E); B still holds digit count
04DA  0E 30         LD C,0x30  ; ASCII '0' base
04DC  CD FA 05      CALL num_to_lcd_alt  ; render number onto LCD
04DF  01 07 00      LD BC,0x0007  ; 7 bytes
04E2  21 4D 31      LD HL,al_status1  ; src = autoloader status buffer
04E5  11 4E 31      LD DE,run_status  ; dst = run status buffer
04E8  36 00         LD (HL),0x00  ; clear first byte
04EA  ED B0         LDIR  ; copy/clear status buffer
04EC  C1            POP BC  ; restore B/C
04ED  C5            PUSH BC  ; re-save B/C
04EE  48            LD C,B  ; C = digit count
04EF  06 00         LD B,0x00  ; high byte 0
04F1  21 38 4F      LD HL,lcd_dec_tmpl+0x9  ; src = LCD decimal template
04F4  11 4D 31      LD DE,al_status1  ; dst = autoloader status buffer

loc_04F7:
04F7  7E            LD A,(HL)  ; load next ASCII digit of the string
04F8  D6 30         SUB 0x30  ; ASCII '0'..'9' -> binary 0..9
04FA  77            LD (HL),A  ; store the converted binary digit back in place
04FB  ED A8         LDD  ; copy byte, dec HL/DE, dec BC (backward pack)
04FD  13            INC DE  ; advance DE past the skipped source byte
04FE  13            INC DE  ; and skip a second byte (2-byte stride)
04FF  EA F7 04      JP PE,loc_04F7  ; loop back while BC parity flag still set (more digits)
0502  CD 2A 4C      CALL lcd_wait_busy  ; wait for LCD controller not busy
0505  C1            POP BC  ; peek saved drive/count pair
0506  C5            PUSH BC  ; keep it on the stack
0507  79            LD A,C  ; A = low count byte
0508  80            ADD A,B  ; add high byte -> total item count
0509  21 4C 31      LD HL,fmt_mode  ; point at current format-menu index
050C  96            SUB (HL)  ; subtract index -> remaining position
050D  3D            DEC A  ; adjust to zero-based
050E  F6 C0         OR 0xC0  ; OR 0xC0 = HD44780 set-DDRAM-addr line 2 (cursor position from menu index)
0510  01 E0 00      LD BC,0x00E0  ; BC = LCD command/instruction port 0xE0
0513  ED 79         OUT (C),A  ; write cursor/attribute byte to LCD
0515  3E 01         LD A,0x01  ; A = 1 (wait/blocking key-scan mode)
0517  CD 89 4D      CALL get_key  ; poll front-panel for a keypress
051A  FE 04         CP 0x04  ; was it the increment/up key (0x04)?
051C  C2 C5 05      JP NZ,loc_05C5  ; not up key -> handle other keys
051F  21 4C 31      LD HL,fmt_mode  ; point at format-menu index
0522  5E            LD E,(HL)  ; E = index
0523  16 00         LD D,0x00  ; clear high byte -> DE = index
0525  21 4D 31      LD HL,al_status1  ; base of per-mode status array
0528  19            ADD HL,DE  ; index into al_status1[mode]
0529  34            INC (HL)  ; bump that mode's status counter
052A  3E 0A         LD A,0x0A  ; compare against wrap limit 10
052C  BE            CP (HL)  ; reached 0x0A?
052D  20 02         JR NZ,loc_0531  ; no wrap needed -> continue
052F  36 00         LD (HL),0x00  ; wrap counter back to 0

loc_0531:
0531  11 E8 03      LD DE,0x03E8  ; DE = 1000 place-value multiplier
0534  3A 54 31      LD A,(edit_max)  ; load edit_max digit field
0537  0E 00         LD C,0x00  ; high byte of multiplicand = 0
0539  CD 05 4F      CALL mul16  ; HL = edit_max * 1000
053C  EB            EX DE,HL  ; move product into DE
053D  3E 10         LD A,0x10  ; AC low byte of 0x2710 = 10000 (second scale factor)
053F  0E 27         LD C,0x27  ; AC high byte of 10000 scale
0541  CD 05 4F      CALL mul16  ; HL = edit_max*1000*10000: edit_max lands at the 10^7 digit
0544  22 43 31      LD (edit_value),HL  ; seed 32-bit edit_value low word
0547  ED 53 45 31   LD (edit_value_hi),DE  ; seed edit_value high word
054B  11 E8 03      LD DE,0x03E8  ; DE = 1000
054E  3A 53 31      LD A,(edit_min)  ; load edit_min field
0551  0E 00         LD C,0x00  ; high byte 0
0553  CD 05 4F      CALL mul16  ; HL = edit_min * 1000
0556  EB            EX DE,HL  ; move product into DE
0557  3E E8         LD A,0xE8  ; low byte of 1000 scale
0559  0E 03         LD C,0x03  ; high byte -> 0x03E8 = 1000
055B  CD 05 4F      CALL mul16  ; rescale edit_min term
055E  CD E6 05      CALL acc32_add  ; add edit_min term into 32-bit edit_value
0561  11 E8 03      LD DE,0x03E8  ; DE = 1000
0564  3A 52 31      LD A,(edit_col)  ; load edit_col field
0567  0E 00         LD C,0x00  ; high byte 0
0569  CD 05 4F      CALL mul16  ; HL = edit_col * 1000
056C  EB            EX DE,HL  ; move product into DE
056D  3E 64         LD A,0x64  ; scale by 100
056F  0E 00         LD C,0x00  ; high byte 0
0571  CD 05 4F      CALL mul16  ; rescale edit_col term
0574  CD E6 05      CALL acc32_add  ; add edit_col term into edit_value
0577  11 E8 03      LD DE,0x03E8  ; DE = 1000
057A  3A 51 31      LD A,(edit_width)  ; load edit_width field
057D  0E 00         LD C,0x00  ; high byte 0
057F  CD 05 4F      CALL mul16  ; HL = edit_width * 1000
0582  EB            EX DE,HL  ; move product into DE
0583  3E 0A         LD A,0x0A  ; scale by 10
0585  0E 00         LD C,0x00  ; high byte 0
0587  CD 05 4F      CALL mul16  ; rescale edit_width term
058A  CD E6 05      CALL acc32_add  ; add edit_width term into edit_value
058D  11 E8 03      LD DE,0x03E8  ; DE = 1000
0590  3A 50 31      LD A,(edit_ndigits)  ; load edit_ndigits field
0593  0E 00         LD C,0x00  ; high byte 0
0595  CD 05 4F      CALL mul16  ; HL = edit_ndigits * 1000
0598  CD E6 05      CALL acc32_add  ; add edit_ndigits term into edit_value
059B  11 64 00      LD DE,0x0064  ; DE = 100 place value
059E  3A 4F 31      LD A,(rd_submode)  ; load rd_submode field
05A1  0E 00         LD C,0x00  ; high byte 0
05A3  CD 05 4F      CALL mul16  ; HL = rd_submode * 100
05A6  CD E6 05      CALL acc32_add  ; add rd_submode term into edit_value
05A9  11 0A 00      LD DE,0x000A  ; DE = 10 place value
05AC  3A 4E 31      LD A,(run_status)  ; load run_status field
05AF  0E 00         LD C,0x00  ; high byte 0
05B1  CD 05 4F      CALL mul16  ; HL = run_status * 10
05B4  CD E6 05      CALL acc32_add  ; add run_status term into edit_value
05B7  3A 4D 31      LD A,(al_status1)  ; load al_status1 (units digit)
05BA  6F            LD L,A  ; L = value
05BB  26 00         LD H,0x00  ; H = 0 -> HL = al_status1
05BD  54            LD D,H  ; D = 0
05BE  5C            LD E,H  ; E = 0 -> high word 0
05BF  CD E6 05      CALL acc32_add  ; add units term into edit_value
05C2  C3 D0 04      JP loc_04D0  ; return to menu redraw loop

loc_05C5:
05C5  FE 08         CP 0x08  ; was it the decrement/down key (0x08)?
05C7  20 10         JR NZ,loc_05D9  ; not down key -> check exit key
05C9  C1            POP BC  ; peek saved item count
05CA  C5            PUSH BC  ; keep on stack
05CB  21 4C 31      LD HL,fmt_mode  ; point at format-menu index
05CE  34            INC (HL)  ; advance menu index
05CF  78            LD A,B  ; A = item count limit
05D0  BE            CP (HL)  ; index past last item?
05D1  C2 D0 04      JP NZ,loc_04D0  ; still in range -> redraw menu
05D4  36 00         LD (HL),0x00  ; wrap index back to 0
05D6  C3 D0 04      JP loc_04D0  ; redraw menu

loc_05D9:
05D9  FE 02         CP 0x02  ; was it the exit/cancel key (0x02)?
05DB  F5            PUSH AF  ; save the compare result flags
05DC  3E 0C         LD A,0x0C  ; A = 0x0C: LCD display-on, cursor off
05DE  0E E0         LD C,0xE0  ; C = LCD command port 0xE0
05E0  CD 43 4C      CALL lcd_byte_out  ; send LCD control byte
05E3  F1            POP AF  ; restore key-compare flags for caller
05E4  C1            POP BC  ; drop saved count
05E5  C9            RET  ; return (Z set if exit key)

; add 16-bit HL into the 32-bit accumulator at 0x3143/0x3145 (edit-field value builder)
acc32_add:
05E6  D5            PUSH DE  ; save caller's high-word argument (DE)
05E7  ED 5B 43 31   LD DE,(edit_value)  ; DE = accumulator low word
05EB  19            ADD HL,DE  ; add HL into low word
05EC  22 43 31      LD (edit_value),HL  ; store back low word
05EF  E1            POP HL  ; recover high-word argument into HL
05F0  ED 5B 45 31   LD DE,(edit_value_hi)  ; DE = accumulator high word
05F4  ED 5A         ADC HL,DE  ; add high words with carry
05F6  22 45 31      LD (edit_value_hi),HL  ; store back high word
05F9  C9            RET  ; return

; num_to_lcd variant with extra attribute bit (0xC0) selecting alternate LCD line/position
num_to_lcd_alt:
05FA  F6 C0         OR 0xC0  ; OR 0xC0: position lands on LCD line 2 (set-DDRAM-addr base)

; render 16-bit value as right-justified decimal on LCD at position A, field width B, pad char C
num_to_lcd:
05FC  F6 80         OR 0x80  ; OR 0x80: position lands on LCD line 1 (set-DDRAM-addr base)
05FE  32 30 06      LD (lcd_num_tmpl+0x1),A  ; store position/attribute into LCD template
0601  E5            PUSH HL  ; save value to render
0602  C5            PUSH BC  ; save field width/pad regs
0603  06 08         LD B,0x08  ; 8 template digit bytes to clear
0605  21 31 06      LD HL,lcd_num_tmpl+0x2  ; point at template digit area

loc_0608:
0608  36 00         LD (HL),0x00  ; blank one template byte
060A  23            INC HL  ; next byte
060B  10 FB         DJNZ loc_0608  ; loop over all 8 template bytes
060D  C1            POP BC  ; restore B=width, C=pad
060E  C5            PUSH BC  ; save them again
060F  21 38 4F      LD HL,lcd_dec_tmpl+0x9  ; point at end of decimal scratch buffer

loc_0612:
0612  71            LD (HL),C  ; prefill scratch cell with pad char C
0613  2B            DEC HL  ; step backward
0614  10 FC         DJNZ loc_0612  ; fill B cells with pad char
0616  C1            POP BC  ; restore B/C
0617  E1            POP HL  ; restore value to render
0618  C5            PUSH BC  ; save width/pad regs
0619  CD B5 4E      CALL bin2dec  ; convert HL to decimal digits in scratch
061C  21 38 4F      LD HL,lcd_dec_tmpl+0x9  ; point at end of decimal string
061F  C1            POP BC  ; restore width into B
0620  48            LD C,B  ; C = requested field width
0621  06 00         LD B,0x00  ; high byte 0 -> BC = width
0623  A7            AND A  ; clear carry
0624  ED 42         SBC HL,BC  ; back up HL by field width
0626  23            INC HL  ; step to first digit of the field
0627  11 31 06      LD DE,lcd_num_tmpl+0x2  ; destination = LCD template digits
062A  ED B0         LDIR  ; copy width digits into template
062C  CD 59 4C      CALL lcd_print  ; send template to LCD

lcd_num_tmpl:
062F  1B 00 31 32 33 34 +  DB ESC(0x00), "12345678", 0  ; LCD template: ESC(pos) + 8 digit slots + terminator
063A  C9            RET  ; return

; show run counters on line 2: track_ctr and pass_ctr as two 4-digit decimals (OK/bad tally)
show_ok_bad_count:
063B  E5            PUSH HL  ; save HL
063C  F5            PUSH AF  ; save AF
063D  CD 70 06      CALL lcd_clear_line2  ; blank LCD line 2
0640  2A 39 31      LD HL,(track_ctr)  ; load track_ctr (OK tally)
0643  11 00 00      LD DE,0x0000  ; high word 0
0646  3E 00         LD A,0x00  ; LCD position 0 (start of line)
0648  0E 20         LD C,0x20  ; pad char = space
064A  06 04         LD B,0x04  ; field width = 4 digits
064C  CD FA 05      CALL num_to_lcd_alt  ; render track_ctr as 4-digit decimal
064F  CD 59 4C      CALL lcd_print  ; print following inline string
0652  20 6F 6B 00   DB " ok", 0  ; inline literal " ok"
0656  2A 3B 31      LD HL,(pass_ctr)  ; load pass_ctr (bad tally)
0659  11 00 00      LD DE,0x0000  ; high word 0
065C  3E 08         LD A,0x08  ; LCD position 8
065E  0E 20         LD C,0x20  ; pad char = space
0660  06 04         LD B,0x04  ; field width = 4 digits
0662  CD FA 05      CALL num_to_lcd_alt  ; render pass_ctr as 4-digit decimal
0665  CD 59 4C      CALL lcd_print  ; print following inline string
0668  20 62 61 64 00  DB " bad", 0  ; inline literal " bad"
066D  F1            POP AF  ; restore AF
066E  E1            POP HL  ; restore HL
066F  C9            RET  ; return

; blank LCD line 2 (ESC 0xC0 home + 20 spaces), preserving AF
lcd_clear_line2:
0670  F5            PUSH AF  ; save AF (preserve caller flags)
0671  CD 59 4C      CALL lcd_print  ; print inline blank-line sequence
0674  1B C0 20 20 20 20 +  DB ESC(0xC0), "                    ", 0  ; ESC(0xC0) home line 2 + 20 spaces
068B  F1            POP AF  ; restore AF
068C  C9            RET  ; return

; blank LCD line 1 (ESC 0x80 home + 20 spaces)
lcd_clear_line1:
068D  CD 59 4C      CALL lcd_print  ; print inline blank-line sequence
0690  1B 80 20 20 20 20 +  DB ESC(0x80), "                    ", 0  ; ESC(0x80) home line 1 + 20 spaces
06A7  C9            RET  ; return

; inc/dec an ASCII digit pair (config value at 0x27FC) per cfg_flags bit7 up/down, 0-9 wrap+carry
pit_adjust_digits:
06A8  3E D2         LD A,0xD2  ; A = 0xD2: LCD position for the config value
06AA  32 FA 27      LD (lcd_val_tmpl+0x1),A  ; store position into LCD value template
06AD  21 FC 27      LD HL,lcd_val_tmpl+0x3  ; point at the digit char in template
06B0  3A 1C 31      LD A,(cfg_flags)  ; load cfg_flags
06B3  CB 7F         BIT 7,A  ; test bit7 = up/down direction
06B5  28 03         JR Z,loc_06BA  ; clear -> decrement path
06B7  34            INC (HL)  ; up: increment ASCII digit
06B8  18 01         JR loc_06BB  ; skip decrement

loc_06BA:
06BA  35            DEC (HL)  ; down: decrement ASCII digit

loc_06BB:
06BB  3E 3A         LD A,0x3A  ; A = ':' ('9'+1)
06BD  BE            CP (HL)  ; digit overflowed past '9'?
06BE  3E 30         LD A,0x30  ; A = '0'
06C0  28 07         JR Z,loc_06C9  ; yes -> wrap to '0'
06C2  3E 2F         LD A,0x2F  ; A = '/' ('0'-1)
06C4  BE            CP (HL)  ; digit underflowed past '0'?
06C5  20 0F         JR NZ,loc_06D6  ; no wrap -> done
06C7  3E 39         LD A,0x39  ; yes -> wrap to '9'

loc_06C9:
06C9  77            LD (HL),A  ; store computed byte into buffer at HL
06CA  2B            DEC HL  ; back up to previous digit byte
06CB  3A 1C 31      LD A,(cfg_flags)  ; read config flags
06CE  CB 7F         BIT 7,A  ; test sign/direction flag bit 7
06D0  28 03         JR Z,loc_06D5  ; if clear, take decrement path
06D2  34            INC (HL)  ; bump digit up (flag-set direction)
06D3  18 01         JR loc_06D6  ; skip over the decrement branch

loc_06D5:
06D5  35            DEC (HL)  ; bump digit down (flag-clear direction)

loc_06D6:
06D6  CD F5 27      CALL hrd_emit_num  ; render the resulting number to display

; reload 8253 counters c1/c2 (control words 0x50,0x90) to restart index timing
pit_reload_c12:
06D9  3E 50         LD A,0x50  ; PIT counter-1 control word (mode/latch)
06DB  D3 AC         OUT (0xAC),A  ; pit_ctrl — program 8253 counter 1 via ctrl port
06DD  3E 90         LD A,0x90  ; PIT counter-2 control word
06DF  D3 AC         OUT (0xAC),A  ; pit_ctrl — program 8253 counter 2 via ctrl port
06E1  C9            RET  ; return

; step drive toward target track A, tracking current track at 0x3133, issuing seeks until reached
fdc_step_to_track:
06E2  21 33 31      LD HL,cur_track  ; point at current-track tracker
06E5  BE            CP (HL)  ; compare target track vs current
06E6  C8            RET Z  ; already at target, done
06E7  FA EC 06      JP M,loc_06EC  ; target below current, step down
06EA  34            INC (HL)  ; provisional step toward higher track
06EB  34            INC (HL)  ; second bump to net +1 after later DEC

loc_06EC:
06EC  F5            PUSH AF  ; save target track across the seek
06ED  35            DEC (HL)  ; advance current track by one step
06EE  7E            LD A,(HL)  ; fetch new current-track value
06EF  32 EB 4A      LD (drive_blk_a),A  ; set FDC seek target (low byte)
06F2  AF            XOR A  ; zero for seek target high byte
06F3  32 EC 4A      LD (drive_blk_a+0x1),A  ; seek target high byte = 0
06F6  3E 01         LD A,0x01  ; select unit 1
06F8  CD 2A 43      CALL fdc_seek_sel  ; issue seek to selected drive
06FB  3E 01         LD A,0x01  ; select unit 1
06FD  CD 25 07      CALL fdc_wait_unit1  ; wait for unit-1 seek to complete
0700  21 00 02      LD HL,0x0200  ; LCD cursor to row 0, col 2
0703  CD 22 4C      CALL lcd_setpos  ; position LCD cursor
0706  F1            POP AF  ; restore target track
0707  18 D9         JR fdc_step_to_track  ; loop until target track reached

; spin-up/ready wait: recalibrate+seek both drives, retry up to 5x; returns Z when ready
motor_ready_wait:
0709  AF            XOR A  ; zero to reset current-track tracker
070A  32 33 31      LD (cur_track),A  ; reset current-track tracker to 0
070D  CD 4F 07      CALL set_drive_cfg  ; drive select/motor active config to latches
0710  CD 2D 07      CALL seek_both_drives  ; recalibrate+seek both drives
0713  C8            RET Z  ; return if drives ready
0714  06 05         LD B,0x05  ; retry counter = 5

loc_0716:
0716  C5            PUSH BC  ; save retry count
0717  CD 4F 07      CALL set_drive_cfg  ; re-apply active drive config
071A  CD 2D 07      CALL seek_both_drives  ; retry recalibrate+seek both drives
071D  C1            POP BC  ; restore retry count
071E  C8            RET Z  ; return if now ready
071F  CD E1 01      CALL reset_seek_state  ; reset FDC seek state before retry
0722  10 F2         DJNZ loc_0716  ; loop while retries remain
0724  C9            RET  ; return (exhausted retries)

; poll FDC unit-1 seek/op completion, looping until done
fdc_wait_unit1:
0725  3E 01         LD A,0x01  ; select unit 1
0727  CD 2D 47      CALL fdc_poll_complete  ; poll unit-1 op completion
072A  28 F9         JR Z,fdc_wait_unit1  ; loop until completion reported
072C  C9            RET  ; return

; recalibrate+seek unit1 (and unit2 if double-sided), then flag not-ready error
seek_both_drives:
072D  3E 01         LD A,0x01  ; select unit 1
072F  CD 4C 39      CALL fdc_recal_seek  ; recalibrate then seek unit 1
0732  CD 25 07      CALL fdc_wait_unit1  ; wait for unit-1 completion
0735  DD 21 DD 52   LD IX,format_desc  ; point IX at format descriptor
0739  DD CB 0B 66   BIT 4,(IX+11)  ; test double-sided flag (byte 11 bit 4)
073D  28 0C         JR Z,loc_074B  ; single-sided, skip second unit
073F  3E 02         LD A,0x02  ; select unit 2
0741  CD 4C 39      CALL fdc_recal_seek  ; recalibrate then seek unit 2

loc_0744:
0744  3E 02         LD A,0x02  ; select unit 2
0746  CD 2D 47      CALL fdc_poll_complete  ; poll unit-2 op completion
0749  28 F9         JR Z,loc_0744  ; loop until unit-2 done

loc_074B:
074B  CD 81 49      CALL fdc_err_notready  ; flag drive not-ready error, sets Z on ready
074E  C9            RET  ; return

; load drv_active_cfg (0x2D active pattern) into both drive-config latches (ports 0x40/0x60); idle pattern is 0x0E
set_drive_cfg:
074F  3A 1E 31      LD A,(drv_active_cfg)  ; load active drive-select pattern
0752  D3 40         OUT (0x40),A  ; drv_lat0 — write to drive latch 0 (port 0x40)
0754  D3 60         OUT (0x60),A  ; drv_lat2 — write to drive latch 2 (port 0x60)
0756  C9            RET  ; return

; write 0x0E to both drive latches (0x40/0x60): deselect / motors-off idle state
drive_cfg_latch:
0757  3E 0E         LD A,0x0E  ; idle/deselect pattern 0x0E
0759  D3 40         OUT (0x40),A  ; drv_lat0 — write idle to drive latch 0
075B  3E 0E         LD A,0x0E  ; idle pattern 0x0E
075D  D3 60         OUT (0x60),A  ; drv_lat2 — write idle to drive latch 2
075F  C9            RET  ; return

; datarate ctrl-latch helper: set/clear bit2 of (HL), OUT to port C, mirror bit0 into ctrl_latch 0x9C
update_ctrl_latch:
0760  B7            OR A  ; set flags from A (rate select)
0761  CB 96         RES 2,(HL)  ; clear datarate bit 2 in latch byte
0763  20 02         JR NZ,loc_0767  ; A nonzero, leave bit 2 cleared
0765  CB D6         SET 2,(HL)  ; A==0, set datarate bit 2

loc_0767:
0767  57            LD D,A  ; save A in D
0768  7E            LD A,(HL)  ; load updated latch byte
0769  ED 79         OUT (C),A  ; write latch to port in C
076B  C8            RET Z  ; done if A was 0
076C  7A            LD A,D  ; restore original A
076D  FE 01         CP 0x01  ; was rate select == 1?
076F  7B            LD A,E  ; load ctrl_latch mirror value from E
0770  20 02         JR NZ,loc_0774  ; not rate 1, leave bit0 unchanged
0772  F6 01         OR 0x01  ; rate 1: set bit0 (EPROM/RAM map line)

loc_0774:
0774  D3 9C         OUT (0x9C),A  ; ctrl_latch — write to addressable ctrl latch
0776  C9            RET  ; return

; threshold table lookup: scan B entries at HL, return value C for the band matching input (rate/precomp by cyl)
range_table_lookup:
0777  C5            PUSH BC  ; save BC
0778  D5            PUSH DE  ; save DE
0779  51            LD D,C  ; copy input value into D

loc_077A:
077A  7A            LD A,D  ; load input value
077B  BE            CP (HL)  ; compare against this threshold
077C  23            INC HL  ; advance to band value slot
077D  FA 81 07      JP M,loc_0781  ; below threshold, keep previous band
0780  4E            LD C,(HL)  ; take this band's value into C

loc_0781:
0781  23            INC HL  ; advance to next threshold entry
0782  10 F6         DJNZ loc_077A  ; loop over remaining table entries
0784  79            LD A,C  ; return selected band value in A
0785  D1            POP DE  ; restore DE
0786  C1            POP BC  ; restore BC
0787  C9            RET  ; return

; duplication engine main loop: spin-up, read source, run current phase
dup_engine_loop:
0788  CD D7 03      CALL ctrl_latch_load  ; load control latch defaults

; ensure motor ready via motor_ready_wait; on failure jump to batch error tail 0x10B0
require_motor_ready:
078B  CD 09 07      CALL motor_ready_wait  ; wait for motors up to speed
078E  28 03         JR Z,loc_0793  ; ready, continue
0790  C3 B0 10      JP loc_10B0  ; not ready, jump to batch error tail

loc_0793:
0793  21 00 00      LD HL,0x0000  ; zero for track/pass counters
0796  22 39 31      LD (track_ctr),HL  ; reset track counter to 0
0799  22 3B 31      LD (pass_ctr),HL  ; reset pass counter to 0

loc_079C:
079C  CD 4F 07      CALL set_drive_cfg  ; re-apply active drive config each pass
079F  3A 34 31      LD A,(op_word)  ; load op word
07A2  A7            AND A  ; test op word
07A3  20 06         JR NZ,loc_07AB  ; op word set, go read source
07A5  3A 4E 31      LD A,(run_status)  ; load run status
07A8  A7            AND A  ; test run status
07A9  20 10         JR NZ,loc_07BB  ; nonzero, skip source read

loc_07AB:
07AB  CD B4 11      CALL read_source  ; read a track from the source disk
07AE  28 0B         JR Z,loc_07BB  ; read ok, continue
07B0  CD CB 1D      CALL show_abort  ; show abort message
07B3  21 34 31      LD HL,op_word  ; point at op word
07B6  CB FE         SET 7,(HL)  ; set abort flag bit 7
07B8  C3 B0 10      JP loc_10B0  ; jump to batch error tail

loc_07BB:
07BB  CD A0 11      CALL is_op_mode9  ; check for operation mode 9
07BE  CA 43 08      JP Z,loc_0843  ; mode 9, branch to display/format path
07C1  CD 34 08      CALL fdc_build_select  ; build FDC drive/head select byte
07C4  30 7D         JR NC,loc_0843  ; no drive selected, skip to error path
07C6  F5            PUSH AF  ; save select result
07C7  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
07CA  F1            POP AF  ; restore select result
07CB  FE 00         CP 0x00  ; was result code 0 (not ready)?
07CD  20 3D         JR NZ,loc_080C  ; nonzero, handle RPM out-of-range
07CF  CD 59 4C      CALL lcd_print  ; print message to LCD
07D2  1B C0 46 44 44 20 +  DB ESC(0xC0), "FDD not ready", 0  ; LCD string: move-to-line2 + "FDD not ready"

loc_07E2:
07E2  3E 05         LD A,0x05  ; beep code/count = 5
07E4  CD 66 27      CALL beep  ; sound alert beep
07E7  CD 2D 11      CALL al_cmd_reject  ; reject autoloader command
07EA  3E 92         LD A,0x92  ; format-mode value 0x92
07EC  32 4C 31      LD (fmt_mode),A  ; store into fmt_mode
07EF  AF            XOR A  ; zero to reset edit digit count
07F0  32 50 31      LD (edit_ndigits),A  ; reset edit digit count
07F3  3A 61 31      LD A,(host_mode)  ; load host-mode flag
07F6  B7            OR A  ; test host mode
07F7  C2 B0 10      JP NZ,loc_10B0  ; host mode active, go to error tail
07FA  AF            XOR A  ; clear A (key row 0)
07FB  CD 89 4D      CALL get_key  ; scan for a key press
07FE  28 9C         JR Z,loc_079C  ; no key, loop back to pass start
0800  3E 01         LD A,0x01  ; key row 1
0802  CD 89 4D      CALL get_key  ; scan key row
0805  E6 0F         AND 0x0F  ; isolate key code low nibble
0807  FE 02         CP 0x02  ; is it key 2 (cancel)?
0809  20 91         JR NZ,loc_079C  ; not cancel, loop back to pass start
080B  C9            RET  ; return

loc_080C:
080C  CD 11 08      CALL show_rpm_low  ; show RPM low/high warning
080F  18 D1         JR loc_07E2  ; join the beep/reject error path

; RPM out-of-range warning: A=1 draws "rpm low", A=2 "rpm high", 0 shows nothing
show_rpm_low:
0811  B7            OR A  ; check RPM warning code (0=none/1=low/2=high)
0812  C8            RET Z  ; 0 means show nothing, return
0813  FE 02         CP 0x02  ; A==2 means RPM high
0815  28 0E         JR Z,loc_0825  ; branch to rpm-high message
0817  CD 59 4C      CALL lcd_print  ; print message to LCD
081A  1B C0 72 70 6D 20 +  DB ESC(0xC0), "rpm low", 0  ; LCD string: move-to-line2 + "rpm low"
0824  C9            RET  ; return

loc_0825:
0825  CD 59 4C      CALL lcd_print  ; print message to LCD
0828  1B C0 72 70 6D 20 +  DB ESC(0xC0), "rpm high", 0  ; LCD string: move-to-line2 + "rpm high"
0833  C9            RET  ; return

; build FDC drive/head select byte from unit_sel/cyl_head
fdc_build_select:
0834  3A 37 31      LD A,(unit_sel)  ; load selected unit number
0837  47            LD B,A  ; unit into B
0838  3A 64 31      LD A,(cyl_head)  ; load cylinder/head byte
083B  E6 7F         AND 0x7F  ; mask off high (head-select) bit
083D  4F            LD C,A  ; cyl/head into C
083E  3E 01         LD A,0x01  ; operation code 1
0840  C3 DB 37      JP index_period_timer  ; tail-call index-period timer to select/seek

loc_0843:
0843  CD 81 49      CALL fdc_err_notready  ; test drive not-ready, sets Z if ready
0846  C4 09 07      CALL NZ,motor_ready_wait  ; if not ready, wait for motors
0849  C0            RET NZ  ; still not ready, return
084A  CD D9 06      CALL pit_reload_c12  ; reload PIT c1/c2 to restart index timing
084D  21 30 2F      LD HL,0x2F30  ; HL constant 0x2F30 (LCD/count param)
0850  3A 1C 31      LD A,(cfg_flags)  ; load config flags
0853  CB 7F         BIT 7,A  ; test flag bit 7
0855  20 18         JR NZ,loc_086F  ; bit 7 set, branch ahead
0857  E6 7F         AND 0x7F  ; mask off bit 7, keep count field
0859  20 04         JR NZ,loc_085F  ; nonzero count, use it
085B  3A DD 52      LD A,(format_desc)  ; load track/side count from format descriptor
085E  3D            DEC A  ; adjust down by 1

loc_085F:
085F  3C            INC A  ; restore/increment count by 1
0860  11 00 00      LD DE,0x0000  ; clear DE
0863  6F            LD L,A  ; count into L (low byte of value)
0864  63            LD H,E  ; high byte = 0
0865  CD B2 4E      CALL bin2dec_clear  ; convert binary to decimal, clearing template
0868  21 38 4F      LD HL,lcd_dec_tmpl+0x9  ; point at last two decimal template bytes
086B  56            LD D,(HL)  ; load high digit-pair byte into D
086C  2B            DEC HL  ; step to preceding byte
086D  5E            LD E,(HL)  ; load low byte into E
086E  EB            EX DE,HL  ; swap value into HL

loc_086F:
086F  22 FB 27      LD (lcd_val_tmpl+0x2),HL  ; store computed value into LCD display template field +2
0872  3A 34 31      LD A,(op_word)  ; load current operation code word
0875  CB 67         BIT 4,A  ; test op-word bit 4 (special/no-count operation flag)
0877  20 11         JR NZ,loc_088A  ; if bit4 set, skip the OK/bad count display
0879  E6 0F         AND 0x0F  ; isolate low nibble = operation type
087B  FE 00         CP 0x00  ; compare against op type 0
087D  28 0B         JR Z,loc_088A  ; op 0 needs no count line -> skip display
087F  FE 07         CP 0x07  ; compare against op type 7
0881  28 07         JR Z,loc_088A  ; op 7 skips count display
0883  FE 09         CP 0x09  ; compare against op type 9
0885  28 03         JR Z,loc_088A  ; op 9 skips count display
0887  CD 3B 06      CALL show_ok_bad_count  ; otherwise render the good/bad drive count on LCD

loc_088A:
088A  21 67 31      LD HL,hrd_desc_tbl  ; point at hardware descriptor table
088D  CB 4E         BIT 1,(HL)  ; test descriptor bit 1 (serial/config-copy enabled)
088F  28 27         JR Z,loc_08B8  ; if clear, skip serial number propagation
0891  3A 34 31      LD A,(op_word)  ; reload operation code word
0894  FE 01         CP 0x01  ; op 1 (copy)?
0896  28 0C         JR Z,loc_08A4  ; yes -> do serial copy
0898  FE 04         CP 0x04  ; op 4?
089A  28 08         JR Z,loc_08A4  ; yes -> do serial copy
089C  FE 02         CP 0x02  ; op 2?
089E  28 04         JR Z,loc_08A4  ; yes -> do serial copy
08A0  FE 06         CP 0x06  ; op 6?
08A2  20 14         JR NZ,loc_08B8  ; not a copy-type op -> skip serial copy

loc_08A4:
08A4  3A 72 31      LD A,(serial_bank)  ; get serial image bank number
08A7  ED 5B 73 31   LD DE,(serial_addr)  ; load destination address for serial block
08AB  21 68 31      LD HL,serial_num_lo  ; source = stored serial number bytes
08AE  01 04 00      LD BC,0x0004  ; copy 4 bytes of serial number
08B1  D3 B0         OUT (0xB0),A  ; dram_bank — select DRAM image bank holding this sector
08B3  ED B0         LDIR  ; block-copy serial bytes into image bank
08B5  CD 9C 51      CALL set_bank_checksum  ; recompute checksum for the modified bank

loc_08B8:
08B8  21 1C 31      LD HL,cfg_flags  ; point at config flags byte
08BB  CB 7E         BIT 7,(HL)  ; test cfg bit 7 (skip-format / manual override)
08BD  20 14         JR NZ,loc_08D3  ; if set, force starting track 0
08BF  7E            LD A,(HL)  ; read config flags
08C0  E6 7F         AND 0x7F  ; mask off bit 7, keep track/step count
08C2  20 04         JR NZ,loc_08C8  ; nonzero -> use configured start track
08C4  3A DD 52      LD A,(format_desc)  ; else derive start from format descriptor
08C7  3D            DEC A  ; format track count minus 1 = last track index

loc_08C8:
08C8  F5            PUSH AF  ; preserve computed start-track value
08C9  CD E2 06      CALL fdc_step_to_track  ; step FDC head to target track
08CC  CD 34 08      CALL fdc_build_select  ; build drive-select mask for the FDCs
08CF  F1            POP AF  ; restore start-track value
08D0  6F            LD L,A  ; put start track into L
08D1  18 02         JR loc_08D5  ; join common path

loc_08D3:
08D3  2E 00         LD L,0x00  ; override start track = 0

loc_08D5:
08D5  26 00         LD H,0x00  ; clear H, HL = 16-bit start track index
08D7  22 35 31      LD (datarate_idx),HL  ; save as current data-rate/track index
08DA  AF            XOR A  ; A = 0
08DB  32 49 31      LD (op_flag_49),A  ; clear operation flag byte 0x3149
08DE  DD 21 DD 52   LD IX,format_desc  ; point IX at format descriptor block
08E2  DD 46 00      LD B,(IX+0)  ; B = descriptor byte 0 (default track/pass count)
08E5  3A 1C 31      LD A,(cfg_flags)  ; read config flags
08E8  E6 7F         AND 0x7F  ; mask off bit 7
08EA  28 02         JR Z,loc_08EE  ; zero -> keep default count from descriptor
08EC  3C            INC A  ; configured count +1
08ED  47            LD B,A  ; use configured value as loop count B

loc_08EE:
08EE  21 77 31      LD HL,serial_ptr+0x2  ; point at serial pointer +2 status byte
08F1  CB C6         SET 0,(HL)  ; set bit 0 (mark pass in progress)

loc_08F3:
08F3  C5            PUSH BC  ; save outer loop counter
08F4  2A 35 31      LD HL,(datarate_idx)  ; load current track index
08F7  FD 21 EB 4A   LD IY,drive_blk_a  ; point IY at drive A control block
08FB  FD 75 00      LD (IY+0),L  ; store track index low into drive block
08FE  FD 74 01      LD (IY+1),H  ; store track index high into drive block
0901  3E 01         LD A,0x01  ; A = 1 (seek command / drive flag)
0903  CD 2A 43      CALL fdc_seek_sel  ; issue FDC seek to selected drive
0906  21 2F 31      LD HL,fmt_geom_ptr+0xF  ; point at format geometry pointer +0xF status
0909  CB C6         SET 0,(HL)  ; set bit 0 flag
090B  CD A8 06      CALL pit_adjust_digits  ; adjust PIT-derived digit/timing values
090E  DD 21 DD 52   LD IX,format_desc  ; point IX at format descriptor
0912  DD 46 01      LD B,(IX+1)  ; B = descriptor byte 1 (inner sector/pass count)

loc_0915:
0915  C5            PUSH BC  ; save inner loop counter
0916  21 5F 31      LD HL,fdc_rate_a  ; point at FDC rate-A scratch pair
0919  AF            XOR A  ; A = 0
091A  77            LD (HL),A  ; clear rate-A byte
091B  23            INC HL  ; advance to rate-B byte
091C  77            LD (HL),A  ; clear rate-B byte
091D  DB F0         IN A,(0xF0)  ; panel — read front panel input port
091F  CB 7F         BIT 7,A  ; test panel bit 7 (abort/key held?)
0921  3A 35 31      LD A,(datarate_idx)  ; load current track index
0924  4F            LD C,A  ; C = index into rate table
0925  06 06         LD B,0x06  ; B = 6 table entries to scan
0927  21 A1 31      LD HL,hrd_hd0  ; point at head-0 range table
092A  CD 77 07      CALL range_table_lookup  ; look up data-rate value for this track range
092D  32 5F 31      LD (fdc_rate_a),A  ; store selected FDC rate-A value
0930  21 AD 31      LD HL,hrd_test_idx+0x8  ; point at second (head-1) range table +8
0933  CD 77 07      CALL range_table_lookup  ; look up data-rate value for head 1
0936  32 60 31      LD (fdc_rate_b),A  ; store selected FDC rate-B value
0939  DD 7E 0B      LD A,(IX+11)  ; A = descriptor byte 11 (mode/flags)
093C  CB 67         BIT 4,A  ; test bit 4 (dual-rate / precomp mode)
093E  28 1C         JR Z,loc_095C  ; if clear, use single-rate branch

; program FDC data rate & write-precomp from geometry via range tables; OUT fdc_reg/precomp/rate
fdc_datarate_precomp:
0940  21 1C 4B      LD HL,drive_blk_b+0x16  ; point at drive-B block +0x16 (rate params)
0943  0E 70         LD C,0x70  ; C = 0x70 control-latch selector
0945  1E 0A         LD E,0x0A  ; E = 0x0A parameter length
0947  3A 60 31      LD A,(fdc_rate_b)  ; A = FDC rate-B value
094A  CD 60 07      CALL update_ctrl_latch  ; program control latch with rate-B settings

loc_094D:
094D  3A 5F 31      LD A,(fdc_rate_a)  ; A = FDC rate-A value

loc_0950:
0950  21 01 4B      LD HL,drive_blk_a+0x16  ; point at drive-A block +0x16 (rate params)
0953  0E 50         LD C,0x50  ; C = 0x50 control-latch selector
0955  1E 08         LD E,0x08  ; E = 0x08 parameter length
0957  CD 60 07      CALL update_ctrl_latch  ; program control latch with rate-A settings
095A  18 0C         JR loc_0968  ; continue to combined-rate register setup

loc_095C:
095C  3A 36 31      LD A,(precomp_idx)  ; load precomp index
095F  CB 7F         BIT 7,A  ; test bit 7 (which head's rate to program first)
0961  3A 60 31      LD A,(fdc_rate_b)  ; A = rate-B value
0964  20 EA         JR NZ,loc_0950  ; bit7 set -> program rate-A block path
0966  18 E5         JR loc_094D  ; else program rate-A value first

loc_0968:
0968  3A 35 31      LD A,(datarate_idx)  ; load current track index
096B  4F            LD C,A  ; C = table index
096C  06 04         LD B,0x04  ; B = 4 entries to scan
096E  21 B9 31      LD HL,param_tables  ; point at parameter range table
0971  CD 77 07      CALL range_table_lookup  ; look up rate-select bits for this track
0974  5F            LD E,A  ; save result in E
0975  21 11 32      LD HL,datarate_tbl+0x50  ; point at data-rate table +0x50
0978  CD 77 07      CALL range_table_lookup  ; look up secondary rate bits
097B  0F            RRCA  ; rotate result right 2 bits
097C  0F            RRCA  ; rotate result right again (align field)
097D  CB 03         RLC E  ; rotate E left into position
097F  CB 03         RLC E  ; rotate E left again
0981  B3            OR E  ; merge E bits into A
0982  F6 30         OR 0x30  ; set bits 4,5 (mode select in rate reg)
0984  E6 FC         AND 0xFC  ; clear low 2 bits
0986  21 89 4B      LD HL,fdc_rate_reg  ; point at FDC rate register shadow
0989  B6            OR (HL)  ; OR in existing rate-reg bits
098A  23            INC HL  ; advance to precomp shadow byte
098B  CB A7         RES 4,A  ; clear bit 4
098D  CB EF         SET 5,A  ; set bit 5
098F  4F            LD C,A  ; keep assembled value in C
0990  D3 B1         OUT (0xB1),A  ; fdc_reg — write assembled value to FDC control register
0992  7E            LD A,(HL)  ; A = precomp shadow byte
0993  D3 C2         OUT (0xC2),A  ; fdc_precomp — write write-precompensation value to FDC
0995  2A 35 31      LD HL,(datarate_idx)  ; load track index
0998  26 00         LD H,0x00  ; clear H = byte offset into rate table
099A  E5            PUSH HL  ; save offset
099B  11 C1 31      LD DE,datarate_tbl  ; DE = base of data-rate table
099E  19            ADD HL,DE  ; HL = table entry address
099F  7E            LD A,(HL)  ; A = per-track data-rate value
09A0  D3 C3         OUT (0xC3),A  ; fdc_rate — write data rate to FDC
09A2  E1            POP HL  ; restore offset
09A3  11 19 32      LD DE,precomp_tbl  ; DE = base of precomp table
09A6  19            ADD HL,DE  ; HL = precomp entry address
09A7  79            LD A,C  ; A = saved rate-reg base value
09A8  CB E7         SET 4,A  ; set bit 4 (select precomp write)
09AA  CB AF         RES 5,A  ; clear bit 5
09AC  D3 B1         OUT (0xB1),A  ; fdc_reg — write updated select to FDC control register
09AE  7E            LD A,(HL)  ; A = per-track precomp value
09AF  D3 C2         OUT (0xC2),A  ; fdc_precomp — write precomp value to FDC
09B1  79            LD A,C  ; A = saved rate-reg base value
09B2  F6 30         OR 0x30  ; set mode bits 4,5
09B4  D3 B1         OUT (0xB1),A  ; fdc_reg — write control register back to FDC
09B6  18 00         JR loc_09B8  ; fall through to precomp verify block

loc_09B8:
09B8  2A 35 31      LD HL,(datarate_idx)  ; load track index
09BB  E5            PUSH HL  ; save it
09BC  7C            LD A,H  ; A = H
09BD  B5            OR L  ; OR L -> test whether track index is zero
09BE  28 1A         JR Z,loc_09DA  ; track 0 -> handle special-track precomp path
09C0  3A 66 31      LD A,(precomp_sel)  ; load precomp-select state
09C3  B7            OR A  ; test if precomp currently active
09C4  28 2F         JR Z,loc_09F5  ; inactive -> skip precomp toggle
09C6  3A 37 31      LD A,(unit_sel)  ; A = selected drive/unit number
09C9  47            LD B,A  ; B = unit number for FDC op
09CA  3A 64 31      LD A,(cyl_head)  ; A = cyl/head parameter
09CD  4F            LD C,A  ; C = cyl/head byte
09CE  3E 01         LD A,0x01  ; A = 1 (command variant)
09D0  CD B2 33      CALL fdc_op_dispatch  ; dispatch FDC operation with these params
09D3  21 66 31      LD HL,precomp_sel  ; point at precomp-select flag
09D6  36 00         LD (HL),0x00  ; clear precomp-select flag
09D8  18 1B         JR loc_09F5  ; continue past special-track block

loc_09DA:
09DA  3A 64 31      LD A,(cyl_head)  ; load cyl/head parameter
09DD  FE 04         CP 0x04  ; compare against 4 (precomp start cyl)
09DF  28 04         JR Z,loc_09E5  ; match -> enable precomp
09E1  FE 0E         CP 0x0E  ; compare against 14
09E3  20 10         JR NZ,loc_09F5  ; no match -> skip

loc_09E5:
09E5  3A 37 31      LD A,(unit_sel)  ; A = selected drive/unit number
09E8  47            LD B,A  ; B = unit number
09E9  0E 11         LD C,0x11  ; C = 0x11 (enable-precomp command byte)
09EB  3E 01         LD A,0x01  ; A = 1 (command variant)
09ED  CD B2 33      CALL fdc_op_dispatch  ; dispatch FDC precomp-enable operation
09F0  21 66 31      LD HL,precomp_sel  ; point at precomp-select flag
09F3  36 01         LD (HL),0x01  ; set precomp-select flag = 1

loc_09F5:
09F5  E1            POP HL  ; restore logical block pointer saved by caller
09F6  FD 21 EB 4A   LD IY,drive_blk_a  ; point IY at drive A geometry block
09FA  FD 75 00      LD (IY+0),L  ; store block low byte into drive A block
09FD  FD 74 01      LD (IY+1),H  ; store block high byte into drive A block

; geometry: logical block -> CHS via block_to_chs, store into both drive blocks
geom_seek_build:
0A00  FD 21 06 4B   LD IY,drive_blk_b  ; point IY at drive B geometry block
0A04  FD 75 00      LD (IY+0),L  ; store block low byte into drive B block
0A07  3A 63 31      LD A,(side_sel)  ; read selected side/head
0A0A  FD 77 01      LD (IY+1),A  ; store side into drive B block+1
0A0D  E5            PUSH HL  ; save logical block pointer
0A0E  4C            LD C,H  ; block high byte -> C
0A0F  45            LD B,L  ; block low byte -> B (BC = logical block)
0A10  CD F2 4F      CALL block_to_chs  ; convert logical block to cylinder/head/sector
0A13  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX at drive A geometry block
0A17  DD 77 07      LD (IX+7),A  ; store cylinder result into drive A block
0A1A  DD 73 08      LD (IX+8),E  ; store CHS low byte E into drive A block
0A1D  DD 72 09      LD (IX+9),D  ; store CHS high byte D into drive A block
0A20  DD 75 0C      LD (IX+12),L  ; store computed offset low into drive A block
0A23  DD 74 0D      LD (IX+13),H  ; store computed offset high into drive A block
0A26  E1            POP HL  ; restore logical block pointer
0A27  3A 63 31      LD A,(side_sel)  ; reload selected side/head
0A2A  4F            LD C,A  ; side -> C for drive B conversion
0A2B  45            LD B,L  ; block low byte -> B
0A2C  CD F2 4F      CALL block_to_chs  ; convert block to CHS for drive B
0A2F  DD 21 06 4B   LD IX,drive_blk_b  ; point IX at drive B geometry block
0A33  DD 77 07      LD (IX+7),A  ; store cylinder result into drive B block
0A36  DD 73 08      LD (IX+8),E  ; store CHS low byte E into drive B block
0A39  DD 72 09      LD (IX+9),D  ; store CHS high byte D into drive B block
0A3C  DD 75 0C      LD (IX+12),L  ; store computed offset low into drive B block
0A3F  DD 74 0D      LD (IX+13),H  ; store computed offset high into drive B block
0A42  21 49 31      LD HL,op_flag_49  ; point at operation flag byte
0A45  34            INC (HL)  ; bump operation-progress flag
0A46  DD 21 DD 52   LD IX,format_desc  ; point IX at active format descriptor
0A4A  3E 00         LD A,0x00  ; default FDC command mode = 0
0A4C  DD CB 0B 66   BIT 4,(IX+11)  ; test format flag bit4 (double-density/side variant)
0A50  28 02         JR Z,loc_0A54  ; keep mode 0 if flag clear
0A52  3E 02         LD A,0x02  ; else use FDC command mode 2

loc_0A54:
0A54  CD EB 48      CALL fdc_set_cmdmode  ; apply selected FDC command mode
0A57  21 2F 31      LD HL,fmt_geom_ptr+0xF  ; point at pending-seek flag in geometry table
0A5A  CB 46         BIT 0,(HL)  ; test pending-seek flag bit0
0A5C  CB 86         RES 0,(HL)  ; clear the pending-seek flag
0A5E  C4 25 07      CALL NZ,fdc_wait_unit1  ; if seek was pending, wait for FDC unit 1
0A61  DD 21 DD 52   LD IX,format_desc  ; point IX at active format descriptor
0A65  3A 35 31      LD A,(datarate_idx)  ; read current data-rate index
0A68  FE 01         CP 0x01  ; is it data-rate index 1?
0A6A  28 05         JR Z,loc_0A71  ; skip count compare if index 1
0A6C  DD 46 00      LD B,(IX+0)  ; load sectors-per-track count
0A6F  05            DEC B  ; count-1
0A70  B8            CP B  ; does data-rate index match last-sector index?

loc_0A71:
0A71  CC 7A 43      CALL Z,fdc_seek45_both  ; if matching, seek both drives (WRITE-45 setup)
0A74  3A 1D 31      LD A,(cfg_byte)  ; read config byte
0A77  E6 A4         AND 0xA4  ; mask config bits 0xA4
0A79  FE 84         CP 0x84  ; is config == 0x84 (specific mode)?
0A7B  20 06         JR NZ,loc_0A83  ; skip LCD update if not that mode
0A7D  21 00 0C      LD HL,0x0C00  ; LCD row/col position 0x0C00
0A80  CD 22 4C      CALL lcd_setpos  ; set LCD cursor position

loc_0A83:
0A83  21 34 31      LD HL,op_word  ; point at operation word
0A86  7E            LD A,(HL)  ; load operation word
0A87  E6 0F         AND 0x0F  ; isolate low nibble = operation code
0A89  FE 00         CP 0x00  ; op 0 (dispatch)?
0A8B  20 32         JR NZ,loc_0ABF  ; not op 0 -> try next code
0A8D  3A 4E 31      LD A,(run_status)  ; read run status
0A90  B7            OR A  ; test run status
0A91  C2 F3 0A      JP NZ,loc_0AF3  ; if running, jump to track-swap path 0AF3
0A94  CB 66         BIT 4,(HL)  ; test in-progress flag bit4
0A96  20 07         JR NZ,loc_0A9F  ; already shown -> skip message
0A98  E5            PUSH HL  ; save operation-word pointer
0A99  CD 57 0C      CALL show_in_progress  ; display in-progress message
0A9C  E1            POP HL  ; restore operation-word pointer
0A9D  CB E6         SET 4,(HL)  ; mark operation in-progress (bit4)

loc_0A9F:
0A9F  3E 64         LD A,0x64  ; PIT control word 0x64 (counter 1, mode 2)
0AA1  D3 AC         OUT (0xAC),A  ; pit_ctrl — program PIT control register
0AA3  3E 00         LD A,0x00  ; counter reload low = 0
0AA5  D3 A4         OUT (0xA4),A  ; pit_c1 — load PIT counter 1
0AA7  3E 0E         LD A,0x0E  ; latch select line7=1 (FDC result strobe)
0AA9  D3 9C         OUT (0x9C),A  ; ctrl_latch — write addressable control latch
0AAB  DD CB 0B 66   BIT 4,(IX+11)  ; test format flag bit4
0AAF  20 08         JR NZ,loc_0AB9  ; flag set -> dual read path
0AB1  3E 01         LD A,0x01  ; drive argument = 1
0AB3  CD 18 3A      CALL fdc_send_dma  ; arm FDC via DMA send
0AB6  C3 71 0D      JP loc_0D71  ; continue at op-complete handler 0D71

loc_0AB9:
0AB9  CD 83 3A      CALL fdc_read_dual  ; read both drives (dual FDC)
0ABC  C3 71 0D      JP loc_0D71  ; continue at op-complete handler 0D71

loc_0ABF:
0ABF  FE 01         CP 0x01  ; op 1?
0AC1  20 14         JR NZ,loc_0AD7  ; not op 1 -> try op 2

loc_0AC3:
0AC3  DD CB 0B 66   BIT 4,(IX+11)  ; test format flag bit4
0AC7  20 08         JR NZ,loc_0AD1  ; flag set -> copy-track path
0AC9  3E 01         LD A,0x01  ; drive argument = 1
0ACB  CD 53 3F      CALL fdc_read_src  ; read from source drive
0ACE  C3 6C 0C      JP loc_0C6C  ; continue at op handler 0C6C

loc_0AD1:
0AD1  CD C3 40      CALL fdc_copy_track  ; copy one track source->dest
0AD4  C3 6C 0C      JP loc_0C6C  ; continue at op handler 0C6C

loc_0AD7:
0AD7  FE 02         CP 0x02  ; op 2?
0AD9  20 14         JR NZ,loc_0AEF  ; not op 2 -> try op 3

loc_0ADB:
0ADB  DD CB 0B 66   BIT 4,(IX+11)  ; test format flag bit4
0ADF  20 08         JR NZ,loc_0AE9  ; flag set -> write-both-sides path
0AE1  3E 01         LD A,0x01  ; drive argument = 1
0AE3  CD 7F 42      CALL fdc_read_src_b  ; read from source drive (B variant)
0AE6  C3 6C 0C      JP loc_0C6C  ; continue at op handler 0C6C

loc_0AE9:
0AE9  CD 38 0C      CALL write_both_sides  ; write both disk sides
0AEC  C3 6C 0C      JP loc_0C6C  ; continue at op handler 0C6C

loc_0AEF:
0AEF  FE 03         CP 0x03  ; op 3?
0AF1  20 59         JR NZ,loc_0B4C  ; not op 3 -> try op 4

loc_0AF3:
0AF3  DD 21 DD 52   LD IX,format_desc  ; point IX at active format descriptor
0AF7  DD 46 0C      LD B,(IX+12)  ; load next-track bank byte
0AFA  DD 5E 0D      LD E,(IX+13)  ; load next-track offset low
0AFD  DD 56 0E      LD D,(IX+14)  ; load next-track offset high
0B00  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX at drive A geometry block
0B04  DD 7E 07      LD A,(IX+7)  ; read drive A current bank
0B07  DD 6E 0C      LD L,(IX+12)  ; read drive A current offset low
0B0A  DD 66 0D      LD H,(IX+13)  ; read drive A current offset high
0B0D  32 56 31      LD (track_bank_a),A  ; save current bank as track bank A
0B10  22 58 31      LD (track_off),HL  ; save current offset as track offset
0B13  DD 70 07      LD (IX+7),B  ; advance drive A to next-track bank
0B16  DD 73 0C      LD (IX+12),E  ; advance drive A offset low
0B19  DD 72 0D      LD (IX+13),D  ; advance drive A offset high
0B1C  DD 21 DD 52   LD IX,format_desc  ; point IX at active format descriptor
0B20  DD 46 0F      LD B,(IX+15)  ; load drive B next-track bank byte
0B23  DD 5E 10      LD E,(IX+16)  ; load drive B next-track offset low
0B26  DD 56 11      LD D,(IX+17)  ; load drive B next-track offset high
0B29  DD 21 06 4B   LD IX,drive_blk_b  ; point IX at drive B geometry block
0B2D  DD 7E 07      LD A,(IX+7)  ; read drive B current bank
0B30  DD 6E 0C      LD L,(IX+12)  ; read drive B current offset low
0B33  DD 66 0D      LD H,(IX+13)  ; read drive B current offset high
0B36  32 57 31      LD (track_bank_b),A  ; save current bank as track bank B
0B39  22 5A 31      LD (read_addr),HL  ; save current offset as read address
0B3C  DD 70 07      LD (IX+7),B  ; advance drive B to next-track bank
0B3F  DD 73 0C      LD (IX+12),E  ; advance drive B offset low
0B42  DD 72 0D      LD (IX+13),D  ; advance drive B offset high
0B45  DD 21 DD 52   LD IX,format_desc  ; restore IX to format descriptor
0B49  C3 9F 0A      JP loc_0A9F  ; resume at read/write arming 0A9F

loc_0B4C:
0B4C  FE 04         CP 0x04  ; op 4?
0B4E  20 03         JR NZ,loc_0B53  ; not op 4 -> try op 5
0B50  C3 C3 0A      JP loc_0AC3  ; op 4 shares op-1 read path

loc_0B53:
0B53  FE 05         CP 0x05  ; op 5?
0B55  20 14         JR NZ,loc_0B6B  ; not op 5 -> try op 6

loc_0B57:
0B57  DD CB 0B 66   BIT 4,(IX+11)  ; test format flag bit4
0B5B  20 08         JR NZ,loc_0B65  ; flag set -> read-DMA-prep path
0B5D  3E 01         LD A,0x01  ; drive argument = 1
0B5F  CD 6B 3E      CALL fdc_dma_arm2  ; arm FDC DMA (variant 2)
0B62  C3 71 0D      JP loc_0D71  ; continue at op-complete handler 0D71

loc_0B65:
0B65  CD B9 3D      CALL fdc_read_dma_prep  ; prepare FDC read via DMA
0B68  C3 71 0D      JP loc_0D71  ; continue at op-complete handler 0D71

loc_0B6B:
0B6B  FE 06         CP 0x06  ; op 6?
0B6D  20 14         JR NZ,loc_0B83  ; not op 6 -> try op 8/9/7

loc_0B6F:
0B6F  DD CB 0B 66   BIT 4,(IX+11)  ; test format flag bit4
0B73  20 08         JR NZ,loc_0B7D  ; flag set -> read-both-sides path
0B75  3E 01         LD A,0x01  ; drive argument = 1
0B77  CD 24 3B      CALL fdc_write_poll  ; write with polled completion
0B7A  C3 6C 0C      JP loc_0C6C  ; continue at op handler 0C6C

loc_0B7D:
0B7D  CD 27 0C      CALL read_both_sides  ; read both disk sides
0B80  C3 6C 0C      JP loc_0C6C  ; continue at op handler 0C6C

loc_0B83:
0B83  FE 08         CP 0x08  ; op 8?
0B85  CA F3 0A      JP Z,loc_0AF3  ; op 8 shares track-swap path 0AF3
0B88  FE 09         CP 0x09  ; op 9?
0B8A  C2 96 0B      JP NZ,loc_0B96  ; not op 9 -> try op 7
0B8D  21 00 10      LD HL,0x1000  ; LCD position 0x1000
0B90  CD 22 4C      CALL lcd_setpos  ; set LCD cursor position
0B93  C3 A4 0D      JP loc_0DA4  ; jump to op-9 handler 0DA4

loc_0B96:
0B96  FE 07         CP 0x07  ; op 7?
0B98  C2 BF 0A      JP NZ,loc_0ABF  ; unrecognized op code -> fall back to op-1 handler
0B9B  21 77 31      LD HL,serial_ptr+0x2  ; point at serial-control flag (autoloader)
0B9E  CB 46         BIT 0,(HL)  ; test serial-control flag bit0
0BA0  28 45         JR Z,loc_0BE7  ; flag clear -> run-status dispatch

loc_0BA2:
0BA2  CD 74 49      CALL fdc_drive_ready  ; check whether source drive is ready
0BA5  20 2A         JR NZ,loc_0BD1  ; not ready -> read-mode branch
0BA7  3A C8 52      LD A,(image_present)  ; is an image already buffered?
0BAA  B7            OR A  ; test image-present flag
0BAB  20 0F         JR NZ,loc_0BBC  ; image present -> copy-mode branch
0BAD  CD 2D 11      CALL al_cmd_reject  ; check/reject autoloader command
0BB0  38 05         JR C,loc_0BB7  ; carry set (rejected) -> abort to 10B0
0BB2  CD B4 11      CALL read_source  ; read source disk into image buffer
0BB5  28 EB         JR Z,loc_0BA2  ; success -> loop back to re-check ready

loc_0BB7:
0BB7  E1            POP HL  ; discard caller return frame
0BB8  E1            POP HL  ; discard second stack word
0BB9  C3 B0 10      JP loc_10B0  ; jump to autoloader abort handler 10B0

loc_0BBC:
0BBC  3A 4F 31      LD A,(rd_submode)  ; load read/copy submode
0BBF  32 4E 31      LD (run_status),A  ; set run status to submode (copy)
0BC2  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
0BC5  CD 59 4C      CALL lcd_print  ; print following inline string to LCD
0BC8  1B C0 63 6F 70 79 +  DB ESC(0xC0), "copy", 0  ; inline LCD string: cursor-to-line2, "copy", NUL
0BCF  18 16         JR loc_0BE7  ; join run-status dispatch

loc_0BD1:
0BD1  3E 00         LD A,0x00  ; run status = 0 (read mode)
0BD3  32 4E 31      LD (run_status),A  ; store run status
0BD6  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
0BD9  CD 59 4C      CALL lcd_print  ; print following inline string to LCD
0BDC  1B C0 72 65 61 64 +  DB ESC(0xC0), "read", 0  ; inline LCD string: cursor-to-line2, "read", NUL
0BE3  AF            XOR A  ; clear A to reset image-present flag
0BE4  32 C8 52      LD (image_present),A  ; clear image-present flag (no image yet)

loc_0BE7:
0BE7  3A 4E 31      LD A,(run_status)  ; reload run status
0BEA  FE 00         CP 0x00  ; run status 0?
0BEC  20 03         JR NZ,loc_0BF1  ; nonzero -> check status 1
0BEE  C3 9F 0A      JP loc_0A9F  ; status 0 -> resume at read/write arming 0A9F

loc_0BF1:
0BF1  FE 01         CP 0x01  ; run status 1?
0BF3  20 03         JR NZ,loc_0BF8  ; not 1 -> check status 2
0BF5  C3 C3 0A      JP loc_0AC3  ; status 1 -> op-1 read handler 0AC3

loc_0BF8:
0BF8  FE 02         CP 0x02  ; run status 2?
0BFA  20 03         JR NZ,loc_0BFF  ; not 2 -> check status 5
0BFC  C3 DB 0A      JP loc_0ADB  ; status 2 -> op-2 read handler 0ADB

loc_0BFF:
0BFF  FE 05         CP 0x05  ; run status 5?
0C01  20 03         JR NZ,loc_0C06  ; not 5 -> fall through
0C03  C3 57 0B      JP loc_0B57  ; status 5 -> op-5 handler 0B57

loc_0C06:
0C06  FE 06         CP 0x06  ; check menu/operation selector == 6
0C08  20 03         JR NZ,loc_0C0D  ; if not entry 6, skip the branch
0C0A  C3 6F 0B      JP loc_0B6F  ; entry 6: jump to handler at 0B6F

loc_0C0D:
0C0D  CD 59 4C      CALL lcd_print  ; show LCD message that BP option is unavailable
0C10  0C 42 50 20 6E 6F +  DB \f, "BP not available>", \x01, \xCD, \x89, "M", \xC9  ; inline string data for the message printed above

; process both disk sides for read: single-sided reads side1 only, else side1 then side2
read_both_sides:
0C27  CD 49 0C      CALL check_double_sided  ; test whether current format is double-sided
0C2A  C2 72 3B      JP NZ,fdc_write_dual  ; double-sided: go do dual-side FDC write
0C2D  3E 01         LD A,0x01  ; single-sided: select side 1
0C2F  CD 24 3B      CALL fdc_write_poll  ; write side 1, poll to completion
0C32  D8            RET C  ; return with error if write failed (carry)
0C33  3E 02         LD A,0x02  ; select side 2
0C35  C3 24 3B      JP fdc_write_poll  ; write side 2 and return via poll routine

; process both sides for source read into buffer: single reads side1, else both sides
write_both_sides:
0C38  CD 49 0C      CALL check_double_sided  ; test whether current format is double-sided
0C3B  C2 89 42      JP NZ,loc_4289  ; double-sided: go read both source sides at 4289
0C3E  3E 01         LD A,0x01  ; single-sided: select side 1
0C40  CD 7F 42      CALL fdc_read_src_b  ; read side 1 from source into buffer
0C43  D8            RET C  ; return with error if read failed (carry)
0C44  3E 02         LD A,0x02  ; select side 2
0C46  C3 7F 42      JP fdc_read_src_b  ; read side 2 into buffer and return

; determine if current format is double-sided (0x3135 nonzero, or cyl_head code 4/0x0E)
check_double_sided:
0C49  3A 35 31      LD A,(datarate_idx)  ; load datarate index (0 => needs cyl_head check)
0C4C  B7            OR A  ; test for zero
0C4D  C0            RET NZ  ; nonzero datarate => double-sided, return
0C4E  3A 64 31      LD A,(cyl_head)  ; load cylinder/head format code
0C51  FE 04         CP 0x04  ; compare against code 4 (double-sided)
0C53  C8            RET Z  ; return if format code 4 (Z=double-sided)
0C54  FE 0E         CP 0x0E  ; compare against code 0x0E (double-sided)
0C56  C9            RET  ; return; Z flag set iff double-sided

; draw "in progress" on line 2 (operation running indicator)
show_in_progress:
0C57  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 for status text
0C5A  CD 59 4C      CALL lcd_print  ; print the in-progress indicator string
0C5D  1B C3 69 6E 20 70 +  DB ESC(0xC3), "in progress", 0  ; inline string 'in progress' with LCD escape
0C6B  C9            RET  ; return to caller

loc_0C6C:
0C6C  21 34 31      LD HL,op_word  ; point HL at op_word status byte
0C6F  F5            PUSH AF  ; save incoming carry/flags across the mask
0C70  3E 1F         LD A,0x1F  ; op-code mask value 0x1F (low 5 bits)
0C72  A6            AND (HL)  ; mask op_word: keep low 5 bits, clear bits 5-7
0C73  77            LD (HL),A  ; store masked op_word back
0C74  F1            POP AF  ; restore saved carry/flags
0C75  DA 4F 0D      JP C,loc_0D4F  ; if entered with carry set, go to error/abort path
0C78  C3 74 0D      JP loc_0D74  ; otherwise jump to common finish at 0D74
0C7B  7E            LD A,(HL)  ; load current op_word low bits
0C7C  FE 01         CP 0x01  ; compare with operation code 1 (read)
0C7E  28 09         JR Z,loc_0C89  ; op 1 => go to copy-setup block
0C80  FE 04         CP 0x04  ; compare with operation code 4
0C82  28 05         JR Z,loc_0C89  ; op 4 => go to copy-setup block
0C84  FE 02         CP 0x02  ; compare with operation code 2 (write)
0C86  C2 74 0D      JP NZ,loc_0D74  ; not a copy op => jump to finish at 0D74

loc_0C89:
0C89  2A 35 31      LD HL,(datarate_idx)  ; load datarate index word
0C8C  7C            LD A,H  ; load datarate high byte
0C8D  B5            OR L  ; OR in low byte to test 16-bit datarate for zero
0C8E  C2 74 0D      JP NZ,loc_0D74  ; nonzero datarate => skip copy, go finish
0C91  DD 21 DD 52   LD IX,format_desc  ; point IX at current format descriptor
0C95  DD 46 0C      LD B,(IX+12)  ; fetch sector-count byte (fmt+12) into B
0C98  DD 5E 0D      LD E,(IX+13)  ; fetch track-length low byte (fmt+13)
0C9B  DD 56 0E      LD D,(IX+14)  ; fetch track-length high byte (fmt+14)
0C9E  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX at drive A block
0CA2  DD 70 07      LD (IX+7),B  ; store sector count into drive A block+7
0CA5  DD 73 0C      LD (IX+12),E  ; store track-length low into drive A block+12
0CA8  DD 72 0D      LD (IX+13),D  ; store track-length high into drive A block+13
0CAB  DD 21 DD 52   LD IX,format_desc  ; re-point IX at format descriptor
0CAF  DD 46 0F      LD B,(IX+15)  ; fetch second sector-count byte (fmt+15)
0CB2  DD 5E 10      LD E,(IX+16)  ; fetch second length low byte (fmt+16)
0CB5  DD 56 11      LD D,(IX+17)  ; fetch second length high byte (fmt+17)
0CB8  DD 21 06 4B   LD IX,drive_blk_b  ; point IX at drive B block
0CBC  DD 70 07      LD (IX+7),B  ; store sector count into drive B block+7
0CBF  DD 73 0C      LD (IX+12),E  ; store length low into drive B block+12
0CC2  DD 72 0D      LD (IX+13),D  ; store length high into drive B block+13
0CC5  DD 21 DD 52   LD IX,format_desc  ; re-point IX at format descriptor
0CC9  DD CB 0B 66   BIT 4,(IX+11)  ; test dual-side flag bit 4 of fmt+11
0CCD  20 07         JR NZ,loc_0CD6  ; if dual-side, take the dual-read path
0CCF  3E 01         LD A,0x01  ; single: select side 1
0CD1  CD 18 3A      CALL fdc_send_dma  ; start FDC/DMA transfer for side 1
0CD4  18 06         JR loc_0CDC  ; join the poll loop

loc_0CD6:
0CD6  CD 83 3A      CALL fdc_read_dual  ; dual-side: start read on both drives
0CD9  C3 DC 0C      JP loc_0CDC  ; fall through to poll loop

loc_0CDC:
0CDC  3E 01         LD A,0x01  ; select drive/side 1 for polling
0CDE  CD 2D 47      CALL fdc_poll_complete  ; poll FDC for completion
0CE1  28 F9         JR Z,loc_0CDC  ; still busy (Z) => keep polling
0CE3  30 03         JR NC,loc_0CE8  ; no carry => success, continue
0CE5  C3 4F 0D      JP loc_0D4F  ; error => jump to abort/error handler

loc_0CE8:
0CE8  DD CB 0B 66   BIT 4,(IX+11)  ; test dual-side flag bit 4 of fmt+11
0CEC  28 0C         JR Z,loc_0CFA  ; single-side => skip second poll

loc_0CEE:
0CEE  3E 02         LD A,0x02  ; select drive/side 2 for polling
0CF0  CD 04 47      CALL fdc_poll_result  ; poll second FDC result
0CF3  28 F9         JR Z,loc_0CEE  ; still busy => keep polling
0CF5  30 03         JR NC,loc_0CFA  ; no carry => success, continue
0CF7  C3 4F 0D      JP loc_0D4F  ; error => jump to abort/error handler

loc_0CFA:
0CFA  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX at drive A block
0CFE  DD 4E 0E      LD C,(IX+14)  ; load byte count low (blk+14)
0D01  DD 46 0F      LD B,(IX+15)  ; load byte count high (blk+15)
0D04  03            INC BC  ; add 1 to make copy length inclusive
0D05  C5            PUSH BC  ; save copy length for verify pass
0D06  DD 7E 07      LD A,(IX+7)  ; load source DRAM bank (blk+7)
0D09  DD 6E 0C      LD L,(IX+12)  ; load source offset low (blk+12)
0D0C  DD 66 0D      LD H,(IX+13)  ; load source offset high (blk+13)
0D0F  D3 B0         OUT (0xB0),A  ; dram_bank — select source image bank
0D11  7C            LD A,H  ; take offset high byte
0D12  F6 80         OR 0x80  ; force into 0x8000+ image-buffer window
0D14  67            LD H,A  ; put adjusted high byte back in H
0D15  11 00 58      LD DE,0x5800  ; destination = scratch buffer 0x5800
0D18  ED B0         LDIR  ; copy track data from image bank to scratch
0D1A  3A 56 31      LD A,(track_bank_a)  ; load track's DRAM bank for drive A
0D1D  D3 B0         OUT (0xB0),A  ; dram_bank — select that image bank
0D1F  2A 58 31      LD HL,(track_off)  ; load track data offset
0D22  7C            LD A,H  ; take offset high byte
0D23  F6 80         OR 0x80  ; force into 0x8000+ image-buffer window
0D25  67            LD H,A  ; put adjusted high byte back in H
0D26  C1            POP BC  ; restore copy length into BC
0D27  11 00 58      LD DE,0x5800  ; point DE at scratch copy for the verify compare

loc_0D2A:
0D2A  1A            LD A,(DE)  ; load a scratch byte
0D2B  13            INC DE  ; advance scratch pointer
0D2C  ED A1         CPI  ; compare against image byte, advance HL, dec BC
0D2E  20 1F         JR NZ,loc_0D4F  ; mismatch => write-verify fault, go to error
0D30  EA 2A 0D      JP PE,loc_0D2A  ; more bytes left => keep comparing
0D33  18 3F         JR loc_0D74  ; verify OK => jump to finish at 0D74
0D35  CD 59 4C      CALL lcd_print  ; print the FDD write-fault message
0D38  1B C0 46 44 44 20 +  DB ESC(0xC0), "FDD write fault", 0  ; inline 'FDD write fault' string with escape
0D4A  3E 01         LD A,0x01  ; prepare key-poll argument
0D4C  CD 89 4D      CALL get_key  ; wait for operator keypress to acknowledge

loc_0D4F:
0D4F  3E 60         LD A,0x60  ; set bits 6/5 of op_word (mark error/state)
0D51  B6            OR (HL)  ; OR error/state bits 6-5 into op_word
0D52  77            LD (HL),A  ; store updated op_word
0D53  3E 64         LD A,0x64  ; PIT timer1 mode: counter1 latch/mode 0x64
0D55  D3 AC         OUT (0xAC),A  ; pit_ctrl — program PIT control word
0D57  3E 80         LD A,0x80  ; load timer1 count high 0x80
0D59  D3 A4         OUT (0xA4),A  ; pit_c1 — write count to PIT counter 1
0D5B  3E 0E         LD A,0x0E  ; control-latch value 0x0E (line7 select)
0D5D  D3 9C         OUT (0x9C),A  ; ctrl_latch — strobe the 0x9C addressable latch
0D5F  06 0A         LD B,0x0A  ; outer loop count = 10 ticks
0D61  0E 01         LD C,0x01  ; expected timer sample starts at 1

loc_0D63:
0D63  3E 40         LD A,0x40  ; PIT latch command 0x40 for counter 1
0D65  D3 AC         OUT (0xAC),A  ; pit_ctrl — write latch to PIT control
0D67  DB A4         IN A,(0xA4)  ; pit_c1 — read back PIT counter 1 value
0D69  B9            CP C  ; compare sample against expected C
0D6A  20 F7         JR NZ,loc_0D63  ; not yet reached => keep sampling
0D6C  0C            INC C  ; advance expected sample value
0D6D  10 F4         DJNZ loc_0D63  ; repeat for all 10 ticks
0D6F  18 03         JR loc_0D74  ; delay done => jump to finish at 0D74

loc_0D71:
0D71  CD 8C 0E      CALL wait_read_done  ; wait for the read operation to finish

loc_0D74:
0D74  3E 0F         LD A,0x0F  ; control-latch value 0x0F
0D76  D3 9C         OUT (0x9C),A  ; ctrl_latch — strobe 0x9C latch (deselect drives/write)
0D78  3A 61 31      LD A,(host_mode)  ; load host-remote mode flag
0D7B  B7            OR A  ; test host_mode
0D7C  20 26         JR NZ,loc_0DA4  ; host mode active => skip panel stop handling
0D7E  AF            XOR A  ; poll code 0 (any-key)
0D7F  CD 89 4D      CALL get_key  ; check for a keypress
0D82  28 20         JR Z,loc_0DA4  ; no key => skip to 0DA4
0D84  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
0D87  CD 59 4C      CALL lcd_print  ; print 'stop' status
0D8A  1B C6 73 74 6F 70 +  DB ESC(0xC6), "stop", 0  ; inline 'stop' string with LCD escape

loc_0D91:
0D91  AF            XOR A  ; poll code 0 (any-key)
0D92  CD 89 4D      CALL get_key  ; check whether key still held
0D95  20 FA         JR NZ,loc_0D91  ; key still down => wait until released
0D97  21 34 31      LD HL,op_word  ; point HL at op_word
0D9A  CB FE         SET 7,(HL)  ; set abort bit 7 of op_word
0D9C  21 49 31      LD HL,op_flag_49  ; point HL at op_flag_49
0D9F  36 00         LD (HL),0x00  ; clear op_flag_49
0DA1  C3 35 0F      JP loc_0F35  ; jump to operation-end handler at 0F35

loc_0DA4:
0DA4  21 34 31      LD HL,op_word  ; point HL at op_word
0DA7  7E            LD A,(HL)  ; load op_word
0DA8  E6 60         AND 0x60  ; isolate bits 6/5 (error/state flags)
0DAA  28 2A         JR Z,loc_0DD6  ; no such flags set => go to 0DD6
0DAC  21 49 31      LD HL,op_flag_49  ; point HL at op_flag_49
0DAF  3A 4A 31      LD A,(err_recovery)  ; load error-recovery counter
0DB2  BE            CP (HL)  ; compare against op_flag_49
0DB3  C2 D0 0D      JP NZ,loc_0DD0  ; mismatch => branch to 0DD0
0DB6  21 00 00      LD HL,0x0000  ; LCD cursor position 0,0
0DB9  CD 22 4C      CALL lcd_setpos  ; set LCD cursor to top-left
0DBC  2A 35 31      LD HL,(datarate_idx)  ; load datarate index word
0DBF  7D            LD A,L  ; load datarate low byte
0DC0  B4            OR H  ; OR in high byte to test datarate index for zero
0DC1  CA B8 09      JP Z,loc_09B8  ; zero => jump to 09B8 (retry/start)
0DC4  3A DD 52      LD A,(format_desc)  ; load first byte of format descriptor (format count)
0DC7  3D            DEC A  ; (format count - 1) for last-format comparison
0DC8  95            SUB L  ; subtract L (index low) from it
0DC9  B4            OR H  ; OR in H to test full 16-bit result
0DCA  CA B8 09      JP Z,loc_09B8  ; result zero => jump to 09B8
0DCD  C3 35 0F      JP loc_0F35  ; otherwise jump to op-end at 0F35

loc_0DD0:
0DD0  F2 B8 09      JP P,loc_09B8  ; if op_flag_49 >= recovery (positive) => 09B8
0DD3  C3 35 0F      JP loc_0F35  ; else jump to op-end at 0F35

loc_0DD6:
0DD6  21 49 31      LD HL,op_flag_49  ; point HL at op_flag_49
0DD9  36 00         LD (HL),0x00  ; clear op_flag_49
0DDB  21 34 31      LD HL,op_word  ; point HL at op_word
0DDE  7E            LD A,(HL)  ; load op_word
0DDF  E6 0F         AND 0x0F  ; isolate low nibble (operation code)
0DE1  20 03         JR NZ,loc_0DE6  ; nonzero op code => branch to 0DE6
0DE3  3A 4E 31      LD A,(run_status)  ; no op selected: load run_status

loc_0DE6:
0DE6  FE 08         CP 0x08  ; check FDC SENSE-INT result code == 0x08 (seek/verify done)
0DE8  C2 3D 0F      JP NZ,loc_0F3D  ; not the expected status -> skip verify entirely
0DEB  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX at drive A descriptor block
0DEF  DD 4E 0E      LD C,(IX+14)  ; byte-count low from descriptor into C
0DF2  DD 46 0F      LD B,(IX+15)  ; byte-count high into B -> BC = track length
0DF5  C5            PUSH BC  ; save track length for the compare pass
0DF6  DD 7E 07      LD A,(IX+7)  ; source DRAM image bank for drive A
0DF9  DD 6E 0C      LD L,(IX+12)  ; source offset low from descriptor
0DFC  DD 66 0D      LD H,(IX+13)  ; source offset high -> HL = image source ptr
0DFF  D3 B0         OUT (0xB0),A  ; dram_bank — select drive A image bank in 0x8000 window
0E01  7C            LD A,H  ; take source page high byte
0E02  F6 80         OR 0x80  ; map into 0x8000-0xFFFF window (set bit7)
0E04  67            LD H,A  ; write mapped high byte back to H
0E05  11 00 58      LD DE,0x5800  ; destination = 0x5800 scratch buffer
0E08  ED B0         LDIR  ; copy track from DRAM image into scratch buffer
0E0A  3A 67 31      LD A,(hrd_desc_tbl)  ; load hardware descriptor flags
0E0D  CB 4F         BIT 1,A  ; test serial-number patch enable (bit1)
0E0F  28 35         JR Z,verify_compare  ; no serial patch -> go straight to compare
0E11  2A 35 31      LD HL,(datarate_idx)  ; load current track/head index
0E14  3A 6D 31      LD A,(serial_cyl)  ; get the cylinder where the serial number lives
0E17  BD            CP L  ; does the current track match the serial cylinder?
0E18  20 2C         JR NZ,verify_compare  ; wrong cylinder -> skip serial patch, compare
0E1A  7C            LD A,H  ; take index high byte
0E1B  E6 80         AND 0x80  ; isolate top bit
0E1D  07            RLCA  ; rotate it into bit0 -> side flag
0E1E  67            LD H,A  ; store computed side into H
0E1F  3A 6E 31      LD A,(serial_head)  ; get the head holding the serial number
0E22  BC            CP H  ; does the head/side match the serial head?
0E23  20 21         JR NZ,verify_compare  ; mismatch -> skip patch, compare
0E25  11 00 58      LD DE,0x5800  ; scratch buffer base 0x5800
0E28  2A 75 31      LD HL,(serial_ptr)  ; serial byte offset within track
0E2B  19            ADD HL,DE  ; HL = scratch address of serial bytes
0E2C  E5            PUSH HL  ; stash that dest address
0E2D  C1            POP BC  ; recover it into BC
0E2E  3A 56 31      LD A,(track_bank_a)  ; select drive A track image bank
0E31  D3 B0         OUT (0xB0),A  ; dram_bank — map that bank into 0x8000 window
0E33  2A 58 31      LD HL,(track_off)  ; load track offset in image
0E36  7C            LD A,H  ; take track offset high byte
0E37  F6 80         OR 0x80  ; map into 0x8000 window
0E39  57            LD D,A  ; store mapped high byte into D
0E3A  5D            LD E,L  ; DE = mapped image track pointer
0E3B  2A 75 31      LD HL,(serial_ptr)  ; add serial byte offset
0E3E  19            ADD HL,DE  ; HL = image source of serial bytes
0E3F  C5            PUSH BC  ; recover scratch dest address
0E40  D1            POP DE  ; into DE as LDIR destination
0E41  01 04 00      LD BC,0x0004  ; patch 4 serial-number bytes
0E44  ED B0         LDIR  ; overwrite scratch serial bytes with image copy

; verify: DMA read-back track into 0x5800 scratch, CPI-compare vs DRAM image
verify_compare:
0E46  3A 56 31      LD A,(track_bank_a)  ; select drive A image bank again
0E49  D3 B0         OUT (0xB0),A  ; dram_bank — map into 0x8000 window
0E4B  2A 58 31      LD HL,(track_off)  ; load image track offset
0E4E  7C            LD A,H  ; take offset high byte
0E4F  F6 80         OR 0x80  ; map into 0x8000 window
0E51  67            LD H,A  ; HL = image source for compare
0E52  C1            POP BC  ; restore track length into BC
0E53  11 00 58      LD DE,0x5800  ; DE points at scratch read-back buffer

loc_0E56:
0E56  1A            LD A,(DE)  ; fetch next scratch (read-back) byte
0E57  13            INC DE  ; advance scratch pointer
0E58  ED A1         CPI  ; compare vs image byte, inc HL, dec BC
0E5A  20 05         JR NZ,loc_0E61  ; byte differs -> report compare error
0E5C  EA 56 0E      JP PE,loc_0E56  ; keep looping while count nonzero
0E5F  18 55         JR loc_0EB6  ; whole track matched -> handle side B

loc_0E61:
0E61  CD 67 0E      CALL show_compare_error  ; show the compare-error message
0E64  C3 35 0F      JP loc_0F35  ; jump to failure-exit cleanup

; draw "Compare error", beep code 5, set op_word bit6 (verify-mismatch flag)
show_compare_error:
0E67  E5            PUSH HL  ; save HL across the message routine
0E68  D5            PUSH DE  ; save DE across the message routine
0E69  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
0E6C  CD 59 4C      CALL lcd_print  ; print the following inline string
0E6F  1B C0 43 6F 6D 70 +  DB ESC(0xC0), "Compare error", 0  ; inline text: cursor to line2, 'Compare error', NUL
0E7F  3E 05         LD A,0x05  ; beep code 5 (verify failure)
0E81  CD 66 27      CALL beep  ; sound the error beep
0E84  21 34 31      LD HL,op_word  ; point at operation status word
0E87  CB F6         SET 6,(HL)  ; set bit6 = verify/compare mismatch flag
0E89  D1            POP DE  ; restore DE
0E8A  E1            POP HL  ; restore HL
0E8B  C9            RET  ; return to caller

; wait for FDC read/verify done on unit1 (and unit2 if double-sided); set op_word bits 6/5 on fail
wait_read_done:
0E8C  21 34 31      LD HL,op_word  ; point at operation status word
0E8F  3E 1F         LD A,0x1F  ; mask keeping low 5 bits
0E91  A6            AND (HL)  ; AND out result bits 5/6/7
0E92  77            LD (HL),A  ; store cleared status word

loc_0E93:
0E93  3E 01         LD A,0x01  ; select FDC unit 1
0E95  CD 2D 47      CALL fdc_poll_complete  ; poll whether unit1 read completed
0E98  28 F9         JR Z,loc_0E93  ; not done yet -> keep polling
0E9A  21 34 31      LD HL,op_word  ; point at operation status word
0E9D  30 02         JR NC,loc_0EA1  ; no error (carry clear) -> skip flag
0E9F  CB F6         SET 6,(HL)  ; set bit6 = unit1 read/verify error

loc_0EA1:
0EA1  DD CB 0B 66   BIT 4,(IX+11)  ; test double-sided flag (IX+11 bit4)
0EA5  28 0E         JR Z,loc_0EB5  ; single-sided -> done
0EA7  3E 02         LD A,0x02  ; select FDC unit 2 (side 2)
0EA9  CD 04 47      CALL fdc_poll_result  ; poll unit2 read result
0EAC  28 F3         JR Z,loc_0EA1  ; not done -> keep polling unit2
0EAE  21 34 31      LD HL,op_word  ; point at operation status word
0EB1  30 02         JR NC,loc_0EB5  ; no error -> done
0EB3  CB EE         SET 5,(HL)  ; set bit5 = unit2 read/verify error

loc_0EB5:
0EB5  C9            RET  ; return to caller

loc_0EB6:
0EB6  DD 21 DD 52   LD IX,format_desc  ; point IX at format descriptor
0EBA  DD CB 0B 66   BIT 4,(IX+11)  ; test double-sided flag
0EBE  28 7D         JR Z,loc_0F3D  ; single-sided -> skip side B verify
0EC0  DD 21 06 4B   LD IX,drive_blk_b  ; point IX at drive B descriptor block
0EC4  DD 4E 0E      LD C,(IX+14)  ; byte-count low into C
0EC7  DD 46 0F      LD B,(IX+15)  ; byte-count high into B -> BC = length
0ECA  DD 7E 07      LD A,(IX+7)  ; source DRAM image bank for drive B
0ECD  DD 6E 0C      LD L,(IX+12)  ; source offset low
0ED0  DD 66 0D      LD H,(IX+13)  ; source offset high -> HL = image source
0ED3  D3 B0         OUT (0xB0),A  ; dram_bank — select drive B image bank
0ED5  7C            LD A,H  ; take source page high byte
0ED6  F6 80         OR 0x80  ; map into 0x8000 window
0ED8  67            LD H,A  ; store mapped high byte back to H
0ED9  11 00 58      LD DE,0x5800  ; destination = 0x5800 scratch
0EDC  C5            PUSH BC  ; save track length
0EDD  ED B0         LDIR  ; copy side-B track into scratch buffer
0EDF  3A 67 31      LD A,(hrd_desc_tbl)  ; load hardware descriptor flags
0EE2  CB 4F         BIT 1,A  ; test serial-patch enable (bit1)
0EE4  28 31         JR Z,loc_0F17  ; not enabled -> go to compare
0EE6  2A 35 31      LD HL,(datarate_idx)  ; load track/head index
0EE9  3A 6D 31      LD A,(serial_cyl)  ; serial cylinder value
0EEC  BD            CP L  ; matches this pass's head?
0EED  20 28         JR NZ,loc_0F17  ; wrong head -> skip patch
0EEF  3A 6E 31      LD A,(serial_head)  ; get serial head
0EF2  FE 01         CP 0x01  ; is it sector 1?
0EF4  20 21         JR NZ,loc_0F17  ; no -> skip patch
0EF6  11 00 58      LD DE,0x5800  ; scratch base 0x5800
0EF9  2A 75 31      LD HL,(serial_ptr)  ; serial byte offset
0EFC  19            ADD HL,DE  ; HL = scratch address of serial bytes
0EFD  E5            PUSH HL  ; stash dest address
0EFE  C1            POP BC  ; recover it into BC
0EFF  3A 57 31      LD A,(track_bank_b)  ; select drive B track image bank
0F02  D3 B0         OUT (0xB0),A  ; dram_bank — map into 0x8000 window
0F04  2A 5A 31      LD HL,(read_addr)  ; load side-B read address
0F07  7C            LD A,H  ; take address high byte
0F08  F6 80         OR 0x80  ; map into 0x8000 window
0F0A  57            LD D,A  ; store mapped high byte into D
0F0B  5D            LD E,L  ; DE = mapped image track pointer
0F0C  2A 75 31      LD HL,(serial_ptr)  ; add serial byte offset
0F0F  19            ADD HL,DE  ; HL = image source of serial bytes
0F10  C5            PUSH BC  ; recover scratch dest address
0F11  D1            POP DE  ; into DE as LDIR destination
0F12  01 04 00      LD BC,0x0004  ; patch 4 serial-number bytes
0F15  ED B0         LDIR  ; overwrite scratch serial bytes from image

loc_0F17:
0F17  3A 57 31      LD A,(track_bank_b)  ; select drive B track image bank
0F1A  D3 B0         OUT (0xB0),A  ; dram_bank — map into 0x8000 window
0F1C  2A 5A 31      LD HL,(read_addr)  ; load side-B read address
0F1F  7C            LD A,H  ; take address high byte
0F20  F6 80         OR 0x80  ; map into 0x8000 window
0F22  67            LD H,A  ; HL = image compare source
0F23  C1            POP BC  ; restore track length
0F24  11 00 58      LD DE,0x5800  ; DE points at scratch read-back buffer

loc_0F27:
0F27  1A            LD A,(DE)  ; fetch next scratch byte
0F28  13            INC DE  ; advance scratch pointer
0F29  ED A1         CPI  ; compare vs image, inc HL, dec BC
0F2B  20 05         JR NZ,loc_0F32  ; differs -> compare error
0F2D  EA 27 0F      JP PE,loc_0F27  ; loop while count nonzero
0F30  18 0B         JR loc_0F3D  ; side B matched -> continue

loc_0F32:
0F32  CD 67 0E      CALL show_compare_error  ; show the compare-error message

loc_0F35:
0F35  C1            POP BC  ; discard saved length
0F36  D1            POP DE  ; discard saved DE
0F37  06 01         LD B,0x01  ; mark B pass as failed (retry count 1)
0F39  16 01         LD D,0x01  ; flag error state D=1
0F3B  D5            PUSH DE  ; push failure flags
0F3C  C5            PUSH BC  ; push failure retry count

loc_0F3D:
0F3D  2A 35 31      LD HL,(datarate_idx)  ; load track/head index
0F40  3A 63 31      LD A,(side_sel)  ; current side selection
0F43  67            LD H,A  ; store side into H
0F44  22 35 31      LD (datarate_idx),HL  ; write back track/head index
0F47  C1            POP BC  ; pop drive-count/retry into BC
0F48  DD 21 DD 52   LD IX,format_desc  ; point IX at format descriptor
0F4C  DD CB 0B 66   BIT 4,(IX+11)  ; test double-sided flag
0F50  28 02         JR Z,loc_0F54  ; single-sided -> keep count
0F52  06 01         LD B,0x01  ; double-sided -> force count B=1

loc_0F54:
0F54  10 1F         DJNZ loc_0F75  ; decrement drive count, branch if more drives
0F56  2A 35 31      LD HL,(datarate_idx)  ; load track/head index
0F59  2C            INC L  ; advance to next head/track
0F5A  3A 1C 31      LD A,(cfg_flags)  ; load config flags
0F5D  CB 7F         BIT 7,A  ; test double-step / side mode (bit7)
0F5F  20 02         JR NZ,loc_0F63  ; flag set -> keep +1
0F61  2D            DEC L  ; flag clear: undo increment...
0F62  2D            DEC L  ; ...and step back one (net -1)

loc_0F63:
0F63  26 00         LD H,0x00  ; clear index high byte
0F65  22 35 31      LD (datarate_idx),HL  ; store updated track/head index
0F68  21 77 31      LD HL,serial_ptr+0x2  ; point at serial_ptr flag byte
0F6B  CB 86         RES 0,(HL)  ; clear bit0 (serial-patched flag)
0F6D  C1            POP BC  ; pop retry/loop count
0F6E  10 02         DJNZ loc_0F72  ; count nonzero -> next iteration
0F70  18 06         JR loc_0F78  ; done -> exit to loc_0F78

loc_0F72:
0F72  C3 F3 08      JP loc_08F3  ; loop back to copy/verify next track

loc_0F75:
0F75  C3 15 09      JP loc_0915  ; jump to next-drive handler

loc_0F78:
0F78  3E 0F         LD A,0x0F  ; ctrl-latch line7 (FDC result strobe) = high
0F7A  D3 9C         OUT (0x9C),A  ; ctrl_latch — drive the 0x9C addressable control latch
0F7C  21 69 32      LD HL,cycle_cnt_lo  ; point at cycle_cnt_lo config block
0F7F  06 04         LD B,0x04  ; transfer 4 bytes
0F81  0E FC         LD C,0xFC  ; block/stride param for eeprom_transfer
0F83  3E 01         LD A,0x01  ; direction = 1 (write out to EEPROM)
0F85  CD 35 27      CALL eeprom_transfer  ; save cycle counters to CAT24C02 EEPROM
0F88  CD D9 06      CALL pit_reload_c12  ; reload PIT counter for ~12ms timing tick
0F8B  CD 09 07      CALL motor_ready_wait  ; spin until selected drive motors up to speed
0F8E  C2 B0 10      JP NZ,loc_10B0  ; abort to cleanup if motors never ready
0F91  AF            XOR A  ; A=0 to clear the fmt_mode/edit_ndigits flags below
0F92  32 4C 31      LD (fmt_mode),A  ; clear format-mode flag
0F95  32 50 31      LD (edit_ndigits),A  ; clear edit-digit count
0F98  21 34 31      LD HL,op_word  ; point at op_word
0F9B  3E E0         LD A,0xE0  ; mask for the top 3 op_word bits
0F9D  A6            AND (HL)  ; test op_word high control bits
0F9E  28 72         JR Z,loc_1012  ; no high bits set -> normal op dispatch
0FA0  2A 3B 31      LD HL,(pass_ctr)  ; load pass counter
0FA3  23            INC HL  ; bump pass count
0FA4  22 3B 31      LD (pass_ctr),HL  ; store pass counter
0FA7  21 50 31      LD HL,edit_ndigits  ; point at edit_ndigits flag byte
0FAA  CB C6         SET 0,(HL)  ; set bit0 of edit_ndigits flag
0FAC  CB FE         SET 7,(HL)  ; set bit7 of edit_ndigits flag
0FAE  CD 2D 11      CALL al_cmd_reject  ; issue autoloader REJECT for this disk
0FB1  30 05         JR NC,loc_0FB8  ; reject sent cleanly -> continue
0FB3  FE 01         CP 0x01  ; reject returned status 1?
0FB5  C2 B0 10      JP NZ,loc_10B0  ; any other status -> jump to cleanup

loc_0FB8:
0FB8  3A 61 31      LD A,(host_mode)  ; load host remote-control mode flag
0FBB  B7            OR A  ; test host_mode
0FBC  C2 B0 10      JP NZ,loc_10B0  ; host driving -> skip local UI, go cleanup
0FBF  21 34 31      LD HL,op_word  ; point at op_word
0FC2  3E 0F         LD A,0x0F  ; mask for op low nibble
0FC4  A6            AND (HL)  ; extract op code
0FC5  20 16         JR NZ,loc_0FDD  ; op code non-zero -> handle at loc_0FDD
0FC7  CB 7E         BIT 7,(HL)  ; op==0: test stopped bit7 of op_word
0FC9  28 28         JR Z,loc_0FF3  ; bit7 clear -> disk was unreadable
0FCB  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
0FCE  CD 59 4C      CALL lcd_print  ; print following string
0FD1  1B C1 73 74 6F 70 +  DB ESC(0xC1), "stopped", 0  ; LCD msg: cursor col1, "stopped"
0FDB  18 29         JR loc_1006  ; join key-wait path at loc_1006

loc_0FDD:
0FDD  CB 7E         BIT 7,(HL)  ; test op_word stopped bit7
0FDF  CA 9C 07      JP Z,loc_079C  ; not stopped -> back to main loop
0FE2  C3 B0 10      JP loc_10B0  ; stopped -> go cleanup

loc_0FE5:
0FE5  FE 00         CP 0x00  ; test copies-count in A
0FE7  CA B0 10      JP Z,loc_10B0  ; zero copies -> cleanup
0FEA  CD 93 04      CALL edit_num_copies  ; edit/decrement number of copies to make
0FED  CA B0 10      JP Z,loc_10B0  ; count reached zero -> cleanup
0FF0  C3 9C 07      JP loc_079C  ; more copies -> back to main loop

loc_0FF3:
0FF3  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
0FF6  CD 59 4C      CALL lcd_print  ; print following string
0FF9  1B C0 75 6E 72 65 +  DB ESC(0xC0), "unreadable", 0  ; LCD msg: cursor col0, "unreadable"

loc_1006:
1006  3E 01         LD A,0x01  ; key-wait param = 1 (blocking)
1008  CD 89 4D      CALL get_key  ; wait for operator keypress
100B  AF            XOR A  ; A=0 to clear image_present
100C  32 C8 52      LD (image_present),A  ; mark no valid image loaded
100F  C3 B0 10      JP loc_10B0  ; go to cleanup

loc_1012:
1012  3A 34 31      LD A,(op_word)  ; load op_word
1015  E6 0F         AND 0x0F  ; isolate op low nibble
1017  20 11         JR NZ,loc_102A  ; op non-zero -> loc_102A
1019  3A 4E 31      LD A,(run_status)  ; load run_status
101C  B7            OR A  ; test run_status
101D  20 18         JR NZ,loc_1037  ; run in progress -> autoloader accept/reject
101F  CD 5D 51      CALL checksum_all_banks  ; checksum all image banks
1022  3A 61 31      LD A,(host_mode)  ; load host_mode
1025  B7            OR A  ; test host_mode
1026  28 14         JR Z,loc_103C  ; local mode -> advance batch at loc_103C
1028  18 0D         JR loc_1037  ; host mode -> accept/reject path

loc_102A:
102A  FE 07         CP 0x07  ; op == 7 (copy/verify)?
102C  20 09         JR NZ,loc_1037  ; not op7 -> accept/reject path
102E  3A 4E 31      LD A,(run_status)  ; load run_status
1031  B7            OR A  ; test run_status
1032  20 03         JR NZ,loc_1037  ; already running -> accept/reject path
1034  CD 5D 51      CALL checksum_all_banks  ; checksum all image banks

loc_1037:
1037  CD D2 10      CALL al_accept_reject  ; run autoloader accept/reject decision
103A  38 3D         JR C,loc_1079  ; carry set (reject/error) -> loc_1079

loc_103C:
103C  2A 39 31      LD HL,(track_ctr)  ; load track/cycle counter
103F  23            INC HL  ; advance it
1040  22 39 31      LD (track_ctr),HL  ; store track counter
1043  21 67 31      LD HL,hrd_desc_tbl  ; point at hardware-descriptor table
1046  CB 4E         BIT 1,(HL)  ; test bit1 (serial-numbering enabled?)
1048  28 46         JR Z,batch_loop_tail  ; not enabled -> batch tail
104A  3A 34 31      LD A,(op_word)  ; load op_word
104D  E6 0F         AND 0x0F  ; isolate op low nibble
104F  FE 01         CP 0x01  ; op == 1?
1051  28 0C         JR Z,loc_105F  ; -> apply serial increment
1053  FE 05         CP 0x05  ; op == 5?
1055  28 08         JR Z,loc_105F  ; -> apply serial increment
1057  FE 04         CP 0x04  ; op == 4?
1059  28 04         JR Z,loc_105F  ; -> apply serial increment
105B  FE 06         CP 0x06  ; op == 6?
105D  20 31         JR NZ,batch_loop_tail  ; none matched -> batch tail

loc_105F:
105F  2A 68 31      LD HL,(serial_num_lo)  ; load current serial number (low word)
1062  3A 6C 31      LD A,(serial_incr)  ; load per-disk serial increment step
1065  5F            LD E,A  ; E = increment step (low byte)
1066  16 00         LD D,0x00  ; D = 0 (16-bit extend)
1068  19            ADD HL,DE  ; serial += step
1069  22 68 31      LD (serial_num_lo),HL  ; store serial number low word
106C  2A 6A 31      LD HL,(serial_num_hi)  ; load serial number high word
106F  11 00 00      LD DE,0x0000  ; DE=0: propagate only the carry into the high word
1072  ED 5A         ADC HL,DE  ; propagate carry into serial high word
1074  22 6A 31      LD (serial_num_hi),HL  ; store serial number high word
1077  18 17         JR batch_loop_tail  ; -> batch tail

loc_1079:
1079  2A 3B 31      LD HL,(pass_ctr)  ; load pass counter
107C  23            INC HL  ; bump pass count
107D  22 3B 31      LD (pass_ctr),HL  ; store pass counter
1080  47            LD B,A  ; stash reject status in B
1081  3A 61 31      LD A,(host_mode)  ; load host_mode
1084  B7            OR A  ; test host_mode
1085  20 29         JR NZ,loc_10B0  ; host mode -> cleanup
1087  78            LD A,B  ; restore reject status
1088  FE 01         CP 0x01  ; status == 1?
108A  CA 9C 07      JP Z,loc_079C  ; -> back to main loop
108D  C3 E5 0F      JP loc_0FE5  ; else re-check copies count at loc_0FE5

; end-of-pass tail: dec run_count, on last pass autoloader-accept, deselect, show OK/bad, wait key
batch_loop_tail:
1090  2A 3D 31      LD HL,(run_count)  ; load remaining run_count
1093  7D            LD A,L  ; A = run_count low byte
1094  B4            OR H  ; test run_count == 0
1095  CA 9C 07      JP Z,loc_079C  ; nothing left -> main loop
1098  2B            DEC HL  ; decrement run_count
1099  22 3D 31      LD (run_count),HL  ; store run_count
109C  7D            LD A,L  ; A = run_count low byte after decrement
109D  B4            OR H  ; test if more passes remain
109E  C2 9C 07      JP NZ,loc_079C  ; still passes left -> main loop
10A1  21 34 31      LD HL,op_word  ; point at op_word
10A4  3E 0F         LD A,0x0F  ; mask op low nibble
10A6  A6            AND (HL)  ; extract op code
10A7  FE 09         CP 0x09  ; op == 9 (autoloader accept)?
10A9  20 05         JR NZ,loc_10B0  ; not mode9 -> cleanup
10AB  36 00         LD (HL),0x00  ; clear op_word
10AD  CD C8 10      CALL al_gate_or_reject  ; gate to accept flow or beep reject

loc_10B0:
10B0  CD 57 07      CALL drive_cfg_latch  ; latch drive select/write-enable config
10B3  3A 34 31      LD A,(op_word)  ; load op_word
10B6  E6 0F         AND 0x0F  ; isolate op low nibble
10B8  28 06         JR Z,loc_10C0  ; op==0 -> skip result display
10BA  CD 3B 06      CALL show_ok_bad_count  ; show OK/bad tally on LCD
10BD  CD 43 4D      CALL keypad_debounce  ; debounce keypad after run

loc_10C0:
10C0  3A 4C 31      LD A,(fmt_mode)  ; load format-mode flag
10C3  21 50 31      LD HL,edit_ndigits  ; point at edit_ndigits
10C6  B6            OR (HL)  ; OR flags together for caller's Z test
10C7  C9            RET  ; return (Z reflects combined flags)

; if autoloader present route to accept/reject flow, else beep once (buzzer_pulse) and return A=0
al_gate_or_reject:
10C8  CD A8 11      CALL al_present_gate  ; autoloader present?
10CB  20 05         JR NZ,al_accept_reject  ; present -> accept/reject flow
10CD  CD FC 49      CALL buzzer_pulse  ; no autoloader -> one buzzer pulse
10D0  AF            XOR A  ; A=0 return value (no autoloader path)
10D1  C9            RET  ; return A=0

; autoloader ACCEPT (mode9): show "ACCEPT", eject good disk, retry build_select+verify up to 20x
al_accept_reject:
10D2  CD A0 11      CALL is_op_mode9  ; check op is mode9 (accept)
10D5  C8            RET Z  ; not mode9 -> return
10D6  06 41         LD B,0x41  ; B = 'A' (0x41) autoloader accept cmd
10D8  CD A8 11      CALL al_present_gate  ; autoloader present?
10DB  20 4C         JR NZ,loc_1129  ; autoloader present -> loc_1129 to send serial accept cmd
10DD  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
10E0  CD 59 4C      CALL lcd_print  ; print following string
10E3  1B C0 41 43 43 45 +  DB ESC(0xC0), "ACCEPT", 0  ; LCD msg: cursor col0, "ACCEPT"
10EC  3E 01         LD A,0x01  ; beep count = 1

loc_10EE:
10EE  21 8B 33      LD HL,retry_ctr+0x1  ; point at retry_ctr high byte (beep count)
10F1  77            LD (HL),A  ; store beep count
10F2  CD E3 49      CALL buzzer_beep  ; sound the beep(s)
10F5  2B            DEC HL  ; point at retry_ctr low byte
10F6  36 00         LD (HL),0x00  ; clear retry counter

loc_10F8:
10F8  CD 34 08      CALL fdc_build_select  ; build drive-select and load image
10FB  38 2A         JR C,loc_1127  ; error/carry -> return via loc_1127
10FD  3A C8 52      LD A,(image_present)  ; load image_present flag
1100  B7            OR A  ; test image_present
1101  C4 BA 51      CALL NZ,verify_ram_bank  ; if present, verify RAM bank vs image
1104  28 03         JR Z,loc_1109  ; verify OK -> loc_1109
1106  CD 2B 12      CALL show_lost_data  ; mismatch -> show "lost data"

loc_1109:
1109  21 8A 33      LD HL,retry_ctr  ; point at retry_ctr low byte
110C  34            INC (HL)  ; increment retry count
110D  3E 14         LD A,0x14  ; A = 20 (0x14) retry limit
110F  BE            CP (HL)  ; reached 20 retries?
1110  20 0A         JR NZ,loc_111C  ; not yet -> loc_111C
1112  21 8B 33      LD HL,retry_ctr+0x1  ; point at retry_ctr high byte
1115  7E            LD A,(HL)  ; load beep count
1116  CD E3 49      CALL buzzer_beep  ; beep to alert operator
1119  2B            DEC HL  ; point at retry_ctr low byte
111A  36 00         LD (HL),0x00  ; reset retry counter

loc_111C:
111C  AF            XOR A  ; A = 0 (non-blocking key check)
111D  CD 89 4D      CALL get_key  ; poll for keypress
1120  28 D6         JR Z,loc_10F8  ; no key -> retry build/verify loop
1122  3E 01         LD A,0x01  ; key-wait param = 1 (blocking)
1124  CD 89 4D      CALL get_key  ; wait for operator keypress

loc_1127:
1127  AF            XOR A  ; A=0 return value
1128  C9            RET  ; return A=0

loc_1129:
1129  06 41         LD B,0x41  ; B = 'A' (0x41) accept cmd
112B  18 1E         JR loc_114B  ; -> send at loc_114B

; autoloader REJECT: show "REJECT", send reject cmd 0x52, await ack with "timeout" handling
al_cmd_reject:
112D  CD A8 11      CALL al_present_gate  ; autoloader present?
1130  20 13         JR NZ,loc_1145  ; present -> loc_1145
1132  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
1135  CD 59 4C      CALL lcd_print  ; print following string
1138  1B C0 52 45 4A 45 +  DB ESC(0xC0), "REJECT", 0  ; LCD msg: cursor col0, "REJECT"
1141  3E 03         LD A,0x03  ; beep count = 3
1143  18 A9         JR loc_10EE  ; -> beep and continue at loc_10EE

loc_1145:
1145  CD A0 11      CALL is_op_mode9  ; check op is mode9
1148  C8            RET Z  ; not mode9 -> return
1149  06 52         LD B,0x52  ; B = 'R' (0x52) autoloader reject cmd

loc_114B:
114B  CD 99 4E      CALL al_tx  ; send command byte to autoloader (SIO)
114E  AF            XOR A  ; A=0 to clear fmt_mode
114F  32 4C 31      LD (fmt_mode),A  ; clear format-mode flag
1152  21 4D 31      LD HL,al_status1  ; point at al_status1 timeout counter
1155  36 40         LD (HL),0x40  ; timeout counter = 0x40

loc_1157:
1157  CD 53 4E      CALL al_rx_ready  ; autoloader reply byte ready?
115A  20 2B         JR NZ,loc_1187  ; ack arrived -> loc_1187
115C  35            DEC (HL)  ; decrement timeout counter
115D  20 1A         JR NZ,loc_1179  ; not expired -> keep polling at loc_1179
115F  CD 59 4C      CALL lcd_print  ; print following string
1162  74 69 6D 65 6F 75 +  DB "timeout", 0  ; LCD msg: "timeout"

loc_116A:
116A  3E 8C         LD A,0x8C  ; seed fmt_mode with 0x8C status code (bad-bin/reject class)
116C  32 4C 31      LD (fmt_mode),A  ; commit 0x8C error class into fmt_mode
116F  21 00 00      LD HL,0x0000  ; cursor to LCD home (row0,col0)
1172  CD 22 4C      CALL lcd_setpos  ; position LCD cursor
1175  3E 01         LD A,0x01  ; return code 1 = error/retry
1177  B7            OR A  ; clear Z so caller sees non-zero result
1178  C9            RET  ; return to caller

loc_1179:
1179  3A C8 52      LD A,(image_present)  ; load image_present flag
117C  B7            OR A  ; test if an image is loaded
117D  28 08         JR Z,loc_1187  ; no image -> skip RAM verify, go poll autoloader
117F  CD BA 51      CALL verify_ram_bank  ; verify current DRAM image bank integrity
1182  28 D3         JR Z,loc_1157  ; bank OK -> back to loc_1157 caller flow
1184  C3 2B 12      JP show_lost_data  ; bank bad -> fatal Lost data handler

loc_1187:
1187  CD E5 13      CALL al_rx_response  ; poll autoloader for a response byte
118A  C8            RET Z  ; no response (Z) -> return idle
118B  FE 02         CP 0x02  ; response == 2 ?
118D  20 DB         JR NZ,loc_116A  ; not status-2 -> retry from loc_116A
118F  CD FB 13      CALL al_cmd_status  ; request full autoloader status
1192  20 D6         JR NZ,loc_116A  ; status query failed -> retry from loc_116A
1194  CD 86 12      CALL al_status_decode  ; decode AL status byte into on-screen message
1197  F5            PUSH AF  ; save decode result across calibrate

; send autoloader calibrate command (0x43) with ack; sets carry (error-exit tail)
al_calibrate:
1198  06 43         LD B,0x43  ; B = autoloader CALIBRATE command 0x43
119A  CD D9 13      CALL al_cmd_ack  ; send command, wait for ack
119D  F1            POP AF  ; restore saved status result
119E  37            SCF  ; set carry = error-exit tail convention
119F  C9            RET  ; return to caller

; test whether op_word low nibble == 9 (autoloader run mode); returns Z if so
is_op_mode9:
11A0  3A 34 31      LD A,(op_word)  ; load op_word (current operation selector)
11A3  E6 0F         AND 0x0F  ; isolate low nibble (mode field)
11A5  FE 09         CP 0x09  ; compare against mode 9 (autoloader run)
11A7  C9            RET  ; return; Z set if op mode == 9

; gate on autoloader-present flag (al_present); returns Z if no autoloader attached
al_present_gate:
11A8  3A 62 31      LD A,(al_present)  ; load al_present (autoloader attached flag)
11AB  B7            OR A  ; test al_present flag
11AC  C9            RET  ; return; Z if no autoloader attached

; enter insert/read-source flow with retry_ctr preset to 1 (single-shot insert)
al_insert_disk:
11AD  21 8A 33      LD HL,retry_ctr  ; point at retry_ctr
11B0  36 01         LD (HL),0x01  ; retry_ctr = 1 (single-shot insert)
11B2  18 09         JR loc_11BD  ; join common insert flow at loc_11BD

; read source disk (autoloader-aware): command INSERT, spin up, verify bank, retry on rpm-low/lost-data
read_source:
11B4  21 8A 33      LD HL,retry_ctr  ; point at retry_ctr
11B7  36 00         LD (HL),0x00  ; retry_ctr = 0 (unlimited/normal source read)
11B9  CD A0 11      CALL is_op_mode9  ; check whether op mode == 9
11BC  C8            RET Z  ; not autoloader run mode -> return

loc_11BD:
11BD  CD A8 11      CALL al_present_gate  ; check autoloader-present flag
11C0  20 3A         JR NZ,al_insert  ; autoloader present -> issue INSERT command
11C2  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
11C5  CD 59 4C      CALL lcd_print  ; print following inline string
11C8  1B C0 49 4E 53 45 +  DB ESC(0xC0), "INSERT", 0  ; LCD msg: goto line2 + 'INSERT'

loc_11D1:
11D1  CD 34 08      CALL fdc_build_select  ; build FDC drive-select and spin up source drive
11D4  30 22         JR NC,loc_11F8  ; spin-up OK (NC) -> continue at loc_11F8
11D6  CD 11 08      CALL show_rpm_low  ; show 'RPM low' warning
11D9  3A C8 52      LD A,(image_present)  ; load image_present flag
11DC  B7            OR A  ; test if image loaded
11DD  C4 BA 51      CALL NZ,verify_ram_bank  ; if loaded, verify DRAM bank still intact
11E0  28 03         JR Z,loc_11E5  ; bank OK -> skip lost-data handler
11E2  CD 2B 12      CALL show_lost_data  ; bank bad -> report Lost data

loc_11E5:
11E5  AF            XOR A  ; A=0 -> non-blocking key poll
11E6  CD 89 4D      CALL get_key  ; read key (0 = poll only)
11E9  28 E6         JR Z,loc_11D1  ; no key -> loop and retry drive select
11EB  3A 8A 33      LD A,(retry_ctr)  ; load retry_ctr
11EE  B7            OR A  ; test retry count
11EF  20 07         JR NZ,loc_11F8  ; retries remain -> continue at loc_11F8
11F1  32 8A 33      LD (retry_ctr),A  ; clear retry_ctr
11F4  3E 01         LD A,0x01  ; return code 1 = aborted/error
11F6  B7            OR A  ; clear Z for non-zero result
11F7  C9            RET  ; return to caller

loc_11F8:
11F8  C3 4C 12      JP loc_124C  ; proceed to cycle-count / done flow
11FB  C9            RET  ; return (fall-through safety)

; send autoloader insert command (0x49), wait ready; "timeout" message on no response
al_insert:
11FC  06 49         LD B,0x49  ; B = autoloader INSERT command 0x49
11FE  CD 99 4E      CALL al_tx  ; transmit command to autoloader
1201  21 4D 31      LD HL,al_status1  ; point at al_status1 timeout counter
1204  36 40         LD (HL),0x40  ; preset timeout counter = 0x40 tries

loc_1206:
1206  CD 53 4E      CALL al_rx_ready  ; poll autoloader ready line
1209  20 3C         JR NZ,loc_1247  ; ready -> handle response at loc_1247
120B  35            DEC (HL)  ; decrement timeout counter
120C  20 12         JR NZ,loc_1220  ; not expired -> keep verifying/waiting
120E  CD 59 4C      CALL lcd_print  ; print inline string
1211  74 69 6D 65 6F 75 +  DB "timeout", 0  ; LCD msg: 'timeout'
1219  CD 43 4D      CALL keypad_debounce  ; wait/debounce keypad
121C  3E 01         LD A,0x01  ; return code 1 = timeout/error
121E  B7            OR A  ; clear Z for non-zero result
121F  C9            RET  ; return to caller

loc_1220:
1220  3A C8 52      LD A,(image_present)  ; load image_present flag
1223  B7            OR A  ; test if image loaded
1224  28 21         JR Z,loc_1247  ; no image -> go read response at loc_1247
1226  CD BA 51      CALL verify_ram_bank  ; verify DRAM image bank integrity
1229  28 DB         JR Z,loc_1206  ; bank OK -> keep polling ready

; fatal image-lost error: hex-dump 0x52C7, draw "Lost data", then halt (spin forever)
show_lost_data:
122B  21 C7 52      LD HL,menu_scratch+0x5  ; HL -> menu_scratch+5 (hex dump source)
122E  3E 01         LD A,0x01  ; A=1 dump length/mode
1230  CD 3B 4F      CALL lcd_dump_hex  ; hex-dump region to LCD for diagnostics
1233  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
1236  CD 59 4C      CALL lcd_print  ; print inline string
1239  1B C0 4C 6F 73 74 +  DB ESC(0xC0), "Lost data", 0  ; LCD msg: goto line2 + 'Lost data'

loc_1245:
1245  18 FE         JR loc_1245  ; halt: spin forever (fatal)

loc_1247:
1247  CD E5 13      CALL al_rx_response  ; poll autoloader for response byte
124A  20 15         JR NZ,loc_1261  ; non-zero -> evaluate response at loc_1261

loc_124C:
124C  2A 69 32      LD HL,(cycle_cnt_lo)  ; load 16-bit cycle counter low word
124F  11 01 00      LD DE,0x0001  ; DE = 1 increment
1252  19            ADD HL,DE  ; add 1 to cycle count
1253  22 69 32      LD (cycle_cnt_lo),HL  ; store updated low word
1256  30 07         JR NC,loc_125F  ; no carry -> done
1258  2A 6B 32      LD HL,(cycle_cnt_hi)  ; load cycle counter high word
125B  23            INC HL  ; carry into high word
125C  22 6B 32      LD (cycle_cnt_hi),HL  ; store high word

loc_125F:
125F  AF            XOR A  ; A=0 success return code
1260  C9            RET  ; return to caller

loc_1261:
1261  FE 02         CP 0x02  ; response == 2 ?
1263  C0            RET NZ  ; not status-2 -> return with code

loc_1264:
1264  CD FB 13      CALL al_cmd_status  ; request full autoloader status
1267  20 F8         JR NZ,loc_1261  ; status query failed -> re-check at loc_1261
1269  CD 86 12      CALL al_status_decode  ; decode AL status byte into message
126C  F5            PUSH AF  ; save decode result across reject/calibrate

; send autoloader reject(0x52)+calibrate(0x43) with ack; on ok re-insert per retry_ctr
al_reject:
126D  06 52         LD B,0x52  ; B = autoloader REJECT command 0x52
126F  CD D9 13      CALL al_cmd_ack  ; send reject, wait ack
1272  06 43         LD B,0x43  ; B = autoloader CALIBRATE command 0x43
1274  CD D9 13      CALL al_cmd_ack  ; send calibrate, wait ack
1277  28 03         JR Z,loc_127C  ; ack OK (Z) -> handle re-insert at loc_127C
1279  F1            POP AF  ; discard saved result
127A  18 E8         JR loc_1264  ; retry status loop at loc_1264

loc_127C:
127C  F1            POP AF  ; restore saved decode result
127D  FE 01         CP 0x01  ; result == 1 (needs re-insert) ?
127F  CA FC 11      JP Z,al_insert  ; yes -> re-issue INSERT command
1282  3E 03         LD A,0x03  ; return code 3 = handled/other
1284  B7            OR A  ; clear Z for non-zero result
1285  C9            RET  ; return to caller

; decode autoloader status byte -> on-screen message (bit1 seated, hi-nibble class)
al_status_decode:
1286  F5            PUSH AF  ; save status byte across LCD clear
1287  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
128A  F1            POP AF  ; restore status byte
128B  CB 4F         BIT 1,A  ; test bit1 = disk-seated flag
128D  CA 7D 13      JP Z,loc_137D  ; not seated -> Hopper-not-seated handler
1290  E6 F0         AND 0xF0  ; isolate high nibble (status class)
1292  FE 20         CP 0x20  ; class 0x20 ?
1294  CA 2B 13      JP Z,loc_132B  ; yes -> Hopper empty
1297  FE 10         CP 0x10  ; class 0x10 ?
1299  CA 98 13      JP Z,loc_1398  ; yes -> loc_1398 handler
129C  FE 80         CP 0x80  ; class 0x80 ?
129E  CA A5 13      JP Z,loc_13A5  ; yes -> loc_13A5 handler
12A1  FE 90         CP 0x90  ; class 0x90 ?
12A3  CA C1 13      JP Z,loc_13C1  ; yes -> loc_13C1 handler
12A6  FE A0         CP 0xA0  ; class 0xA0 ?
12A8  CA 0F 13      JP Z,loc_130F  ; yes -> Accept hopper full
12AB  FE D0         CP 0xD0  ; class 0xD0 ?
12AD  CA F9 12      JP Z,loc_12F9  ; yes -> Bad bin full
12B0  FE C0         CP 0xC0  ; class 0xC0 ?
12B2  CA E3 12      JP Z,loc_12E3  ; yes -> Reject error
12B5  FE 00         CP 0x00  ; class 0x00 ?
12B7  20 20         JR NZ,loc_12D9  ; non-zero class -> generic AL error
12B9  32 4C 31      LD (fmt_mode),A  ; clear fmt_mode (status = ok)
12BC  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
12BF  CD 59 4C      CALL lcd_print  ; print inline string
12C2  0C 1B C0 41 4C 20 +  DB \f, ESC(0xC0), "AL status ok", 0  ; LCD msg: clear + line2 + 'AL status ok'
12D2  CD 43 4D      CALL keypad_debounce  ; wait/debounce keypad
12D5  AF            XOR A  ; clear A/flags (immediately overwritten by next load)
12D6  3E 01         LD A,0x01  ; return code 1 = ok/acknowledged
12D8  C9            RET  ; return to caller

loc_12D9:
12D9  CD B0 02      CALL show_al_error  ; show generic autoloader error
12DC  CD 43 4D      CALL keypad_debounce  ; wait/debounce keypad
12DF  3E 8A         LD A,0x8A  ; A = 0x8A error-class code
12E1  18 5C         JR loc_133F  ; join common message/wait tail

loc_12E3:
12E3  CD 59 4C      CALL lcd_print  ; print inline string
12E6  1B C0 52 65 6A 65 +  DB ESC(0xC0), "Reject error", 0  ; LCD msg: line2 + 'Reject error'
12F5  3E 8C         LD A,0x8C  ; A = 0x8C reject/bad-bin class
12F7  18 46         JR loc_133F  ; join common message/wait tail

loc_12F9:
12F9  CD 59 4C      CALL lcd_print  ; print inline string
12FC  1B C0 42 61 64 20 +  DB ESC(0xC0), "Bad bin full", 0  ; LCD msg: line2 + 'Bad bin full'
130B  3E 8C         LD A,0x8C  ; A = 0x8C error class
130D  18 30         JR loc_133F  ; join common message/wait tail

loc_130F:
130F  CD 59 4C      CALL lcd_print  ; print inline string
1312  1B C0 41 63 63 65 +  DB ESC(0xC0), "Accept hopper full", 0  ; LCD msg: line2 + 'Accept hopper full'
1327  3E 8C         LD A,0x8C  ; A = 0x8C error class
1329  18 14         JR loc_133F  ; join common message/wait tail

loc_132B:
132B  CD 59 4C      CALL lcd_print  ; print inline string
132E  1B C0 48 6F 70 70 +  DB ESC(0xC0), "Hopper empty", 0  ; LCD msg: line2 + 'Hopper empty'
133D  3E 82         LD A,0x82  ; A = 0x82 hopper-empty class

loc_133F:
133F  32 4C 31      LD (fmt_mode),A  ; store status class into fmt_mode
1342  47            LD B,A  ; B = copy of class code
1343  3A 4C 31      LD A,(fmt_mode)  ; reload fmt_mode
1346  FE 8A         CP 0x8A  ; class == 0x8A (generic error) ?
1348  3E 01         LD A,0x01  ; A = 1 return code
134A  C8            RET Z  ; yes -> return code 1
134B  3A 61 31      LD A,(host_mode)  ; load host_mode flag
134E  A7            AND A  ; test host (remote) mode
134F  3E 02         LD A,0x02  ; A = 2 return code
1351  C0            RET NZ  ; host mode active -> return code 2
1352  06 64         LD B,0x64  ; B = 0x64 beep/timeout loop count

loc_1354:
1354  AF            XOR A  ; A=0 non-blocking key poll
1355  CD 89 4D      CALL get_key  ; poll keypad (non-blocking) during beep/timeout wait
1358  20 11         JR NZ,loc_136B  ; key pressed -> exit wait at loc_136B
135A  2B            DEC HL  ; decrement 16-bit delay counter (HL)
135B  7D            LD A,L  ; A = low byte
135C  B4            OR H  ; OR high byte to test HL==0
135D  20 F5         JR NZ,loc_1354  ; not zero -> keep waiting
135F  78            LD A,B  ; A = beep count B
1360  B7            OR A  ; test remaining beeps
1361  28 F1         JR Z,loc_1354  ; none left -> keep polling
1363  05            DEC B  ; consume one beep
1364  3E 01         LD A,0x01  ; A=1
1366  CD 66 27      CALL beep  ; sound a beep
1369  18 E9         JR loc_1354  ; loop back to key/delay wait

loc_136B:
136B  3A 34 31      LD A,(op_word)  ; load op_word
136E  E6 0F         AND 0x0F  ; isolate low nibble (mode)
1370  28 03         JR Z,loc_1375  ; mode 0 -> skip count display
1372  CD 3B 06      CALL show_ok_bad_count  ; show OK/BAD copy counts

loc_1375:
1375  3E 01         LD A,0x01  ; A=1 blocking key read
1377  CD 89 4D      CALL get_key  ; read key (wait for press)
137A  E6 0F         AND 0x0F  ; mask key to low nibble as return value
137C  C9            RET  ; return key code to caller

loc_137D:
137D  CD 59 4C      CALL lcd_print  ; print inline string
1380  1B C0 48 6F 70 70 +  DB ESC(0xC0), "Hopper not seated", 0  ; LCD msg: line2 + 'Hopper not seated'
1394  3E 82         LD A,0x82  ; A = 0x82 not-seated class
1396  18 A7         JR loc_133F  ; join common message/wait tail

loc_1398:
1398  CD 59 4C      CALL lcd_print  ; show LCD error message for a paper/media jam
139B  1B C0 4A 61 6D 00  DB ESC(0xC0), "Jam", 0  ; inline string: cursor-to-line2 (ESC 0xC0) + "Jam", NUL-terminated
13A1  3E 84         LD A,0x84  ; error code 0x84 = jam
13A3  18 9A         JR loc_133F  ; join common error-exit path loc_133F

loc_13A5:
13A5  CD 59 4C      CALL lcd_print  ; show LCD "Calibration error" message
13A8  1B C0 43 61 6C 69 +  DB ESC(0xC0), "Calibration error", 0  ; inline string: cursor-to-line2 + "Calibration error", NUL-terminated
13BC  3E 86         LD A,0x86  ; error code 0x86 = calibration error
13BE  C3 3F 13      JP loc_133F  ; jump to common error-exit path loc_133F

loc_13C1:
13C1  CD 59 4C      CALL lcd_print  ; show LCD "Eject timeout" message
13C4  1B C0 45 6A 65 63 +  DB ESC(0xC0), "Eject timeout", 0  ; inline string: cursor-to-line2 + "Eject timeout", NUL-terminated
13D4  3E 88         LD A,0x88  ; error code 0x88 = eject timeout
13D6  C3 3F 13      JP loc_133F  ; jump to common error-exit path loc_133F

; send 1-char autoloader command in B, read reply; 'X'=ok/1=timeout/2=other
al_cmd_ack:
13D9  DB D0         IN A,(0xD0)  ; al_data — drain stale byte 1 from autoloader SIO RX
13DB  DB D0         IN A,(0xD0)  ; al_data — drain stale byte 2 from autoloader SIO RX
13DD  DB D0         IN A,(0xD0)  ; al_data — drain stale byte 3 from autoloader SIO RX
13DF  CD 91 4E      CALL al_cmd_reset  ; reset autoloader SIO channel status before sending
13E2  CD 99 4E      CALL al_tx  ; transmit the 1-char command in B to the autoloader

; receive one autoloader response byte into fmt_mode; return 0 if 'X' ack, else error code 1/2
al_rx_response:
13E5  CD A1 4E      CALL al_rx  ; receive one response byte from the autoloader
13E8  32 4C 31      LD (fmt_mode),A  ; stash received byte in fmt_mode
13EB  20 06         JR NZ,loc_13F3  ; if RX timed out (NZ) return timeout code 1
13ED  3E 58         LD A,0x58  ; expected ack char 'X' (0x58)
13EF  B8            CP B  ; compare received byte against 'X'
13F0  20 05         JR NZ,loc_13F7  ; if not 'X' report other-error code 2
13F2  C9            RET  ; return 0: autoloader acknowledged 'X'

loc_13F3:
13F3  3E 01         LD A,0x01  ; load timeout status code 1
13F5  B7            OR A  ; set flags (NZ) to signal error
13F6  C9            RET  ; return with timeout code 1

loc_13F7:
13F7  3E 02         LD A,0x02  ; load other-error status code 2
13F9  B7            OR A  ; set flags (NZ) to signal error
13FA  C9            RET  ; return with error code 2

; autoloader S(tatus): read 2 ASCII-hex chars, decode to status byte
al_cmd_status:
13FB  CD 33 14      CALL al_flush_rx  ; flush any stale autoloader RX bytes first
13FE  06 53         LD B,0x53  ; 'S' (0x53) = autoloader Status query command
1400  CD 99 4E      CALL al_tx  ; transmit 'S' to the autoloader
1403  CD A1 4E      CALL al_rx  ; receive first ASCII-hex status digit
1406  20 20         JR NZ,loc_1428  ; on RX timeout return error code 1
1408  78            LD A,B  ; copy received high-nibble char into A
1409  32 4C 31      LD (fmt_mode),A  ; save high-nibble char to fmt_mode
140C  CD A1 4E      CALL al_rx  ; receive second ASCII-hex status digit
140F  20 17         JR NZ,loc_1428  ; on RX timeout return error code 1
1411  78            LD A,B  ; copy received low-nibble char into A
1412  32 4D 31      LD (al_status1),A  ; save low-nibble char to al_status1
1415  CD 2B 14      CALL ascii_hex_to_nibble  ; decode low-nibble ASCII-hex char to 0-15
1418  47            LD B,A  ; keep low nibble in B
1419  3A 4C 31      LD A,(fmt_mode)  ; reload the high-nibble char from fmt_mode
141C  CD 2B 14      CALL ascii_hex_to_nibble  ; decode high-nibble ASCII-hex char to 0-15
141F  87            ADD A,A  ; shift high nibble left by 1 (build <<4)
1420  87            ADD A,A  ; shift high nibble left by 2
1421  87            ADD A,A  ; shift high nibble left by 3
1422  87            ADD A,A  ; shift high nibble left by 4 -> high nibble in bits[7:4]
1423  B0            OR B  ; merge low nibble to form the status byte
1424  47            LD B,A  ; hold assembled status byte in B
1425  AF            XOR A  ; clear A (Z flag = success)
1426  78            LD A,B  ; return the decoded status byte in A
1427  C9            RET  ; return success with status byte

loc_1428:
1428  3E 01         LD A,0x01  ; return error code 1 (status read failed)
142A  C9            RET  ; return with error code 1

; convert one ASCII hex character in A to its 0-15 nibble value
ascii_hex_to_nibble:
142B  D6 30         SUB 0x30  ; subtract '0' to map ASCII digit to value
142D  FE 0A         CP 0x0A  ; check if result is a decimal digit (<0x0A)
142F  D8            RET C  ; if 0-9, return the nibble value
1430  D6 07         SUB 0x07  ; else adjust A-F: subtract 7 to land on 10-15
1432  C9            RET  ; return the decoded nibble

; drain 3 stale bytes from autoloader SIO RX (0xD0) and reset its status
al_flush_rx:
1433  DB D0         IN A,(0xD0)  ; al_data — read+discard stale autoloader RX byte 1
1435  F5            PUSH AF  ; brief settle delay (push)
1436  F1            POP AF  ; brief settle delay (pop)
1437  DB D0         IN A,(0xD0)  ; al_data — read+discard stale autoloader RX byte 2
1439  F5            PUSH AF  ; brief settle delay (push)
143A  F1            POP AF  ; brief settle delay (pop)
143B  DB D0         IN A,(0xD0)  ; al_data — read+discard stale autoloader RX byte 3
143D  F5            PUSH AF  ; brief settle delay (push)
143E  F1            POP AF  ; brief settle delay (pop)
143F  3E 30         LD A,0x30  ; SIO error-reset command value 0x30
1441  D3 D4         OUT (0xD4),A  ; al_stat — write reset to autoloader SIO status/control port
1443  C9            RET  ; return, RX drained and status cleared

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
1540  CD 59 4C      CALL lcd_print  ; print the "HRD diagnostics" menu title
1543  0C 48 52 44 20 64 +  DB \f, "HRD diagnostics", 0  ; inline string: form-feed (clear) + "HRD diagnostics", NUL
1554  C9            RET  ; return to caller

; print "Special formats" menu title
special_formats_menu:
1555  CD 59 4C      CALL lcd_print  ; print the "Special formats" menu title
1558  0C 53 70 65 63 69 +  DB \f, "Special formats", 0  ; inline string: form-feed (clear) + "Special formats", NUL
1569  C9            RET  ; return to caller

; run special-format submenu A (spfmt_menu_a) via menu_run
menu_show_a:
156A  21 54 14      LD HL,spfmt_menu_a  ; point HL at special-format submenu A table
156D  CD 2F 52      CALL menu_run  ; drive the submenu via menu_run
1570  C9            RET  ; return to caller

; run special-format submenu B (spfmt_menu_b) via menu_run
menu_show_b:
1571  21 8E 14      LD HL,spfmt_menu_b  ; point HL at special-format submenu B table
1574  CD 2F 52      CALL menu_run  ; drive the submenu via menu_run
1577  C9            RET  ; return to caller

; run special-format submenu C (spfmt_menu_c) via menu_run
menu_show_c:
1578  21 72 14      LD HL,spfmt_menu_c  ; point HL at special-format submenu C table
157B  CD 2F 52      CALL menu_run  ; drive the submenu via menu_run
157E  C9            RET  ; return to caller

; run special-format submenu D (spfmt_menu_d) via menu_run
menu_show_d:
157F  21 80 14      LD HL,spfmt_menu_d  ; point HL at special-format submenu D table
1582  CD 2F 52      CALL menu_run  ; drive the submenu via menu_run
1585  C9            RET  ; return to caller

; run special-format submenu E (spfmt_menu_e) via menu_run
menu_show_e:
1586  21 9C 14      LD HL,spfmt_menu_e  ; point HL at special-format submenu E table
1589  CD 2F 52      CALL menu_run  ; drive the submenu via menu_run
158C  C9            RET  ; return to caller

; display "Special format No. 1" screen (selects number string, stores cyl_head to 0x3165)
spfmt_show_01:
158D  21 FB 15      LD HL,loc_15FB  ; HL -> " 1" suffix printer for slot 1
1590  18 49         JR loc_15DB  ; join shared "No.N" display code loc_15DB

; display "Special format No. 2" screen (shared No.-N display code)
spfmt_show_02:
1592  21 02 16      LD HL,loc_1602  ; HL -> " 2" suffix printer for slot 2
1595  18 44         JR loc_15DB  ; join shared "No.N" display code

; display "Special format No. 3" screen (shared No.-N display code)
spfmt_show_03:
1597  21 09 16      LD HL,loc_1609  ; HL -> " 3" suffix printer for slot 3
159A  18 3F         JR loc_15DB  ; join shared "No.N" display code

; display "Special format No. 4" screen (shared No.-N display code)
spfmt_show_04:
159C  21 10 16      LD HL,loc_1610  ; HL -> " 4" suffix printer for slot 4
159F  18 3A         JR loc_15DB  ; join shared "No.N" display code

; display "Special format No. 5" screen (shared No.-N display code)
spfmt_show_05:
15A1  21 17 16      LD HL,loc_1617  ; HL -> " 5" suffix printer for slot 5
15A4  18 35         JR loc_15DB  ; join shared "No.N" display code

; display "Special format No. 6" screen (shared No.-N display code)
spfmt_show_06:
15A6  21 1E 16      LD HL,loc_161E  ; HL -> " 6" suffix printer for slot 6
15A9  18 30         JR loc_15DB  ; join shared "No.N" display code

; display "Special format No. 7" screen (shared No.-N display code)
spfmt_show_07:
15AB  21 25 16      LD HL,loc_1625  ; HL -> " 7" suffix printer for slot 7
15AE  18 2B         JR loc_15DB  ; join shared "No.N" display code

; draw 'Special format No. 8' menu title, latch cyl_head into 0x3165 (slot 8 of 8-16 chain)
spfmt_show_08:
15B0  21 2C 16      LD HL,loc_162C  ; HL -> " 8" suffix printer for slot 8
15B3  18 26         JR loc_15DB  ; join shared "No.N" display code

; draw 'Special format No. 9' menu title, latch cyl_head into 0x3165
spfmt_show_09:
15B5  21 33 16      LD HL,loc_1633  ; HL -> " 9" suffix printer for slot 9
15B8  18 21         JR loc_15DB  ; join shared "No.N" display code

; draw 'Special format No.10' menu title, latch cyl_head into 0x3165
spfmt_show_10:
15BA  21 3A 16      LD HL,loc_163A  ; HL -> "10" suffix printer for slot 10
15BD  18 1C         JR loc_15DB  ; join shared "No.N" display code

; draw 'Special format No.11' menu title, latch cyl_head into 0x3165
spfmt_show_11:
15BF  21 41 16      LD HL,loc_1641  ; HL -> "11" suffix printer for slot 11
15C2  18 17         JR loc_15DB  ; join shared "No.N" display code

; draw 'Special format No.12' menu title, latch cyl_head into 0x3165
spfmt_show_12:
15C4  21 48 16      LD HL,loc_1648  ; HL -> "12" suffix printer for slot 12
15C7  18 12         JR loc_15DB  ; join shared "No.N" display code

; draw 'Special format No.13' menu title, latch cyl_head into 0x3165
spfmt_show_13:
15C9  21 4F 16      LD HL,loc_164F  ; HL -> "13" suffix printer for slot 13
15CC  18 0D         JR loc_15DB  ; join shared "No.N" display code

; draw 'Special format No.14' menu title, latch cyl_head into 0x3165
spfmt_show_14:
15CE  21 56 16      LD HL,loc_1656  ; HL -> "14" suffix printer for slot 14
15D1  18 08         JR loc_15DB  ; join shared "No.N" display code

; draw 'Special format No.15' menu title, latch cyl_head into 0x3165
spfmt_show_15:
15D3  21 5D 16      LD HL,loc_165D  ; HL -> "15" suffix printer for slot 15
15D6  18 03         JR loc_15DB  ; join shared "No.N" display code

; draw 'Special format No.16' menu title, latch cyl_head into 0x3165
spfmt_show_16:
15D8  21 64 16      LD HL,loc_1664  ; HL -> "16" suffix printer for slot 16 (falls through)

loc_15DB:
15DB  E5            PUSH HL  ; save the per-slot suffix-printer pointer
15DC  CD 59 4C      CALL lcd_print  ; print the shared title text
15DF  0C 53 70 65 63 69 +  DB \f, "Special format No.", 0  ; inline string: form-feed (clear) + "Special format No.", NUL
15F3  3A 64 31      LD A,(cyl_head)  ; read current cyl_head selection
15F6  32 65 31      LD (spfmt_num),A  ; latch it into spfmt_num for this slot
15F9  E1            POP HL  ; restore the suffix-printer pointer
15FA  E9            JP (HL)  ; tail-call the per-slot suffix printer

loc_15FB:
15FB  CD 59 4C      CALL lcd_print  ; print the " 1" slot-number suffix
15FE  20 31 00      DB " 1", 0  ; inline string: " 1", NUL
1601  C9            RET  ; return to caller

loc_1602:
1602  CD 59 4C      CALL lcd_print  ; print the " 2" slot-number suffix
1605  20 32 00      DB " 2", 0  ; inline string: " 2", NUL
1608  C9            RET  ; return to caller

loc_1609:
1609  CD 59 4C      CALL lcd_print  ; print the " 3" slot-number suffix
160C  20 33 00      DB " 3", 0  ; inline string: " 3", NUL
160F  C9            RET  ; return to caller

loc_1610:
1610  CD 59 4C      CALL lcd_print  ; print the " 4" slot-number suffix
1613  20 34 00      DB " 4", 0  ; inline string: " 4", NUL
1616  C9            RET  ; return to caller

loc_1617:
1617  CD 59 4C      CALL lcd_print  ; print the " 5" slot-number suffix
161A  20 35 00      DB " 5", 0  ; inline string: " 5", NUL
161D  C9            RET  ; return to caller

loc_161E:
161E  CD 59 4C      CALL lcd_print  ; print the " 6" slot-number suffix
1621  20 36 00      DB " 6", 0  ; inline string: " 6", NUL
1624  C9            RET  ; return to caller

loc_1625:
1625  CD 59 4C      CALL lcd_print  ; print the " 7" slot-number suffix
1628  20 37 00      DB " 7", 0  ; inline string: " 7", NUL
162B  C9            RET  ; return to caller

loc_162C:
162C  CD 59 4C      CALL lcd_print  ; print the " 8" slot-number suffix
162F  20 38 00      DB " 8", 0  ; inline string: " 8", NUL
1632  C9            RET  ; return to caller

loc_1633:
1633  CD 59 4C      CALL lcd_print  ; print the " 9" slot-number suffix
1636  20 39 00      DB " 9", 0  ; inline string: " 9", NUL
1639  C9            RET  ; return to caller

loc_163A:
163A  CD 59 4C      CALL lcd_print  ; print the "10" slot-number suffix
163D  31 30 00      DB "10", 0  ; inline string: "10", NUL
1640  C9            RET  ; return to caller

loc_1641:
1641  CD 59 4C      CALL lcd_print  ; print the "11" slot-number suffix
1644  31 31 00      DB "11", 0  ; inline string: "11", NUL
1647  C9            RET  ; return to caller

loc_1648:
1648  CD 59 4C      CALL lcd_print  ; print the "12" slot-number suffix
164B  31 32 00      DB "12", 0  ; inline string: "12", NUL
164E  C9            RET  ; return to caller

loc_164F:
164F  CD 59 4C      CALL lcd_print  ; print the "13" slot-number suffix
1652  31 33 00      DB "13", 0  ; inline string: "13", NUL
1655  C9            RET  ; return to caller

loc_1656:
1656  CD 59 4C      CALL lcd_print  ; print the "14" slot-number suffix
1659  31 34 00      DB "14", 0  ; inline string: "14", NUL
165C  C9            RET  ; return to caller

loc_165D:
165D  CD 59 4C      CALL lcd_print  ; print the "15" slot-number suffix
1660  31 35 00      DB "15", 0  ; inline string: "15", NUL
1663  C9            RET  ; return to caller

loc_1664:
1664  CD 59 4C      CALL lcd_print  ; print the "16" slot-number suffix
1667  31 36 00      DB "16", 0  ; inline string: "16", NUL
166A  C9            RET  ; return to caller

; apply special-format slot 1 as DD: cyl_head=1, clear density bit, run fmt_apply
spfmt_apply_01:
166B  3E 01         LD A,0x01  ; select special-format slot 1 (cyl_head=1)
166D  C3 2A 18      JP loc_182A  ; jump to DD apply path (clear density bit, run fmt_apply)

loc_1670:
1670  21 64 31      LD HL,cyl_head  ; point HL at cyl_head slot for the special-format index
1673  77            LD (HL),A  ; store selected special-format slot number into cyl_head
1674  C3 5D 18      JP loc_185D  ; jump into fmt_apply core (skip density change)

; apply special-format slot 2 as DD: cyl_head=2, clear density bit, run fmt_apply
spfmt_apply_02:
1677  3E 02         LD A,0x02  ; special-format slot 2 -> A=2 (DD)
1679  C3 2A 18      JP loc_182A  ; go clear density bit then run fmt_apply

; apply special-format slot 3 as DD: cyl_head=3, clear density bit, run fmt_apply
spfmt_apply_03:
167C  3E 03         LD A,0x03  ; special-format slot 3 -> A=3 (DD)
167E  C3 2A 18      JP loc_182A  ; go clear density bit then run fmt_apply

; apply special-format slot 4 as HD: cyl_head=4, set density bit, run fmt_apply
spfmt_apply_04:
1681  3E 04         LD A,0x04  ; special-format slot 4 -> A=4 (HD)
1683  C3 42 18      JP loc_1842  ; go set density bit then run fmt_apply

; apply special-format slot 5 as HD: cyl_head=5, set density bit, run fmt_apply
spfmt_apply_05:
1686  3E 05         LD A,0x05  ; special-format slot 5 -> A=5 (HD)
1688  C3 42 18      JP loc_1842  ; go set density bit then run fmt_apply

; apply special-format slot 6 as HD: cyl_head=6, set density bit, run fmt_apply
spfmt_apply_06:
168B  3E 06         LD A,0x06  ; special-format slot 6 -> A=6 (HD)
168D  C3 42 18      JP loc_1842  ; go set density bit then run fmt_apply

; apply special-format slot 7 as HD: cyl_head=7, set density bit, run fmt_apply
spfmt_apply_07:
1690  3E 07         LD A,0x07  ; special-format slot 7 -> A=7 (HD)
1692  C3 42 18      JP loc_1842  ; go set density bit then run fmt_apply

; apply special-format slot 8: set cyl_head=8, run fmt_apply core (no density change)
spfmt_apply_08:
1695  3E 08         LD A,0x08  ; special-format slot 8 -> A=8 (no density change)
1697  18 D7         JR loc_1670  ; store slot 8 and run fmt_apply core

; apply special-format slot 9: set cyl_head=9, run fmt_apply core (no density change)
spfmt_apply_09:
1699  3E 09         LD A,0x09  ; special-format slot 9 -> A=9 (no density change)
169B  18 D3         JR loc_1670  ; store slot 9 and run fmt_apply core

; apply special-format slot 10: set cyl_head=10, run fmt_apply core
spfmt_apply_10:
169D  3E 0A         LD A,0x0A  ; special-format slot 10 -> A=0x0A
169F  18 CF         JR loc_1670  ; store slot 10 and run fmt_apply core

; apply special-format slot 11: set cyl_head=11, run fmt_apply core
spfmt_apply_11:
16A1  3E 0B         LD A,0x0B  ; special-format slot 11 -> A=0x0B
16A3  18 CB         JR loc_1670  ; store slot 11 and run fmt_apply core

; apply special-format slot 12: set cyl_head=12, run fmt_apply core
spfmt_apply_12:
16A5  3E 0C         LD A,0x0C  ; special-format slot 12 -> A=0x0C
16A7  18 C7         JR loc_1670  ; store slot 12 and run fmt_apply core

; apply special-format slot 13: set cyl_head=13, run fmt_apply core
spfmt_apply_13:
16A9  3E 0D         LD A,0x0D  ; special-format slot 13 -> A=0x0D
16AB  18 C3         JR loc_1670  ; store slot 13 and run fmt_apply core

; apply special-format slot 14: set cyl_head=14, run fmt_apply core
spfmt_apply_14:
16AD  3E 0E         LD A,0x0E  ; special-format slot 14 -> A=0x0E
16AF  18 BF         JR loc_1670  ; store slot 14 and run fmt_apply core

; apply special-format slot 15: set cyl_head=15, run fmt_apply core
spfmt_apply_15:
16B1  3E 0F         LD A,0x0F  ; special-format slot 15 -> A=0x0F
16B3  18 BB         JR loc_1670  ; store slot 15 and run fmt_apply core

; apply special-format slot 16: set cyl_head=16, run fmt_apply core
spfmt_apply_16:
16B5  3E 10         LD A,0x10  ; special-format slot 16 -> A=0x10
16B7  18 B7         JR loc_1670  ; store slot 16 and run fmt_apply core

; print media spec line '3.5" 720kB 9sec 80cyl 2h' for the format-select menu
fmt_35_720k:
16B9  CD 59 4C      CALL lcd_print  ; print inline media spec string via lcd_print (address follows CALL)
16BC  0C 33 2E 35 22 20 +  DB \f, "3.5\"  720 kB 512 b/s 9 sec. 80 cyl. 2 h.", 0  ; inline NUL-terminated spec string: 3.5" 720kB 9 sec 80 cyl
16E6  C9            RET  ; return to caller after printing 3.5" 720kB spec

; print media spec line '3.5" 1.44MB 18sec 80cyl 2h' for the format-select menu
fmt_35_144m:
16E7  CD 59 4C      CALL lcd_print  ; print inline media spec string via lcd_print
16EA  0C 33 2E 35 22 20 +  DB \f, "3.5\" 1.44 MB 512 b/s18 sec. 80 cyl. 2 h.", 0  ; inline spec string: 3.5" 1.44MB 18 sec 80 cyl
1714  C9            RET  ; return after printing 3.5" 1.44MB spec

; print media spec line '5.25" 360kB 9sec 40cyl 2h'
fmt_525_360k:
1715  CD 59 4C      CALL lcd_print  ; print inline media spec string via lcd_print
1718  0C 35 2E 32 35 22 +  DB \f, "5.25\" 360 kB 512 b/s 9 sec. 40 cyl. 2 h.", 0  ; inline spec string: 5.25" 360kB 9 sec 40 cyl
1742  C9            RET  ; return after printing 5.25" 360kB spec

; print media spec line '5.25" 180kB 9sec 40cyl 1h'
fmt_525_180k:
1743  CD 59 4C      CALL lcd_print  ; print inline media spec string via lcd_print
1746  0C 35 2E 32 35 22 +  DB \f, "5.25\" 180 kB 512 b/s 9 sec. 40 cyl. 1 h.", 0  ; inline spec string: 5.25" 180kB 9 sec 40 cyl 1h
1770  C9            RET  ; return after printing 5.25" 180kB spec

; print media spec line '5.25" 320kB 8sec 40cyl 2h'
fmt_525_320k:
1771  CD 59 4C      CALL lcd_print  ; print inline media spec string via lcd_print
1774  0C 35 2E 32 35 22 +  DB \f, "5.25\" 320 kB 512 b/s 8 sec. 40 cyl. 2 h.", 0  ; inline spec string: 5.25" 320kB 8 sec 40 cyl
179E  C9            RET  ; return after printing 5.25" 320kB spec

; print media spec line '5.25" 160kB 8sec 40cyl 1h'
fmt_525_160k:
179F  CD 59 4C      CALL lcd_print  ; print inline media spec string via lcd_print
17A2  0C 35 2E 32 35 22 +  DB \f, "5.25\" 160 kB 512 b/s 8 sec. 40 cyl. 1 h.", 0  ; inline spec string: 5.25" 160kB 8 sec 40 cyl 1h
17CC  C9            RET  ; return after printing 5.25" 160kB spec

; print media spec line '5.25" 720kB 9sec 80cyl 2h'
fmt_525_720k:
17CD  CD 59 4C      CALL lcd_print  ; print inline media spec string via lcd_print
17D0  0C 35 2E 32 35 22 +  DB \f, "5.25\" 720 kB 512 b/s 9 sec. 80 cyl. 2 h.", 0  ; inline spec string: 5.25" 720kB 9 sec 80 cyl
17FA  C9            RET  ; return after printing 5.25" 720kB spec

; print media spec line '5.25" 1.2MB 15sec 80cyl 2h'
fmt_525_12m:
17FB  CD 59 4C      CALL lcd_print  ; print inline media spec string via lcd_print
17FE  0C 35 2E 32 35 22 +  DB \f, "5.25\" 1.2 MB 512 b/s15 sec. 80 cyl. 2 h.", 0  ; inline spec string: 5.25" 1.2MB 15 sec 80 cyl
1828  C9            RET  ; return after printing 5.25" 1.2MB spec

; enter fmt_apply selecting DD density: cyl_head=0, clear format_desc[11] bit7, sync image flag
fmt_apply_dd:
1829  AF            XOR A  ; DD entry: A=0 (cyl_head=0, base slot)

loc_182A:
182A  32 64 31      LD (cyl_head),A  ; store cyl_head = selected slot
182D  DD 21 DD 52   LD IX,format_desc  ; point IX at format_desc for density bit edit
1831  DD CB 0B BE   RES 7,(IX+11)  ; clear format_desc[11] bit7 -> select DD (double density)
1835  3A 37 31      LD A,(unit_sel)  ; load current unit_sel drive-config flags
1838  CB 4F         BIT 1,A  ; test unit_sel bit1 (image-valid-for-density flag)
183A  C4 29 19      CALL NZ,clear_image_present  ; if bit1 set, density changed -> invalidate cached image
183D  CB 8F         RES 1,A  ; clear unit_sel bit1 to mark DD state
183F  18 1F         JR loc_1860  ; jump to shared apply path at loc_1860

; enter fmt_apply selecting HD density: cyl_head=0, set format_desc[11] bit7, sync image flag
fmt_apply_hd:
1841  AF            XOR A  ; HD entry: A=0 (cyl_head=0, base slot)

loc_1842:
1842  32 64 31      LD (cyl_head),A  ; store cyl_head = selected slot
1845  DD 21 DD 52   LD IX,format_desc  ; point IX at format_desc for density bit edit
1849  DD CB 0B FE   SET 7,(IX+11)  ; set format_desc[11] bit7 -> select HD (high density)
184D  3A 37 31      LD A,(unit_sel)  ; load current unit_sel drive-config flags
1850  CB 4F         BIT 1,A  ; test unit_sel bit1 (image-valid-for-density flag)
1852  CC 29 19      CALL Z,clear_image_present  ; if bit1 clear, density changed -> invalidate cached image
1855  CB CF         SET 1,A  ; set unit_sel bit1 to mark HD state
1857  18 07         JR loc_1860  ; jump to shared apply path at loc_1860

; format-apply core: program both FDCs, build format block + sector layout, warn on non-std max cyl, run ops_menu
fmt_apply:
1859  AF            XOR A  ; fmt_apply entry: A=0
185A  32 64 31      LD (cyl_head),A  ; store cyl_head=0 (standard format, no special slot)

loc_185D:
185D  3A 37 31      LD A,(unit_sel)  ; reload current unit_sel drive selection

loc_1860:
1860  21 85 4A      LD HL,fdc_result_buf  ; point HL at fdc_result_buf (setup, overwritten below)
1863  21 DA 4A      LD HL,fdc_param_recs+0x1E  ; point HL at fdc_param_recs+0x1E (setup, overwritten below)
1866  21 DD 52      LD HL,format_desc  ; point HL at format_desc (setup, overwritten below)
1869  21 EB 4A      LD HL,drive_blk_a  ; point HL at drive_blk_a (last pointer setup)
186C  32 37 31      LD (unit_sel),A  ; write selected drive config back to unit_sel
186F  CD 7B 04      CALL fdc_cmd_both_drives  ; issue FDC command to both drive controllers
1872  CD CB 4F      CALL build_format_block  ; build the FDC format parameter block for this media
1875  CD CC 50      CALL layout_sectors  ; compute the per-track sector layout
1878  3A 64 31      LD A,(cyl_head)  ; load selected special-format slot number
187B  FE 04         CP 0x04  ; is this slot 4 (HD special needing DRAM stack-fill)?
187D  28 04         JR Z,loc_1883  ; slot 4 -> special DRAM stack-fill path
187F  FE 0E         CP 0x0E  ; else check slot 14, the other stack-fill special
1881  20 11         JR NZ,loc_1894  ; not 4 or 14 -> skip stack fill

loc_1883:
1883  21 00 00      LD HL,0x0000  ; start block 0 for CHS conversion
1886  CD F2 4F      CALL block_to_chs  ; convert logical block 0 to cylinder/head/sector
1889  EB            EX DE,HL  ; swap CHS result into HL for fill args
188A  47            LD B,A  ; B = cylinder count from conversion
188B  0E 00         LD C,0x00  ; C=0 head/start value
188D  79            LD A,C  ; A = start value (0)
188E  59            LD E,C  ; E = 0
188F  16 1A         LD D,0x1A  ; D = 0x1A (fill parameter / sector count)
1891  CD 1E 48      CALL dram_stack_fill  ; fill DRAM image stack region with this pattern

loc_1894:
1894  DD 7E 0B      LD A,(IX+11)  ; read format_desc[11] flags byte
1897  CB 47         BIT 0,A  ; test bit0 (image-source vs generated layout)
1899  20 0F         JR NZ,loc_18AA  ; if set, copy prebuilt hard-drive block via LDIR path
189B  CD 25 27      CALL drive_block_pos  ; compute drive_block position for eeprom transfer
189E  06 18         LD B,0x18  ; B=0x18 (24-byte block length)
18A0  21 A1 31      LD HL,hrd_hd0  ; HL -> hrd_hd0 source table
18A3  3E 00         LD A,0x00  ; A=0 (read direction / bank select for transfer)
18A5  CD 35 27      CALL eeprom_transfer  ; transfer 24-byte drive block via eeprom_transfer
18A8  18 0C         JR loc_18B6  ; skip the LDIR copy path

loc_18AA:
18AA  CD 07 27      CALL drive_block_ptr  ; get pointer into drive_block for direct copy
18AD  11 A1 31      LD DE,hrd_hd0  ; DE -> hrd_hd0 destination table
18B0  06 00         LD B,0x00  ; B=0 (high byte of length)
18B2  0E 18         LD C,0x18  ; C=0x18 -> copy 24 bytes
18B4  ED B0         LDIR  ; block-copy 24-byte hard-drive descriptor

loc_18B6:
18B6  3A 37 31      LD A,(unit_sel)  ; reload unit_sel drive selection
18B9  21 38 31      LD HL,unit_sel+0x1  ; point HL at previous unit_sel snapshot (unit_sel+1)
18BC  BE            CP (HL)  ; compare current vs previous drive selection
18BD  77            LD (HL),A  ; store current selection as new snapshot
18BE  C4 29 19      CALL NZ,clear_image_present  ; if selection changed, invalidate cached image
18C1  3A 64 31      LD A,(cyl_head)  ; load current special-format slot number
18C4  21 65 31      LD HL,spfmt_num  ; point HL at stored spfmt_num
18C7  BE            CP (HL)  ; compare current vs stored special-format number
18C8  77            LD (HL),A  ; store current special-format number
18C9  C4 29 19      CALL NZ,clear_image_present  ; if it changed, invalidate cached image
18CC  3A 1C 31      LD A,(cfg_flags)  ; load config flags byte
18CF  E6 7F         AND 0x7F  ; mask off bit7, keep max-cyl override bits
18D1  28 2E         JR Z,loc_1901  ; if zero (standard max cyl), skip the warning
18D3  CD 59 4C      CALL lcd_print  ; print the non-standard-max-cylinder warning
18D6  0C 20 20 20 20 57 +  DB \f, "    WARNING !", \r, \n, "non std. max. cyl.", 0  ; inline string: 'WARNING ! non std. max. cyl.'
18F9  3E 03         LD A,0x03  ; A=3 -> beep count/tone
18FB  CD 66 27      CALL beep  ; sound warning beep
18FE  CD A9 03      CALL lcd_home3  ; home LCD cursor to line 3

loc_1901:
1901  21 FC 14      LD HL,ops_menu  ; HL -> ops_menu table
1904  CD 2F 52      CALL menu_run  ; run the operations menu (copy/format/verify)
1907  21 34 31      LD HL,op_word  ; point HL at op_word flags
190A  CB A6         RES 4,(HL)  ; clear op_word bit4 on menu exit
190C  C9            RET  ; return to caller

; pick drive model 1 (unit_sel low bits=01) then run fmt_apply
sel_model_1:
190D  3A 37 31      LD A,(unit_sel)  ; load current unit_sel
1910  E6 FC         AND 0xFC  ; clear low 2 model-select bits
1912  F6 01         OR 0x01  ; set model bits = 01 (drive model 1)
1914  C3 59 18      JP fmt_apply  ; run fmt_apply with model 1 selected

; pick drive model 2 (unit_sel low bits=10) then run fmt_apply
sel_model_2:
1917  3A 37 31      LD A,(unit_sel)  ; load current unit_sel
191A  E6 FC         AND 0xFC  ; clear low 2 model-select bits
191C  F6 02         OR 0x02  ; set model bits = 10 (drive model 2)
191E  C3 59 18      JP fmt_apply  ; run fmt_apply with model 2 selected

; pick drive model 0/3 (clear unit_sel low bits) then run fmt_apply
sel_model_3:
1921  3A 37 31      LD A,(unit_sel)  ; load current unit_sel
1924  E6 FC         AND 0xFC  ; clear low 2 model-select bits (model 0/3)
1926  C3 59 18      JP fmt_apply  ; run fmt_apply with default model

; invalidate cached RAM disk image by zeroing image_present (AF preserved)
clear_image_present:
1929  F5            PUSH AF  ; preserve A across image-flag clear
192A  AF            XOR A  ; A=0
192B  32 C8 52      LD (image_present),A  ; zero image_present -> mark RAM image invalid
192E  F1            POP AF  ; restore A
192F  C9            RET  ; return to caller

; draw 'Insert model' prompt; decode model-ID sense (0x52E8) to 528/526/325-400 handler else Not available
show_insert_model:
1930  CD 59 4C      CALL lcd_print  ; print 'Insert model ' prompt on LCD
1933  1B C0 49 6E 73 65 +  DB ESC(0xC0), "Insert model ", 0  ; inline string: cursor-to-col ESC + 'Insert model '
1943  3A E8 52      LD A,(format_desc+0xB)  ; load model-ID sense byte format_desc[0xB]
1946  E6 C8         AND 0xC8  ; isolate model-ID bits (0xC8) for drive-type decode
1948  FE 08         CP 0x08  ; 0x08 pattern -> 528-400 drive model
194A  28 21         JR Z,loc_196D  ; 0x08 -> 528-400 model handler
194C  FE C8         CP 0xC8  ; 0xC8 pattern -> 526-400 drive model
194E  28 2E         JR Z,loc_197E  ; 0xC8 -> 526-400 model handler
1950  E6 48         AND 0x48  ; re-isolate bits 0x48 for the third model test
1952  FE 40         CP 0x40  ; 0x40 pattern -> 325-400 drive model
1954  28 39         JR Z,loc_198F  ; 0x40 -> 325-400 model handler

; draw 'Not available' on LCD line 2 and home cursor
show_not_available:
1956  CD 59 4C      CALL lcd_print  ; print 'Not available' on LCD line 2
1959  1B C0 4E 6F 74 20 +  DB ESC(0xC0), "Not available", 0  ; inline string: cursor-to-col ESC + 'Not available'
1969  CD A9 03      CALL lcd_home3  ; home LCD cursor to line 3
196C  C9            RET  ; return to caller

loc_196D:
196D  CD 59 4C      CALL lcd_print  ; print '528-400' model name
1970  35 32 38 2D 34 30 +  DB "528-400", 0  ; inline string: '528-400'
1978  3E 00         LD A,0x00  ; A=0 (model index 0)
197A  06 14         LD B,0x14  ; B=0x14 (cyl_head value for this model)
197C  18 25         JR loc_19A3  ; jump to common model-setup tail

loc_197E:
197E  CD 59 4C      CALL lcd_print  ; print '526-400' model name
1981  35 32 36 2D 34 30 +  DB "526-400", 0  ; inline string: '526-400'
1989  3E 01         LD A,0x01  ; A=1 (model index 1)
198B  06 13         LD B,0x13  ; B=0x13 (cyl_head value for this model)
198D  18 14         JR loc_19A3  ; jump to common model-setup tail

loc_198F:
198F  CD 59 4C      CALL lcd_print  ; print '325-400' model name
1992  33 32 35 2D 34 30 +  DB "325-400", 0  ; inline string: '325-400'
199A  21 E8 52      LD HL,format_desc+0xB  ; point HL at format_desc[0xB] ID byte
199D  CB BE         RES 7,(HL)  ; clear bit7 -> mark this model as DD/special
199F  3E 02         LD A,0x02  ; A=2 (model index 2)
19A1  06 12         LD B,0x12  ; B=0x12 (cyl_head value for this model)

loc_19A3:
19A3  32 78 31      LD (hrd_model_idx),A  ; store selected hard-drive model index
19A6  78            LD A,B  ; A = per-model cyl_head value
19A7  32 64 31      LD (cyl_head),A  ; store cyl_head for this hard-drive model
19AA  3E 01         LD A,0x01  ; A=1 (key-wait / prompt mode)
19AC  CD 89 4D      CALL get_key  ; wait for operator key confirmation
19AF  CD 4F 07      CALL set_drive_cfg  ; apply drive configuration for selected model
19B2  CD B4 11      CALL read_source  ; read the source disk into RAM image
19B5  C0            RET NZ  ; abort if source read failed (NZ)
19B6  CD E7 51      CALL fdc_build_unit_sel  ; build unit_sel value from drive config
19B9  32 37 31      LD (unit_sel),A  ; store computed unit_sel
19BC  CD 7B 04      CALL fdc_cmd_both_drives  ; issue FDC command to both controllers
19BF  CD A9 03      CALL lcd_home3  ; home LCD cursor to line 3
19C2  CD 09 07      CALL motor_ready_wait  ; wait for drive motors to spin up ready
19C5  CD 57 07      CALL drive_cfg_latch  ; latch drive config via 0x9C control latch
19C8  21 22 15      LD HL,hrd_test_menu  ; HL -> hard-drive test menu
19CB  CD 2F 52      CALL menu_run  ; run the hard-drive test menu
19CE  CD 2D 11      CALL al_cmd_reject  ; send autoloader command reject/ack
19D1  C9            RET  ; return to caller

; draw 'Read source disk'; show 'data image present' or 'insert source disk' per image_present
show_read_source:
19D2  CD 59 4C      CALL lcd_print  ; print 'Read source disk' header
19D5  0C 52 65 61 64 20 +  DB \f, "Read source disk", 0  ; inline string: form-feed + 'Read source disk'
19E7  3A C8 52      LD A,(image_present)  ; load image_present flag
19EA  B7            OR A  ; test if a RAM image is already cached
19EB  28 1C         JR Z,loc_1A09  ; if none, show 'insert source disk' prompt
19ED  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 before status message
19F0  CD 59 4C      CALL lcd_print  ; print status message
19F3  1B C0 64 61 74 61 +  DB ESC(0xC0), "data image present", 0  ; inline string: cursor-to-col ESC + 'data image present'
1A08  C9            RET  ; return after showing 'data image present'

loc_1A09:
1A09  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 for prompt
1A0C  CD 59 4C      CALL lcd_print  ; print the inline string that follows
1A0F  1B C0 69 6E 73 65 +  DB ESC(0xC0), "insert source disk", 0  ; inline LCD string: cursor to line2, 'insert source disk'
1A24  C9            RET  ; return to caller

; print 'Format Write Verify' copy-mode menu label
show_copy_fwv:
1A25  CD 59 4C      CALL lcd_print  ; print the inline menu-label string
1A28  0C 46 6F 72 6D 61 +  DB \f, "Format Write Verify", \n, \r, 0  ; inline string: form-feed + 'Format Write Verify' + CRLF
1A3F  C9            RET  ; return to caller

; print 'Write and verify' copy-mode menu label
show_copy_wv:
1A40  CD 59 4C      CALL lcd_print  ; print the inline menu-label string
1A43  0C 57 72 69 74 65 +  DB \f, "Write and verify", \n, \r, 0  ; inline string: 'Write and verify' + CRLF
1A57  C9            RET  ; return to caller

; print 'CRC check' copy-mode menu label
show_copy_crc:
1A58  CD 59 4C      CALL lcd_print  ; print the inline menu-label string
1A5B  0C 43 52 43 20 63 +  DB \f, "CRC check", \n, \r, 0  ; inline string: 'CRC check' + CRLF
1A68  C9            RET  ; return to caller

; print 'Format and verify' copy-mode menu label
show_copy_fv:
1A69  CD 59 4C      CALL lcd_print  ; print the inline menu-label string
1A6C  0C 46 6F 72 6D 61 +  DB \f, "Format and verify", \n, \r, 0  ; inline string: 'Format and verify' + CRLF
1A81  C9            RET  ; return to caller

; print 'Write disk' copy-mode menu label
show_copy_wd:
1A82  CD 59 4C      CALL lcd_print  ; print the inline menu-label string
1A85  0C 57 72 69 74 65 +  DB \f, "Write disk", \n, \r, 0  ; inline string: 'Write disk' + CRLF
1A93  C9            RET  ; return to caller

; force error-recovery mode (0x314A=3), run duplication then image-compare pass, restore, set image_present on success
set_error_recovery:
1A94  21 4A 31      LD HL,err_recovery  ; point at error-recovery mode flag
1A97  7E            LD A,(HL)  ; save current err_recovery value
1A98  36 03         LD (HL),0x03  ; force error-recovery mode = 3
1A9A  23            INC HL  ; advance to saved-value slot
1A9B  77            LD (HL),A  ; stash previous mode for later restore
1A9C  3E 00         LD A,0x00  ; A=0: clears image_present/run_status and becomes op_word=0 for the run
1A9E  21 01 00      LD HL,0x0001  ; run_count = 1 (single pass)
1AA1  32 C8 52      LD (image_present),A  ; clear image_present before the run
1AA4  32 4E 31      LD (run_status),A  ; clear run_status
1AA7  CD ED 1A      CALL start_run_op  ; run the duplication pass
1AAA  AF            XOR A  ; A=0 to clear image_present after the run
1AAB  32 C8 52      LD (image_present),A  ; clear image_present again
1AAE  3A 34 31      LD A,(op_word)  ; read op result word
1AB1  E6 E0         AND 0xE0  ; isolate error bits [7:5]
1AB3  20 29         JR NZ,loc_1ADE  ; skip compare pass if the run had errors
1AB5  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
1AB8  CD 59 4C      CALL lcd_print  ; print the inline status string
1ABB  1B C0 69 6D 61 67 +  DB ESC(0xC0), "image comparing", 0  ; inline LCD string: cursor to line2, 'image comparing'
1ACD  3E 08         LD A,0x08  ; run_status = 8 (image-compare phase)
1ACF  32 4E 31      LD (run_status),A  ; store run_status
1AD2  AF            XOR A  ; A=0 -> op_word=0 selects the compare pass
1AD3  21 01 00      LD HL,0x0001  ; run_count = 1
1AD6  CD ED 1A      CALL start_run_op  ; run the image-compare pass
1AD9  3A 34 31      LD A,(op_word)  ; read op result word
1ADC  E6 E0         AND 0xE0  ; isolate error bits [7:5]

loc_1ADE:
1ADE  F5            PUSH AF  ; save error flags across the restore
1ADF  21 4B 31      LD HL,err_recovery+0x1  ; point at stashed previous mode
1AE2  7E            LD A,(HL)  ; load saved mode value
1AE3  2B            DEC HL  ; back to err_recovery slot
1AE4  77            LD (HL),A  ; restore original err_recovery mode
1AE5  F1            POP AF  ; recover error flags
1AE6  C0            RET NZ  ; bail (image stays invalid) if any errors
1AE7  3E 01         LD A,0x01  ; A = 1
1AE9  32 C8 52      LD (image_present),A  ; mark image_present on clean success
1AEC  C9            RET  ; return to caller

; set op_word=A and run_count=HL, then enter dup_engine_loop to run the duplication op
start_run_op:
1AED  32 34 31      LD (op_word),A  ; set requested op_word
1AF0  22 3D 31      LD (run_count),HL  ; set run/copy count
1AF3  C3 9E 1C      JP loc_1C9E  ; enter the dup engine

; start Format-Write-Verify copy (op_word=1); if no image show 'data image missing', else prompt copy count and run
start_copy_fwv:
1AF6  3E 01         LD A,0x01  ; op_word = 1 (Format-Write-Verify)

loc_1AF8:
1AF8  32 34 31      LD (op_word),A  ; store selected op_word
1AFB  21 00 00      LD HL,0x0000  ; HL=0 -> run_count=0 (prompt fills it in later)
1AFE  22 3D 31      LD (run_count),HL  ; clear run_count
1B01  3A C8 52      LD A,(image_present)  ; check whether an image is loaded
1B04  B7            OR A  ; test image_present == 0
1B05  20 2B         JR NZ,loc_1B32  ; proceed if an image is present
1B07  CD 59 4C      CALL lcd_print  ; print the inline error string
1B0A  0C 4E 6F 74 20 61 +  DB \f, "Not available", \r, \n, "data image missing", 0  ; inline string: 'Not available / data image missing'
1B2D  3E 01         LD A,0x01  ; return code 1 (error)
1B2F  C3 89 4D      JP get_key  ; wait for key then return

loc_1B32:
1B32  2A 41 31      LD HL,(copy_count)  ; load saved copy count
1B35  22 3D 31      LD (run_count),HL  ; seed run_count with it
1B38  CD 93 04      CALL edit_num_copies  ; prompt user for number of copies
1B3B  C8            RET Z  ; abort if user cancelled
1B3C  21 67 31      LD HL,hrd_desc_tbl  ; point at hardware descriptor table
1B3F  CB 4E         BIT 1,(HL)  ; test format/serial-numbering flag bit 1
1B41  CA 88 07      JP Z,dup_engine_loop  ; run directly if serial numbering not enabled
1B44  3A 34 31      LD A,(op_word)  ; read op_word
1B47  E6 0F         AND 0x0F  ; isolate mode nibble
1B49  FE 03         CP 0x03  ; compare mode vs 3 (CRC)
1B4B  CA 88 07      JP Z,dup_engine_loop  ; skip serial setup, run directly for CRC mode
1B4E  FE 08         CP 0x08  ; compare mode vs 8 (compare)
1B50  CA 88 07      JP Z,dup_engine_loop  ; skip serial setup, run directly for compare mode
1B53  CD 59 4C      CALL lcd_print  ; print the inline prompt string
1B56  0C 49 6E 69 74 69 +  DB \f, "Initial serial Nr.", 0  ; inline string: 'Initial serial Nr.'
1B6A  2A 68 31      LD HL,(serial_num_lo)  ; load current serial number
1B6D  22 43 31      LD (edit_value),HL  ; seed edit field with it
1B70  2A 6A 31      LD HL,(serial_num_hi)  ; load serial number high word
1B73  22 45 31      LD (edit_value_hi),HL  ; seed hi edit field with it
1B76  06 08         LD B,0x08  ; 8-digit edit field
1B78  3E 0A         LD A,0x0A  ; field type/base-10 code
1B7A  CD C3 04      CALL edit_num_field  ; edit the initial serial number
1B7D  C8            RET Z  ; abort if user cancelled
1B7E  2A 43 31      LD HL,(edit_value)  ; read edited value
1B81  22 68 31      LD (serial_num_lo),HL  ; store new serial number
1B84  2A 45 31      LD HL,(edit_value_hi)  ; read edited increment
1B87  22 6A 31      LD (serial_num_hi),HL  ; store serial number high word
1B8A  CD 59 4C      CALL lcd_print  ; print the inline prompt string
1B8D  0C 49 6E 63 72 65 +  DB \f, "Increment", 0  ; inline string: 'Increment'
1B98  3A 6C 31      LD A,(serial_incr)  ; load the current increment step
1B9B  6F            LD L,A  ; increment -> L (low byte of edit value)
1B9C  26 00         LD H,0x00  ; zero-extend into HL
1B9E  22 43 31      LD (edit_value),HL  ; seed edit field
1BA1  6C            LD L,H  ; L = 0
1BA2  22 45 31      LD (edit_value_hi),HL  ; clear hi edit field
1BA5  06 02         LD B,0x02  ; 2-digit edit field
1BA7  3E 10         LD A,0x10  ; field type code
1BA9  CD C3 04      CALL edit_num_field  ; edit cylinder increment
1BAC  C8            RET Z  ; abort if user cancelled
1BAD  3A 43 31      LD A,(edit_value)  ; read edited value
1BB0  32 6C 31      LD (serial_incr),A  ; store the per-copy increment step

loc_1BB3:
1BB3  CD 59 4C      CALL lcd_print  ; print the inline prompt string
1BB6  0C 43 79 6C 69 6E +  DB \f, "Cylinder", 0  ; inline string: 'Cylinder'
1BC0  3A 6D 31      LD A,(serial_cyl)  ; load the serial target cylinder
1BC3  6F            LD L,A  ; cylinder -> L (low byte of edit value)
1BC4  26 00         LD H,0x00  ; zero-extend into HL
1BC6  22 43 31      LD (edit_value),HL  ; seed edit field
1BC9  6C            LD L,H  ; L = 0
1BCA  22 45 31      LD (edit_value_hi),HL  ; clear hi edit field
1BCD  06 02         LD B,0x02  ; 2-digit edit field
1BCF  3E 10         LD A,0x10  ; field type code
1BD1  CD C3 04      CALL edit_num_field  ; edit head value
1BD4  C8            RET Z  ; abort if user cancelled
1BD5  21 DD 52      LD HL,format_desc  ; point at format geometry descriptor
1BD8  CD A5 1C      CALL check_cyl_limit  ; validate value against cylinder/geometry limit
1BDB  38 D6         JR C,loc_1BB3  ; re-prompt if out of range
1BDD  32 6D 31      LD (serial_cyl),A  ; store serialization target cylinder

loc_1BE0:
1BE0  CD 59 4C      CALL lcd_print  ; print the inline prompt string
1BE3  0C 48 65 61 64 00  DB \f, "Head", 0  ; inline string: 'Head'
1BE9  3A 6E 31      LD A,(serial_head)  ; load the serial target head
1BEC  6F            LD L,A  ; head -> L (low byte of edit value)
1BED  26 00         LD H,0x00  ; zero-extend into HL
1BEF  22 43 31      LD (edit_value),HL  ; seed edit field
1BF2  6C            LD L,H  ; L = 0
1BF3  22 45 31      LD (edit_value_hi),HL  ; clear hi edit field
1BF6  06 01         LD B,0x01  ; 1-digit edit field
1BF8  3E 11         LD A,0x11  ; field type code
1BFA  CD C3 04      CALL edit_num_field  ; edit sector value
1BFD  C8            RET Z  ; abort if user cancelled
1BFE  21 DE 52      LD HL,format_desc+0x1  ; point at sector limit in format descriptor
1C01  CD A5 1C      CALL check_cyl_limit  ; validate against limit
1C04  38 DA         JR C,loc_1BE0  ; re-prompt if out of range
1C06  32 6E 31      LD (serial_head),A  ; store serialization target head

loc_1C09:
1C09  CD 59 4C      CALL lcd_print  ; print the inline prompt string
1C0C  0C 53 65 63 74 6F +  DB \f, "Sector", 0  ; inline string: 'Sector'
1C14  3A 6F 31      LD A,(serial_sector)  ; load the serial target sector
1C17  6F            LD L,A  ; sector -> L (low byte of edit value)
1C18  26 00         LD H,0x00  ; zero-extend into HL
1C1A  22 43 31      LD (edit_value),HL  ; seed edit field
1C1D  6C            LD L,H  ; L = 0
1C1E  22 45 31      LD (edit_value_hi),HL  ; clear hi edit field
1C21  06 02         LD B,0x02  ; 2-digit edit field
1C23  3E 10         LD A,0x10  ; field type code
1C25  CD C3 04      CALL edit_num_field  ; edit offset value
1C28  C8            RET Z  ; abort if user cancelled
1C29  21 DF 52      LD HL,format_desc+0x2  ; point at offset limit in format descriptor
1C2C  34            INC (HL)  ; bump limit for inclusive range check
1C2D  CD A5 1C      CALL check_cyl_limit  ; validate against limit
1C30  35            DEC (HL)  ; restore limit
1C31  38 D6         JR C,loc_1C09  ; re-prompt if out of range
1C33  A7            AND A  ; test value == 0
1C34  CC AC 1C      CALL Z,show_out_of_range  ; reject a zero value as out of range
1C37  38 D0         JR C,loc_1C09  ; re-prompt if rejected
1C39  32 6F 31      LD (serial_sector),A  ; store serialization target sector

loc_1C3C:
1C3C  CD 59 4C      CALL lcd_print  ; print the inline prompt string
1C3F  0C 4F 66 66 73 65 +  DB \f, "Offset", 0  ; inline string: 'Offset'
1C47  2A 70 31      LD HL,(serial_offset)  ; load the byte offset within the sector
1C4A  22 43 31      LD (edit_value),HL  ; seed edit field
1C4D  21 00 00      LD HL,0x0000  ; HL=0 for the hi edit field
1C50  22 45 31      LD (edit_value_hi),HL  ; clear hi edit field
1C53  06 04         LD B,0x04  ; 4-digit edit field
1C55  3E 0E         LD A,0x0E  ; field type code
1C57  CD C3 04      CALL edit_num_field  ; edit position value
1C5A  C8            RET Z  ; abort if user cancelled
1C5B  2A 43 31      LD HL,(edit_value)  ; read edited value
1C5E  ED 5B E0 52   LD DE,(format_desc+0x3)  ; load total track/sector count
1C62  1B            DEC DE  ; limit -= 1
1C63  1B            DEC DE  ; limit -= 1
1C64  1B            DEC DE  ; limit -= 1
1C65  1B            DEC DE  ; DE = limit - 4
1C66  A7            AND A  ; clear carry for compare
1C67  E5            PUSH HL  ; save value
1C68  ED 52         SBC HL,DE  ; compare position vs limit
1C6A  E1            POP HL  ; restore value
1C6B  38 05         JR C,loc_1C72  ; accept if below limit
1C6D  CD AC 1C      CALL show_out_of_range  ; show out-of-range message
1C70  18 CA         JR loc_1C3C  ; re-prompt for position

loc_1C72:
1C72  22 70 31      LD (serial_offset),HL  ; store serialization byte offset
1C75  ED 4B 6D 31   LD BC,(serial_cyl)  ; load head/sector word (C=head, B=sector)
1C79  79            LD A,C  ; begin B<->C swap via A (A = serial cylinder)
1C7A  48            LD C,B  ; C = serial head
1C7B  47            LD B,A  ; B = serial cylinder (swap complete)
1C7C  CB 09         RRC C  ; RRC C: rotate the head bit (C = head after swap)
1C7E  3A 6F 31      LD A,(serial_sector)  ; load the serial target sector
1C81  CD A5 2B      CALL track_buf_ptr  ; compute track buffer pointer
1C84  32 72 31      LD (serial_bank),A  ; store the serial-stamp image bank
1C87  ED 5B 70 31   LD DE,(serial_offset)  ; load the byte offset
1C8B  19            ADD HL,DE  ; add position offset to pointer
1C8C  22 73 31      LD (serial_addr),HL  ; store serial write address
1C8F  2A 70 31      LD HL,(serial_offset)  ; reload the byte offset
1C92  3A 6F 31      LD A,(serial_sector)  ; load the serial target sector
1C95  CD AB 2B      CALL track_ptr_scale  ; scale pointer by offset
1C98  22 75 31      LD (serial_ptr),HL  ; store scaled serial pointer
1C9B  CD A1 1C      CALL jump_phase_handler  ; dispatch to the run-phase handler

loc_1C9E:
1C9E  C3 88 07      JP dup_engine_loop  ; resume the main duplication engine loop

; indirect jump through phase_handler vector to the current duplication-phase routine
jump_phase_handler:
1CA1  2A 31 31      LD HL,(phase_handler)  ; load current duplication-phase handler pointer
1CA4  E9            JP (HL)  ; dispatch to the phase routine

; test requested cyl in HL against max-cyl 0x3143; returns in-range via M flag (no carry if OK)
check_cyl_limit:
1CA5  3A 43 31      LD A,(edit_value)  ; fetch operator-entered edit value to validate
1CA8  BE            CP (HL)  ; compare edit value against max-cyl limit at (HL)
1CA9  37            SCF  ; set carry (first half of clear-carry idiom)
1CAA  3F            CCF  ; complement to clear carry = accept; M flag from CP gates in-range
1CAB  F8            RET M  ; return accepting the value if within range

; draw 'Out of range' on LCD line 2, home cursor, set carry to reject the value
show_out_of_range:
1CAC  E5            PUSH HL  ; save HL across the LCD update
1CAD  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 for the error message
1CB0  CD 59 4C      CALL lcd_print  ; print the following inline string to the LCD
1CB3  1B C0 4F 75 74 20 +  DB ESC(0xC0), "Out of range", 0  ; LCD string: cursor line2, 'Out of range'
1CC2  CD A9 03      CALL lcd_home3  ; reposition/home the LCD cursor
1CC5  E1            POP HL  ; restore HL
1CC6  37            SCF  ; set carry to signal value rejected
1CC7  C9            RET  ; return to caller

; start Write-and-Verify copy (op_word=2) via the shared start_copy_fwv path
start_copy_wv:
1CC8  3E 02         LD A,0x02  ; op_word=2: Write-and-Verify copy mode
1CCA  C3 F8 1A      JP loc_1AF8  ; join the shared copy-start path

; start Format-only copy (op_word=3), jump to copy-count prompt and run
start_copy_format:
1CCD  3E 03         LD A,0x03  ; op_word=3: Format-only copy mode

loc_1CCF:
1CCF  32 34 31      LD (op_word),A  ; store the selected operation word
1CD2  21 00 00      LD HL,0x0000  ; clear run counter accumulator
1CD5  22 3D 31      LD (run_count),HL  ; reset run_count to 0
1CD8  C3 32 1B      JP loc_1B32  ; jump to the copy-count prompt and run

; FORMAT: if cyl_head!=0 skip; else build blank FAT12 image in DRAM bank 0xFE from ROM template, stamp 0x55AA, zero-fill+FAT-init every track
start_copy_fmtverify:
1CDB  3A 64 31      LD A,(cyl_head)  ; read cyl/head progress marker
1CDE  B7            OR A  ; test whether format already started
1CDF  C2 8D 1D      JP NZ,loc_1D8D  ; if nonzero skip template build, go format tracks

; FORMAT: build FAT12 boot sector from ROM template, stamp 0x55AA, format tracks
format_track:
1CE2  AF            XOR A  ; clear A to zero the image-present flag before formatting
1CE3  32 C8 52      LD (image_present),A  ; mark image buffer as not-yet-present
1CE6  DD 21 DD 52   LD IX,format_desc  ; point IX at the format geometry descriptor
1CEA  3E FE         LD A,0xFE  ; select DRAM image bank 0xFE (scratch/format bank)
1CEC  D3 B0         OUT (0xB0),A  ; dram_bank — switch banked image window to bank 0xFE
1CEE  DD 4E 07      LD C,(IX+7)  ; low byte of image byte-count from descriptor+7
1CF1  DD 46 08      LD B,(IX+8)  ; high byte of image byte-count from descriptor+8
1CF4  0B            DEC BC  ; BC = count-1 for the fill LDIR
1CF5  21 00 80      LD HL,image_buf  ; HL = start of image buffer
1CF8  11 01 80      LD DE,image_buf+0x1  ; DE = image_buf+1 (LDIR propagate target)
1CFB  36 00         LD (HL),0x00  ; seed first byte with 0x00
1CFD  ED B0         LDIR  ; zero-fill the entire image buffer
1CFF  21 05 33      LD HL,fat12_template  ; source = ROM FAT12 boot-sector template
1D02  11 00 80      LD DE,image_buf  ; dest = image buffer start
1D05  01 0B 00      LD BC,0x000B  ; copy 0x0B bytes (OEM/jump area of boot sector)
1D08  ED B0         LDIR  ; write boot-sector prefix into image
1D0A  11 2B 80      LD DE,image_buf+0x2B  ; dest = image_buf+0x2B
1D0D  01 13 00      LD BC,0x0013  ; copy 0x13 bytes (volume label/fs-type field)
1D10  ED B0         LDIR  ; write into boot sector
1D12  11 50 80      LD DE,image_buf+0x50  ; dest = image_buf+0x50
1D15  01 2B 00      LD BC,0x002B  ; copy 0x2B bytes (boot code stub)
1D18  ED B0         LDIR  ; write remaining template block
1D1A  21 55 AA      LD HL,0xAA55  ; 0xAA55 boot signature
1D1D  22 FE 81      LD (image_buf+0x1FE),HL  ; stamp 55AA at offset 0x1FE of the boot sector
1D20  CD 83 2B      CALL fdd_geom_index  ; compute FDD geometry index for current format
1D23  0E 00         LD C,0x00  ; C=0 high part of multiplier
1D25  11 13 00      LD DE,0x0013  ; DE=0x13 (BPB record length) multiplicand
1D28  CD 05 4F      CALL mul16  ; 16-bit multiply to offset into geometry table
1D2B  11 6D 32      LD DE,cycle_cnt_hi+0x2  ; DE = base of stored geometry BPB entries
1D2E  19            ADD HL,DE  ; HL = pointer to this format's BPB record
1D2F  E5            PUSH HL  ; save that BPB pointer for later
1D30  11 0B 80      LD DE,image_buf+0xB  ; dest = image_buf+0xB (BPB field in boot sector)
1D33  01 13 00      LD BC,0x0013  ; copy 0x13-byte BPB record
1D36  ED B0         LDIR  ; install BPB into the boot sector
1D38  DD E1         POP IX  ; recover BPB pointer into IX
1D3A  DD 7E 06      LD A,(IX+6)  ; load byte at BPB+6 (reserved/sectors field)
1D3D  07            RLCA  ; build track count: (IX+6)<<4, rotate step 1/4
1D3E  07            RLCA  ; (IX+6)<<4, rotate step 2/4
1D3F  07            RLCA  ; (IX+6)<<4, rotate step 3/4
1D40  07            RLCA  ; (IX+6)<<4 done: nibble now in high 4 bits (x16)
1D41  DD 46 0B      LD B,(IX+11)  ; load BPB+11 (heads/track-related count)
1D44  CB 20         SLA B  ; double it
1D46  80            ADD A,B  ; combine into total-track count
1D47  47            LD B,A  ; B = format track loop counter
1D48  DD 7E 03      LD A,(IX+3)  ; A = starting track number from BPB+3

loc_1D4B:
1D4B  C5            PUSH BC  ; save track loop counter
1D4C  F5            PUSH AF  ; save current track number
1D4D  CD B7 2B      CALL geom_sector_calc  ; compute this track's sector geometry
1D50  CD A5 2B      CALL track_buf_ptr  ; get DRAM bank + buffer pointer for the track
1D53  E5            PUSH HL  ; point DE at the sector buffer (copy HL)
1D54  D1            POP DE  ; DE = sector fill target
1D55  D3 B0         OUT (0xB0),A  ; dram_bank — select the track's DRAM image bank
1D57  13            INC DE  ; advance DE past first byte for propagate
1D58  01 FF 01      LD BC,0x01FF  ; BC=0x1FF: fill rest of 512-byte sector
1D5B  36 00         LD (HL),0x00  ; seed sector with 0x00
1D5D  ED B0         LDIR  ; zero-fill the track/sector buffer
1D5F  F1            POP AF  ; restore current track number
1D60  3C            INC A  ; advance to next track
1D61  C1            POP BC  ; restore track loop counter
1D62  10 E7         DJNZ loc_1D4B  ; loop over all tracks to blank them
1D64  01 00 00      LD BC,0x0000  ; BC=0: track 0 for FAT setup
1D67  3E 02         LD A,0x02  ; A=2: FAT-region sector index
1D69  CD A5 2B      CALL track_buf_ptr  ; get DRAM bank + pointer for the FAT sector
1D6C  D3 B0         OUT (0xB0),A  ; dram_bank — select that DRAM bank
1D6E  DD 7E 0A      LD A,(IX+10)  ; media descriptor byte from BPB+10
1D71  77            LD (HL),A  ; write FAT[0] = media descriptor
1D72  23            INC HL  ; advance to FAT[1]
1D73  36 FF         LD (HL),0xFF  ; write FAT12 reserved byte 0xFF
1D75  23            INC HL  ; advance to FAT[2]
1D76  36 FF         LD (HL),0xFF  ; write FAT12 reserved byte 0xFF (end of FAT id)
1D78  DD 7E 0B      LD A,(IX+11)  ; sectors-per-FAT from BPB+11
1D7B  3C            INC A  ; +1 (skip to second FAT copy)
1D7C  3C            INC A  ; +2 to index the second FAT copy
1D7D  01 00 00      LD BC,0x0000  ; BC=0: track 0 again
1D80  CD A5 2B      CALL track_buf_ptr  ; get bank + pointer for the second FAT sector
1D83  DD 7E 0A      LD A,(IX+10)  ; media descriptor byte from BPB+10
1D86  77            LD (HL),A  ; write FAT[0] of second FAT copy
1D87  23            INC HL  ; advance to FAT[1] of second copy
1D88  36 FF         LD (HL),0xFF  ; write 0xFF reserved byte
1D8A  23            INC HL  ; advance to FAT[2] of second copy
1D8B  36 FF         LD (HL),0xFF  ; write 0xFF reserved byte (finish FAT init)

loc_1D8D:
1D8D  3E 04         LD A,0x04  ; A=4: proceed with the format run mode
1D8F  C3 CF 1C      JP loc_1CCF  ; store op_word and start the run

; start a 'Copy: write' run (start_run_op with mode 6)
start_copy_write:
1D92  3E 06         LD A,0x06  ; op_word=6: 'Copy: write' run mode
1D94  C3 F8 1A      JP loc_1AF8  ; start the run via shared path

; draw the 'Bit per bit verify' status line
show_copy_bitverify:
1D97  CD 59 4C      CALL lcd_print  ; print the following status string
1D9A  0C 42 69 74 20 70 +  DB \f, "Bit per bit verify", 0  ; LCD string: clear-screen, 'Bit per bit verify'
1DAE  C9            RET  ; return

; start a 'Copy: verify' run (start_run_op with mode 8)
start_copy_verify:
1DAF  3E 08         LD A,0x08  ; op_word=8: 'Copy: verify' run mode
1DB1  C3 F8 1A      JP loc_1AF8  ; start the run via shared path

; draw the 'Cleaning FDD' status line
show_clean_fdd:
1DB4  CD 59 4C      CALL lcd_print  ; print the following status string
1DB7  0C 43 6C 65 61 6E +  DB \f, "Cleaning FDD", 0  ; LCD string: clear-screen, 'Cleaning FDD'
1DC5  C9            RET  ; return

; if autoloader disk present launch run op 9, else fall through to show_abort prompt
abort_check:
1DC6  CD AD 11      CALL al_insert_disk  ; check whether autoloader disk is present
1DC9  28 1D         JR Z,loc_1DE8  ; if present, branch to launch run op 9

; show 'Abort' on line2, beep once, reset LCD cursor; returns fmt_mode
show_abort:
1DCB  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 for the abort prompt
1DCE  CD 59 4C      CALL lcd_print  ; print the following string
1DD1  1B C0 41 62 6F 72 +  DB ESC(0xC0), "Abort", 0  ; LCD string: cursor line2, 'Abort'
1DD9  3E 01         LD A,0x01  ; A=1: single beep
1DDB  CD 66 27      CALL beep  ; sound the beep
1DDE  21 00 00      LD HL,0x0000  ; HL=0: home cursor position
1DE1  CD 22 4C      CALL lcd_setpos  ; set LCD cursor to 0,0
1DE4  3A 4C 31      LD A,(fmt_mode)  ; return current fmt_mode to caller
1DE7  C9            RET  ; return

loc_1DE8:
1DE8  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
1DEB  21 0A 00      LD HL,0x000A  ; HL=0x0A run parameter
1DEE  3E 09         LD A,0x09  ; A=9: autoloader run op
1DF0  C3 ED 1A      JP start_run_op  ; start the run operation

; read 4-byte host command packet (opcode in D)
host_read_packet:
1DF3  CD 01 1E      CALL host_rx_word  ; read little-endian word (fills op count) from host
1DF6  C0            RET NZ  ; abort on rx error
1DF7  CD AD 4E      CALL host_rx  ; receive next command byte from host
1DFA  68            LD L,B  ; store into L (address low)
1DFB  C0            RET NZ  ; abort on rx error
1DFC  CD AD 4E      CALL host_rx  ; receive next command byte
1DFF  60            LD H,B  ; store into H (address high)
1E00  C9            RET  ; return with 4-byte packet in D/HL

; read a little-endian 16-bit word from host SIO into E,D (abort on rx error)
host_rx_word:
1E01  CD AD 4E      CALL host_rx  ; receive a byte from host SIO
1E04  58            LD E,B  ; low byte into E
1E05  C0            RET NZ  ; abort on rx error
1E06  CD AD 4E      CALL host_rx  ; receive second byte
1E09  50            LD D,B  ; high byte into D
1E0A  C9            RET  ; return word in DE

; host remote-control server dispatcher (opcode table)
host_dispatch:
1E0B  3E 01         LD A,0x01  ; A=1: enter host remote-control mode
1E0D  32 61 31      LD (host_mode),A  ; set host_mode flag active
1E10  18 19         JR loc_1E2B  ; jump into the command wait loop

loc_1E12:
1E12  B7            OR A  ; test error/retry code
1E13  28 07         JR Z,loc_1E1C  ; if zero, show idle dot animation
1E15  06 45         LD B,0x45  ; B=0x45 'E' NAK/error reply byte
1E17  CD 9D 4E      CALL host_tx  ; send error response to host
1E1A  18 EF         JR host_dispatch  ; restart the dispatcher

loc_1E1C:
1E1C  CD 59 4C      CALL lcd_print  ; print the following idle-indicator string
1E1F  1B 93 2E 00   DB ESC(0x93), ".", 0  ; LCD string: reposition + '.' idle marker
1E23  3A 21 1E      LD A,(loc_1E1C+0x5)  ; load the '.'-char cell to toggle it
1E26  EE 0F         XOR 0x0F  ; flip low nibble: '.' (0x2E) <-> '!' (0x21) blink
1E28  32 21 1E      LD (loc_1E1C+0x5),A  ; store the toggled char back (self-modifying)

loc_1E2B:
1E2B  CD F3 1D      CALL host_read_packet  ; read a 4-byte host command packet
1E2E  20 E2         JR NZ,loc_1E12  ; on rx error, send NAK and retry
1E30  7A            LD A,D  ; A = opcode from packet
1E31  32 34 31      LD (op_word),A  ; store opcode as op_word
1E34  22 3D 31      LD (run_count),HL  ; store packet HL as run_count

; host op 0x0A: download disk image over bulk channel - AA55 sync, validate geometry header, stream tracks into DRAM banks, verify checksum, set image_present
host_op_image_dl:
1E37  FE 0A         CP 0x0A  ; is this the image-download opcode 0x0A?
1E39  C2 9F 1F      JP NZ,host_op_enter_run  ; if not, dispatch to run-op handler
1E3C  06 58         LD B,0x58  ; B=0x58 'X' ACK/ready reply
1E3E  CD 9D 4E      CALL host_tx  ; send ready reply to host
1E41  21 00 00      LD HL,0x0000  ; HL=0
1E44  22 39 31      LD (track_ctr),HL  ; reset track counter
1E47  22 47 31      LD (dl_rec_count),HL  ; reset downloaded-record count
1E4A  3E FF         LD A,0xFF  ; A=0xFF sentinel
1E4C  32 33 31      LD (cur_track),A  ; init cur_track to 'none yet'
1E4F  CD 59 4C      CALL lcd_print  ; print the following prompt
1E52  1B C0 77 61 69 74 +  DB ESC(0xC0), "wait for data", 0  ; LCD string: cursor line2, 'wait for data'
1E62  CD 96 21      CALL bulk_sync_aa55  ; wait for AA55 sync on the bulk channel
1E65  C2 F6 1E      JP NZ,loc_1EF6  ; on error/timeout, abort the download
1E68  CD 59 4C      CALL lcd_print  ; print the following status
1E6B  1B C8 72 65 61 64 +  DB ESC(0xC8), "read RI", 0  ; LCD string: cursor line2+8, 'read RI'
1E75  18 06         JR loc_1E7D  ; enter the record-read loop

loc_1E77:
1E77  CD 96 21      CALL bulk_sync_aa55  ; re-sync AA55 for the next record
1E7A  C2 F6 1E      JP NZ,loc_1EF6  ; on error, abort the download

loc_1E7D:
1E7D  21 00 00      LD HL,0x0000  ; HL=0
1E80  22 39 31      LD (track_ctr),HL  ; reset track counter for this record
1E83  CD 6A 21      CALL bulk_read_byte  ; read the record-type byte from bulk stream
1E86  79            LD A,C  ; A = record type
1E87  32 4E 33      LD (fmt_buf1),A  ; save it to format buffer
1E8A  32 39 31      LD (track_ctr),A  ; also stash in track_ctr low byte
1E8D  E6 7F         AND 0x7F  ; mask off high bit (last-record flag)
1E8F  FE 01         CP 0x01  ; is it a track/record-info block (type 1)?
1E91  28 28         JR Z,loc_1EBB  ; if so, process the track record
1E93  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 for the error
1E96  CD 59 4C      CALL lcd_print  ; print the following error
1E99  1B C0 52 65 6D 6F +  DB ESC(0xC0), "Remote command error", 0  ; LCD string: cursor line2, 'Remote command error'
1EB0  CD 43 4D      CALL keypad_debounce  ; debounce/flush keypad after error
1EB3  06 90         LD B,0x90  ; B=0x90 error status reply byte
1EB5  CD 9D 4E      CALL host_tx  ; report error to host
1EB8  C3 0B 1E      JP host_dispatch  ; return to the dispatcher loop

loc_1EBB:
1EBB  21 4F 33      LD HL,fmt_buf1+0x1  ; point HL at format-header (skip first byte)
1EBE  06 08         LD B,0x08  ; read 8 header bytes
1EC0  E5            PUSH HL  ; save buffer pointer
1EC1  CD 34 21      CALL bulk_read_bytes  ; receive 8 header bytes from host
1EC4  E1            POP HL  ; restore buffer pointer
1EC5  3A 37 31      LD A,(unit_sel)  ; get selected unit/format id
1EC8  E6 1F         AND 0x1F  ; mask drive/format bits
1ECA  BE            CP (HL)  ; compare with image's stored format id
1ECB  28 30         JR Z,loc_1EFD  ; match -> proceed with transfer
1ECD  FE 04         CP 0x04  ; check special-case value 4
1ECF  20 04         JR NZ,loc_1ED5  ; not 4 -> reject as wrong image
1ED1  3C            INC A  ; bump to 5 and retry
1ED2  BE            CP (HL)  ; compare again
1ED3  28 28         JR Z,loc_1EFD  ; match -> proceed with transfer

loc_1ED5:
1ED5  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
1ED8  CD 59 4C      CALL lcd_print  ; print following message
1EDB  1B C0 4E 6F 74 20 +  DB ESC(0xC0), "Not proper image", 0  ; LCD text: wrong-image error
1EEE  06 B0         LD B,0xB0  ; error status code 0xB0
1EF0  CD 9D 4E      CALL host_tx  ; report error to host
1EF3  C3 0B 1E      JP host_dispatch  ; back to host command loop

loc_1EF6:
1EF6  CD CB 1D      CALL show_abort  ; display abort message
1EF9  C3 0B 1E      JP host_dispatch  ; back to host command loop
1EFC  C9            RET  ; return

loc_1EFD:
1EFD  CD 41 21      CALL bulk_validate  ; validate incoming block header
1F00  28 16         JR Z,loc_1F18  ; valid/continuation -> resume pass
1F02  DD 21 4F 33   LD IX,fmt_buf1+0x1  ; point IX at header
1F06  DD 46 01      LD B,(IX+1)  ; get block index high byte
1F09  DD 7E 02      LD A,(IX+2)  ; get flags byte
1F0C  0F            RRCA  ; rotate bit0 into bit7
1F0D  E6 80         AND 0x80  ; isolate that bit
1F0F  4F            LD C,A  ; save as bank-high bit
1F10  CD F2 4F      CALL block_to_chs  ; convert block index to bank/CHS (bank in A, count in HL)
1F13  D3 B0         OUT (0xB0),A  ; dram_bank — select image DRAM bank for this block
1F15  22 3B 31      LD (pass_ctr),HL  ; store remaining byte count for pass

loc_1F18:
1F18  2A 3B 31      LD HL,(pass_ctr)  ; load remaining byte count
1F1B  06 00         LD B,0x00  ; request 256-byte chunk
1F1D  CD 34 21      CALL bulk_read_bytes  ; read data bytes from host into buffer
1F20  22 3B 31      LD (pass_ctr),HL  ; update remaining count
1F23  20 D1         JR NZ,loc_1EF6  ; rx error -> abort
1F25  11 00 00      LD DE,0x0000  ; clear DE high accumulator
1F28  DD 21 00 00   LD IX,0x0000  ; clear IX checksum accumulator
1F2C  2B            DEC HL  ; back up to last buffer byte
1F2D  43            LD B,E  ; loop count 0 -> 256 via DJNZ

loc_1F2E:
1F2E  5E            LD E,(HL)  ; fetch byte
1F2F  DD 19         ADD IX,DE  ; add to running checksum
1F31  2B            DEC HL  ; step pointer back
1F32  5E            LD E,(HL)  ; fetch next byte
1F33  DD 19         ADD IX,DE  ; add to running checksum
1F35  2B            DEC HL  ; step pointer back
1F36  10 F6         DJNZ loc_1F2E  ; loop over data buffer
1F38  21 4E 33      LD HL,fmt_buf1  ; point at header block
1F3B  06 11         LD B,0x11  ; 17 header bytes

loc_1F3D:
1F3D  5E            LD E,(HL)  ; fetch header byte
1F3E  DD 19         ADD IX,DE  ; add to running checksum
1F40  23            INC HL  ; advance
1F41  10 FA         DJNZ loc_1F3D  ; loop over header
1F43  CD 61 21      CALL bulk_read_word  ; read expected checksum word from host
1F46  DD E5         PUSH IX  ; move computed checksum
1F48  E1            POP HL  ; into HL
1F49  B7            OR A  ; clear carry
1F4A  ED 52         SBC HL,DE  ; compare computed vs received checksum
1F4C  28 20         JR Z,loc_1F6E  ; match -> continue
1F4E  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
1F51  CD 59 4C      CALL lcd_print  ; print following message
1F54  1B C0 54 72 61 6E +  DB ESC(0xC0), "Transfer failed", 0  ; LCD text: "Transfer failed" (checksum mismatch)
1F66  06 A0         LD B,0xA0  ; error status code 0xA0
1F68  CD 9D 4E      CALL host_tx  ; report error to host
1F6B  C3 0B 1E      JP host_dispatch  ; back to host command loop

loc_1F6E:
1F6E  21 4E 33      LD HL,fmt_buf1  ; point at header
1F71  CB 7E         BIT 7,(HL)  ; test last-block flag (bit 7)
1F73  20 14         JR NZ,loc_1F89  ; final block -> finalize transfer
1F75  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
1F78  2A 47 31      LD HL,(dl_rec_count)  ; load records-received count
1F7B  23            INC HL  ; increment
1F7C  22 47 31      LD (dl_rec_count),HL  ; store back
1F7F  3E 00         LD A,0x00  ; format value 0
1F81  1E 20         LD E,0x20  ; pad char space / field width
1F83  CD FA 05      CALL num_to_lcd_alt  ; show record count on LCD
1F86  C3 77 1E      JP loc_1E77  ; back to receive next block

loc_1F89:
1F89  CD 61 21      CALL bulk_read_word  ; read trailing word (final block)
1F8C  3E 01         LD A,0x01  ; flag value 1
1F8E  32 C8 52      LD (image_present),A  ; mark image now present in RAM
1F91  CD 5D 51      CALL checksum_all_banks  ; verify checksum across all DRAM banks
1F94  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
1F97  06 00         LD B,0x00  ; success status code 0
1F99  CD 9D 4E      CALL host_tx  ; ack success to host
1F9C  C3 0B 1E      JP host_dispatch  ; back to host command loop

; host op 0x0B: enter interactive run mode - install iovec callbacks (key/out/annun) and JP run_entry
host_op_enter_run:
1F9F  FE 0B         CP 0x0B  ; is host op 0x0B (enter run mode)?
1FA1  20 23         JR NZ,host_op_disk_write  ; no -> next handler
1FA3  AF            XOR A  ; clear A for host_mode = 0
1FA4  32 61 31      LD (host_mode),A  ; clear host-mode flag
1FA7  06 58         LD B,0x58  ; ack byte 0x58
1FA9  CD 9D 4E      CALL host_tx  ; send ack to host
1FAC  06 00         LD B,0x00  ; status 0
1FAE  CD 9D 4E      CALL host_tx  ; send to host
1FB1  21 8E 4D      LD HL,get_key_dispatch  ; key-input callback
1FB4  22 CB 52      LD (iovec_poll),HL  ; install poll/keys iovec
1FB7  21 4A 4C      LD HL,byte_out  ; byte-output callback
1FBA  22 C9 52      LD (iovec_out),HL  ; install output iovec
1FBD  21 E3 49      LD HL,buzzer_beep  ; beep/annunciator callback
1FC0  22 CD 52      LD (iovec_beep),HL  ; install beep iovec
1FC3  C3 61 01      JP run_entry  ; enter interactive run mode

; host op 0x0D: receive format params from host (each byte echoed via host_rx_echo) - cfg_flags+unit -> unit_sel; write-protect byte -> OUT 0x9C (line 2) + wprot_mode @0x200B; err_recovery byte; then a 24-byte per-head zone table -> hrd_hd0 (remote variable-rate Special format). Programs FDC + builds format block
host_op_disk_write:
1FC6  FE 0D         CP 0x0D  ; is host op 0x0D (receive format params)?
1FC8  C2 4B 20      JP NZ,host_op_ping  ; no -> next handler
1FCB  06 58         LD B,0x58  ; ack byte 0x58
1FCD  CD 9D 4E      CALL host_tx  ; send ack
1FD0  AF            XOR A  ; clear A to reset image_present
1FD1  32 C8 52      LD (image_present),A  ; clear image-present flag
1FD4  CD 3E 20      CALL host_rx_echo  ; receive cfg_flags+unit byte
1FD7  78            LD A,B  ; move received byte to A
1FD8  32 1C 31      LD (cfg_flags),A  ; store config flags
1FDB  CD 3E 20      CALL host_rx_echo  ; receive unit byte
1FDE  C2 48 20      JP NZ,loc_2048  ; rx error -> bail
1FE1  78            LD A,B  ; received byte
1FE2  32 E8 52      LD (format_desc+0xB),A  ; store into format descriptor
1FE5  CD E7 51      CALL fdc_build_unit_sel  ; build FDC unit-select value
1FE8  32 37 31      LD (unit_sel),A  ; store unit_sel
1FEB  4F            LD C,A  ; keep unit_sel in C
1FEC  3A 1C 31      LD A,(cfg_flags)  ; reload config flags
1FEF  47            LD B,A  ; into B
1FF0  79            LD A,C  ; unit_sel back to A
1FF1  E6 0F         AND 0x0F  ; isolate drive-index nibble
1FF3  FE 00         CP 0x00  ; is drive index zero?
1FF5  20 04         JR NZ,loc_1FFB  ; nonzero -> keep as-is
1FF7  79            LD A,C  ; reload unit_sel
1FF8  E6 FC         AND 0xFC  ; clear low 2 bits
1FFA  B0            OR B  ; merge in config flags

loc_1FFB:
1FFB  32 37 31      LD (unit_sel),A  ; store final unit select
1FFE  CD 7B 04      CALL fdc_cmd_both_drives  ; issue FDC command to both drives
2001  CD CB 4F      CALL build_format_block  ; build format parameter block
2004  CD CC 50      CALL layout_sectors  ; compute sector layout
2007  CD 3E 20      CALL host_rx_echo  ; receive write-protect byte
200A  78            LD A,B  ; to A
200B  D3 9C         OUT (0x9C),A  ; ctrl_latch — drive ctrl latch line 2 (write-protect)
200D  32 55 31      LD (wprot_mode),A  ; store write-protect mode
2010  CD 3E 20      CALL host_rx_echo  ; receive err_recovery byte
2013  78            LD A,B  ; to A
2014  32 4A 31      LD (err_recovery),A  ; store error-recovery setting
2017  CD 3E 20      CALL host_rx_echo  ; receive leading zone-table byte
201A  06 18         LD B,0x18  ; 24-byte per-head zone table
201C  21 A1 31      LD HL,hrd_hd0  ; dest = per-head rate table

loc_201F:
201F  C5            PUSH BC  ; save loop counter
2020  CD 3E 20      CALL host_rx_echo  ; receive one table byte
2023  70            LD (HL),B  ; store into table
2024  23            INC HL  ; advance
2025  C1            POP BC  ; restore counter
2026  10 F7         DJNZ loc_201F  ; loop 24 times
2028  06 B0         LD B,0xB0  ; 176 param-table bytes
202A  21 B9 31      LD HL,param_tables  ; dest = param tables

loc_202D:
202D  C5            PUSH BC  ; save loop counter
202E  CD 3E 20      CALL host_rx_echo  ; receive param byte
2031  70            LD (HL),B  ; store
2032  23            INC HL  ; advance
2033  C1            POP BC  ; restore counter
2034  10 F7         DJNZ loc_202D  ; loop 176 times
2036  06 00         LD B,0x00  ; success status code 0
2038  CD 9D 4E      CALL host_tx  ; ack to host
203B  C3 2B 1E      JP loc_1E2B  ; back to host command loop

; receive one byte from host and echo it back as ack (returns byte in B, NZ on error)
host_rx_echo:
203E  CD AD 4E      CALL host_rx  ; receive byte from host (in B)
2041  C0            RET NZ  ; propagate rx error
2042  CD 9D 4E      CALL host_tx  ; echo the just-received byte back to the host
2045  AF            XOR A  ; A=0 / Z set for success
2046  C9            RET  ; return
2047  C1            POP BC  ; discard saved BC

loc_2048:
2048  C3 2B 1E      JP loc_1E2B  ; back to host command loop

; host op 0x0C: ping - ack with 0x58 then 0x00
host_op_ping:
204B  FE 0C         CP 0x0C  ; is host op 0x0C (ping)?
204D  20 0D         JR NZ,host_op_start  ; no -> next handler
204F  06 58         LD B,0x58  ; ack byte 0x58
2051  CD 9D 4E      CALL host_tx  ; send ack
2054  06 00         LD B,0x00  ; status 0
2056  CD 9D 4E      CALL host_tx  ; send to host
2059  C3 2B 1E      JP loc_1E2B  ; back to host command loop

; host op 0x09: clear op_word, ack, run abort_check gate then execute run
host_op_start:
205C  FE 09         CP 0x09  ; is host op 0x09 (start run)?
205E  20 0F         JR NZ,host_op_load_exec  ; no -> next handler
2060  AF            XOR A  ; clear A to reset op_word
2061  32 34 31      LD (op_word),A  ; clear operation word
2064  06 58         LD B,0x58  ; ack byte 0x58
2066  CD 9D 4E      CALL host_tx  ; send ack
2069  CD C6 1D      CALL abort_check  ; run abort/gate check
206C  C3 2A 21      JP loc_212A  ; execute run

; host op 0x0F: ack then code_loader (download+execute code image), loop dispatch
host_op_load_exec:
206F  FE 0F         CP 0x0F  ; is host op 0x0F (download+exec code)?
2071  20 0B         JR NZ,loc_207E  ; no -> next handler
2073  06 58         LD B,0x58  ; ack byte 0x58
2075  CD 9D 4E      CALL host_tx  ; send ack
2078  CD A9 21      CALL code_loader  ; download and run code image
207B  C3 0B 1E      JP host_dispatch  ; back to host command loop

loc_207E:
207E  FE 0E         CP 0x0E  ; is host op 0x0E (diag bridge)?
2080  20 61         JR NZ,host_op_begin_run  ; no -> next handler

; host op 0x0E: diagnostic bridge - relay bytes between host (port DC) and autoloader SIO
host_op_diag_out:
2082  06 58         LD B,0x58  ; ack byte 0x58
2084  CD 9D 4E      CALL host_tx  ; send ack
2087  06 00         LD B,0x00  ; status 0
2089  CD 9D 4E      CALL host_tx  ; send to host
208C  21 00 06      LD HL,0x0600  ; LCD setpos argument (row/col)
208F  CD 22 4C      CALL lcd_setpos  ; set LCD cursor position
2092  21 9C 20      LD HL,host_ser_blob0  ; source = SIO init blob
2095  01 DC 0D      LD BC,0x0DDC  ; B=0x0D count, C=0xDC host SIO port
2098  ED B3         OTIR  ; stream init bytes to SIO port 0xDC
209A  18 0D         JR loc_20A9  ; jump ahead to diag-bridge relay loop

host_ser_blob0:
209C  18 03 C0 04 44 05 E0 01 80 03 C1 05 EA          |....D........|

loc_20A9:
20A9  CD 53 4E      CALL al_rx_ready  ; poll autoloader SIO chan A for a received byte
20AC  20 15         JR NZ,loc_20C3  ; autoloader has data -> pass it through to host
20AE  CD 4F 4E      CALL host_rx_ready  ; else poll host SIO chan B for a byte
20B1  28 F6         JR Z,loc_20A9  ; nothing on either channel, keep polling
20B3  CD AD 4E      CALL host_rx  ; read the host command byte (into B)
20B6  3E DF         LD A,0xDF  ; mask to clear bit5 (fold to uppercase)
20B8  A0            AND B  ; apply mask to received byte
20B9  FE 57         CP 0x57  ; is it 'W' (send serial-config blob)?
20BB  CA CB 20      JP Z,loc_20CB  ; yes -> handle 'W' command
20BE  CD 99 4E      CALL al_tx  ; else forward byte to autoloader channel
20C1  18 E6         JR loc_20A9  ; back to the poll loop

loc_20C3:
20C3  CD A1 4E      CALL al_rx  ; read byte from autoloader chan A
20C6  CD 9D 4E      CALL host_tx  ; forward it out to the host channel
20C9  18 DE         JR loc_20A9  ; back to the poll loop

loc_20CB:
20CB  21 D6 20      LD HL,host_ser_blob1  ; point at host SIO init blob
20CE  01 DC 0D      LD BC,0x0DDC  ; B=0x0D byte count, C=0xDC = host SIO port
20D1  ED B3         OTIR  ; stream the 13-byte SIO/baud setup to port 0xDC
20D3  C3 0B 1E      JP host_dispatch  ; return to the host command dispatcher

host_ser_blob1:
20D6  18 03 C0 04 45 05 E0 01 80 03 C1 05 EA          |....E........|

; start a duplication/blank-check run - ack, show 'FDD', clear fmt_mode; op 0x07 sets up blank-pass ('BP')
host_op_begin_run:
20E3  F5            PUSH AF  ; save the run opcode across ack/LCD
20E4  06 58         LD B,0x58  ; ack byte 'X' (0x58) to host
20E6  CD 9D 4E      CALL host_tx  ; send the ack
20E9  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
20EC  CD 59 4C      CALL lcd_print  ; print the inline LCD string
20EF  1B C0 46 44 44 00  DB ESC(0xC0), "FDD", 0  ; LCD text 'FDD' at col0 of line2
20F5  AF            XOR A  ; A=0 to clear the two flags below
20F6  32 4C 31      LD (fmt_mode),A  ; clear format-mode flag
20F9  32 50 31      LD (edit_ndigits),A  ; clear edit digit-count
20FC  F1            POP AF  ; restore the run opcode
20FD  FE 07         CP 0x07  ; is it op 0x07 (blank-check pass)?
20FF  20 23         JR NZ,loc_2124  ; no -> run normal duplication
2101  21 00 00      LD HL,0x0000  ; HL=0 to reset the run counter
2104  22 3D 31      LD (run_count),HL  ; reset the run counter
2107  7D            LD A,L  ; A=L=0 to clear the image-present flag
2108  32 C8 52      LD (image_present),A  ; clear image-present flag
210B  3E 01         LD A,0x01  ; run-status = 1 (running)
210D  32 4E 31      LD (run_status),A  ; store run status
2110  3E 04         LD A,0x04  ; ctrl latch: line2 (write-protect) = 0
2112  D3 9C         OUT (0x9C),A  ; ctrl_latch — write the control latch
2114  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
2117  CD 59 4C      CALL lcd_print  ; print inline LCD string
211A  1B C0 42 50 00  DB ESC(0xC0), "BP", 0  ; LCD text 'BP' (blank pass)
211F  CD 8B 07      CALL require_motor_ready  ; spin up and wait for drive motors ready
2122  18 06         JR loc_212A  ; join the common tail

loc_2124:
2124  32 4E 31      LD (run_status),A  ; store the opcode as run status
2127  CD 88 07      CALL dup_engine_loop  ; run the duplication engine

loc_212A:
212A  47            LD B,A  ; result code -> B for host reply
212B  CD 9D 4E      CALL host_tx  ; send result byte to host
212E  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
2131  C3 0B 1E      JP host_dispatch  ; return to the host dispatcher

; read B*2 bytes from the bulk-image channel into (HL++)
bulk_read_bytes:
2134  CD 6A 21      CALL bulk_read_byte  ; read one byte from bulk channel (into C)
2137  71            LD (HL),C  ; store it to the buffer
2138  23            INC HL  ; advance buffer pointer
2139  CD 6A 21      CALL bulk_read_byte  ; read the second byte
213C  71            LD (HL),C  ; store it
213D  23            INC HL  ; advance pointer
213E  10 F4         DJNZ bulk_read_bytes  ; loop B times (B*2 bytes total)
2140  C9            RET  ; done

; compare received image geometry header (0x334F+1/+2) with stored (0x3133/0x3135); update and return NZ if changed
bulk_validate:
2141  DD 21 4F 33   LD IX,fmt_buf1+0x1  ; point IX at received geometry header
2145  3A 33 31      LD A,(cur_track)  ; load stored track count
2148  DD BE 01      CP (IX+1)  ; compare with received track
214B  20 07         JR NZ,loc_2154  ; differs -> update stored geometry
214D  3A 35 31      LD A,(datarate_idx)  ; load stored datarate index
2150  DD BE 02      CP (IX+2)  ; compare with received datarate
2153  C8            RET Z  ; unchanged -> return Z

loc_2154:
2154  DD 7E 02      LD A,(IX+2)  ; take received datarate
2157  32 35 31      LD (datarate_idx),A  ; store it
215A  DD 7E 01      LD A,(IX+1)  ; take received track count
215D  32 33 31      LD (cur_track),A  ; store it
2160  C9            RET  ; return NZ (geometry changed)

; read a little-endian 16-bit word from the bulk-image channel into DE
bulk_read_word:
2161  CD 6A 21      CALL bulk_read_byte  ; read low byte from bulk channel
2164  59            LD E,C  ; into E
2165  CD 6A 21      CALL bulk_read_byte  ; read high byte from bulk channel
2168  51            LD D,C  ; into D
2169  C9            RET  ; return word in DE

; read one byte from host bulk-image channel (0x90/0x94/0x9C handshake)
bulk_read_byte:
216A  E5            PUSH HL  ; save HL (reused as timeout counter)
216B  21 00 00      LD HL,0x0000  ; timeout = 65536 iterations

loc_216E:
216E  DB 94         IN A,(0x94)  ; status_in — read bulk handshake status
2170  CB 77         BIT 6,A  ; test data-ready bit 6
2172  20 07         JR NZ,loc_217B  ; ready -> ack and read
2174  2B            DEC HL  ; decrement timeout
2175  7D            LD A,L  ; check HL for zero
2176  B4            OR H  ; HL == 0?
2177  20 F5         JR NZ,loc_216E  ; not yet -> keep waiting
2179  18 0F         JR loc_218A  ; timed out

loc_217B:
217B  3E 0E         LD A,0x0E  ; ctrl latch: assert host handshake
217D  D3 9C         OUT (0x9C),A  ; ctrl_latch — write the control latch

loc_217F:
217F  DB 94         IN A,(0x94)  ; status_in — poll status again
2181  CB 77         BIT 6,A  ; test data-ready bit 6
2183  28 08         JR Z,loc_218D  ; cleared -> data valid, read it
2185  2B            DEC HL  ; decrement timeout
2186  7D            LD A,L  ; check HL
2187  B4            OR H  ; HL == 0?
2188  20 F5         JR NZ,loc_217F  ; keep waiting

loc_218A:
218A  3D            DEC A  ; A 0->0xFF: set NZ error/timeout return
218B  E1            POP HL  ; restore HL
218C  C9            RET  ; return NZ on timeout

loc_218D:
218D  DB 90         IN A,(0x90)  ; bulk_data — read the bulk data byte
218F  4F            LD C,A  ; return value in C
2190  3E 0F         LD A,0x0F  ; ctrl latch: deassert handshake
2192  D3 9C         OUT (0x9C),A  ; ctrl_latch — write the control latch
2194  E1            POP HL  ; restore HL
2195  C9            RET  ; return Z (success)

; wait for 0xAA 0x55 sync word on the bulk-image channel
bulk_sync_aa55:
2196  CD 6A 21      CALL bulk_read_byte  ; read a byte from bulk channel
2199  C0            RET NZ  ; abort on timeout
219A  79            LD A,C  ; A = received byte
219B  FE AA         CP 0xAA  ; first sync byte 0xAA?
219D  20 F7         JR NZ,bulk_sync_aa55  ; no -> keep scanning
219F  CD 6A 21      CALL bulk_read_byte  ; read the next byte
21A2  C0            RET NZ  ; abort on timeout
21A3  79            LD A,C  ; A = received byte
21A4  FE 55         CP 0x55  ; second sync byte 0x55?
21A6  20 EE         JR NZ,bulk_sync_aa55  ; no -> resync from start
21A8  C9            RET  ; sync word found

; code loader: copy 256-byte bootstrap to 0x7800, verify image to 0x8000, JP
code_loader:
21A9  21 4A 4C      LD HL,byte_out  ; output-vector target = byte_out
21AC  22 C9 52      LD (iovec_out),HL  ; install byte_out as output routine
21AF  CD 59 4C      CALL lcd_print  ; print inline LCD string
21B2  0C 43 6F 64 65 20 +  DB \f, "Code loading", 0  ; LCD text 'Code loading'
21C0  21 CE 21      LD HL,dl_code  ; source = ROM copy of loader (0x21CE)
21C3  11 00 78      LD DE,dl_code  ; dest = 0x7800
21C6  01 00 01      LD BC,boot_init  ; length = 0x0100 (256 bytes)
21C9  ED B0         LDIR  ; copy bootstrap loader to 0x7800
21CB  C3 00 78      JP dl_code  ; run the relocated loader at 0x7800

; downloaded-code block (copied to 0x7800 by host opcode 0x0F); runs from RAM, labeled at its ROM source
dl_code:
21CE  3E 0E         LD A,0x0E  ; ctrl latch: assert host handshake
21D0  D3 9C         OUT (0x9C),A  ; ctrl_latch — write the control latch

loc_21D2:
21D2  06 10         LD B,0x10  ; 16 sync bytes expected
21D4  16 00         LD D,0x00  ; expected counter starts at 0

loc_21D6:
21D6  CD 68 78      CALL dl_boot_entry_b  ; read a handshake byte
21D9  BA            CP D  ; matches ascending counter?
21DA  20 F6         JR NZ,loc_21D2  ; mismatch -> restart sync
21DC  14            INC D  ; next expected value
21DD  10 F7         DJNZ loc_21D6  ; loop the 0..15 ramp
21DF  06 10         LD B,0x10  ; 16 more sync bytes
21E1  16 0F         LD D,0x0F  ; expected counter starts at 15

loc_21E3:
21E3  CD 68 78      CALL dl_boot_entry_b  ; read a byte
21E6  BA            CP D  ; matches descending counter?
21E7  20 E9         JR NZ,loc_21D2  ; mismatch -> restart sync
21E9  15            DEC D  ; next expected value
21EA  10 F7         DJNZ loc_21E3  ; loop the 15..0 ramp
21EC  CD 5F 78      CALL dl_boot_entry_a  ; read a 16-bit word
21EF  22 85 78      LD (dl_code+0x85),HL  ; store as download byte count
21F2  CD 5F 78      CALL dl_boot_entry_a  ; read a 16-bit word
21F5  22 81 78      LD (dl_code+0x81),HL  ; store as download dest address
21F8  CD 5F 78      CALL dl_boot_entry_a  ; read a 16-bit word
21FB  22 83 78      LD (dl_code+0x83),HL  ; store as download entry address
21FE  21 00 80      LD HL,image_buf  ; HL = image_buf staging area (0x8000)
2201  3E FE         LD A,0xFE  ; DRAM bank 0xFE (staging bank)
2203  D3 B0         OUT (0xB0),A  ; dram_bank — select the staging bank
2205  ED 4B 85 78   LD BC,(dl_code+0x85)  ; BC = download byte count
2209  16 00         LD D,0x00  ; D = 0 (running checksum)

loc_220B:
220B  CD 68 78      CALL dl_boot_entry_b  ; read one code byte from host
220E  77            LD (HL),A  ; store it into the staging buffer
220F  82            ADD A,D  ; add to running checksum
2210  57            LD D,A  ; update checksum accumulator
2211  23            INC HL  ; advance buffer pointer
2212  0B            DEC BC  ; decrement remaining count
2213  78            LD A,B  ; test BC
2214  B1            OR C  ; BC == 0?
2215  20 F4         JR NZ,loc_220B  ; loop over all bytes
2217  CD 68 78      CALL dl_boot_entry_b  ; read the expected checksum byte
221A  BA            CP D  ; matches computed checksum?
221B  C0            RET NZ  ; bad checksum -> abort
221C  ED 5B 81 78   LD DE,(dl_code+0x81)  ; DE = download dest address
2220  21 00 80      LD HL,image_buf  ; HL = staging buffer source
2223  ED 4B 85 78   LD BC,(dl_code+0x85)  ; BC = length
2227  ED B0         LDIR  ; copy downloaded code to its dest
2229  2A 83 78      LD HL,(dl_code+0x83)  ; HL = downloaded entry point
222C  E9            JP (HL)  ; jump into the downloaded code

; download entry A (runs at 0x785F after relocation to 0x7800)
dl_boot_entry_a:
222D  CD 68 78      CALL dl_boot_entry_b  ; read low byte
2230  6F            LD L,A  ; into L
2231  CD 68 78      CALL dl_boot_entry_b  ; read high byte
2234  67            LD H,A  ; into H
2235  C9            RET  ; return word in HL

; download entry B (runs at 0x7868 after relocation to 0x7800)
dl_boot_entry_b:
2236  DB 94         IN A,(0x94)  ; status_in — poll bulk handshake status
2238  CB 77         BIT 6,A  ; test data-ready bit 6
223A  20 FA         JR NZ,dl_boot_entry_b  ; wait until data is ready
223C  DB 90         IN A,(0x90)  ; bulk_data — read the bulk data byte
223E  F5            PUSH AF  ; save it
223F  3E 0F         LD A,0x0F  ; ctrl latch: deassert handshake
2241  D3 9C         OUT (0x9C),A  ; ctrl_latch — write the control latch

loc_2243:
2243  DB 94         IN A,(0x94)  ; status_in — poll status
2245  CB 77         BIT 6,A  ; test bit 6
2247  28 FA         JR Z,loc_2243  ; wait for host to raise handshake again
2249  3E 0E         LD A,0x0E  ; ctrl latch: reassert handshake
224B  D3 9C         OUT (0x9C),A  ; ctrl_latch — write the control latch
224D  F1            POP AF  ; restore the data byte
224E  C9            RET  ; return byte in A

padding:
224F  00 00 00 00 00 00                               |......|

; clear line2 and draw the '(curr.= ' prefix for a config current-value readout
show_curr_prefix:
2255  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
2258  CD 59 4C      CALL lcd_print  ; print inline LCD string
225B  1B C0 28 63 75 72 +  DB ESC(0xC0), "(curr.= ", 0  ; LCD prefix '(curr.= '
2266  C9            RET  ; done

; CONFIG menu top level
config_menu:
2267  CD 59 4C      CALL lcd_print  ; print inline LCD string
226A  0C 43 6F 6E 66 69 +  DB \f, "Config. setting", 0  ; LCD header 'Config. setting'

loc_227B:
227B  AF            XOR A  ; A=0 (accept any key)
227C  CD 89 4D      CALL get_key  ; wait for a front-panel key
227F  20 FA         JR NZ,loc_227B  ; no key yet -> keep waiting

loc_2281:
2281  CD B4 03      CALL dram_bank_cfg  ; Reconfigure DRAM banking for the config-menu context
2284  CD F8 28      CALL show_media_status  ; Refresh media/drive status line on the LCD
2287  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
2289  CD 89 4D      CALL get_key  ; Poll the panel for one key
228C  FE 01         CP 0x01  ; Was EXIT pressed?
228E  28 25         JR Z,loc_22B5  ; Yes -> jump to Precomp. setting page
2290  21 1D 31      LD HL,cfg_byte  ; Point HL at cfg_byte config record
2293  22 1A 31      LD (cfg_ptr),HL  ; Save that pointer for the FDD-config menu
2296  3A 1D 31      LD A,(cfg_byte)  ; Load current cfg_byte value
2299  E6 03         AND 0x03  ; Keep low 2 bits (drive-desc field)
229B  32 67 31      LD (hrd_desc_tbl),A  ; Seed hrd_desc_tbl with that field
229E  21 F4 30      LD HL,config_fdd_menu  ; Load the FDD-config submenu descriptor
22A1  CD 2F 52      CALL menu_run  ; Run the FDD config submenu
22A4  21 1D 31      LD HL,cfg_byte  ; Point HL back at cfg_byte
22A7  3E FC         LD A,0xFC  ; Mask to clear low 2 bits
22A9  A6            AND (HL)  ; Drop cfg_byte's low 2 bits
22AA  47            LD B,A  ; Hold masked value in B
22AB  3A 67 31      LD A,(hrd_desc_tbl)  ; Fetch the edited drive-desc field
22AE  B0            OR B  ; Merge it back into the masked cfg_byte
22AF  77            LD (HL),A  ; Store updated cfg_byte
22B0  CD F4 28      CALL save_cfg_block  ; Persist config block to EEPROM
22B3  18 CC         JR loc_2281  ; Loop back to top of config page

loc_22B5:
22B5  CD 59 4C      CALL lcd_print  ; Print the Precomp. setting header
22B8  0C 50 72 65 63 6F +  DB \f, "Precomp. setting", 0  ; Inline LCD string 'Precomp. setting' (form-feed clears)
22CA  CD 55 22      CALL show_curr_prefix  ; Print 'current= ' prefix
22CD  21 1D 31      LD HL,cfg_byte  ; Point HL at cfg_byte
22D0  CB 46         BIT 0,(HL)  ; Test precomp source bit0 (user vs default)
22D2  20 0D         JR NZ,loc_22E1  ; Bit set -> show 'default'
22D4  CD 59 4C      CALL lcd_print  ; Print the value suffix
22D7  75 73 65 72 27 73 +  DB "user's)", 0  ; Inline string "user's)"
22DF  18 0C         JR loc_22ED  ; Skip past the default branch

loc_22E1:
22E1  CD 59 4C      CALL lcd_print  ; Print the value suffix
22E4  64 65 66 61 75 6C +  DB "default)", 0  ; Inline string 'default)'

loc_22ED:
22ED  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
22EF  CD 89 4D      CALL get_key  ; Poll the panel for one key
22F2  FE 02         CP 0x02  ; Was ENTER pressed?
22F4  CA 6C 26      JP Z,loc_266C  ; Yes -> jump to precomp edit handler
22F7  CD 9E 24      CALL config_wprotect  ; Handle write-protect recognition submenu
22FA  CD 1E 23      CALL config_err_recovery  ; Handle data-error-recovery submenu
22FD  DB 98         IN A,(0x98)  ; key_scan — Read panel key-scan / config DIP inputs
22FF  21 1E 31      LD HL,drv_active_cfg  ; Point HL at drv_active_cfg
2302  CB 57         BIT 2,A  ; Test key_scan bit2
2304  3E 04         LD A,0x04  ; Default drive-active value 0x04
2306  28 02         JR Z,loc_230A  ; Bit clear -> store 0x04 as-is
2308  EE 01         XOR 0x01  ; Bit set -> flip low bit to 0x05

loc_230A:
230A  77            LD (HL),A  ; Store resulting drive-active config
230B  3A 4A 31      LD A,(err_recovery)  ; Load current err_recovery setting
230E  32 1F 31      LD (cfg_batch),A  ; Copy it into cfg_batch field
2311  0E 01         LD C,0x01  ; EEPROM count C=1 record
2313  06 03         LD B,0x03  ; EEPROM param B=3
2315  3E 01         LD A,0x01  ; EEPROM direction A=1 (write)
2317  21 1D 31      LD HL,cfg_byte  ; Point HL at cfg_byte source buffer
231A  CD 35 27      CALL eeprom_transfer  ; Transfer config block to/from EEPROM
231D  C9            RET  ; Return to caller

; config menu item: toggle data-error-recovery (0x314A=1 enable / 3 disable) via ENTER/EXIT prompt
config_err_recovery:
231E  CD 69 25      CALL show_err_recovery  ; Render the data-error-recovery status line
2321  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
2323  CD 89 4D      CALL get_key  ; Poll the panel for one key
2326  FE 02         CP 0x02  ; Was ENTER pressed?
2328  C0            RET NZ  ; No -> return without changes
2329  CD 59 4C      CALL lcd_print  ; Print the enable/disable prompt
232C  0C 64 69 73 61 62 +  DB \f, "disable    ...  EXITenable     ... ENTER", 0  ; Inline string 'disable ...EXIT / enable ...ENTER'
2356  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
2358  CD 89 4D      CALL get_key  ; Poll the panel for one key
235B  FE 01         CP 0x01  ; Was EXIT pressed?
235D  21 4A 31      LD HL,err_recovery  ; Point HL at err_recovery
2360  3E 03         LD A,0x03  ; Disable value = 3
2362  28 02         JR Z,loc_2366  ; EXIT -> store 3 (disable)
2364  3E 01         LD A,0x01  ; Otherwise enable value = 1

loc_2366:
2366  77            LD (HL),A  ; Write chosen err_recovery value
2367  18 B5         JR config_err_recovery  ; Loop to redraw the recovery submenu

; config menu item: toggle serialization (hrd_desc_tbl bit1 & cfg_byte bit1) via ENTER/EXIT prompt
config_serialization:
2369  CD A5 25      CALL show_serial_batch  ; Render the serialization status line
236C  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
236E  CD 89 4D      CALL get_key  ; Poll the panel for one key
2371  FE 02         CP 0x02  ; Was ENTER pressed?
2373  C0            RET NZ  ; No -> return without changes
2374  CD 59 4C      CALL lcd_print  ; Print the enable/disable prompt
2377  0C 64 69 73 61 62 +  DB \f, "disable    ...  EXITenable     ... ENTER", 0  ; Inline string 'disable ...EXIT / enable ...ENTER'
23A1  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
23A3  CD 89 4D      CALL get_key  ; Poll the panel for one key
23A6  FE 01         CP 0x01  ; Was EXIT pressed?
23A8  21 67 31      LD HL,hrd_desc_tbl  ; Point HL at hrd_desc_tbl
23AB  DD 21 1D 31   LD IX,cfg_byte  ; Point IX at cfg_byte
23AF  CB CE         SET 1,(HL)  ; Set serialization bit1 in hrd_desc_tbl
23B1  DD CB 00 CE   SET 1,(IX+0)  ; Set serialization bit1 in cfg_byte
23B5  28 06         JR Z,loc_23BD  ; EXIT branch -> keep bits set (disable path skips clear)
23B7  CB 8E         RES 1,(HL)  ; Clear serialization bit1 in hrd_desc_tbl
23B9  DD CB 00 8E   RES 1,(IX+0)  ; Clear serialization bit1 in cfg_byte

loc_23BD:
23BD  18 AA         JR config_serialization  ; Loop to redraw the serialization submenu

; config menu item: toggle copy direction (cfg_flags bit7: in->out / out->in)
config_copy_dir:
23BF  CD 2C 25      CALL show_copy_dir  ; Render the copy-direction status line
23C2  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
23C4  CD 89 4D      CALL get_key  ; Poll the panel for one key
23C7  FE 02         CP 0x02  ; Was ENTER pressed?
23C9  C0            RET NZ  ; No -> return without changes
23CA  CD 59 4C      CALL lcd_print  ; Print the direction prompt
23CD  0C 69 6E 20 2D 3E +  DB \f, "in -> out  ...  EXITout -> in  ... ENTER", 0  ; Inline string 'in->out ...EXIT / out->in ...ENTER'
23F7  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
23F9  CD 89 4D      CALL get_key  ; Poll the panel for one key
23FC  FE 01         CP 0x01  ; Was EXIT pressed?
23FE  21 1C 31      LD HL,cfg_flags  ; Point HL at cfg_flags
2401  CB FE         SET 7,(HL)  ; Set direction bit7 (out->in)
2403  28 02         JR Z,loc_2407  ; EXIT -> keep bit7 set
2405  CB BE         RES 7,(HL)  ; Otherwise clear bit7 (in->out)

loc_2407:
2407  18 B6         JR config_copy_dir  ; Loop to redraw the copy-direction submenu

; config menu item: edit maximal cylinder - edit_num_field, clamp to 0x55, store in cfg_flags preserving bit7
config_max_cyl:
2409  CD 53 24      CALL show_max_cyl  ; Render the maximal-cylinder status line
240C  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
240E  CD 89 4D      CALL get_key  ; Poll the panel for one key
2411  FE 02         CP 0x02  ; Was ENTER pressed?
2413  C0            RET NZ  ; No -> return without changes
2414  CD 29 19      CALL clear_image_present  ; Invalidate any loaded image (cyl count changed)
2417  CD 59 4C      CALL lcd_print  ; Print the edit header
241A  0C 53 65 74 20 6D +  DB \f, "Set maximal cylinder", 0  ; Inline string 'Set maximal cylinder'
2430  3A 1C 31      LD A,(cfg_flags)  ; Load cfg_flags
2433  E6 80         AND 0x80  ; Isolate direction bit7
2435  F5            PUSH AF  ; Stash bit7 across the edit
2436  AF            XOR A  ; Zero A
2437  32 43 31      LD (edit_value),A  ; Clear edit_value accumulator
243A  3E 12         LD A,0x12  ; LCD column 0x12 for the field
243C  06 02         LD B,0x02  ; Field width = 2 digits
243E  CD C3 04      CALL edit_num_field  ; Run numeric field editor
2441  3A 43 31      LD A,(edit_value)  ; Read the edited value
2444  FE 56         CP 0x56  ; Compare against 0x56 (clamp limit+1)
2446  FA 4B 24      JP M,loc_244B  ; Below 0x56 -> keep it
2449  3E 55         LD A,0x55  ; Else clamp to 0x55 (max cylinder)

loc_244B:
244B  47            LD B,A  ; Move value into B
244C  F1            POP AF  ; Restore saved direction bit7
244D  B0            OR B  ; Merge bit7 with cylinder value
244E  32 1C 31      LD (cfg_flags),A  ; Store combined value into cfg_flags
2451  18 B6         JR config_max_cyl  ; Loop to redraw the max-cylinder submenu

; render 'Maximal cylinder' header + current value from 0x4AFC/cfg_flags
show_max_cyl:
2453  CD 59 4C      CALL lcd_print  ; Print the header
2456  0C 4D 61 78 69 6D +  DB \f, "Maximal cylinder ", 0  ; Inline string 'Maximal cylinder '
2469  06 02         LD B,0x02  ; Field width = 2 digits
246B  2A FC 4A      LD HL,(drive_blk_a+0x11)  ; Load stored max-cyl word from drive_blk_a+0x11
246E  2D            DEC L  ; Decrement L (cylinders are 1-based display)
246F  26 00         LD H,0x00  ; Clear high byte
2471  5C            LD E,H  ; Zero E (upper operand)
2472  54            LD D,H  ; Zero D (upper operand)
2473  3E 12         LD A,0x12  ; LCD column 0x12
2475  0E 20         LD C,0x20  ; LCD attribute/space char 0x20
2477  CD FC 05      CALL num_to_lcd  ; Render number to LCD
247A  CD 55 22      CALL show_curr_prefix  ; Print 'current= ' prefix
247D  06 02         LD B,0x02  ; Field width = 2 digits
247F  2A 1C 31      LD HL,(cfg_flags)  ; Load cfg_flags word
2482  CB BD         RES 7,L  ; Strip direction bit7 to leave cylinder value
2484  26 00         LD H,0x00  ; Clear high byte
2486  5C            LD E,H  ; Zero E (upper operand)
2487  54            LD D,H  ; Zero D (upper operand)
2488  7D            LD A,L  ; A = low byte (current setting)
2489  B7            OR A  ; Is it zero (unset)?
248A  20 05         JR NZ,loc_2491  ; Nonzero -> use it as-is
248C  3A FC 4A      LD A,(drive_blk_a+0x11)  ; Zero -> fall back to stored max-cyl
248F  3D            DEC A  ; Adjust to 0-based
2490  6F            LD L,A  ; Put fallback into L

loc_2491:
2491  3E 89         LD A,0x89  ; LCD column 0x89
2493  0E 30         LD C,0x30  ; LCD attribute char 0x30
2495  CD FA 05      CALL num_to_lcd_alt  ; Render number (alt formatting) to LCD
2498  CD 59 4C      CALL lcd_print  ; Print closing text
249B  29 00         DB ")", 0  ; Inline string ')'
249D  C9            RET  ; Return to caller

; config menu item: toggle write-protect recognition (ctrl_latch bit0 / 0x3155)
config_wprotect:
249E  CD EC 24      CALL show_wprotect  ; Render the write-protect status line
24A1  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
24A3  CD 89 4D      CALL get_key  ; Poll the panel for one key
24A6  FE 02         CP 0x02  ; Was ENTER pressed?
24A8  C0            RET NZ  ; No -> return without changes
24A9  CD 59 4C      CALL lcd_print  ; Print the recognize/unrecognize prompt
24AC  0C 75 6E 72 65 63 +  DB \f, "unrecognize ..  EXITrecognize   .. ENTER", 0  ; Inline string 'unrecognize ..EXIT / recognize ..ENTER'
24D6  3E 01         LD A,0x01  ; Request a single keypress (mode 1)
24D8  CD 89 4D      CALL get_key  ; Poll the panel for one key
24DB  FE 01         CP 0x01  ; Was EXIT pressed?
24DD  3E 05         LD A,0x05  ; Preset WP latch line2 value 0x05 (data=1 = recognize/ENTER)
24DF  20 02         JR NZ,loc_24E3  ; Not EXIT (ENTER) -> keep 0x05 (recognize)
24E1  EE 01         XOR 0x01  ; EXIT (unrecognize) -> clear data bit to 0x04

loc_24E3:
24E3  D3 9C         OUT (0x9C),A  ; ctrl_latch — Drive the 0x9C control latch (WP-recognition line)
24E5  32 55 31      LD (wprot_mode),A  ; Save chosen mode to wprot_mode
24E8  18 B4         JR config_wprotect  ; Loop to redraw the write-protect submenu
24EA  F1            POP AF  ; Discard stacked AF (stray/unreached cleanup)
24EB  C9            RET  ; Return to caller

; render 'Write protect (curr.= recognize/unrecognize)' from key_scan bit2
show_wprotect:
24EC  CD 59 4C      CALL lcd_print  ; Print the header
24EF  0C 57 72 69 74 65 +  DB \f, "Write protect", \r, \n, 0  ; Inline string 'Write protect' + CR/LF
2500  CD 55 22      CALL show_curr_prefix  ; Print 'current= ' prefix
2503  DB 98         IN A,(0x98)  ; key_scan — Read panel key-scan inputs
2505  CB 57         BIT 2,A  ; Test WP-recognition bit2
2507  F5            PUSH AF  ; Stash flags across the print
2508  28 12         JR Z,loc_251C  ; Bit clear -> show 'recognize'
250A  CD 59 4C      CALL lcd_print  ; Print the value suffix
250D  75 6E 72 65 63 6F +  DB "unrecognize)", 0  ; Inline string 'unrecognize)'
251A  18 0E         JR loc_252A  ; Skip past the recognize branch

loc_251C:
251C  CD 59 4C      CALL lcd_print  ; Print the value suffix
251F  72 65 63 6F 67 6E +  DB "recognize)", 0  ; Inline string 'recognize)'

loc_252A:
252A  F1            POP AF  ; Restore saved flags
252B  C9            RET  ; Return to caller

; render 'Copy direction (curr.= in->out/out->in)' from cfg_flags bit7
show_copy_dir:
252C  CD 59 4C      CALL lcd_print  ; Print the header
252F  0C 43 6F 70 79 20 +  DB \f, "Copy direction", \r, \n, 0  ; Inline string 'Copy direction' + CR/LF
2541  CD 55 22      CALL show_curr_prefix  ; Print 'current= ' prefix
2544  21 1C 31      LD HL,cfg_flags  ; Point HL at cfg_flags
2547  CB 7E         BIT 7,(HL)  ; Test direction bit7
2549  20 0F         JR NZ,loc_255A  ; Bit set -> show 'out->in'
254B  CD 59 4C      CALL lcd_print  ; Print the value suffix
254E  69 6E 20 2D 3E 20 +  DB "in -> out)", 0  ; Inline string 'in -> out)'
2559  C9            RET  ; Return to caller

loc_255A:
255A  CD 59 4C      CALL lcd_print  ; Print the value suffix
255D  6F 75 74 20 2D 3E +  DB "out -> in)", 0  ; Inline string 'out -> in)'
2568  C9            RET  ; Return to caller

; render 'Data error recovery (curr.= enable/disable)' from 0x314A
show_err_recovery:
2569  CD 59 4C      CALL lcd_print  ; Print the header
256C  0C 44 61 74 61 20 +  DB \f, "Data error recovery", 0  ; Inline string 'Data error recovery'
2581  CD 55 22      CALL show_curr_prefix  ; Print 'current= ' prefix
2584  21 4A 31      LD HL,err_recovery  ; Point HL at err_recovery
2587  3E 01         LD A,0x01  ; Enable value = 1
2589  BE            CP (HL)  ; Is current setting = enable?

loc_258A:
258A  28 0C         JR Z,loc_2598  ; Equal -> show 'disable' branch
258C  CD 59 4C      CALL lcd_print  ; Print the value suffix
258F  65 6E 61 62 6C 65 +  DB "enable)", 0  ; Inline string 'enable)'
2597  C9            RET  ; Return to caller

loc_2598:
2598  CD 59 4C      CALL lcd_print  ; print the trailing '(curr.= ...) disable)' text fragment on the LCD
259B  64 69 73 61 62 6C +  DB "disable)", 0  ; inline string 'disable)' + NUL consumed by the preceding lcd_print
25A4  C9            RET  ; return to caller

; render 'Serialization (curr.= enable/disable)' from hrd_desc_tbl bit1
show_serial_batch:
25A5  CD 59 4C      CALL lcd_print  ; start LCD render of the Serialization menu line
25A8  0C 53 65 72 69 61 +  DB \f, "Serialization", 0  ; inline form-feed + 'Serialization' + NUL for lcd_print
25B7  CD 55 22      CALL show_curr_prefix  ; append the '(curr.= ' current-value prefix
25BA  21 67 31      LD HL,hrd_desc_tbl  ; point HL at the hardware-descriptor byte table
25BD  CB 4E         BIT 1,(HL)  ; test bit1 = serialization enable/disable flag
25BF  18 C9         JR loc_258A  ; join common enable/disable text tail via loc_258A

; draw the 'Batch processing' menu header
show_batch:
25C1  CD 59 4C      CALL lcd_print  ; start LCD render of the Batch-processing header
25C4  0C 42 61 74 63 68 +  DB \f, "Batch processing", 0  ; inline form-feed + 'Batch processing' + NUL for lcd_print
25D6  C9            RET  ; return to caller

; batch-processing entry: gate on autoloader-present, else show 'not available'
start_batch:
25D7  CD A8 11      CALL al_present_gate  ; check that an autoloader is present (Z=absent)
25DA  20 04         JR NZ,loc_25E0  ; autoloader present -> run the batch menu
25DC  CD 56 19      CALL show_not_available  ; no autoloader: show 'not available' message
25DF  C9            RET  ; return to caller

loc_25E0:
25E0  21 02 26      LD HL,loc_2602  ; point HL at the batch submenu descriptor table
25E3  C3 2F 52      JP menu_run  ; dispatch into the generic menu runner

loc_25E6:
25E6  3E 04         LD A,0x04  ; value for ctrl_latch line2 (write-protect / static enable strobe)
25E8  D3 9C         OUT (0x9C),A  ; ctrl_latch — drive the 0x9C addressable control latch
25EA  CD 4F 07      CALL set_drive_cfg  ; apply per-drive rate/config to the FDCs
25ED  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 for status output
25F0  21 00 00      LD HL,0x0000  ; zero the run counter accumulator
25F3  3E 07         LD A,0x07  ; operation code 0x07 = read/verify batch op
25F5  32 34 31      LD (op_word),A  ; store the selected operation word
25F8  22 3D 31      LD (run_count),HL  ; reset the completed-run count to 0
25FB  7D            LD A,L  ; A=0 (from L=0) to flag no image loaded
25FC  32 C8 52      LD (image_present),A  ; mark no image currently loaded
25FF  C3 8B 07      JP require_motor_ready  ; spin up motors and start the operation once ready

loc_2602:
2602  14            INC D  ; batch submenu table: entry-count / first field byte
2603  26 26         LD H,0x26  ; submenu table data (handler pointer bytes)
2605  26 37         LD H,0x37  ; submenu table data (handler pointer bytes)
2607  26 48         LD H,0x48  ; submenu table data (handler pointer bytes)
2609  26 00         LD H,0x00  ; submenu table data (terminator / null entry)
260B  00            NOP  ; submenu table padding byte
260C  58            LD E,B  ; submenu table data byte
260D  26 60         LD H,0x60  ; submenu table data (handler pointer bytes)
260F  26 64         LD H,0x64  ; submenu table data (handler pointer bytes)
2611  26 68         LD H,0x68  ; submenu table data (handler pointer bytes)
2613  26 CD         LD H,0xCD  ; submenu table data byte
2615  70            LD (HL),B  ; submenu table data byte
2616  06 CD         LD B,0xCD  ; submenu table data byte
2618  59            LD E,C  ; submenu table data byte
2619  4C            LD C,H  ; submenu table data byte
261A  1B            DEC DE  ; submenu table data byte
261B  C0            RET NZ  ; submenu table data byte
261C  52            LD D,D  ; submenu table data byte
261D  44            LD B,H  ; submenu table data byte
261E  20 2B         JR NZ,loc_264B  ; submenu table data byte
2620  20 46         JR NZ,loc_2668  ; submenu table data byte
2622  57            LD D,A  ; submenu table data byte
2623  56            LD D,(HL)  ; submenu table data byte
2624  00            NOP  ; submenu table padding byte
2625  C9            RET  ; submenu table terminator
2626  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 before drawing the label
2629  CD 59 4C      CALL lcd_print  ; render the 'RD + WV' (read + write-verify) mode label
262C  1B C0 52 44 20 2B +  DB ESC(0xC0), "RD + WV", 0  ; inline cursor-to-line2 escape + 'RD + WV' + NUL
2636  C9            RET  ; return to caller
2637  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 before drawing the label
263A  CD 59 4C      CALL lcd_print  ; render the 'RD + FW' (read + format-write) mode label
263D  1B C0 52 44 20 2B +  DB ESC(0xC0), "RD + FW", 0  ; inline cursor-to-line2 escape + 'RD + FW' + NUL
2647  C9            RET  ; return to caller
2648  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 before drawing the label

loc_264B:
264B  CD 59 4C      CALL lcd_print  ; render the 'RD + W' (read + write) mode label
264E  1B C0 52 44 20 2B +  DB ESC(0xC0), "RD + W", 0  ; inline cursor-to-line2 escape + 'RD + W' + NUL
2657  C9            RET  ; return to caller
2658  3E 01         LD A,0x01  ; read-submode 0x01 (plain read+write)

loc_265A:
265A  32 4F 31      LD (rd_submode),A  ; store the selected read/write submode
265D  C3 E6 25      JP loc_25E6  ; launch the batch read/write operation
2660  3E 02         LD A,0x02  ; read-submode 0x02 selected
2662  18 F6         JR loc_265A  ; store submode and start op
2664  3E 05         LD A,0x05  ; read-submode 0x05 selected
2666  18 F2         JR loc_265A  ; store submode and start op

loc_2668:
2668  3E 06         LD A,0x06  ; read-submode 0x06 selected
266A  18 EE         JR loc_265A  ; store submode and start op

loc_266C:
266C  21 5E 31      LD HL,read_addr+0x4  ; point HL at the user/default flag byte (read_addr+4)
266F  36 00         LD (HL),0x00  ; clear that flag byte
2671  3A 1D 31      LD A,(cfg_byte)  ; load current config byte to derive drive index
2674  CD 25 27      CALL drive_block_pos  ; compute this drive's record offset (low byte -> C)
2677  79            LD A,C  ; A = record offset low byte
2678  32 49 31      LD (op_flag_49),A  ; save it in op_flag_49 for later EEPROM access
267B  06 18         LD B,0x18  ; byte count 0x18 = one drive geometry record
267D  21 A1 31      LD HL,hrd_hd0  ; HL = head-0 parameter buffer
2680  3E 00         LD A,0x00  ; direction 0 = load EEPROM -> RAM
2682  CD 35 27      CALL eeprom_transfer  ; read the drive record from the CAT24C02 EEPROM
2685  CD 59 4C      CALL lcd_print  ; render the user/default selection screen
2688  0C 75 73 65 72 20 +  DB \f, "user     ...    EXIT", \r, \n, "default  ...   ENTER", 0  ; inline two-line 'user ... EXIT / default ... ENTER' menu text
26B4  3E 01         LD A,0x01  ; arm key-input mode 0x01
26B6  CD 89 4D      CALL get_key  ; wait for and read a front-panel key
26B9  FE 02         CP 0x02  ; was it the EXIT/ENTER key (code 0x02)?
26BB  21 5E 31      LD HL,read_addr+0x4  ; reload HL = user/default flag byte
26BE  28 24         JR Z,loc_26E4  ; yes -> handle 'default/ENTER' path
26C0  FE 08         CP 0x08  ; was key code 0x08 (special/format select)?
26C2  20 0E         JR NZ,loc_26D2  ; no -> skip the geometry preload
26C4  E5            PUSH HL  ; preserve the flag pointer
26C5  21 29 4B      LD HL,fmt_geom_recs  ; HL = format geometry record table in RAM
26C8  06 60         LD B,0x60  ; byte count 0x60 = four 0x18-byte records
26CA  3E 01         LD A,0x01  ; direction 1 = save RAM -> EEPROM
26CC  0E 04         LD C,0x04  ; EEPROM word address 0x04 = special-format zone tables
26CE  CD 35 27      CALL eeprom_transfer  ; write the geometry records back to EEPROM
26D1  E1            POP HL  ; restore the flag pointer

loc_26D2:
26D2  CB 46         BIT 0,(HL)  ; test bit0 of the flag byte (which config target)
26D4  21 1C 31      LD HL,cfg_flags  ; assume cfg_flags as the target byte
26D7  20 03         JR NZ,loc_26DC  ; if bit set keep cfg_flags
26D9  21 1D 31      LD HL,cfg_byte  ; otherwise target cfg_byte

loc_26DC:
26DC  CB C6         SET 0,(HL)  ; set the enable bit (bit0) on the chosen config byte
26DE  CD F4 28      CALL save_cfg_block  ; persist the config block to EEPROM
26E1  C3 B5 22      JP loc_22B5  ; return to the calling menu (loc_22B5)

loc_26E4:
26E4  CB 46         BIT 0,(HL)  ; test bit0 of the flag byte (which config target)
26E6  21 1C 31      LD HL,cfg_flags  ; assume cfg_flags as the target byte
26E9  20 03         JR NZ,loc_26EE  ; if bit set keep cfg_flags
26EB  21 1D 31      LD HL,cfg_byte  ; otherwise target cfg_byte

loc_26EE:
26EE  CB 86         RES 0,(HL)  ; clear the enable bit (bit0) on the chosen config byte
26F0  CD F4 28      CALL save_cfg_block  ; persist the config block to EEPROM
26F3  CD 6A 27      CALL hrd_head_edit  ; run the head-parameter zone-table editor
26F6  3A 49 31      LD A,(op_flag_49)  ; reload the saved record offset
26F9  4F            LD C,A  ; C = record offset (EEPROM word address)
26FA  21 A1 31      LD HL,hrd_hd0  ; HL = head-0 parameter buffer
26FD  06 18         LD B,0x18  ; byte count 0x18 = one drive record
26FF  3E 01         LD A,0x01  ; direction 1 = save RAM -> EEPROM
2701  CD 35 27      CALL eeprom_transfer  ; write the edited head record back to EEPROM
2704  C3 B5 22      JP loc_22B5  ; return to the calling menu (loc_22B5)

; compute pointer to a drive's 0x18-byte record in the table at 0x4B29 (index from unit-select bits)
drive_block_ptr:
2707  CD 16 27      CALL drive_index_bits  ; derive 0..3 drive index from the unit-select byte
270A  3E 18         LD A,0x18  ; multiplier 0x18 = record size in bytes
270C  0E 00         LD C,0x00  ; high byte of multiply operand = 0
270E  CD 05 4F      CALL mul16  ; HL = index * 0x18 (record byte offset)
2711  11 29 4B      LD DE,fmt_geom_recs  ; DE = base of the geometry record table (0x4B29)
2714  19            ADD HL,DE  ; HL = pointer to this drive's record
2715  C9            RET  ; return with record pointer in HL

; map unit-select byte bits7,3 to a 0..3 drive index in E
drive_index_bits:
2716  16 00         LD D,0x00  ; clear D (high byte of index result)
2718  5A            LD E,D  ; clear E as well (index = 0)
2719  CB 7F         BIT 7,A  ; test unit-select bit7
271B  28 02         JR Z,loc_271F  ; bit7 clear -> skip low index bit
271D  CB C3         SET 0,E  ; bit7 set -> set index bit0

loc_271F:
271F  CB 5F         BIT 3,A  ; test unit-select bit3
2721  C0            RET NZ  ; bit3 set -> done (return index in E)
2722  CB CB         SET 1,E  ; bit3 clear -> set index bit1
2724  C9            RET  ; return with 0..3 drive index in E

; compute a drive's record offset (0x18*index + 4), returns low byte in C
drive_block_pos:
2725  CD 16 27      CALL drive_index_bits  ; derive 0..3 drive index from the unit-select byte
2728  3E 18         LD A,0x18  ; multiplier 0x18 = record size in bytes
272A  0E 00         LD C,0x00  ; high byte of multiply operand = 0
272C  CD 05 4F      CALL mul16  ; HL = index * 0x18 (record byte offset)
272F  11 04 00      LD DE,0x0004  ; DE = 4 (offset to the sub-field within the record)
2732  19            ADD HL,DE  ; HL = index*0x18 + 4
2733  4D            LD C,L  ; return low byte of offset in C
2734  C9            RET  ; return to caller

; bidirectional CAT24C02 EEPROM block transfer (NOT save-only). A=direction (0=load EEPROM->RAM, else save RAM->EEPROM); HL=RAM buffer; B=byte count; C=EEPROM word address. Save = one I2C byte-write per byte (INC addr, honours write cycle); load = single sequential read (ACK..NAK+stop). Map: 0x00 config block (cfg_flags/cfg_byte/drv_active_cfg/cfg_batch), 0x04+ Special-format zone tables (24B/slot), 0xFC 32-bit lifetime cycle counter (shown by show_model_cycles)
eeprom_transfer:
2735  F5            PUSH AF  ; save direction/flags for restore on exit
2736  C5            PUSH BC  ; save byte count and address
2737  B7            OR A  ; test A: 0 = load (EEPROM->RAM), else save
2738  59            LD E,C  ; E = C = EEPROM word address
2739  28 10         JR Z,loc_274B  ; A==0 -> take the sequential-read (load) path

loc_273B:
273B  CD CB 2A      CALL eeprom_write  ; start an I2C byte-write at the current address
273E  7E            LD A,(HL)  ; fetch next RAM byte to send
273F  CD D4 2A      CALL eeprom_send_byte  ; clock the data byte out to the EEPROM
2742  CD 3E 2B      CALL eeprom_io  ; run the write/ack I2C phase (honours write cycle)
2745  23            INC HL  ; advance the RAM source pointer
2746  1C            INC E  ; advance the EEPROM word address
2747  10 F2         DJNZ loc_273B  ; loop until all bytes written
2749  18 18         JR loc_2763  ; done -> restore and return

loc_274B:
274B  CD 55 2B      CALL eeprom_read  ; begin a sequential read (address the EEPROM)
274E  05            DEC B  ; reserve the last byte for the NAK+stop read

loc_274F:
274F  CD 66 2B      CALL i2c_read_byte  ; read one byte from the EEPROM over I2C
2752  CD 4D 2B      CALL i2c_ack  ; send ACK to request the next byte
2755  77            LD (HL),A  ; store the received byte to RAM
2756  23            INC HL  ; advance the RAM destination pointer
2757  10 F6         DJNZ loc_274F  ; loop for B-1 bytes
2759  CD 66 2B      CALL i2c_read_byte  ; read the final byte
275C  CD EF 2A      CALL eeprom_clk_idle  ; hold clock idle to finish with NAK
275F  CD 3E 2B      CALL eeprom_io  ; issue stop condition
2762  77            LD (HL),A  ; store the final byte to RAM

loc_2763:
2763  C1            POP BC  ; restore byte count
2764  F1            POP AF  ; restore direction/flags
2765  C9            RET  ; return to caller

; beep via the iovec_beep vector (default buzzer_beep); beep count encodes the alert/error code
beep:
2766  2A CD 52      LD HL,(iovec_beep)  ; load the beep handler vector (default buzzer_beep)
2769  E9            JP (HL)  ; tail-jump into the beep routine; count encodes alert code

; BC-preserving wrapper to edit the two-head data-rate zone table (per head: 6 entries { start cyl : low byte, data-rate : high byte 0/1/2 = N/L/H }; consumed by range_table_lookup @0x092A -> fdc_rate_a/b)
hrd_head_edit:
276A  C5            PUSH BC  ; preserve BC across the head-pair edit
276B  CD 00 28      CALL hrd_edit_head_pair  ; edit the two-head data-rate zone tables
276E  C1            POP BC  ; restore BC
276F  C9            RET  ; return to caller

; render head-1 row of the head parameter table (sets prefix '1', buffer 0x31AF)
hrd_row_head1:
2770  E5            PUSH HL  ; save HL across the head-1 row render
2771  C5            PUSH BC  ; save BC
2772  3E 31         LD A,0x31  ; A = '1', head-1 row prefix digit
2774  21 AF 31      LD HL,hrd_test_idx+0xA  ; HL = head-1 zone-table buffer (0x31AF)
2777  32 92 27      LD (loc_2786+0xC),A  ; patch the row-prefix char into the shared print stub
277A  18 0A         JR loc_2786  ; join the shared row-render code

; render head-0 row: print 'H C-0' grid, then the zone entries - low byte of each word = value (hrd_fmt_num), high byte = N/L/H rate flag
hrd_row_head0:
277C  E5            PUSH HL  ; save HL
277D  C5            PUSH BC  ; save BC
277E  3E 30         LD A,0x30  ; A = '0' digit for the head-0 row prefix
2780  32 92 27      LD (loc_2786+0xC),A  ; patch the row-prefix char into the shared print stub
2783  21 A3 31      LD HL,hrd_hd1  ; HL = head-1 zone-table buffer for head-0 grid

loc_2786:
2786  E5            PUSH HL  ; save the buffer pointer
2787  CD 59 4C      CALL lcd_print  ; draw the 'H C-0 / 0 v-' zone grid header
278A  0C 48 20 43 2D 30 +  DB \f, "H C-0", \r, \n, "0 v-", 0  ; inline two-line 'H C-0' grid header text
2797  0E 86         LD C,0x86  ; C = 0x86 LCD cursor address for the value cells
2799  E1            POP HL  ; restore the buffer pointer
279A  E5            PUSH HL  ; save it again for the entry loop
279B  06 05         LD B,0x05  ; B = 0x05 zone entries to render

loc_279D:
279D  E5            PUSH HL  ; save row pointer for the head-table print loop
279E  C5            PUSH BC  ; save loop counter/cursor column pair
279F  7E            LD A,(HL)  ; fetch this cell's raw byte value
27A0  CD E7 27      CALL hrd_fmt_num  ; convert byte to decimal and patch digits into print template
27A3  C1            POP BC  ; restore counter/cursor column
27A4  79            LD A,C  ; get current LCD column into A
27A5  32 FA 27      LD (lcd_val_tmpl+0x1),A  ; store column as the cell's cursor-position template byte
27A8  CD F5 27      CALL hrd_emit_num  ; emit the formatted number cell to the LCD
27AB  0C            INC C  ; advance cursor column by 3 (cell width)
27AC  0C            INC C  ; advance cursor column by 3 (cell width)
27AD  0C            INC C  ; advance cursor column by 3 (cell width)
27AE  E1            POP HL  ; restore row pointer
27AF  23            INC HL  ; step to next table entry (2 bytes per entry)
27B0  23            INC HL  ; step to next table entry (2 bytes per entry)
27B1  10 EA         DJNZ loc_279D  ; repeat for each cell in the row
27B3  E1            POP HL  ; restore base table pointer
27B4  2B            DEC HL  ; back up one byte to the row's first field
27B5  AF            XOR A  ; clear A for template blanking
27B6  32 FC 27      LD (lcd_val_tmpl+0x3),A  ; blank the trailing template digit byte
27B9  0E C4         LD C,0xC4  ; start cursor column at 0xC4 for second row
27BB  06 06         LD B,0x06  ; loop over the 6 cells in this row

loc_27BD:
27BD  E5            PUSH HL  ; save row pointer
27BE  C5            PUSH BC  ; save counter/cursor column
27BF  7E            LD A,(HL)  ; fetch this cell's mode selector byte
27C0  B7            OR A  ; test selector for zero
27C1  20 04         JR NZ,loc_27C7  ; nonzero -> check next value
27C3  3E 4E         LD A,0x4E  ; value 0 -> ASCII 'N' (0x4E)
27C5  18 0A         JR loc_27D1  ; go store the letter

loc_27C7:
27C7  FE 01         CP 0x01  ; compare selector against 1
27C9  20 04         JR NZ,loc_27CF  ; not 1 -> use default letter
27CB  3E 4C         LD A,0x4C  ; value 1 -> ASCII 'L' (0x4C)
27CD  18 02         JR loc_27D1  ; go store the letter

loc_27CF:
27CF  3E 48         LD A,0x48  ; default -> ASCII 'H' (0x48)

loc_27D1:
27D1  32 FB 27      LD (lcd_val_tmpl+0x2),A  ; store letter into the cell template
27D4  79            LD A,C  ; get current LCD column into A
27D5  32 FA 27      LD (lcd_val_tmpl+0x1),A  ; store column as the cell's cursor-position template byte
27D8  CD F5 27      CALL hrd_emit_num  ; emit the formatted mode-letter cell to the LCD
27DB  C1            POP BC  ; restore counter/cursor column
27DC  0C            INC C  ; advance cursor column by 3 (cell width)
27DD  0C            INC C  ; advance cursor column by 3 (cell width)
27DE  0C            INC C  ; advance cursor column by 3 (cell width)
27DF  E1            POP HL  ; restore row pointer
27E0  23            INC HL  ; step to next table entry (2 bytes per entry)
27E1  23            INC HL  ; step to next table entry (2 bytes per entry)
27E2  10 D9         DJNZ loc_27BD  ; repeat for each cell in this row
27E4  C1            POP BC  ; restore caller's BC
27E5  E1            POP HL  ; restore caller's HL
27E6  C9            RET  ; return to caller

; convert a byte to decimal (bin2dec_clear) and patch the digits into the head-table print buffer
hrd_fmt_num:
27E7  6F            LD L,A  ; byte value into low half of HL
27E8  26 00         LD H,0x00  ; zero high byte for 16-bit conversion
27EA  5C            LD E,H  ; clear E (bin2dec sign/leading flag)
27EB  CD B2 4E      CALL bin2dec_clear  ; run binary-to-decimal with leading-zero clear
27EE  2A 37 4F      LD HL,(lcd_dec_tmpl+0x8)  ; load the two converted decimal digits
27F1  22 FB 27      LD (lcd_val_tmpl+0x2),HL  ; patch digits into the cell print template
27F4  C9            RET  ; return to caller

; print a formatted head-table number cell (BC-preserving lcd_print of patched inline bytes)
hrd_emit_num:
27F5  C5            PUSH BC  ; preserve BC across the LCD print
27F6  CD 59 4C      CALL lcd_print  ; print the patched inline template bytes to LCD

lcd_val_tmpl:
27F9  1B 00 00 00 00  DB ESC(0x00), \x00, \x00, \x00  ; inline LCD template: ESC + 3 patchable bytes (cursor,digit,digit)
27FE  C1            POP BC  ; restore BC
27FF  C9            RET  ; return to caller

; render both head rows (0 and 1) of the head parameter table with framing escapes
hrd_edit_head_pair:
2800  CD 59 4C      CALL lcd_print  ; print inline framing escape sequence
2803  1B 0D 00      DB ESC(0x0D), 0  ; inline LCD escape 0x0D (open head-table frame)
2806  21 A3 31      LD HL,hrd_hd1  ; point HL at head-0 parameter row data
2809  3E 00         LD A,0x00  ; row index 0
280B  CD 1D 28      CALL hrd_edit_head_row  ; render/edit head row 0
280E  21 AF 31      LD HL,hrd_test_idx+0xA  ; point HL at head-1 parameter row data
2811  3E 01         LD A,0x01  ; row index 1
2813  CD 1D 28      CALL hrd_edit_head_row  ; render/edit head row 1
2816  CD 59 4C      CALL lcd_print  ; print inline closing framing escape
2819  1B 0C 00      DB ESC(0x0C), 0  ; inline LCD escape 0x0C (close head-table frame)
281C  C9            RET  ; return to caller

; render one head row (0 or 1) computing per-column LCD cursor positions
hrd_edit_head_row:
281D  06 00         LD B,0x00  ; clear column-loop counter B
281F  0E 87         LD C,0x87  ; base LCD column 0x87 for this row

loc_2821:
2821  F5            PUSH AF  ; save A (current row index) across the cell edit
2822  B7            OR A  ; test row index for zero
2823  20 05         JR NZ,loc_282A  ; row 1 -> use head1 field pointers
2825  CD 7C 27      CALL hrd_row_head0  ; row 0: fetch head0 field base pointer
2828  18 03         JR loc_282D  ; skip head1 branch

loc_282A:
282A  CD 70 27      CALL hrd_row_head1  ; fetch head1 field base pointer

loc_282D:
282D  E5            PUSH HL  ; save field pointer
282E  C5            PUSH BC  ; save column counter/base
282F  78            LD A,B  ; get column index B
2830  07            RLCA  ; index*2
2831  5F            LD E,A  ; keep index*2 in E
2832  80            ADD A,B  ; add index -> index*3 (cell stride)
2833  81            ADD A,C  ; add base column -> absolute LCD column
2834  16 00         LD D,0x00  ; high byte of DE offset = 0
2836  19            ADD HL,DE  ; advance field pointer by index*2
2837  47            LD B,A  ; save computed column into B
2838  AF            XOR A  ; clear A for template blanking
2839  32 FB 27      LD (lcd_val_tmpl+0x2),A  ; blank template digit byte
283C  32 FC 27      LD (lcd_val_tmpl+0x3),A  ; blank template digit byte
283F  78            LD A,B  ; computed column into A
2840  32 FA 27      LD (lcd_val_tmpl+0x1),A  ; store column as cell cursor-position template byte
2843  CD F5 27      CALL hrd_emit_num  ; emit this field's value cell to LCD
2846  3E 01         LD A,0x01  ; request cursor display for the active field
2848  CD 89 4D      CALL get_key  ; poll the front panel for a keypress
284B  FE 08         CP 0x08  ; is it the up/increment key (0x08)?
284D  20 09         JR NZ,loc_2858  ; not up -> check other keys
284F  34            INC (HL)  ; increment the field value in place
2850  7E            LD A,(HL)  ; reload updated value
2851  D6 51         SUB 0x51  ; subtract wrap limit 0x51
2853  38 1F         JR C,loc_2874  ; below limit -> keep value, restart cell
2855  77            LD (HL),A  ; at/over limit -> wrap to 0
2856  18 1C         JR loc_2874  ; restart cell render

loc_2858:
2858  FE 04         CP 0x04  ; is it the down/decrement key (0x04)?
285A  20 0B         JR NZ,loc_2867  ; not down -> check enter key
285C  35            DEC (HL)  ; decrement the field value in place
285D  7E            LD A,(HL)  ; reload updated value
285E  FE FF         CP 0xFF  ; did it underflow past 0 (to 0xFF)?
2860  20 12         JR NZ,loc_2874  ; no underflow -> restart cell
2862  3E 50         LD A,0x50  ; underflow -> wrap to max 0x50
2864  77            LD (HL),A  ; store wrapped value
2865  18 0D         JR loc_2874  ; restart cell render

loc_2867:
2867  FE 01         CP 0x01  ; is it the enter/advance key (0x01)?
2869  20 0E         JR NZ,loc_2879  ; no -> exit this row's edit loop
286B  C1            POP BC  ; restore column counter
286C  04            INC B  ; advance to next column
286D  78            LD A,B  ; get new column index
286E  D6 05         SUB 0x05  ; compare against 5 columns
2870  20 01         JR NZ,loc_2873  ; not yet 5 -> keep index
2872  47            LD B,A  ; reached 5 -> wrap column index to 0

loc_2873:
2873  C5            PUSH BC  ; save updated column counter

loc_2874:
2874  C1            POP BC  ; restore column counter
2875  E1            POP HL  ; restore field pointer
2876  F1            POP AF  ; restore row index
2877  18 A8         JR loc_2821  ; loop back to render/edit next cell

loc_2879:
2879  C1            POP BC  ; restore column counter
287A  E1            POP HL  ; restore field pointer
287B  F1            POP AF  ; restore row index into A
287C  B7            OR A  ; test row index for zero
287D  20 05         JR NZ,loc_2884  ; row 1 -> use head1 second field set
287F  21 A2 31      LD HL,hrd_hd0+0x1  ; row 0: point at head0 second field
2882  18 03         JR loc_2887  ; skip head1 branch

loc_2884:
2884  21 AE 31      LD HL,hrd_test_idx+0x9  ; point at head1 second field

loc_2887:
2887  0E C4         LD C,0xC4  ; base LCD column 0xC4 for second field set
2889  06 00         LD B,0x00  ; clear column-loop counter B

loc_288B:
288B  F5            PUSH AF  ; save A (row index) across cell edit
288C  B7            OR A  ; test row index for zero
288D  20 05         JR NZ,loc_2894  ; row 1 -> use head1 field pointers
288F  CD 7C 27      CALL hrd_row_head0  ; row 0: fetch head0 field base pointer
2892  18 03         JR loc_2897  ; skip head1 branch

loc_2894:
2894  CD 70 27      CALL hrd_row_head1  ; fetch head1 field base pointer

loc_2897:
2897  E5            PUSH HL  ; save field pointer
2898  C5            PUSH BC  ; save column counter/base
2899  78            LD A,B  ; get column index B
289A  07            RLCA  ; index*2
289B  5F            LD E,A  ; keep index*2 in E
289C  80            ADD A,B  ; add index -> index*3 (cell stride)
289D  81            ADD A,C  ; add base column -> absolute LCD column
289E  16 00         LD D,0x00  ; high byte of DE offset = 0
28A0  19            ADD HL,DE  ; advance field pointer by index*2
28A1  47            LD B,A  ; save computed column into B
28A2  AF            XOR A  ; clear A for template blanking
28A3  32 FB 27      LD (lcd_val_tmpl+0x2),A  ; blank template digit byte
28A6  32 FC 27      LD (lcd_val_tmpl+0x3),A  ; blank template digit byte
28A9  78            LD A,B  ; computed column into A
28AA  32 FA 27      LD (lcd_val_tmpl+0x1),A  ; store column as cell cursor-position template byte
28AD  CD F5 27      CALL hrd_emit_num  ; emit this field's value cell to LCD
28B0  3E 01         LD A,0x01  ; request cursor display for the active field
28B2  CD 89 4D      CALL get_key  ; poll the front panel for a keypress
28B5  FE 08         CP 0x08  ; is it the up/increment key (0x08)?
28B7  20 09         JR NZ,loc_28C2  ; not up -> check other keys
28B9  34            INC (HL)  ; increment the field value in place
28BA  7E            LD A,(HL)  ; reload updated value
28BB  D6 03         SUB 0x03  ; subtract wrap limit 3 (mode 0/1/2)
28BD  20 1F         JR NZ,loc_28DE  ; below limit -> keep value, restart cell
28BF  77            LD (HL),A  ; at/over limit -> wrap to 0
28C0  18 1C         JR loc_28DE  ; restart cell render

loc_28C2:
28C2  FE 04         CP 0x04  ; is it the down/decrement key (0x04)?
28C4  20 0B         JR NZ,loc_28D1  ; not down -> check enter key
28C6  35            DEC (HL)  ; decrement the field value in place
28C7  7E            LD A,(HL)  ; reload updated value
28C8  FE FF         CP 0xFF  ; did it underflow past 0 (to 0xFF)?
28CA  20 12         JR NZ,loc_28DE  ; no underflow -> restart cell
28CC  3E 02         LD A,0x02  ; underflow -> wrap to max mode 2
28CE  77            LD (HL),A  ; store wrapped value
28CF  18 0D         JR loc_28DE  ; restart cell render

loc_28D1:
28D1  FE 01         CP 0x01  ; is it the enter/advance key (0x01)?
28D3  20 0E         JR NZ,loc_28E3  ; no -> exit this row's edit loop
28D5  C1            POP BC  ; restore column counter
28D6  04            INC B  ; advance to next column
28D7  78            LD A,B  ; get new column index
28D8  D6 06         SUB 0x06  ; compare against 6 columns
28DA  20 01         JR NZ,loc_28DD  ; not yet 6 -> keep index
28DC  47            LD B,A  ; reached 6 -> wrap column index to 0

loc_28DD:
28DD  C5            PUSH BC  ; save updated column counter

loc_28DE:
28DE  C1            POP BC  ; restore column counter
28DF  E1            POP HL  ; restore field pointer
28E0  F1            POP AF  ; restore row index
28E1  18 A8         JR loc_288B  ; loop back to render/edit next cell

loc_28E3:
28E3  C1            POP BC  ; restore column counter
28E4  E1            POP HL  ; restore field pointer
28E5  F1            POP AF  ; restore row index
28E6  C9            RET  ; return to caller
28E7  3E 00         LD A,0x00  ; load initial row/mode index 0

loc_28E9:
28E9  21 1C 31      LD HL,cfg_flags  ; point HL at cfg_flags block for EEPROM transfer
28EC  0E 00         LD C,0x00  ; C=0: EEPROM byte offset 0 for the block
28EE  06 02         LD B,0x02  ; B=2: transfer 2 bytes (cfg_flags)
28F0  CD 35 27      CALL eeprom_transfer  ; run EEPROM read/write per A (0=read,1=write)
28F3  C9            RET  ; return to caller

; persist the 2-byte cfg_flags block to serial EEPROM (eeprom_transfer write mode)
save_cfg_block:
28F4  3E 01         LD A,0x01  ; A=1: select write mode for eeprom_transfer
28F6  18 F1         JR loc_28E9  ; join common cfg_flags transfer at loc_28E9

; render media summary from cfg_byte: size, density, S/N and HS/NS/DS; self-patches LCD cursor
show_media_status:
28F8  3A 1D 31      LD A,(cfg_byte)  ; load cfg_byte (media config bits)
28FB  4F            LD C,A  ; keep config bits in C for the bit tests below
28FC  3E 8C         LD A,0x8C  ; A=0x8C: LCD cursor DDRAM address for column patch
28FE  32 4E 29      LD (show_size_density+0x8),A  ; self-patch show_size_density's cursor arg to 0x8C
2901  32 5B 29      LD (loc_2957+0x4),A  ; self-patch loc_2957's cursor arg to 0x8C
2904  3E CA         LD A,0xCA  ; A=0xCA: second LCD cursor DDRAM address
2906  32 69 29      LD (loc_2961+0x8),A  ; self-patch loc_2961's cursor arg to 0xCA
2909  32 77 29      LD (loc_2973+0x4),A  ; self-patch loc_2973's cursor arg to 0xCA
290C  32 85 29      LD (loc_297D+0x8),A  ; self-patch loc_297D's cursor arg to 0xCA
290F  CD 59 4C      CALL lcd_print  ; print inline string that follows
2912  0C 00         DB \f, 0  ; inline data: form-feed (clear) then terminator
2914  CD 46 29      CALL show_size_density  ; print size + density portion (5.25/3.5, HD/DD/QD)
2917  CB 61         BIT 4,C  ; test cfg bit4: simultaneous-mode flag
2919  28 08         JR Z,loc_2923  ; if bit4 clear, show 'N' (normal) branch
291B  CD 59 4C      CALL lcd_print  ; print inline string
291E  53 20 00      DB "S ", 0  ; inline text 'S ' (simultaneous)
2921  18 06         JR loc_2929  ; continue to spindle-speed section

loc_2923:
2923  CD 59 4C      CALL lcd_print  ; print inline string
2926  4E 20 00      DB "N ", 0  ; inline text 'N ' (normal mode)

loc_2929:
2929  CB 51         BIT 2,C  ; test cfg bit2: spindle-double flag
292B  20 12         JR NZ,loc_293F  ; if bit2 set, show 'DS' (double speed)
292D  CB 69         BIT 5,C  ; test cfg bit5: high-spindle flag
292F  28 07         JR Z,loc_2938  ; if bit5 clear, show 'NS' (normal speed)
2931  CD 59 4C      CALL lcd_print  ; print inline string
2934  48 53 00      DB "HS", 0  ; inline text 'HS' (high spindle speed)
2937  C9            RET  ; done

loc_2938:
2938  CD 59 4C      CALL lcd_print  ; print inline string
293B  4E 53 00      DB "NS", 0  ; inline text 'NS' (normal spindle speed)
293E  C9            RET  ; done

loc_293F:
293F  CD 59 4C      CALL lcd_print  ; print inline string
2942  44 53 00      DB "DS", 0  ; inline text 'DS' (double spindle speed)
2945  C9            RET  ; done

; print size+density portion of media summary (5.25"/3.5", HD/DD/QD) from cfg_byte bits3,7,6
show_size_density:
2946  CB 59         BIT 3,C  ; test cfg bit3: form-factor 5.25 vs 3.5
2948  28 0D         JR Z,loc_2957  ; if bit3 clear, print 3.5" branch
294A  CD 59 4C      CALL lcd_print  ; print inline string
294D  1B 00 35 2E 32 35 +  DB ESC(0x00), "5.25\"", 0  ; inline: LCD cursor esc + '5.25"'
2955  18 0A         JR loc_2961  ; skip to density section

loc_2957:
2957  CD 59 4C      CALL lcd_print  ; print inline string
295A  1B 00 33 2E 35 22 +  DB ESC(0x00), "3.5\"", 0  ; inline: LCD cursor esc + '3.5"'

loc_2961:
2961  CB 79         BIT 7,C  ; test cfg bit7: HD flag
2963  28 0A         JR Z,loc_296F  ; if bit7 clear, check DD/QD instead
2965  CD 59 4C      CALL lcd_print  ; print inline string
2968  1B 80 48 44 20 00  DB ESC(0x80), "HD ", 0  ; inline: LCD cursor esc + 'HD '
296E  C9            RET  ; done

loc_296F:
296F  CB 71         BIT 6,C  ; test cfg bit6: DD vs QD selector
2971  20 0A         JR NZ,loc_297D  ; if bit6 set, branch to QD/DD tie-break at loc_297D

loc_2973:
2973  CD 59 4C      CALL lcd_print  ; print inline string
2976  1B 80 44 44 20 00  DB ESC(0x80), "DD ", 0  ; inline: LCD cursor esc + 'DD '
297C  C9            RET  ; done

loc_297D:
297D  CB 59         BIT 3,C  ; test cfg bit3: form factor for QD/DD tie-break
297F  28 F2         JR Z,loc_2973  ; if bit3 clear, fall back to DD
2981  CD 59 4C      CALL lcd_print  ; print inline string
2984  1B 80 51 44 20 00  DB ESC(0x80), "QD ", 0  ; inline: LCD cursor esc + 'QD '
298A  C9            RET  ; done

; draw 'Form factor 3.5"' menu header
show_ff_35:
298B  CD 59 4C      CALL lcd_print  ; print inline string
298E  0C 46 6F 72 6D 20 +  DB \f, "Form factor 3.5\"", 0  ; inline: form-feed + 'Form factor 3.5"' header
29A0  C9            RET  ; done

; draw 'Form factor 5.25"' menu header
show_ff_525:
29A1  CD 59 4C      CALL lcd_print  ; print inline string
29A4  0C 46 6F 72 6D 20 +  DB \f, "Form factor 5.25\"", 0  ; inline: form-feed + 'Form factor 5.25"' header
29B7  C9            RET  ; done

; draw 'Double density' menu header
show_density_dd:
29B8  CD 59 4C      CALL lcd_print  ; print inline string
29BB  0C 44 6F 75 62 6C +  DB \f, "Double density", 0  ; inline: form-feed + 'Double density' header
29CB  C9            RET  ; done

; draw 'High density' menu header
show_density_hd:
29CC  CD 59 4C      CALL lcd_print  ; print inline string
29CF  0C 48 69 67 68 20 +  DB \f, "High density", 0  ; inline: form-feed + 'High density' header
29DD  C9            RET  ; done

; draw 'Simultaneous mode' menu header
show_mode_simul:
29DE  CD 59 4C      CALL lcd_print  ; print inline string
29E1  0C 53 69 6D 75 6C +  DB \f, "Simultaneous mode", 0  ; inline: form-feed + 'Simultaneous mode' header
29F4  C9            RET  ; done

; draw 'Normal mode' menu header
show_mode_normal:
29F5  CD 59 4C      CALL lcd_print  ; print inline string
29F8  0C 4E 6F 72 6D 61 +  DB \f, "Normal mode", 0  ; inline: form-feed + 'Normal mode' header
2A05  C9            RET  ; done

; draw 'High spindle speed' menu header
show_spindle_high:
2A06  CD 59 4C      CALL lcd_print  ; print inline string
2A09  0C 48 69 67 68 20 +  DB \f, "High spindle speed", 0  ; inline: form-feed + 'High spindle speed' header
2A1D  C9            RET  ; done

; draw 'Normal spindle speed' menu header
show_spindle_normal:
2A1E  CD 59 4C      CALL lcd_print  ; print inline string
2A21  0C 4E 6F 72 6D 61 +  DB \f, "Normal spindle speed", 0  ; inline: form-feed + 'Normal spindle speed' header
2A37  C9            RET  ; done

; draw 'Double spindle speed' menu header
show_spindle_double:
2A38  CD 59 4C      CALL lcd_print  ; print inline string
2A3B  0C 44 6F 75 62 6C +  DB \f, "Double spindle speed", 0  ; inline: form-feed + 'Double spindle speed' header
2A51  C9            RET  ; done
2A52  CD 59 4C      CALL lcd_print  ; print inline string
2A55  0C 4E 6F 20 46 44 +  DB \f, "No FDD", 0  ; inline: form-feed + 'No FDD' message
2A5D  C9            RET  ; done

; set config form factor to 3.5" (cfg_ptr: RES bit3, SET bit6, clear bit1)
set_ff_35:
2A5E  2A 1A 31      LD HL,(cfg_ptr)  ; load pointer to active cfg byte
2A61  CB 9E         RES 3,(HL)  ; clear bit3: form factor 3.5"
2A63  CB F6         SET 6,(HL)  ; set bit6: DD-capable form factor
2A65  18 07         JR loc_2A6E  ; join common clear-bit1 / refresh path

; media-config toggle: select 5.25" form-factor (cfg flags SET3/RES6/RES1), then refresh LCD
set_ff_525:
2A67  2A 1A 31      LD HL,(cfg_ptr)  ; load pointer to active cfg byte
2A6A  CB DE         SET 3,(HL)  ; set bit3: form factor 5.25"
2A6C  CB B6         RES 6,(HL)  ; clear bit6

loc_2A6E:
2A6E  CB 8E         RES 1,(HL)  ; clear bit1 (density/mode default) on cfg byte
2A70  18 44         JR loc_2AB6  ; refresh LCD with 'selected' confirmation
2A72  C9            RET  ; return

; media-config toggle: select DD/double density (cfg flags RES7), then refresh LCD
set_density_dd:
2A73  2A 1A 31      LD HL,(cfg_ptr)  ; load pointer to active cfg byte
2A76  CB BE         RES 7,(HL)  ; clear bit7: select DD (double density)
2A78  18 3C         JR loc_2AB6  ; refresh LCD with 'selected' confirmation
2A7A  C9            RET  ; return

; media-config toggle: select HD/high density (cfg flags SET7/SET6), then refresh LCD
set_density_hd:
2A7B  2A 1A 31      LD HL,(cfg_ptr)  ; load pointer to active cfg byte
2A7E  CB FE         SET 7,(HL)  ; set bit7: select HD (high density)
2A80  CB F6         SET 6,(HL)  ; set bit6: HD-capable form factor
2A82  18 32         JR loc_2AB6  ; refresh LCD with 'selected' confirmation
2A84  C9            RET  ; return

; media-config toggle: enable simultaneous copy mode (cfg flags SET4), refresh LCD
set_mode_simul:
2A85  2A 1A 31      LD HL,(cfg_ptr)  ; load pointer to active cfg byte
2A88  CB E6         SET 4,(HL)  ; set bit4: enable simultaneous copy mode
2A8A  18 2A         JR loc_2AB6  ; refresh LCD with 'selected' confirmation
2A8C  C9            RET  ; return

; media-config toggle: select normal copy mode (cfg flags RES4), refresh LCD
set_mode_normal:
2A8D  2A 1A 31      LD HL,(cfg_ptr)  ; load pointer to active cfg byte
2A90  CB A6         RES 4,(HL)  ; clear bit4: select normal copy mode
2A92  18 22         JR loc_2AB6  ; refresh LCD with 'selected' confirmation
2A94  C9            RET  ; return

; media-config toggle: high spindle speed (cfg flags RES2/SET5), refresh LCD
set_spindle_high:
2A95  2A 1A 31      LD HL,(cfg_ptr)  ; load pointer to active cfg byte
2A98  CB 96         RES 2,(HL)  ; clear bit2: not double spindle
2A9A  CB EE         SET 5,(HL)  ; set bit5: high spindle speed
2A9C  18 18         JR loc_2AB6  ; refresh LCD with 'selected' confirmation
2A9E  C9            RET  ; return

; media-config toggle: normal spindle speed (cfg flags RES2/RES5), refresh LCD
set_spindle_normal:
2A9F  2A 1A 31      LD HL,(cfg_ptr)  ; load pointer to active cfg byte
2AA2  CB 96         RES 2,(HL)  ; clear bit2: not double spindle
2AA4  CB AE         RES 5,(HL)  ; clear bit5: normal spindle speed
2AA6  18 0E         JR loc_2AB6  ; refresh LCD with 'selected' confirmation

; media-config toggle: double spindle speed (cfg flags SET2/RES5), refresh LCD
set_spindle_double:
2AA8  2A 1A 31      LD HL,(cfg_ptr)  ; load pointer to active cfg byte
2AAB  CB D6         SET 2,(HL)  ; set bit2: double spindle speed
2AAD  CB AE         RES 5,(HL)  ; clear bit5
2AAF  18 05         JR loc_2AB6  ; refresh LCD with 'selected' confirmation
2AB1  2A 1A 31      LD HL,(cfg_ptr)  ; load pointer to active cfg byte
2AB4  CB CE         SET 1,(HL)  ; set bit1 on cfg byte (alternate toggle)

loc_2AB6:
2AB6  CD 59 4C      CALL lcd_print  ; print inline string
2AB9  1B C5 73 65 6C 65 +  DB ESC(0xC5), "selected", 0  ; inline: LCD cursor esc(0xC5) + 'selected'
2AC4  21 00 00      LD HL,0x0000  ; HL=0x0000: home LCD cursor position
2AC7  CD 22 4C      CALL lcd_setpos  ; move LCD cursor to top-left
2ACA  C9            RET  ; return

; bit-bang serial EEPROM: I2C start, control 0xA0 (write), then clock data byte E out MSB-first
eeprom_write:
2ACB  CD 39 2B      CALL i2c_start  ; issue I2C start condition on EEPROM bus
2ACE  3E A0         LD A,0xA0  ; A=0xA0: EEPROM control byte, write address
2AD0  CD D4 2A      CALL eeprom_send_byte  ; clock control byte out to EEPROM
2AD3  7B            LD A,E  ; A=E: data byte to transmit next

; bit-bang one byte to the serial config EEPROM
eeprom_send_byte:
2AD4  C5            PUSH BC  ; save BC across bit loop
2AD5  06 08         LD B,0x08  ; B=8: clock out 8 bits MSB-first

loc_2AD7:
2AD7  CD 09 2B      CALL i2c_scl_lo  ; drive SCL low before setting data bit
2ADA  17            RLA  ; rotate MSB of A into carry
2ADB  38 05         JR C,loc_2AE2  ; if bit=1, drive SDA high
2ADD  CD 2B 2B      CALL i2c_sda_lo  ; bit=0: drive SDA low
2AE0  18 03         JR loc_2AE5  ; proceed to clock this bit out

loc_2AE2:
2AE2  CD 1D 2B      CALL i2c_sda_hi  ; drive SDA high for a 1 bit

loc_2AE5:
2AE5  CD F5 2A      CALL eeprom_clk_high  ; pulse SCL high to clock out the bit just placed on SDA
2AE8  10 ED         DJNZ loc_2AD7  ; loop back for the next of 8 EEPROM bits
2AEA  CD EF 2A      CALL eeprom_clk_idle  ; return the I2C bus to idle after the byte
2AED  C1            POP BC  ; restore saved BC
2AEE  C9            RET  ; done

; return bit-banged I2C bus to idle: SCL low, SDA released high, then pulse SCL high w/ settle
eeprom_clk_idle:
2AEF  CD 09 2B      CALL i2c_scl_lo  ; drive SCL low first
2AF2  CD 1D 2B      CALL i2c_sda_hi  ; release SDA high, then fall into SCL-high pulse

; drive I2C SCL high on panel latch (bit5 of 0x4A58/port F0) with a short settle delay
eeprom_clk_high:
2AF5  F5            PUSH AF  ; save AF
2AF6  E5            PUSH HL  ; save HL
2AF7  21 58 4A      LD HL,panel_shadow  ; point at the panel-latch shadow byte
2AFA  7E            LD A,(HL)  ; read current panel latch state
2AFB  F6 20         OR 0x20  ; set bit5 = I2C SCL high
2AFD  77            LD (HL),A  ; store back to shadow
2AFE  D3 F0         OUT (0xF0),A  ; panel — drive updated latch to panel port F0
2B00  21 0A 00      LD HL,0x000A  ; settle-delay count
2B03  CD 22 4C      CALL lcd_setpos  ; reuse lcd_setpos as a short settle delay
2B06  E1            POP HL  ; restore HL
2B07  F1            POP AF  ; restore AF
2B08  C9            RET  ; done

; drive I2C SCL low (clear bit5 of panel latch 0x4A58, OUT port F0)
i2c_scl_lo:
2B09  F5            PUSH AF  ; save AF
2B0A  E5            PUSH HL  ; save HL
2B0B  21 58 4A      LD HL,panel_shadow  ; point at the panel-latch shadow byte
2B0E  7E            LD A,(HL)  ; read current panel latch state
2B0F  E6 DF         AND 0xDF  ; clear bit5 = I2C SCL low
2B11  77            LD (HL),A  ; store back to shadow
2B12  D3 F0         OUT (0xF0),A  ; panel — drive updated latch to panel port F0
2B14  21 0A 00      LD HL,0x000A  ; settle-delay count
2B17  CD 22 4C      CALL lcd_setpos  ; reuse lcd_setpos as a short settle delay
2B1A  E1            POP HL  ; restore HL
2B1B  F1            POP AF  ; restore AF
2B1C  C9            RET  ; done

; release I2C SDA high (set bit4 of panel latch 0x4A58, OUT port F0)
i2c_sda_hi:
2B1D  F5            PUSH AF  ; save AF
2B1E  E5            PUSH HL  ; save HL
2B1F  21 58 4A      LD HL,panel_shadow  ; point at the panel-latch shadow byte
2B22  7E            LD A,(HL)  ; read current panel latch state
2B23  F6 10         OR 0x10  ; set bit4 = release I2C SDA high
2B25  77            LD (HL),A  ; store back to shadow
2B26  D3 F0         OUT (0xF0),A  ; panel — drive updated latch to panel port F0
2B28  E1            POP HL  ; restore HL
2B29  F1            POP AF  ; restore AF
2B2A  C9            RET  ; done

; pull I2C SDA low (clear bit4 of panel latch 0x4A58, OUT port F0)
i2c_sda_lo:
2B2B  F5            PUSH AF  ; save AF
2B2C  E5            PUSH HL  ; save HL
2B2D  21 58 4A      LD HL,panel_shadow  ; point at the panel-latch shadow byte
2B30  7E            LD A,(HL)  ; read current panel latch state
2B31  E6 EF         AND 0xEF  ; clear bit4 = pull I2C SDA low
2B33  77            LD (HL),A  ; store back to shadow
2B34  D3 F0         OUT (0xF0),A  ; panel — drive updated latch to panel port F0
2B36  E1            POP HL  ; restore HL
2B37  F1            POP AF  ; restore AF
2B38  C9            RET  ; done

; I2C start condition (config EEPROM)
i2c_start:
2B39  CD EF 2A      CALL eeprom_clk_idle  ; bring bus to idle before the start edge
2B3C  18 ED         JR i2c_sda_lo  ; pull SDA low while SCL high = I2C start condition

; finish an EEPROM byte transfer: emit ACK clock, release SDA, then delay
eeprom_io:
2B3E  CD 4D 2B      CALL i2c_ack  ; clock out the ACK bit
2B41  CD 1D 2B      CALL i2c_sda_hi  ; release SDA high
2B44  E5            PUSH HL  ; save HL
2B45  21 E8 03      LD HL,0x03E8  ; post-transfer delay count
2B48  CD 22 4C      CALL lcd_setpos  ; reuse lcd_setpos as an inter-byte delay
2B4B  E1            POP HL  ; restore HL
2B4C  C9            RET  ; done

; generate I2C ACK bit: SCL low, SDA low, then pulse SCL high
i2c_ack:
2B4D  CD 09 2B      CALL i2c_scl_lo  ; SCL low
2B50  CD 2B 2B      CALL i2c_sda_lo  ; SDA low = ACK level
2B53  18 A0         JR eeprom_clk_high  ; pulse SCL high to clock the ACK bit

; EEPROM random read: send word address via eeprom_write, then repeated-start read (0xA1)
eeprom_read:
2B55  C5            PUSH BC  ; save BC
2B56  CD CB 2A      CALL eeprom_write  ; send device+word-address (write phase)
2B59  CD 5E 2B      CALL i2c_read_start  ; repeated-start and issue read control byte
2B5C  C1            POP BC  ; restore BC
2B5D  C9            RET  ; done

; issue I2C (re)start and send control byte 0xA1 to address EEPROM for reading
i2c_read_start:
2B5E  CD 39 2B      CALL i2c_start  ; issue (re)start condition
2B61  3E A1         LD A,0xA1  ; EEPROM control byte 0xA1 = read address
2B63  C3 D4 2A      JP eeprom_send_byte  ; shift the control byte out onto the bus

; read one byte from the I2C config EEPROM
i2c_read_byte:
2B66  C5            PUSH BC  ; save BC
2B67  3E 00         LD A,0x00  ; clear accumulator to build the byte
2B69  06 08         LD B,0x08  ; 8 bits to read

loc_2B6B:
2B6B  CD 09 2B      CALL i2c_scl_lo  ; SCL low
2B6E  CD 1D 2B      CALL i2c_sda_hi  ; release SDA so EEPROM can drive it
2B71  CD F5 2A      CALL eeprom_clk_high  ; raise SCL to sample the bit
2B74  4F            LD C,A  ; stash partial byte in C
2B75  DB F0         IN A,(0xF0)  ; panel — read SDA level from panel port F0
2B77  37            SCF  ; assume bit=1 (set carry)
2B78  CB 67         BIT 4,A  ; test SDA (bit4) of the sampled input
2B7A  20 01         JR NZ,loc_2B7D  ; if SDA high, keep carry set
2B7C  3F            CCF  ; SDA low -> clear carry

loc_2B7D:
2B7D  79            LD A,C  ; reload the partial byte
2B7E  17            RLA  ; shift sampled bit in from carry
2B7F  10 EA         DJNZ loc_2B6B  ; loop for the remaining bits
2B81  C1            POP BC  ; restore BC
2B82  C9            RET  ; return byte in A

; map media/geometry config to a drive-geom table index; for cfg==4 add unit 0-3, else code 7/6/3
fdd_geom_index:
2B83  CD 0A 52      CALL media_cfg_index  ; get media/geometry config code
2B86  FE 04         CP 0x04  ; config == 4 (per-unit geometry)?
2B88  20 08         JR NZ,loc_2B92  ; no -> map fixed codes instead
2B8A  47            LD B,A  ; keep base index in B
2B8B  3A 37 31      LD A,(unit_sel)  ; read selected drive unit
2B8E  E6 03         AND 0x03  ; mask to unit 0-3
2B90  80            ADD A,B  ; index = base + unit
2B91  C9            RET  ; return geom index

loc_2B92:
2B92  06 03         LD B,0x03  ; start candidate index at 3
2B94  FE 07         CP 0x07  ; code 7?
2B96  28 0B         JR Z,loc_2BA3  ; yes -> index 3
2B98  05            DEC B  ; next candidate index 2
2B99  FE 06         CP 0x06  ; code 6?
2B9B  28 06         JR Z,loc_2BA3  ; yes -> index 2
2B9D  05            DEC B  ; next candidate index 1
2B9E  FE 03         CP 0x03  ; code 3?
2BA0  28 01         JR Z,loc_2BA3  ; yes -> index 1
2BA2  05            DEC B  ; else index 0

loc_2BA3:
2BA3  78            LD A,B  ; move resolved index into A
2BA4  C9            RET  ; return geom index

; compute track-image buffer pointer: derive head via block_to_chs, then scale by track size
track_buf_ptr:
2BA5  F5            PUSH AF  ; save A (block/sector arg)
2BA6  CD F2 4F      CALL block_to_chs  ; decode block -> C/H/S, head returned in A
2BA9  4F            LD C,A  ; stash head in C
2BAA  F1            POP AF  ; restore original A (track number)

; advance HL by (A-1)*track_size (0x52E0) to reach a track's image slot; returns head in A
track_ptr_scale:
2BAB  3D            DEC A  ; tracks past the first
2BAC  47            LD B,A  ; use as DJNZ loop count
2BAD  79            LD A,C  ; bring head back into A
2BAE  C8            RET Z  ; if no extra tracks, done (head in A)
2BAF  ED 5B E0 52   LD DE,(format_desc+0x3)  ; DE = per-track byte size loaded from format_desc+3

loc_2BB3:
2BB3  19            ADD HL,DE  ; add one track's worth to the pointer
2BB4  10 FD         DJNZ loc_2BB3  ; repeat for each remaining track
2BB6  C9            RET  ; return with head in A

; from the BPB record (IX = installed boot-sector BPB, not format_desc): IX+13/+15 give sectors-per-track/interleave, div32_16 -> sector index
geom_sector_calc:
2BB7  6F            LD L,A  ; A -> L (low byte of dividend)
2BB8  26 00         LD H,0x00  ; clear H
2BBA  5C            LD E,H  ; clear E (high dividend word)
2BBB  54            LD D,H  ; clear D
2BBC  DD 4E 0D      LD C,(IX+13)  ; divisor = sectors/track from the BPB record (IX+13), not format_desc
2BBF  06 00         LD B,0x00  ; high divisor byte = 0
2BC1  CD CE 4E      CALL div32_16  ; 32/16 divide to get sector index
2BC4  0C            INC C  ; make it 1-based
2BC5  79            LD A,C  ; quotient+1 into A
2BC6  45            LD B,L  ; remainder low -> B
2BC7  DD 4E 0F      LD C,(IX+15)  ; load interleave field from the BPB record (IX+15), not format_desc
2BCA  0D            DEC C  ; interleave-1
2BCB  CB 09         RRC C  ; halve interleave, test parity
2BCD  C8            RET Z  ; if it divided evenly, return
2BCE  CB 08         RRC B  ; otherwise also halve remainder in B
2BD0  C9            RET  ; return

; HRD radial-alignment test (head variant a)
hrd_radial_a:
2BD1  CD EC 2B      CALL show_radial_align  ; print the radial-alignment header
2BD4  3E 00         LD A,0x00  ; select radial reading index 0 (drive A)
2BD6  CD 04 2C      CALL hrd_show_radial  ; show that radial measurement
2BD9  C9            RET  ; done

; HRD radial-alignment diag: show header, then display drive-B radial reading (index 1)
hrd_radial_b:
2BDA  CD EC 2B      CALL show_radial_align  ; print the radial-alignment header
2BDD  3E 01         LD A,0x01  ; select radial reading index 1 (drive B)
2BDF  CD 04 2C      CALL hrd_show_radial  ; show that radial measurement
2BE2  C9            RET  ; done

; HRD radial-alignment diag: show header, then display radial reading index 2
hrd_radial_c:
2BE3  CD EC 2B      CALL show_radial_align  ; print the radial-alignment header
2BE6  3E 02         LD A,0x02  ; select radial reading index 2
2BE8  CD 04 2C      CALL hrd_show_radial  ; show that radial measurement
2BEB  C9            RET  ; done

; print the radial-alignment test header line on the LCD
show_radial_align:
2BEC  CD 59 4C      CALL lcd_print  ; print the following literal string to the LCD
2BEF  0C 52 61 64 69 61 +  DB \f, "Radial alignment T", 0  ; inline LCD string: \f clears screen, then 'Radial alignment T'
2C03  C9            RET  ; return past the inline string

; read radial measurement byte (via hrd_radial_ptr[B]) and format it to the LCD
hrd_show_radial:
2C04  C5            PUSH BC  ; save BC
2C05  DD E5         PUSH IX  ; save IX
2C07  47            LD B,A  ; index -> B
2C08  CD 1E 2C      CALL hrd_radial_ptr  ; get pointer to the radial record for this index
2C0B  6E            LD L,(HL)  ; load the measurement byte
2C0C  26 00         LD H,0x00  ; zero-extend to 16 bits
2C0E  11 00 00      LD DE,0x0000  ; no fractional part
2C11  06 02         LD B,0x02  ; field width 2 digits
2C13  0E 30         LD C,0x30  ; pad char '0'
2C15  3E 12         LD A,0x12  ; LCD column 0x12 for the value
2C17  CD FC 05      CALL num_to_lcd  ; format the number to the LCD
2C1A  DD E1         POP IX  ; restore IX
2C1C  C1            POP BC  ; restore BC
2C1D  C9            RET  ; done

; return pointer to the radial-measurement record for index B (index 0 -> 0x3179)
hrd_radial_ptr:
2C1E  78            LD A,B  ; index -> A
2C1F  B7            OR A  ; index == 0?
2C20  20 04         JR NZ,loc_2C26  ; no -> compute record address
2C22  21 79 31      LD HL,hrd_model_idx+0x1  ; index 0 record at fixed 0x3179
2C25  C9            RET  ; return pointer

loc_2C26:
2C26  05            DEC B  ; index -= 1
2C27  3A 78 31      LD A,(hrd_model_idx)  ; load per-model stride
2C2A  87            ADD A,A  ; *2
2C2B  87            ADD A,A  ; *4 (record size)
2C2C  80            ADD A,B  ; add adjusted index
2C2D  6F            LD L,A  ; offset -> L
2C2E  26 00         LD H,0x00  ; clear H
2C30  11 7A 31      LD DE,hrd_model_idx+0x2  ; base of radial record table
2C33  19            ADD HL,DE  ; HL = base + offset
2C34  C9            RET  ; return pointer

; print the ECC diagnostic test header line on the LCD
hrd_show_ecc:
2C35  CD 59 4C      CALL lcd_print  ; print the following literal string to the LCD
2C38  0C 45 63 63 65 6E +  DB \f, "Eccentricity", 0  ; inline LCD string: \f clears screen, then 'Eccentricity'
2C46  C9            RET  ; return past the inline string

; print the azimuth-alignment test header line on the LCD
hrd_show_azimuth:
2C47  CD 59 4C      CALL lcd_print  ; print the following literal string to the LCD
2C4A  0C 48 65 61 64 20 +  DB \f, "Head azimuth", 0  ; inline LCD string: \f clears screen, then 'Head azimuth'
2C58  C9            RET  ; return past the inline string

; print the head-positioner test header line on the LCD
hrd_show_positioner:
2C59  CD 59 4C      CALL lcd_print  ; print the following literal string to the LCD
2C5C  0C 50 6F 73 69 74 +  DB \f, "Positioner", \r, \n, "hystheresis", 0  ; inline LCD string: 'Positioner' / 'hystheresis' (2 lines)
2C75  C9            RET  ; return past the inline string

; print the spindle-speed test header line on the LCD
hrd_show_spindle:
2C76  CD 59 4C      CALL lcd_print  ; print the following literal string to the LCD
2C79  0C 53 70 69 6E 64 +  DB \f, "Spindle motor speed", 0  ; inline LCD string: \f clears screen, then 'Spindle motor speed'
2C8E  C9            RET  ; return past the inline string

loc_2C8F:
2C8F  CD 59 4C      CALL lcd_print  ; print the 'HRD unreadable' error message on the LCD
2C92  1B C0 48 52 44 20 +  DB ESC(0xC0), "HRD unreadable", 0  ; inline ESC-positioned LCD string: cursor to line2, 'HRD unreadable', NUL-terminated
2CA3  CD 57 07      CALL drive_cfg_latch  ; restore/latch the per-drive config after the aborted measurement
2CA6  3E 01         LD A,0x01  ; arg = 1: acknowledge/consume one keypress
2CA8  CD 43 4D      CALL keypad_debounce  ; wait for debounced keypad input before returning
2CAB  C9            RET  ; return to caller

; HRD alignment-run entry (variant A): set test index 1, fall into measure+display tail
hrd_run_a:
2CAC  3E 01         LD A,0x01  ; variant A: select test index 1 (radial single-head)
2CAE  18 13         JR loc_2CC3  ; fall into shared measure+display tail

; HRD alignment-run entry (variant B): set test index 2, fall into measure+display tail
hrd_run_b:
2CB0  3E 02         LD A,0x02  ; variant B: select test index 2
2CB2  18 0F         JR loc_2CC3  ; fall into shared measure+display tail

; HRD alignment-run entry (variant C): set test index 0/flag 1, fall into measure+display tail
hrd_run_c:
2CB4  3E 00         LD A,0x00  ; variant C: test index 0
2CB6  06 01         LD B,0x01  ; sub-mode flag = 1
2CB8  C3 C3 2C      JP loc_2CC3  ; enter shared measure+display tail

; HRD alignment-run entry (variant D): set test index 0/flag 2, fall into measure+display tail
hrd_run_d:
2CBB  3E 00         LD A,0x00  ; variant D: test index 0
2CBD  06 02         LD B,0x02  ; sub-mode flag = 2
2CBF  18 02         JR loc_2CC3  ; enter shared measure+display tail

; HRD alignment run: measure radial, print head0/head1 scaled values, then jump to test's handler
hrd_run_e:
2CC1  AF            XOR A  ; variant E: test index 0
2CC2  47            LD B,A  ; sub-mode flag = 0

loc_2CC3:
2CC3  CD 5B 2D      CALL hrd_radial_measure  ; run the radial measurement for the selected test (A=idx, B=flag)
2CC6  DA 8F 2C      JP C,loc_2C8F  ; carry set = read failed -> show 'HRD unreadable' and bail
2CC9  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 for the result readout
2CCC  2A A1 31      LD HL,(hrd_hd0)  ; load head-0 measured value
2CCF  3E 44         LD A,0x44  ; prefix char 'D' (head-0 label) for the scaled display
2CD1  CD EE 2C      CALL hrd_show_scaled  ; print head-0 value scaled to display units
2CD4  3A A5 31      LD A,(hrd_test_idx)  ; reload current test index
2CD7  FE 01         CP 0x01  ; is this the single-head (index 1) test?
2CD9  28 08         JR Z,loc_2CE3  ; yes -> skip the head-1 readout
2CDB  2A A3 31      LD HL,(hrd_hd1)  ; load head-1 measured value

loc_2CDE:
2CDE  3E 4F         LD A,0x4F  ; prefix char 'O' (head-1 label) for the scaled display
2CE0  CD EE 2C      CALL hrd_show_scaled  ; print head-1 value scaled to display units

loc_2CE3:
2CE3  21 88 31      LD HL,hrd_test_tbl+0x2  ; point at this test's record +2 (handler pointer field)
2CE6  CD 2C 2D      CALL hrd_rec_ptr  ; index HL to the current test's record
2CE9  5E            LD E,(HL)  ; fetch handler address low byte
2CEA  23            INC HL  ; advance to high byte
2CEB  56            LD D,(HL)  ; fetch handler address high byte
2CEC  D5            PUSH DE  ; push the handler address as a return target
2CED  C9            RET  ; tail-jump into the per-test result handler

; scale a signed measurement to display units: value * K / 10000, K = hrd_test_tbl[test].scale (ROM const: 422 radial/ecc/positioner um, 696 azimuth, 1 spindle-RPM); print preserving sign
hrd_show_scaled:
2CEE  F5            PUSH AF  ; preserve prefix char in A
2CEF  E5            PUSH HL  ; preserve the value pointer
2CF0  21 86 31      LD HL,hrd_test_tbl  ; point at start of this test's record table
2CF3  CD 2C 2D      CALL hrd_rec_ptr  ; index HL to the current test's scale record
2CF6  7E            LD A,(HL)  ; read scale factor K (value*K/10000)
2CF7  23            INC HL  ; advance to flags byte
2CF8  4E            LD C,(HL)  ; read display flags into C
2CF9  D1            POP DE  ; recover the 16-bit value into DE
2CFA  CB 7A         BIT 7,D  ; test sign bit of the value
2CFC  CB BA         RES 7,D  ; strip sign bit to get magnitude
2CFE  F5            PUSH AF  ; save sign flag across the arithmetic
2CFF  CD 05 4F      CALL mul16  ; multiply magnitude by scale factor K
2D02  01 10 27      LD BC,0x2710  ; divisor = 10000
2D05  CD CE 4E      CALL div32_16  ; divide product by 10000 -> display units
2D08  C1            POP BC  ; recover flags byte into C
2D09  F1            POP AF  ; recover sign flag
2D0A  F5            PUSH AF  ; re-save sign flag
2D0B  C5            PUSH BC  ; re-save flags byte
2D0C  0E 20         LD C,0x20  ; pad/fill char = space
2D0E  06 03         LD B,0x03  ; field width = 3 digits
2D10  CD FC 05      CALL num_to_lcd  ; render the scaled number right-justified on the LCD
2D13  C1            POP BC  ; restore flags byte
2D14  F1            POP AF  ; restore sign flag
2D15  3D            DEC A  ; prefix char - 1 = base LCD column for the sign glyph
2D16  CB 71         BIT 6,C  ; test display-flags bit 6 (sign-suffix enable)
2D18  C0            RET NZ  ; flags bit 6 set -> skip the sign glyph, return
2D19  F6 80         OR 0x80  ; OR 0x80 -> HD44780 set-DDRAM-address (line2) cursor command
2D1B  32 28 2D      LD (hrd_show_scaled+0x3A),A  ; self-modify the ESC position arg in the sign-glyph string
2D1E  3A A5 31      LD A,(hrd_test_idx)  ; reload test index
2D21  FE 01         CP 0x01  ; single-head test?
2D23  C8            RET Z  ; yes -> skip printing the sign glyph
2D24  CD 59 4C      CALL lcd_print  ; print the sign glyph string
2D27  1B 00 2D 00   DB ESC(0x00), "-", 0  ; inline string: ESC-arg, '-' (sign), NUL
2D2B  C9            RET  ; return to caller

; index into the per-test result record table (stride 5) selected by hrd_test_idx
hrd_rec_ptr:
2D2C  3A A5 31      LD A,(hrd_test_idx)  ; load current test index
2D2F  4F            LD C,A  ; keep copy of index in C
2D30  87            ADD A,A  ; index*2
2D31  87            ADD A,A  ; index*4
2D32  81            ADD A,C  ; index*5 (record stride = 5)
2D33  5F            LD E,A  ; offset low byte
2D34  16 00         LD D,0x00  ; offset high byte = 0
2D36  19            ADD HL,DE  ; advance HL to the selected record
2D37  C9            RET  ; return with HL at record
2D38  C9            RET  ; return (padding/alt entry)
2D39  F5            PUSH AF  ; save A across the error report
2D3A  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2
2D3D  CD 59 4C      CALL lcd_print  ; print the reading-error message
2D40  1B C0 48 52 44 20 +  DB ESC(0xC0), "HRD reading error", 0  ; inline LCD string: line2, 'HRD reading error', NUL
2D54  3E 05         LD A,0x05  ; beep pattern id = 5
2D56  CD E3 49      CALL buzzer_beep  ; sound the error buzzer
2D59  F1            POP AF  ; restore A
2D5A  C9            RET  ; return to caller

; HRD alignment measure: seek+capture 4 windows (hd0 A/B @ image_buf+0/+0x2000, hd1 A/B @ +0x4000/+0x6000); per-head result = burst-position difference (hrd_find_burst, SBC); 10 samples -> hrd_median_filter -> hrd_hd0/hd1
hrd_radial_measure:
2D5B  21 A5 31      LD HL,hrd_test_idx  ; point at hrd_test_idx
2D5E  77            LD (HL),A  ; store test index
2D5F  23            INC HL  ; advance to sub-mode flag byte
2D60  70            LD (HL),B  ; store sub-mode flag
2D61  3E 04         LD A,0x04  ; retry counter = 4
2D63  32 49 31      LD (op_flag_49),A  ; seed the per-attempt retry counter
2D66  DD 21 A7 31   LD IX,hrd_test_idx+0x2  ; IX = start of the 10-sample capture buffer
2D6A  3E 64         LD A,0x64  ; PIT mode word 0x64 for the measurement timer
2D6C  D3 AC         OUT (0xAC),A  ; pit_ctrl — program PIT control register
2D6E  3E 00         LD A,0x00  ; counter reload value = 0
2D70  D3 A4         OUT (0xA4),A  ; pit_c1 — load PIT counter 1
2D72  3E 0E         LD A,0x0E  ; ctrl-latch value: select line + data for measurement setup
2D74  D3 9C         OUT (0x9C),A  ; ctrl_latch — drive the 0x9C addressable control latch
2D76  CD 4F 07      CALL set_drive_cfg  ; apply per-drive datarate/config for the read
2D79  CD 57 0C      CALL show_in_progress  ; show 'in progress' indicator on the LCD
2D7C  CD A9 03      CALL lcd_home3  ; position LCD cursor to line 3 home
2D7F  06 0A         LD B,0x0A  ; sample loop count = 10

loc_2D81:
2D81  C5            PUSH BC  ; save the sample-loop counter

loc_2D82:
2D82  21 A5 31      LD HL,hrd_test_idx  ; point at hrd_test_idx (retry re-entry)
2D85  7E            LD A,(HL)  ; load test index
2D86  23            INC HL  ; advance to sub-mode flag

loc_2D87:
2D87  B7            OR A  ; test index zero?
2D88  20 07         JR NZ,loc_2D91  ; nonzero -> handle index 1/2 track selection
2D8A  46            LD B,(HL)  ; index 0: use stored sub-mode flag as track/drive param

loc_2D8B:
2D8B  CD 1E 2C      CALL hrd_radial_ptr  ; map the param to the radial read pointer/track
2D8E  7E            LD A,(HL)  ; load the resolved track/param
2D8F  18 0E         JR loc_2D9F  ; proceed to the seek+read

loc_2D91:
2D91  FE 01         CP 0x01  ; test index == 1?
2D93  20 04         JR NZ,loc_2D99  ; no -> try index 2
2D95  06 03         LD B,0x03  ; index 1: param = 3
2D97  18 F2         JR loc_2D8B  ; go resolve the read pointer

loc_2D99:
2D99  FE 02         CP 0x02  ; test index == 2?
2D9B  06 04         LD B,0x04  ; index 2: param = 4
2D9D  18 EC         JR loc_2D8B  ; go resolve the read pointer

loc_2D9F:
2D9F  CD BA 2E      CALL hrd_seek_read  ; seek to track and capture the alignment windows
2DA2  47            LD B,A  ; keep returned FDC status in B
2DA3  21 8A 31      LD HL,hrd_test_tbl+0x4  ; point at this test's record +4 (status mask field)
2DA6  CD 2C 2D      CALL hrd_rec_ptr  ; index HL to the current test's record
2DA9  4E            LD C,(HL)  ; load the expected status mask
2DAA  78            LD A,B  ; get the FDC status
2DAB  A1            AND C  ; mask off the relevant status bits
2DAC  B9            CP C  ; do the masked bits match the expected mask?
2DAD  28 09         JR Z,loc_2DB8  ; match -> read succeeded, process windows
2DAF  21 49 31      LD HL,op_flag_49  ; point at the retry counter
2DB2  35            DEC (HL)  ; decrement remaining retries
2DB3  20 CD         JR NZ,loc_2D82  ; retries left -> re-attempt the sample
2DB5  C1            POP BC  ; discard the sample-loop counter
2DB6  37            SCF  ; set carry to signal measurement failure
2DB7  C9            RET  ; return with error

loc_2DB8:
2DB8  21 00 80      LD HL,image_buf  ; point at head-0 window A (image_buf+0)
2DBB  CD 08 30      CALL hrd_find_burst  ; locate the sync burst position in window A
2DBE  22 A1 31      LD (hrd_hd0),HL  ; stash head-0 A burst position
2DC1  21 00 A0      LD HL,image_buf+0x2000  ; point at head-0 window B (image_buf+0x2000)
2DC4  CD 08 30      CALL hrd_find_burst  ; locate the burst position in window B
2DC7  54            LD D,H  ; move B position into DE (high)
2DC8  5D            LD E,L  ; move B position into DE (low)
2DC9  2A A1 31      LD HL,(hrd_hd0)  ; reload head-0 A burst position
2DCC  B7            OR A  ; clear carry for the subtraction
2DCD  ED 52         SBC HL,DE  ; head-0 radial offset = A - B
2DCF  22 A1 31      LD (hrd_hd0),HL  ; store head-0 offset
2DD2  21 00 C0      LD HL,image_buf+0x4000  ; point at head-1 window A (image_buf+0x4000)
2DD5  CD 08 30      CALL hrd_find_burst  ; locate the burst position in window A
2DD8  22 A3 31      LD (hrd_hd1),HL  ; stash head-1 A burst position
2DDB  21 00 E0      LD HL,image_buf+0x6000  ; point at head-1 window B (image_buf+0x6000)
2DDE  CD 08 30      CALL hrd_find_burst  ; locate the burst position in window B
2DE1  54            LD D,H  ; move B position into DE (high)
2DE2  5D            LD E,L  ; move B position into DE (low)
2DE3  2A A3 31      LD HL,(hrd_hd1)  ; reload head-1 A burst position
2DE6  B7            OR A  ; clear carry for the subtraction
2DE7  ED 52         SBC HL,DE  ; head-1 radial offset = A - B
2DE9  22 A3 31      LD (hrd_hd1),HL  ; store head-1 offset
2DEC  DD 75 14      LD (IX+20),L  ; write head-1 offset low into sample slot +20
2DEF  DD 74 15      LD (IX+21),H  ; write head-1 offset high into sample slot +21
2DF2  2A A1 31      LD HL,(hrd_hd0)  ; reload head-0 offset
2DF5  DD 75 00      LD (IX+0),L  ; write head-0 offset low into sample slot +0
2DF8  DD 74 01      LD (IX+1),H  ; write head-0 offset high into sample slot +1
2DFB  DD 23         INC IX  ; advance sample pointer (low)
2DFD  DD 23         INC IX  ; advance sample pointer (high) -> next sample slot
2DFF  C1            POP BC  ; recover the sample-loop counter
2E00  10 02         DJNZ loc_2E04  ; more samples? loop
2E02  18 03         JR loc_2E07  ; all 10 samples captured -> continue to median filter

loc_2E04:
2E04  C3 81 2D      JP loc_2D81  ; take the next of the 10 samples

loc_2E07:
2E07  CD 09 07      CALL motor_ready_wait  ; wait for spindle motor to reach speed before measuring
2E0A  CD 57 07      CALL drive_cfg_latch  ; latch per-drive config (datarate/select) for the test
2E0D  21 A7 31      LD HL,hrd_test_idx+0x2  ; point HL at head-0 radial test sample buffer (+2)
2E10  06 0A         LD B,0x0A  ; take median of 10 samples
2E12  CD 84 30      CALL hrd_median_filter  ; median-filter the 10 head-0 readings, HL -> result
2E15  22 A1 31      LD (hrd_hd0),HL  ; store filtered head-0 radial position
2E18  21 BB 31      LD HL,param_tables+0x2  ; point HL at head-1 sample table (param_tables+2)
2E1B  06 0A         LD B,0x0A  ; 10 samples for head 1
2E1D  CD 84 30      CALL hrd_median_filter  ; median-filter the 10 head-1 readings
2E20  22 A3 31      LD (hrd_hd1),HL  ; store filtered head-1 radial position
2E23  B7            OR A  ; clear carry: signal success
2E24  C9            RET  ; return to caller

; HRD positioner hysteresis: step in/out, difference of approach positions (um)
hrd_hysteresis:
2E25  AF            XOR A  ; step direction 0 (inward)
2E26  06 01         LD B,0x01  ; step 1 track
2E28  CD 5B 2D      CALL hrd_radial_measure  ; measure radial position after inward approach
2E2B  2A A1 31      LD HL,(hrd_hd0)  ; load head-0 approach position
2E2E  DA 8F 2C      JP C,loc_2C8F  ; on measure error, abort to error handler
2E31  E5            PUSH HL  ; save inward-approach position
2E32  CD 4F 07      CALL set_drive_cfg  ; re-latch drive config for opposite step
2E35  06 02         LD B,0x02  ; step count 2 tracks
2E37  CD 1E 2C      CALL hrd_radial_ptr  ; get pointer to track-step target value
2E3A  7E            LD A,(HL)  ; fetch the target track number
2E3B  CD E2 06      CALL fdc_step_to_track  ; seek/step heads to that track
2E3E  AF            XOR A  ; step direction 0
2E3F  06 01         LD B,0x01  ; step 1 track
2E41  CD 5B 2D      CALL hrd_radial_measure  ; measure radial position after outward approach
2E44  2A A1 31      LD HL,(hrd_hd0)  ; load head-0 result of this approach
2E47  D1            POP DE  ; recover the saved inward-approach position
2E48  DA 8F 2C      JP C,loc_2C8F  ; on measure error, abort to error handler
2E4B  ED 53 A3 31   LD (hrd_hd1),DE  ; store outward-approach position
2E4F  CB 7C         BIT 7,H  ; test sign bit of head-0 value
2E51  CB BC         RES 7,H  ; clear sign bit to get magnitude
2E53  C4 EB 30      CALL NZ,neg16  ; negate if it was negative (abs value)
2E56  E5            PUSH HL  ; save abs inward value
2E57  2A A3 31      LD HL,(hrd_hd1)  ; load outward-approach position
2E5A  CB 7C         BIT 7,H  ; test its sign bit
2E5C  CB BC         RES 7,H  ; clear sign bit to get magnitude
2E5E  C4 EB 30      CALL NZ,neg16  ; negate if negative (abs value)
2E61  D1            POP DE  ; recover abs inward value into DE
2E62  B7            OR A  ; clear carry for clean subtract
2E63  ED 52         SBC HL,DE  ; compute hysteresis = |out| - |in|
2E65  CB 7C         BIT 7,H  ; test sign of the difference
2E67  C4 EB 30      CALL NZ,neg16  ; negate if negative (abs hysteresis in um)
2E6A  3E 03         LD A,0x03  ; test result index 3 (hysteresis display slot)
2E6C  32 A5 31      LD (hrd_test_idx),A  ; store which HRD test result to show
2E6F  C3 DE 2C      JP loc_2CDE  ; jump to shared result-display routine

; HRD spindle RPM: time index period (8253 c1/c2), RPM = 9230769/ticks
hrd_spindle_rpm:
2E72  CD 4F 07      CALL set_drive_cfg  ; latch drive config for the selected unit
2E75  CD 57 0C      CALL show_in_progress  ; show 'in progress' prompt on LCD

loc_2E78:
2E78  3A 37 31      LD A,(unit_sel)  ; load currently selected drive unit
2E7B  47            LD B,A  ; pass unit number in B
2E7C  3E 01         LD A,0x01  ; mode 1: measure index period
2E7E  CD DB 37      CALL index_period_timer  ; time one index-pulse period via 8253
2E81  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 for the RPM readout
2E84  30 08         JR NC,loc_2E8E  ; skip zero-handling if timer returned a value (NC)
2E86  B7            OR A  ; clear carry
2E87  21 00 00      LD HL,0x0000  ; zero the RPM value (no index/timeout)
2E8A  54            LD D,H  ; clear D (high byte of divisor operand)
2E8B  5C            LD E,H  ; clear E (low byte)
2E8C  28 11         JR Z,loc_2E9F  ; if zero, display 0 RPM directly

loc_2E8E:
2E8E  2A 9F 31      LD HL,(rpm_residual)  ; load measured index period residual
2E91  CD EB 30      CALL neg16  ; negate it (make positive for division)
2E94  4D            LD C,L  ; low byte of divisor into C
2E95  44            LD B,H  ; high byte into B
2E96  11 8C 00      LD DE,0x008C  ; DE = 0x008C, high word of 9230769 dividend
2E99  21 B1 D9      LD HL,0xD9B1  ; HL = 0xD9B1, low word of dividend
2E9C  CD CE 4E      CALL div32_16  ; RPM = 9230769 / ticks via 32/16 divide

loc_2E9F:
2E9F  0E 20         LD C,0x20  ; leading-space pad char for LCD field
2EA1  06 03         LD B,0x03  ; field width 3 digits (leading zeros suppressed)
2EA3  3E 47         LD A,0x47  ; LCD column 0x47 for the RPM value
2EA5  CD FC 05      CALL num_to_lcd  ; print the RPM number to the LCD
2EA8  CD 7A 30      CALL show_rpm_suffix  ; append 'RPM' unit suffix
2EAB  AF            XOR A  ; key mode 0: poll
2EAC  CD 89 4D      CALL get_key  ; poll front-panel key
2EAF  28 C7         JR Z,loc_2E78  ; loop back and keep updating RPM if no key
2EB1  3E 01         LD A,0x01  ; key mode 1: wait/consume
2EB3  CD 89 4D      CALL get_key  ; consume the pressed key
2EB6  CD 57 07      CALL drive_cfg_latch  ; restore normal drive config latch
2EB9  C9            RET  ; return

; HRD read-back: step both heads to cyl 0x3133, arm per-drive DMA, read all sides, CRC-verify, build 4-bit success mask in op_word
hrd_seek_read:
2EBA  DD E5         PUSH IX  ; save IX (drive block base) across routine
2EBC  21 33 31      LD HL,cur_track  ; point HL at current cylinder value
2EBF  47            LD B,A  ; stash requested track in B
2EC0  96            SUB (HL)  ; delta = requested - current track
2EC1  78            LD A,B  ; restore requested track to A
2EC2  28 17         JR Z,loc_2EDB  ; already on track: skip stepping
2EC4  FA D4 2E      JP M,loc_2ED4  ; negative delta: step outward branch
2EC7  3D            DEC A  ; adjust step count by one
2EC8  CD E2 06      CALL fdc_step_to_track  ; step heads toward target track
2ECB  3C            INC A  ; restore step count

loc_2ECC:
2ECC  CD A9 03      CALL lcd_home3  ; refresh LCD line 3 during seek
2ECF  CD E2 06      CALL fdc_step_to_track  ; final step to reach target track
2ED2  18 07         JR loc_2EDB  ; join common post-seek path

loc_2ED4:
2ED4  3C            INC A  ; adjust step count for outward move
2ED5  CD E2 06      CALL fdc_step_to_track  ; step heads outward
2ED8  3D            DEC A  ; restore step count
2ED9  18 F1         JR loc_2ECC  ; continue to LCD refresh / final step

loc_2EDB:
2EDB  DD 21 EB 4A   LD IX,drive_blk_a  ; IX -> drive A control block
2EDF  FD 21 06 4B   LD IY,drive_blk_b  ; IY -> drive B control block
2EE3  DD 77 00      LD (IX+0),A  ; store target track in drive A block
2EE6  FD 77 00      LD (IY+0),A  ; store target track in drive B block
2EE9  3E FE         LD A,0xFE  ; sector-count/EOT marker 0xFE
2EEB  DD 77 07      LD (IX+7),A  ; set drive A block EOT field (+7)
2EEE  FD 77 07      LD (IY+7),A  ; set drive B block EOT field (+7)
2EF1  AF            XOR A  ; clear A (head 0)
2EF2  DD 77 01      LD (IX+1),A  ; drive A reads head 0
2EF5  3A 63 31      LD A,(side_sel)  ; load selected side/head for drive B
2EF8  FD 77 01      LD (IY+1),A  ; drive B reads the selected side
2EFB  21 00 80      LD HL,image_buf  ; HL = image buffer base 0x8000
2EFE  DD 75 0C      LD (IX+12),L  ; drive A DMA target low byte
2F01  DD 74 0D      LD (IX+13),H  ; drive A DMA target high byte
2F04  21 00 C0      LD HL,image_buf+0x4000  ; HL = image_buf+0x4000 (drive B target)
2F07  FD 75 0C      LD (IY+12),L  ; drive B DMA target low byte
2F0A  FD 74 0D      LD (IY+13),H  ; drive B DMA target high byte
2F0D  AF            XOR A  ; clear A
2F0E  32 34 31      LD (op_word),A  ; reset op_word success mask
2F11  3A E8 52      LD A,(format_desc+0xB)  ; load format flag byte (format_desc+0xB)
2F14  CB 67         BIT 4,A  ; test bit 4: dual-head-per-pass format?
2F16  28 41         JR Z,loc_2F59  ; if clear, use single-head read path
2F18  CD 83 3A      CALL fdc_read_dual  ; read both heads via DMA in one pass
2F1B  CD C0 2F      CALL hrd_read_verify  ; wait/CRC-verify the read
2F1E  38 31         JR C,loc_2F51  ; on error, skip remaining reads
2F20  CB C6         SET 0,(HL)  ; mark side-0 head-A success (op_word bit0)
2F22  CD D4 2F      CALL hrd_result_verify  ; verify FDC result status too
2F25  38 2A         JR C,loc_2F51  ; on error, skip remaining reads
2F27  CB CE         SET 1,(HL)  ; mark bit1 success
2F29  3E 02         LD A,0x02  ; transfer count 2 (second half of track)
2F2B  CD F1 2F      CALL fdc_set_xfer_cnt  ; set DMA transfer count
2F2E  21 00 A0      LD HL,image_buf+0x2000  ; HL = image_buf+0x2000 (drive A 2nd target)
2F31  DD 75 0C      LD (IX+12),L  ; drive A DMA target low byte
2F34  DD 74 0D      LD (IX+13),H  ; drive A DMA target high byte
2F37  21 00 E0      LD HL,image_buf+0x6000  ; HL = image_buf+0x6000 (drive B 2nd target)
2F3A  FD 75 0C      LD (IY+12),L  ; drive B DMA target low byte
2F3D  FD 74 0D      LD (IY+13),H  ; drive B DMA target high byte
2F40  CD 83 3A      CALL fdc_read_dual  ; read both heads, second pass
2F43  CD C0 2F      CALL hrd_read_verify  ; wait/CRC-verify
2F46  38 09         JR C,loc_2F51  ; on error, skip to result assembly
2F48  CB D6         SET 2,(HL)  ; mark bit2 success
2F4A  CD D4 2F      CALL hrd_result_verify  ; verify FDC result status
2F4D  38 02         JR C,loc_2F51  ; on error, skip
2F4F  CB DE         SET 3,(HL)  ; mark bit3 success

loc_2F51:
2F51  DD E1         POP IX  ; restore IX
2F53  3A 34 31      LD A,(op_word)  ; load accumulated success mask
2F56  E6 0F         AND 0x0F  ; keep low 4 bits (per-side success)
2F58  C9            RET  ; return with 4-bit mask in A

loc_2F59:
2F59  3E 01         LD A,0x01  ; transfer count 1 (single head)
2F5B  CD F1 2F      CALL fdc_set_xfer_cnt  ; set DMA transfer count
2F5E  3E 01         LD A,0x01  ; drive/DMA channel 1
2F60  CD 18 3A      CALL fdc_send_dma  ; issue single-head DMA read
2F63  CD C0 2F      CALL hrd_read_verify  ; wait/CRC-verify
2F66  38 E9         JR C,loc_2F51  ; on error, skip to result assembly
2F68  CB C6         SET 0,(HL)  ; mark bit0 success
2F6A  3E 02         LD A,0x02  ; transfer count 2
2F6C  CD F1 2F      CALL fdc_set_xfer_cnt  ; set DMA transfer count
2F6F  21 00 A0      LD HL,image_buf+0x2000  ; HL = image_buf+0x2000
2F72  DD 75 0C      LD (IX+12),L  ; drive A DMA target low byte
2F75  DD 74 0D      LD (IX+13),H  ; drive A DMA target high byte
2F78  3E 01         LD A,0x01  ; DMA channel 1
2F7A  CD 18 3A      CALL fdc_send_dma  ; issue single-head DMA read
2F7D  CD C0 2F      CALL hrd_read_verify  ; wait/CRC-verify
2F80  38 CF         JR C,loc_2F51  ; on error, skip to result assembly
2F82  CB CE         SET 1,(HL)  ; mark bit1 success
2F84  3E 01         LD A,0x01  ; transfer count 1
2F86  CD F1 2F      CALL fdc_set_xfer_cnt  ; set DMA transfer count
2F89  3A 63 31      LD A,(side_sel)  ; load selected side/head
2F8C  32 EC 4A      LD (drive_blk_a+0x1),A  ; set drive A block head field to selected side
2F8F  21 00 C0      LD HL,image_buf+0x4000  ; HL = image_buf+0x4000
2F92  DD 75 0C      LD (IX+12),L  ; drive A DMA target low byte
2F95  DD 74 0D      LD (IX+13),H  ; drive A DMA target high byte
2F98  3E 01         LD A,0x01  ; DMA channel 1
2F9A  CD 18 3A      CALL fdc_send_dma  ; issue single-head DMA read
2F9D  CD C0 2F      CALL hrd_read_verify  ; wait/CRC-verify
2FA0  38 AF         JR C,loc_2F51  ; on error, skip to result assembly
2FA2  CB D6         SET 2,(HL)  ; mark bit2 success
2FA4  3E 02         LD A,0x02  ; transfer count 2
2FA6  CD F1 2F      CALL fdc_set_xfer_cnt  ; set DMA transfer count
2FA9  21 00 E0      LD HL,image_buf+0x6000  ; HL = image_buf+0x6000
2FAC  DD 75 0C      LD (IX+12),L  ; drive A DMA target low byte
2FAF  DD 74 0D      LD (IX+13),H  ; drive A DMA target high byte
2FB2  3E 01         LD A,0x01  ; DMA channel 1
2FB4  CD 18 3A      CALL fdc_send_dma  ; issue single-head DMA read
2FB7  CD C0 2F      CALL hrd_read_verify  ; wait/CRC-verify
2FBA  38 95         JR C,loc_2F51  ; on error, skip to result assembly
2FBC  CB DE         SET 3,(HL)  ; mark bit3 success
2FBE  18 91         JR loc_2F51  ; join result assembly path

; wait for FDC read to complete, then CRC/status-check fdc0_result via chk_fdc_crc
hrd_read_verify:
2FC0  DD E5         PUSH IX  ; save IX across verify
2FC2  DD 21 DD 52   LD IX,format_desc  ; IX -> format descriptor block
2FC6  CD 8C 0E      CALL wait_read_done  ; wait for FDC read/DMA to complete
2FC9  E5            PUSH HL  ; save HL (op_word pointer)
2FCA  21 85 4A      LD HL,fdc_result_buf  ; HL -> fdc0 result/status buffer

loc_2FCD:
2FCD  CD DC 2F      CALL chk_fdc_crc  ; validate the FDC result block pointed to by HL (good-termination check)
2FD0  E1            POP HL  ; restore caller's HL
2FD1  DD E1         POP IX  ; restore caller's IX
2FD3  C9            RET  ; return with carry = result invalid

; verify fdc0_result: normal termination (ST0&0xC0==0x40) plus sector/data-mark bits set
hrd_result_verify:
2FD4  DD E5         PUSH IX  ; save IX across the check
2FD6  E5            PUSH HL  ; save HL across the check
2FD7  21 85 4A      LD HL,fdc_result_buf  ; point at FDC0 7-byte result buffer to verify it
2FDA  18 F1         JR loc_2FCD  ; shared exit: run check then pop HL/IX and return

; validate FDC 7-byte result: ST0 top bits==0x40 and bit5 of ST1/ST2 set (good termination)
chk_fdc_crc:
2FDC  7E            LD A,(HL)  ; read ST0 from the result block
2FDD  E6 C0         AND 0xC0  ; isolate interrupt-code bits (top two)
2FDF  FE 40         CP 0x40  ; test for normal termination code 0x40
2FE1  20 0C         JR NZ,loc_2FEF  ; not normal termination -> fail
2FE3  23            INC HL  ; advance to ST1
2FE4  CB 6E         BIT 5,(HL)  ; check ST1 bit5 (data/CRC/address-mark ok)
2FE6  28 07         JR Z,loc_2FEF  ; ST1 bit clear -> fail
2FE8  23            INC HL  ; advance to ST2
2FE9  CB 6E         BIT 5,(HL)  ; check ST2 bit5 (data-field CRC/mark ok)
2FEB  28 02         JR Z,loc_2FEF  ; ST2 bit clear -> fail
2FED  B7            OR A  ; clear carry = result valid
2FEE  C9            RET  ; return success

loc_2FEF:
2FEF  37            SCF  ; set carry = result invalid
2FF0  C9            RET  ; return failure

; store transfer sector count A into per-drive blocks and derived end-count (0x4AFF-1) fields
fdc_set_xfer_cnt:
2FF1  32 05 4B      LD (drive_blk_a+0x1A),A  ; store transfer sector count into drive block A
2FF4  32 20 4B      LD (drive_blk_b+0x1A),A  ; store same count into drive block B
2FF7  32 EE 4A      LD (drive_blk_a+0x3),A  ; mirror count into drive block A field +3
2FFA  32 09 4B      LD (drive_blk_b+0x3),A  ; mirror count into drive block B field +3
2FFD  2A FF 4A      LD HL,(drive_blk_a+0x14)  ; load the run's end-count base (drive_blk_a+0x14)
3000  2B            DEC HL  ; compute end-count-1
3001  22 F9 4A      LD (drive_blk_a+0xE),HL  ; store derived end count into drive block A
3004  22 14 4B      LD (drive_blk_b+0xE),HL  ; store derived end count into drive block B
3007  C9            RET  ; return

; scan captured read data for alignment sync bursts, return byte offset
hrd_find_burst:
3008  3E FE         LD A,0xFE  ; select the capture DRAM bank 0xFE
300A  D3 B0         OUT (0xB0),A  ; dram_bank — commit bank select to hardware latch
300C  06 00         LD B,0x00  ; clear the consecutive-sync counter

loc_300E:
300E  7E            LD A,(HL)  ; read first byte of a 3-byte group
300F  23            INC HL  ; advance
3010  86            ADD A,(HL)  ; add second byte
3011  23            INC HL  ; advance
3012  86            ADD A,(HL)  ; add third byte
3013  23            INC HL  ; advance to next group
3014  FE FF         CP 0xFF  ; does the group sum equal 0xFF (a sync burst)?
3016  28 F6         JR Z,loc_300E  ; yes -> keep scanning for start of run
3018  04            INC B  ; count one sync group found
3019  2B            DEC HL  ; back up one byte
301A  2B            DEC HL  ; back up second byte to realign to group start
301B  78            LD A,B  ; check the run length so far
301C  FE 07         CP 0x07  ; need 7 consecutive sync groups
301E  20 EE         JR NZ,loc_300E  ; not yet 7 -> keep scanning
3020  7C            LD A,H  ; take high byte of the found offset
3021  E6 1F         AND 0x1F  ; keep low bits of H -> bank-relative burst offset
3023  67            LD H,A  ; store masked high byte back
3024  C9            RET  ; return HL = burst byte offset

hrd_disp_radial:
3025  CD 59 4C      CALL lcd_print  ; print the radial-alignment LCD template
3028  1B C0 48 64 30 1B +  DB ESC(0xC0), "Hd0", ESC(0xC7), \x01, "m", ESC(0xCB), "Hd1", ESC(0xD2), \x01, "m", 0  ; LCD string: cursor moves + "Hd0"/"Hd1" head labels with um value fields

loc_303B:
303B  3E 01         LD A,0x01  ; select key-input mode 1
303D  C3 89 4D      JP get_key  ; poll for a keypress (tail-call)

hrd_disp_ecc:
3040  CD 59 4C      CALL lcd_print  ; print the eccentricity LCD template
3043  1B C7 01 6D 00  DB ESC(0xC7), \x01, "m", 0  ; LCD string: value field + "m" suffix for eccentricity readout
3048  18 F1         JR loc_303B  ; join common key-poll exit

hrd_disp_azimuth:
304A  CD 59 4C      CALL lcd_print  ; print the azimuth LCD template
304D  1B C0 48 64 30 1B +  DB ESC(0xC0), "Hd0", ESC(0xC7), "'", ESC(0xCB), "Hd1", ESC(0xD2), "'", 0  ; LCD string: "Hd0"/"Hd1" azimuth fields with minute-of-arc suffix
305E  18 DB         JR loc_303B  ; join common key-poll exit

hrd_disp_positioner:
3060  CD 59 4C      CALL lcd_print  ; print the positioner-hysteresis LCD template
3063  1B C0 68 79 73 74 +  DB ESC(0xC0), "hystheresis   ", ESC(0xD2), \x01, "m", 0  ; LCD string: "hystheresis" label with um value field
3078  18 C1         JR loc_303B  ; join common key-poll exit

; print the RPM units suffix string on the LCD
show_rpm_suffix:
307A  CD 59 4C      CALL lcd_print  ; print the RPM display suffix
307D  1B CA 72 70 6D 00  DB ESC(0xCA), "rpm", 0  ; LCD string: cursor move + "rpm" units
3083  C9            RET  ; return

; median filter: bubble-sort B signed 16-bit samples, sum the middle ones and divide (sign-preserved)
hrd_median_filter:
3084  48            LD C,B  ; C = sample count as bubble-sort outer bound
3085  0D            DEC C  ; one fewer pass than samples

loc_3086:
3086  C5            PUSH BC  ; save loop counter across a pass
3087  E5            PUSH HL  ; save list base pointer
3088  E5            PUSH HL  ; duplicate list base onto stack
3089  DD E1         POP IX  ; point IX at start of the sample list
308B  41            LD B,C  ; B = comparisons remaining this pass

loc_308C:
308C  DD 7E 00      LD A,(IX+0)  ; load low byte of sample[i]
308F  DD 96 02      SUB (IX+2)  ; subtract low byte of sample[i+1]
3092  DD 7E 01      LD A,(IX+1)  ; load high byte of sample[i]
3095  DD 9E 03      SBC A,(IX+3)  ; subtract-with-borrow high byte (signed compare)
3098  FA B3 30      JP M,loc_30B3  ; already in order -> skip swap
309B  DD 5E 00      LD E,(IX+0)  ; read sample[i] low for swap
309E  DD 56 02      LD D,(IX+2)  ; read sample[i+1] low
30A1  DD 72 00      LD (IX+0),D  ; write neighbour low into sample[i]
30A4  DD 73 02      LD (IX+2),E  ; write sample[i] low into neighbour
30A7  DD 5E 01      LD E,(IX+1)  ; read sample[i] high
30AA  DD 56 03      LD D,(IX+3)  ; read sample[i+1] high
30AD  DD 72 01      LD (IX+1),D  ; write neighbour high into sample[i]
30B0  DD 73 03      LD (IX+3),E  ; write sample[i] high into neighbour

loc_30B3:
30B3  DD 23         INC IX  ; step IX to next word (byte 1 of 2)
30B5  DD 23         INC IX  ; step IX to next word (byte 2 of 2)
30B7  10 D3         DJNZ loc_308C  ; continue inner comparison pass
30B9  E1            POP HL  ; restore list base
30BA  C1            POP BC  ; restore outer counter
30BB  10 C9         DJNZ loc_3086  ; run remaining bubble-sort passes
30BD  41            LD B,C  ; B = count-1 (working copy of sorted length)
30BE  05            DEC B  ; B = count-2
30BF  48            LD C,B  ; C = count-2 = number of middle samples (divisor)
30C0  05            DEC B  ; B = count-3 = inner add-loop count (sample[1] seeded separately)
30C1  E5            PUSH HL  ; reload sorted list base
30C2  DD E1         POP IX  ; point IX at sorted samples
30C4  DD 6E 02      LD L,(IX+2)  ; seed accumulator low with sample[1]
30C7  DD 66 03      LD H,(IX+3)  ; seed accumulator high with sample[1]

loc_30CA:
30CA  DD 5E 04      LD E,(IX+4)  ; add next middle sample low
30CD  DD 56 05      LD D,(IX+5)  ; add next middle sample high
30D0  19            ADD HL,DE  ; accumulate 16-bit sum
30D1  DD 23         INC IX  ; step IX to next word (byte 1)
30D3  DD 23         INC IX  ; step IX to next word (byte 2)
30D5  10 F3         DJNZ loc_30CA  ; sum all middle samples
30D7  CB 7C         BIT 7,H  ; test sign of the sum
30D9  F5            PUSH AF  ; remember sign flag
30DA  28 03         JR Z,loc_30DF  ; sum positive -> divide directly
30DC  CD EB 30      CALL neg16  ; negative -> negate to divide by magnitude

loc_30DF:
30DF  11 00 00      LD DE,0x0000  ; high divisor word = 0
30E2  43            LD B,E  ; B = 0 (divisor high byte)
30E3  CD CE 4E      CALL div32_16  ; divide summed middle samples by the count
30E6  F1            POP AF  ; recover the saved sign
30E7  C8            RET Z  ; positive result -> return as-is
30E8  CB FC         SET 7,H  ; restore negative sign on the quotient
30EA  C9            RET  ; return signed median

; negate 16-bit value in HL (compute 0 - HL)
neg16:
30EB  5D            LD E,L  ; copy HL low into E
30EC  54            LD D,H  ; copy HL high into D
30ED  21 00 00      LD HL,0x0000  ; clear HL for subtraction
30F0  B7            OR A  ; clear carry before subtract
30F1  ED 52         SBC HL,DE  ; HL = 0 - HL (two's-complement negate)
30F3  C9            RET  ; return negated value

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
; serialization: 32-bit serial number, low word
serial_num_lo:
3168  00 00                                           |..|
; serialization: 32-bit serial number, high word
serial_num_hi:
316A  00 00                                           |..|
; serialization: increment added to the number per copy
serial_incr:
316C  00                                              |.|
; serialization: target cylinder for the stamp
serial_cyl:
316D  00                                              |.|
; serialization: target head for the stamp
serial_head:
316E  00                                              |.|
; serialization: target sector for the stamp
serial_sector:
316F  01                                              |.|
; serialization: byte offset within the sector
serial_offset:
3170  00 00                                           |..|
; serialization: image bank for the stamp (via OUT 0xB0)
serial_bank:
3172  00                                              |.|
; serialization: computed write address in the image
serial_addr:
3173  00 00                                           |..|
; serialization: scaled byte pointer for the stamp
serial_ptr:
3175  00 00 00                                        |...|
; HRD head/model index
hrd_model_idx:
3178  00 00 10 27 14 22 20 4F 2C 4C 28 4F 2C 4C       |...'." O,L(O,L|
; hrd_test_tbl: 5 per-test records { scale K:word, display handler:word, result mask:byte } (idx 0-4 = radial/eccentricity/azimuth/positioner/spindle)
hrd_test_tbl:
3186  A6 01 25 30 0F                                  |..%0.|   ; radial      K=422  handler=hrd_disp_radial      mask=0x0F
318B  A6 01 40 30 03                                  |..@0.|   ; eccentric.  K=422  handler=hrd_disp_ecc         mask=0x03
3190  B8 02 4A 30 0F                                  |..J0.|   ; azimuth     K=696  handler=hrd_disp_azimuth     mask=0x0F
3195  A6 01 60 30 0F                                  |..`0.|   ; positioner  K=422  handler=hrd_disp_positioner  mask=0x0F
319A  01 00 7A 30 0F                                  |..z0.|   ; spindle     K=1    handler=show_rpm_suffix      mask=0x0F

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

; fmt_param_tbl: 8 built-in disk formats, packed 19-byte BPB { secsz/256, spc, resv:w, nFAT, root:w, total:w, media, spf:w, spt:w, heads:w, hidden:3 }. NOTE: UNREFERENCED by firmware code
fmt_param_tbl:
326E  02 02 01 00 02 70 00 A0 05 F9 03 00 09 00 02 00 00 00 00 |.....p.............|   ; 720K 3.5" DD   1440 sec   9 spt  2h  F9  root 112  spc 2  spf 3
fmt_1440k:
3281  02 01 01 00 02 E0 00 40 0B F0 09 00 12 00 02 00 00 00 00 |.......@...........|   ; 1.44M 3.5" HD  2880 sec  18 spt  2h  F0  root 224  spc 1  spf 9
fmt_720k_b:
3294  02 02 01 00 02 90 00 A0 05 F9 03 00 09 00 02 00 00 00 00 |...................|   ; 720K variant   1440 sec   9 spt  2h  F9  root 144  spc 2  spf 3
fmt_1200k:
32A7  02 01 01 00 02 E0 00 60 09 F9 07 00 0F 00 02 00 00 00 00 |.......`...........|   ; 1.2M 5.25" HD  2400 sec  15 spt  2h  F9  root 224  spc 1  spf 7
fmt_160k:
32BA  02 01 01 00 02 40 00 40 01 FE 01 00 08 00 01 00 00 00 00 |.....@.@...........|   ; 160K 5.25" SS  320 sec    8 spt  1h  FE  root  64  spc 1  spf 1
fmt_180k:
32CD  02 01 01 00 02 40 00 68 01 FC 02 00 09 00 01 00 00 00 00 |.....@.h...........|   ; 180K 5.25" SS  360 sec    9 spt  1h  FC  root  64  spc 1  spf 2
fmt_320k:
32E0  02 02 01 00 02 70 00 80 02 FF 01 00 08 00 02 00 00 00 00 |.....p.............|   ; 320K 5.25" DS  640 sec    8 spt  2h  FF  root 112  spc 2  spf 1
fmt_360k:
32F3  02 02 01 00 02 70 00 D0 02 FD 02 00 09 00 02 00 00 00 |.....p............|   ; 360K 5.25" DS  720 sec    9 spt  2h  FD  root 112  spc 2  spf 2

fat12_template:
3305  EB 4E 90 4A 75 6D 62 6F 20 20 20                |.N.Jumbo   |
3310  20 20 20 20 20 20 20 20 20 20 20 46 41 54 31 32 20 20 20 |           FAT12   |
3323  E8 10 00 4E 6F 6E 20 73 79 73 74 65 6D 20 64 69 73 6B 00 5B B4 0E 2E 8A 07 3C 00 74 05 CD 10 43 EB F2 30 E4 CD 16 EA 00 00 FF FF |...Non system disk.[.....<.t...C..0........|

fmt_buf1:
334E  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
335E  00                                              |.|
335F  F5            PUSH AF  ; save A (caller's value byte)
3360  C5            PUSH BC  ; save BC
3361  D5            PUSH DE  ; save DE
3362  E5            PUSH HL  ; save HL
3363  DD E5         PUSH IX  ; save IX
3365  FD E5         PUSH IY  ; save IY
3367  32 87 33      LD (fmt_buf2),A  ; stash A byte into fmt_buf2 for hex display
336A  22 88 33      LD (fmt_buf2+0x1),HL  ; stash HL word into fmt_buf2+1
336D  21 87 33      LD HL,fmt_buf2  ; point at the 3-byte hex-dump buffer
3370  3E 03         LD A,0x03  ; byte count = 3 for the hex dump
3372  CD 3B 4F      CALL lcd_dump_hex  ; render buffer as hex on the display
3375  CD 43 4D      CALL keypad_debounce  ; wait/debounce the keypad
3378  CD 8D 06      CALL lcd_clear_line1  ; clear LCD line 1
337B  32 4C 31      LD (fmt_mode),A  ; record returned key/mode into fmt_mode
337E  FD E1         POP IY  ; restore IY
3380  DD E1         POP IX  ; restore IX
3382  E1            POP HL  ; restore HL
3383  D1            POP DE  ; restore DE
3384  C1            POP BC  ; restore BC
3385  F1            POP AF  ; restore A
3386  C9            RET  ; return

fmt_buf2:
3387  00 00 00                                        |...|
retry_ctr:
338A  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
339A  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |................|
33AA  00 00 00 00 00 00 00 00                         |........|

; top-level FDC op dispatcher: mask op (A&0x7F), pick drive block A/B from B.bit0, decode class B&0xE0 to a handler and JP
fdc_op_dispatch:
33B2  DD E5         PUSH IX  ; save IX
33B4  E5            PUSH HL  ; save HL
33B5  FD E5         PUSH IY  ; save IY
33B7  C5            PUSH BC  ; save BC
33B8  E6 7F         AND 0x7F  ; strip top bit -> raw op code
33BA  F5            PUSH AF  ; stash op code in alt A
33BB  08            EX AF,AF'  ; swap to alt register set
33BC  3E 01         LD A,0x01  ; default per-drive block active flag = 1
33BE  32 05 4B      LD (drive_blk_a+0x1A),A  ; mark drive block A active
33C1  32 20 4B      LD (drive_blk_b+0x1A),A  ; mark drive block B active
33C4  78            LD A,B  ; take the drive/flags byte from B
33C5  E6 1F         AND 0x1F  ; isolate low 5 bits (drive selector)
33C7  08            EX AF,AF'  ; keep selector in alt A
33C8  FD 21 06 4B   LD IY,drive_blk_b  ; default IY -> drive block B
33CC  FE 01         CP 0x01  ; is drive selector == 1?
33CE  20 04         JR NZ,loc_33D4  ; no -> keep block B
33D0  FD 21 EB 4A   LD IY,drive_blk_a  ; yes -> IY = drive block A

loc_33D4:
33D4  08            EX AF,AF'  ; restore op code into A
33D5  F5            PUSH AF  ; save op code for the handler
33D6  78            LD A,B  ; reload flags byte from B
33D7  E6 E0         AND 0xE0  ; isolate op class bits [7:5]
33D9  21 06 34      LD HL,fdc_format_build  ; default handler = format-build
33DC  28 26         JR Z,loc_3404  ; class 0 -> dispatch
33DE  21 A2 34      LD HL,fdc_build_20  ; handler for class 0x20
33E1  FE 20         CP 0x20  ; class == 0x20?
33E3  28 1F         JR Z,loc_3404  ; yes -> dispatch
33E5  21 AA 34      LD HL,fdc_build_40  ; handler for class 0x40
33E8  FE 40         CP 0x40  ; class == 0x40?
33EA  28 18         JR Z,loc_3404  ; yes -> dispatch
33EC  21 F9 34      LD HL,fdc_build_60  ; handler for class 0x60
33EF  FE 60         CP 0x60  ; class == 0x60?
33F1  28 11         JR Z,loc_3404  ; yes -> dispatch
33F3  21 FD 34      LD HL,fdc_build_80  ; handler for class 0x80
33F6  FE 80         CP 0x80  ; class == 0x80?
33F8  28 0A         JR Z,loc_3404  ; yes -> dispatch
33FA  21 7C 35      LD HL,fdc_build_A0  ; handler for class 0xA0
33FD  FE A0         CP 0xA0  ; class == 0xA0?
33FF  28 03         JR Z,loc_3404  ; yes -> dispatch
3401  21 80 35      LD HL,fdc_build_C0  ; fall-through handler for class 0xC0

loc_3404:
3404  F1            POP AF  ; recover op code for the handler
3405  E9            JP (HL)  ; jump to the selected build handler

; build FDC format command parameters (rate/precomp/sector fields)
fdc_format_build:
3406  CD 23 37      CALL set_fdc_pending  ; mark an FDC operation pending
3409  FE 02         CP 0x02  ; compare op parameter with 2
340B  26 02         LD H,0x02  ; H = 2 (default sector-size/rate selector)
340D  30 02         JR NC,loc_3411  ; param >= 2 -> keep H=2
340F  26 01         LD H,0x01  ; param < 2 -> H = 1

loc_3411:
3411  FD 74 12      LD (IY+18),H  ; store H into drive-block field +18 (mode/flag from caller)
3414  CD 0E 37      CALL panel_bit6_on  ; set panel latch bit6 via port 0xF0 (flags preserved)
3417  FE 06         CP 0x06  ; compare command code against 0x06 (density/format boundary)
3419  26 00         LD H,0x00  ; field +22 default value = 0
341B  F5            PUSH AF  ; save CP 0x06 flags across the rate call
341C  C5            PUSH BC  ; save BC across the rate call
341D  3E 02         LD A,0x02  ; rate value 2 -> fdc_rate_reg (via store_rate_precomp)
341F  06 28         LD B,0x28  ; precomp 0x28 -> fdc_precomp_reg
3421  CD 66 48      CALL store_rate_precomp  ; store rate=2/precomp=0x28 into fdc_rate_reg/fdc_precomp_reg shadows
3424  C1            POP BC  ; restore BC
3425  F1            POP AF  ; restore CP 0x06 flags
3426  30 0D         JR NC,loc_3435  ; cmd>=6: keep rate=2, field +22 stays 0
3428  26 02         LD H,0x02  ; cmd<6: field +22 = 2
342A  F5            PUSH AF  ; save command code
342B  C5            PUSH BC  ; save BC
342C  3E 00         LD A,0x00  ; rate value 0 -> fdc_rate_reg
342E  06 00         LD B,0x00  ; precomp 0 -> fdc_precomp_reg
3430  CD 66 48      CALL store_rate_precomp  ; override shadows with rate=0/precomp=0
3433  C1            POP BC  ; restore BC
3434  F1            POP AF  ; restore command code

loc_3435:
3435  FD 74 16      LD (IY+22),H  ; store field +22 (data-rate marker, 0 or 2 by command)
3438  26 01         LD H,0x01  ; H=1 constant flag
343A  FD 74 17      LD (IY+23),H  ; store 1 into drive-block field +23 (enable/step flag)
343D  FE 05         CP 0x05  ; compare command code against 0x05
343F  26 2A         LD H,0x2A  ; assume 42 sectors (0x2A) for field +4
3441  2E 45         LD L,0x45  ; assume sector-size/gap byte 0x45 for field +16
3443  38 12         JR C,loc_3457  ; cmd<5: commit these params
3445  26 1B         LD H,0x1B  ; else 27 sectors (0x1B)
3447  2E 4A         LD L,0x4A  ; sector-size/gap byte 0x4A
3449  28 0C         JR Z,loc_3457  ; cmd==5: commit these params
344B  FE 07         CP 0x07  ; compare command code against 0x07
344D  26 2A         LD H,0x2A  ; 42 sectors (0x2A)
344F  2E 44         LD L,0x44  ; sector-size/gap byte 0x44
3451  38 04         JR C,loc_3457  ; cmd<7: commit these params
3453  26 1B         LD H,0x1B  ; else 27 sectors (0x1B)
3455  2E 50         LD L,0x50  ; sector-size/gap byte 0x50

loc_3457:
3457  FD 74 04      LD (IY+4),H  ; store sectors-per-track into drive-block field +4
345A  FD 75 10      LD (IY+16),L  ; store sector-size/gap byte into field +16
345D  DD 21 B4 4A   LD IX,fdc_gap_tbl  ; point IX at FDC gap-length lookup table
3461  D9            EXX  ; swap to alt register set for index math
3462  06 00         LD B,0x00  ; B=0 high byte of table index
3464  4F            LD C,A  ; C=command code as table offset
3465  DD 09         ADD IX,BC  ; index into fdc_gap_tbl by command code
3467  D9            EXX  ; restore main register set
3468  DD 66 00      LD H,(IX+0)  ; load gap-length byte for this command
346B  FD 74 03      LD (IY+3),H  ; store gap length into drive-block field +3
346E  FD 74 13      LD (IY+19),H  ; mirror gap length into field +19
3471  FE 04         CP 0x04  ; compare command code against 0x04
3473  26 50         LD H,0x50  ; cmd>=4: 80-cyl geometry marker 0x50
3475  30 02         JR NC,loc_3479  ; if cmd>=4 keep 0x50
3477  26 28         LD H,0x28  ; else 40-cyl marker 0x28

loc_3479:
3479  FD 74 11      LD (IY+17),H  ; store cylinder/geometry marker into field +17
347C  21 01 02      LD HL,0x0201  ; HL=0x0201: head-count 2 / sector-base 1
347F  FD 74 02      LD (IY+2),H  ; store 2 (heads/sides) into field +2
3482  FD 75 05      LD (IY+5),L  ; store 1 (first sector) into field +5
3485  21 00 02      LD HL,0x0200  ; HL=0x0200
3488  FD 75 14      LD (IY+20),L  ; store 0 into field +20 (low)
348B  FD 74 15      LD (IY+21),H  ; store 2 into field +21 (high)
348E  21 01 0F      LD HL,0x0F01  ; HL=0x0F01: FDC gap 0x0F / count 1
3491  FD 74 18      LD (IY+24),H  ; store 0x0F (format gap) into field +24
3494  FD 75 19      LD (IY+25),L  ; store 1 into field +25
3497  26 01         LD H,0x01  ; H=1 constant
3499  FD 74 06      LD (IY+6),H  ; store 1 into field +6 (retry/enable flag)
349C  CD 51 37      CALL fdc_dma_from_blk  ; run the FDC/DMA read from the drive block just built
349F  C3 83 35      JP loc_3583  ; join common tail at loc_3583

; op-word bits7-5=0x20 handler: set FDC pending, H=2, rejoin build at loc_3411
fdc_build_20:
34A2  CD 23 37      CALL set_fdc_pending  ; mark FDC operation pending (fdc_op_flags=1)
34A5  26 02         LD H,0x02  ; H=2 -> field +18 mode value
34A7  C3 11 34      JP loc_3411  ; rejoin the parameter-build path at loc_3411

; op-word bits7-5=0x40 handler: build write/verify FDC rate+precomp+gap params
fdc_build_40:
34AA  FE 02         CP 0x02  ; compare command code against 0x02
34AC  26 02         LD H,0x02  ; cmd>=2: field +18 value H=2
34AE  30 02         JR NC,loc_34B2  ; branch keeping H=2
34B0  26 01         LD H,0x01  ; else H=1

loc_34B2:
34B2  FD 74 12      LD (IY+18),H  ; store mode into drive-block field +18
34B5  FE 06         CP 0x06  ; compare command code against 0x06
34B7  26 01         LD H,0x01  ; field +22 candidate = 1
34B9  F5            PUSH AF  ; save CP 0x06 flags
34BA  C5            PUSH BC  ; save BC
34BB  3E 01         LD A,0x01  ; rate value 1 -> fdc_rate_reg
34BD  06 00         LD B,0x00  ; precomp 0 -> fdc_precomp_reg
34BF  CD 66 48      CALL store_rate_precomp  ; store rate=1/precomp=0 into shadow regs
34C2  C1            POP BC  ; restore BC
34C3  F1            POP AF  ; restore CP 0x06 flags
34C4  30 05         JR NC,loc_34CB  ; cmd>=6: take alt rate/pending path at loc_34CB
34C6  CD 0E 37      CALL panel_bit6_on  ; cmd<6: set panel bit6 via port 0xF0 (flags preserved)
34C9  38 13         JR C,loc_34DE  ; carry still set (cmd<6): commit with rate=1, skip alt path

loc_34CB:
34CB  CD 23 37      CALL set_fdc_pending  ; mark FDC operation pending
34CE  CD 0E 37      CALL panel_bit6_on  ; set panel latch bit6 via port 0xF0
34D1  26 00         LD H,0x00  ; field +22 = 0
34D3  F5            PUSH AF  ; save command code
34D4  C5            PUSH BC  ; save BC
34D5  3E 02         LD A,0x02  ; rate value 2 -> fdc_rate_reg
34D7  06 28         LD B,0x28  ; precomp 0x28 -> fdc_precomp_reg
34D9  CD 66 48      CALL store_rate_precomp  ; store rate=2/precomp=0x28 into shadow regs
34DC  C1            POP BC  ; restore BC
34DD  F1            POP AF  ; restore command code

loc_34DE:
34DE  FD 74 16      LD (IY+22),H  ; store field +22 (data-rate marker)
34E1  CD 23 37      CALL set_fdc_pending  ; mark FDC operation pending
34E4  26 01         LD H,0x01  ; H=1 constant flag
34E6  FD 74 17      LD (IY+23),H  ; store 1 into field +23
34E9  FE 05         CP 0x05  ; compare command code against 0x05
34EB  26 2A         LD H,0x2A  ; 42 sectors (0x2A)
34ED  2E 40         LD L,0x40  ; sector-size/gap byte 0x40
34EF  DA 57 34      JP C,loc_3457  ; cmd<5: commit params via loc_3457
34F2  26 1B         LD H,0x1B  ; else 27 sectors (0x1B)
34F4  2E 4C         LD L,0x4C  ; sector-size/gap byte 0x4C
34F6  C3 57 34      JP loc_3457  ; commit params via loc_3457

; op-word bits7-5=0x60 handler: H=2, enter the 0x40 build body at loc_34B2
fdc_build_60:
34F9  26 02         LD H,0x02  ; H=2 -> field +18 mode value
34FB  18 B5         JR loc_34B2  ; enter the 0x40 build body at loc_34B2

; op-word bits7-5=0x80 handler: build params with unit_sel-dependent pending, alt density
fdc_build_80:
34FD  FE 02         CP 0x02  ; compare command code against 0x02
34FF  26 02         LD H,0x02  ; cmd>=2: field +18 value H=2
3501  30 02         JR NC,loc_3505  ; branch keeping H=2
3503  26 01         LD H,0x01  ; else H=1

loc_3505:
3505  FD 74 12      LD (IY+18),H  ; store mode into drive-block field +18
3508  F5            PUSH AF  ; save command code across the unit-select test
3509  3A 37 31      LD A,(unit_sel)  ; load currently selected drive/unit code (unit_sel)
350C  FE 83         CP 0x83  ; unit_sel == 0x83?
350E  28 1A         JR Z,loc_352A  ; yes: clear-pending path
3510  FE 87         CP 0x87  ; unit_sel == 0x87?
3512  28 16         JR Z,loc_352A  ; yes: clear-pending path
3514  FE 86         CP 0x86  ; unit_sel == 0x86?
3516  28 12         JR Z,loc_352A  ; yes: clear-pending path
3518  FE A3         CP 0xA3  ; unit_sel == 0xA3?
351A  28 0E         JR Z,loc_352A  ; yes: clear-pending path
351C  FE A7         CP 0xA7  ; unit_sel == 0xA7?
351E  28 0A         JR Z,loc_352A  ; yes: clear-pending path
3520  FE A6         CP 0xA6  ; unit_sel == 0xA6?
3522  28 06         JR Z,loc_352A  ; yes: clear-pending path
3524  F1            POP AF  ; restore command code
3525  CD 23 37      CALL set_fdc_pending  ; other units: mark FDC operation pending
3528  18 04         JR loc_352E  ; continue to rate/precomp build

loc_352A:
352A  F1            POP AF  ; restore command code
352B  CD 2B 37      CALL clr_fdc_pending  ; clear FDC pending for these units

loc_352E:
352E  FE 06         CP 0x06  ; compare command code against 0x06
3530  26 00         LD H,0x00  ; field +22 = 0
3532  F5            PUSH AF  ; save CP 0x06 flags
3533  C5            PUSH BC  ; save BC
3534  3E 02         LD A,0x02  ; rate value 2 -> fdc_rate_reg
3536  06 28         LD B,0x28  ; precomp 0x28 -> fdc_precomp_reg
3538  CD 66 48      CALL store_rate_precomp  ; store rate=2/precomp=0x28 into shadow regs
353B  C1            POP BC  ; restore BC
353C  F1            POP AF  ; restore CP 0x06 flags
353D  30 05         JR NC,loc_3544  ; cmd>=6: take alt rate path at loc_3544
353F  CD 0E 37      CALL panel_bit6_on  ; cmd<6: set panel bit6 via port 0xF0 (flags preserved)
3542  38 10         JR C,loc_3554  ; carry set (cmd<6): commit, keep rate=2

loc_3544:
3544  26 00         LD H,0x00  ; field +22 = 0
3546  CD 1B 37      CALL clr_ctrl_bit6  ; clear panel latch bit6 via port 0xF0
3549  F5            PUSH AF  ; save command code
354A  C5            PUSH BC  ; save BC
354B  3E 03         LD A,0x03  ; rate value 3 -> fdc_rate_reg
354D  06 A3         LD B,0xA3  ; precomp 0xA3 -> fdc_precomp_reg
354F  CD 66 48      CALL store_rate_precomp  ; store rate=3/precomp=0xA3 into shadow regs
3552  C1            POP BC  ; restore BC
3553  F1            POP AF  ; restore command code

loc_3554:
3554  FD 74 16      LD (IY+22),H  ; store field +22 (data-rate marker)
3557  26 01         LD H,0x01  ; H=1 constant flag
3559  FD 74 17      LD (IY+23),H  ; store 1 into field +23
355C  FE 05         CP 0x05  ; compare command code against 0x05
355E  26 2A         LD H,0x2A  ; 42 sectors (0x2A)
3560  2E 50         LD L,0x50  ; sector-size/gap byte 0x50
3562  DA 57 34      JP C,loc_3457  ; cmd<5: commit params via loc_3457
3565  26 1B         LD H,0x1B  ; else 27 sectors (0x1B)
3567  2E 41         LD L,0x41  ; sector-size/gap byte 0x41
3569  CA 57 34      JP Z,loc_3457  ; cmd==5: commit params via loc_3457
356C  FE 06         CP 0x06  ; compare command code against 0x06
356E  26 2A         LD H,0x2A  ; 42 sectors (0x2A)
3570  2E 50         LD L,0x50  ; sector-size/gap byte 0x50
3572  CA 57 34      JP Z,loc_3457  ; cmd==6: commit params via loc_3457
3575  26 1B         LD H,0x1B  ; else 27 sectors (0x1B)
3577  2E 5A         LD L,0x5A  ; sector-size/gap byte 0x5A
3579  C3 57 34      JP loc_3457  ; commit params via loc_3457

; op-word bits7-5=0xA0 handler: H=2, enter the 0x80 build body at loc_3505
fdc_build_A0:
357C  26 02         LD H,0x02  ; H=2 -> field +18 mode value
357E  18 85         JR loc_3505  ; enter the 0x80 build body at loc_3505

; op-word bits7-5=0xC0/0xE0 handler: JP fdc_format_build
fdc_build_C0:
3580  C3 06 34      JP fdc_format_build  ; 0xC0/0xE0 op: dispatch to fdc_format_build

loc_3583:
3583  F1            POP AF  ; restore masked op code (saved at dispatch entry)
3584  C1            POP BC  ; restore BC (drive count in C)
3585  08            EX AF,AF'  ; stash op code in AF' while testing loop count
3586  79            LD A,C  ; A = remaining drive count from C
3587  B7            OR A  ; test if any drives remain to process
3588  CA FE 36      JP Z,loc_36FE  ; no drives left: exit to loc_36FE
358B  08            EX AF,AF'  ; recover op code from AF'
358C  FD 21 06 4B   LD IY,drive_blk_b  ; default IY to drive block B
3590  FE 01         CP 0x01  ; masked op == 1? select drive block A vs B
3592  20 04         JR NZ,loc_3598  ; if not 1, keep drive block B
3594  FD 21 EB 4A   LD IY,drive_blk_a  ; op==1: use drive block A

loc_3598:
3598  26 02         LD H,0x02  ; seed value 2 for op-record type/count field
359A  FD 74 12      LD (IY+18),H  ; store 2 into drive-op record field 18
359D  26 00         LD H,0x00  ; clear H to build 16-bit index from sub-command
359F  69            LD L,C  ; L = sub-command number in C
35A0  2D            DEC L  ; index = C-1 (sub-commands numbered from 1)
35A1  E5            PUSH HL  ; stash index
35A2  D1            POP DE  ; copy index into DE
35A3  29            ADD HL,HL  ; HL = index*2
35A4  19            ADD HL,DE  ; HL = index*3 (each table entry is a 3-byte JP)
35A5  11 AA 35      LD DE,fdc_sub_jmptbl  ; point DE at base of sub-command jump table
35A8  19            ADD HL,DE  ; HL -> the JP entry for this sub-command
35A9  E9            JP (HL)  ; dispatch to the selected sub-command handler

; JP jump-table indexed by sub-command (C-1): 3-byte JP entries dispatched by JP (HL) @0x35A9
fdc_sub_jmptbl:
35AA  C3 E6 35      JP loc_35E6  ; sub-cmd 1 -> loc_35E6
35AD  C3 07 36      JP loc_3607  ; sub-cmd 2 -> loc_3607 (no-op return)
35B0  C3 0A 36      JP loc_360A  ; sub-cmd 3 -> loc_360A
35B3  C3 21 36      JP loc_3621  ; sub-cmd 4 -> loc_3621
35B6  C3 38 36      JP loc_3638  ; sub-cmd 5 -> loc_3638
35B9  C3 4F 36      JP loc_364F  ; sub-cmd 6 -> loc_364F
35BC  C3 66 36      JP loc_3666  ; sub-cmd 7 -> loc_3666 (no-op return)
35BF  C3 69 36      JP loc_3669  ; sub-cmd 8 -> loc_3669
35C2  C3 80 36      JP loc_3680  ; sub-cmd 9 -> loc_3680 (no-op return)
35C5  C3 83 36      JP loc_3683  ; sub-cmd 10 -> loc_3683
35C8  C3 9A 36      JP loc_369A  ; sub-cmd 11 -> loc_369A
35CB  C3 B1 36      JP loc_36B1  ; sub-cmd 12 -> loc_36B1 (no-op return)
35CE  C3 B4 36      JP loc_36B4  ; sub-cmd 13 -> loc_36B4
35D1  C3 B7 36      JP loc_36B7  ; sub-cmd 14 -> loc_36B7
35D4  C3 BA 36      JP loc_36BA  ; sub-cmd 15 -> loc_36BA
35D7  C3 C2 36      JP loc_36C2  ; sub-cmd 16 -> loc_36C2
35DA  C3 C5 36      JP loc_36C5  ; sub-cmd 17 -> loc_36C5
35DD  C3 D7 36      JP loc_36D7  ; sub-cmd 18 -> loc_36D7
35E0  C3 E9 36      JP loc_36E9  ; sub-cmd 19 -> loc_36E9
35E3  C3 FB 36      JP loc_36FB  ; sub-cmd 20 -> loc_36FB

loc_35E6:
35E6  C5            PUSH BC  ; save sub-command/drive in BC
35E7  DD 21 C6 4A   LD IX,fdc_param_recs+0xA  ; point IX at FDC param record +0x0A for this op
35EB  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
35EE  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
35F1  26 50         LD H,0x50  ; op parameter 0x50 for record field 17
35F3  FD 74 11      LD (IY+17),H  ; store param into record field 17
35F6  26 0E         LD H,0x0E  ; high byte of 16-bit block/DMA pointer (0x0E36)
35F8  2E 36         LD L,0x36  ; low byte of the block/DMA pointer

loc_35FA:
35FA  FD 74 04      LD (IY+4),H  ; store pointer high byte into record field 4
35FD  FD 75 10      LD (IY+16),L  ; store pointer low byte into record field 16
3600  CD 51 37      CALL fdc_dma_from_blk  ; launch the FDC DMA transfer for this block
3603  C1            POP BC  ; restore BC
3604  C3 FE 36      JP loc_36FE  ; finish: refresh drive latches and return

loc_3607:
3607  C3 FE 36      JP loc_36FE  ; sub-command is a no-op; just return

loc_360A:
360A  C5            PUSH BC  ; save sub-command/drive in BC
360B  DD 21 D5 4A   LD IX,fdc_param_recs+0x19  ; point IX at FDC param record +0x19
360F  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
3612  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
3615  26 50         LD H,0x50  ; op parameter 0x50 for record field 17
3617  FD 74 11      LD (IY+17),H  ; store param into record field 17
361A  26 35         LD H,0x35  ; high byte of block/DMA pointer (0x3574)
361C  2E 74         LD L,0x74  ; low byte of the block/DMA pointer
361E  C3 FA 35      JP loc_35FA  ; join common store/launch path

loc_3621:
3621  C5            PUSH BC  ; save sub-command/drive in BC
3622  DD 21 C1 4A   LD IX,fdc_param_recs+0x5  ; point IX at FDC param record +0x05
3626  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
3629  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
362C  26 4D         LD H,0x4D  ; op parameter 0x4D (FORMAT) for record field 17
362E  FD 74 11      LD (IY+17),H  ; store param into record field 17
3631  26 0E         LD H,0x0E  ; high byte of block/DMA pointer (0x0E36)
3633  2E 36         LD L,0x36  ; low byte of the block/DMA pointer
3635  C3 FA 35      JP loc_35FA  ; join common store/launch path

loc_3638:
3638  C5            PUSH BC  ; save sub-command/drive in BC
3639  DD 21 CB 4A   LD IX,fdc_param_recs+0xF  ; point IX at FDC param record +0x0F
363D  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
3640  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
3643  26 4D         LD H,0x4D  ; op parameter 0x4D (FORMAT) for record field 17
3645  FD 74 11      LD (IY+17),H  ; store param into record field 17
3648  26 1B         LD H,0x1B  ; high byte of block/DMA pointer (0x1B54)
364A  2E 54         LD L,0x54  ; low byte of the block/DMA pointer
364C  C3 FA 35      JP loc_35FA  ; join common store/launch path

loc_364F:
364F  C5            PUSH BC  ; save sub-command/drive in BC
3650  DD 21 D0 4A   LD IX,fdc_param_recs+0x14  ; point IX at FDC param record +0x14
3654  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
3657  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
365A  26 4D         LD H,0x4D  ; op parameter 0x4D (FORMAT) for record field 17
365C  FD 74 11      LD (IY+17),H  ; store param into record field 17
365F  26 35         LD H,0x35  ; high byte of block/DMA pointer (0x3574)
3661  2E 74         LD L,0x74  ; low byte of the block/DMA pointer
3663  C3 FA 35      JP loc_35FA  ; join common store/launch path

loc_3666:
3666  C3 FE 36      JP loc_36FE  ; sub-command is a no-op; just return

loc_3669:
3669  C5            PUSH BC  ; save sub-command/drive in BC
366A  DD 21 C6 4A   LD IX,fdc_param_recs+0xA  ; point IX at FDC param record +0x0A
366E  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
3671  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
3674  26 28         LD H,0x28  ; op parameter 0x28 for record field 17
3676  FD 74 11      LD (IY+17),H  ; store param into record field 17
3679  26 0E         LD H,0x0E  ; high byte of block/DMA pointer (0x0E36)
367B  2E 36         LD L,0x36  ; low byte of the block/DMA pointer
367D  C3 FA 35      JP loc_35FA  ; join common store/launch path

loc_3680:
3680  C3 FE 36      JP loc_36FE  ; sub-command is a no-op; just return

loc_3683:
3683  C5            PUSH BC  ; save sub-command/drive in BC
3684  DD 21 D5 4A   LD IX,fdc_param_recs+0x19  ; point IX at FDC param record +0x19
3688  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
368B  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
368E  26 28         LD H,0x28  ; op parameter 0x28 for record field 17
3690  FD 74 11      LD (IY+17),H  ; store param into record field 17
3693  26 35         LD H,0x35  ; high byte of block/DMA pointer (0x3574)
3695  2E 74         LD L,0x74  ; low byte of the block/DMA pointer
3697  C3 FA 35      JP loc_35FA  ; join common store/launch path

loc_369A:
369A  C5            PUSH BC  ; save sub-command/drive in BC
369B  DD 21 C6 4A   LD IX,fdc_param_recs+0xA  ; point IX at FDC param record +0x0A
369F  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
36A2  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
36A5  26 50         LD H,0x50  ; op parameter 0x50 for record field 17
36A7  FD 74 11      LD (IY+17),H  ; store param into record field 17
36AA  26 0E         LD H,0x0E  ; high byte of block/DMA pointer (0x0E36)
36AC  2E 36         LD L,0x36  ; low byte of the block/DMA pointer
36AE  C3 FA 35      JP loc_35FA  ; join common store/launch path

loc_36B1:
36B1  C3 FE 36      JP loc_36FE  ; sub-command is a no-op; just return

loc_36B4:
36B4  C3 0A 36      JP loc_360A  ; alias: run sub-command 3 handler (loc_360A)

loc_36B7:
36B7  C3 21 36      JP loc_3621  ; alias: run sub-command 4 handler (loc_3621)

loc_36BA:
36BA  26 4D         LD H,0x4D  ; op parameter 0x4D (FORMAT) for record field 17
36BC  FD 74 11      LD (IY+17),H  ; store param into record field 17
36BF  C3 FE 36      JP loc_36FE  ; finish: refresh drive latches and return

loc_36C2:
36C2  C3 4F 36      JP loc_364F  ; alias: run sub-command 6 handler (loc_364F)

loc_36C5:
36C5  C5            PUSH BC  ; save sub-command/drive in BC
36C6  DD 21 BC 4A   LD IX,fdc_param_recs  ; point IX at base FDC param record
36CA  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
36CD  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
36D0  26 07         LD H,0x07  ; high byte of block/DMA pointer (0x071B)
36D2  2E 1B         LD L,0x1B  ; low byte of the block/DMA pointer
36D4  C3 FA 35      JP loc_35FA  ; join common store/launch path

loc_36D7:
36D7  C5            PUSH BC  ; save sub-command/drive in BC
36D8  DD 21 DF 4A   LD IX,fdc_param_recs+0x23  ; point IX at FDC param record +0x23
36DC  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
36DF  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
36E2  26 C8         LD H,0xC8  ; high byte of block/DMA pointer (0xC8FF)
36E4  2E FF         LD L,0xFF  ; low byte of the block/DMA pointer
36E6  C3 FA 35      JP loc_35FA  ; join common store/launch path

loc_36E9:
36E9  C5            PUSH BC  ; save sub-command/drive in BC
36EA  DD 21 E4 4A   LD IX,fdc_param_recs+0x28  ; point IX at FDC param record +0x28
36EE  CD 2F 37      CALL copy_fdc_params  ; copy the FDC command params into the work record
36F1  CD 2B 37      CALL clr_fdc_pending  ; clear the FDC-command-pending flag
36F4  26 C8         LD H,0xC8  ; high byte of block/DMA pointer (0xC8FF)
36F6  2E FF         LD L,0xFF  ; low byte of the block/DMA pointer
36F8  C3 FA 35      JP loc_35FA  ; join common store/launch path

loc_36FB:
36FB  C3 D7 36      JP loc_36D7  ; alias: run sub-command 18 handler (loc_36D7)

loc_36FE:
36FE  3A 01 4B      LD A,(drive_blk_a+0x16)  ; load drive-block A latch shadow
3701  D3 50         OUT (0x50),A  ; drv_lat1 — write it to drive latch 1 (drv_lat1)
3703  3A 1C 4B      LD A,(drive_blk_b+0x16)  ; load drive-block B latch shadow
3706  D3 70         OUT (0x70),A  ; drv_lat3 — write it to drive latch 3 (drv_lat3)
3708  FD E1         POP IY  ; restore IY
370A  E1            POP HL  ; restore HL
370B  DD E1         POP IX  ; restore IX
370D  C9            RET  ; return to caller

; assert panel latch bit6 (0x40) via port F0 (drive/head control line)
panel_bit6_on:
370E  F5            PUSH AF  ; save A
370F  3A 58 4A      LD A,(panel_shadow)  ; load current panel latch shadow
3712  F6 40         OR 0x40  ; set bit6 (drive/head control line)

loc_3714:
3714  D3 F0         OUT (0xF0),A  ; panel — drive the panel latch with new value
3716  32 58 4A      LD (panel_shadow),A  ; update the panel latch shadow copy
3719  F1            POP AF  ; restore A
371A  C9            RET  ; return to caller

; clear panel latch bit6 (0x40) via port F0
clr_ctrl_bit6:
371B  F5            PUSH AF  ; save A
371C  3A 58 4A      LD A,(panel_shadow)  ; load current panel latch shadow
371F  E6 BF         AND 0xBF  ; clear bit6 (drive/head control line)
3721  18 F1         JR loc_3714  ; write back via shared panel-latch path

; set the FDC-command-pending flag (0x4AE9 = 1)
set_fdc_pending:
3723  F5            PUSH AF  ; save A
3724  3E 01         LD A,0x01  ; flag value 1 to mark FDC command pending

loc_3726:
3726  32 E9 4A      LD (fdc_op_flags),A  ; store A into the FDC-command-pending flag (shared exit for set/clear)
3729  F1            POP AF  ; restore caller's AF saved on entry
372A  C9            RET  ; return

; clear the FDC-command-pending flag (0x4AE9 = 0)
clr_fdc_pending:
372B  F5            PUSH AF  ; save AF before clearing the pending flag
372C  AF            XOR A  ; A=0 to clear the FDC-command-pending flag
372D  18 F7         JR loc_3726  ; join common store/restore/return tail

; copy geometry params (sector/size fields) from IX format descriptor into IY drive block
copy_fdc_params:
372F  DD 6E 00      LD L,(IX+0)  ; fetch sectors-per-track from format descriptor (IX+0)
3732  FD 75 05      LD (IY+5),L  ; store sectors/track into drive block (IY+5)
3735  DD 6E 01      LD L,(IX+1)  ; fetch low byte of format field (IX+1)
3738  DD 66 02      LD H,(IX+2)  ; fetch high byte of format field (IX+2)
373B  FD 75 14      LD (IY+20),L  ; store 16-bit field low into drive block (IY+20)
373E  FD 74 15      LD (IY+21),H  ; store 16-bit field high into drive block (IY+21)
3741  DD 6E 03      LD L,(IX+3)  ; fetch sector-size code from descriptor (IX+3)
3744  FD 75 03      LD (IY+3),L  ; store sector-size code into drive block (IY+3)
3747  FD 75 13      LD (IY+19),L  ; mirror sector-size code into drive block (IY+19)
374A  DD 6E 04      LD L,(IX+4)  ; fetch last-sector/EOT from descriptor (IX+4)
374D  FD 75 02      LD (IY+2),L  ; store EOT into drive block (IY+2)
3750  C9            RET  ; return

; arm DMA for a track: compute byte count from block sector range, call fdc_dma_setup, store count and count*4-1 back
fdc_dma_from_blk:
3751  D5            PUSH DE  ; preserve DE across the byte-count computation
3752  FD 5E 03      LD E,(IY+3)  ; E = current sector-size/track base (IY+3)
3755  16 00         LD D,0x00  ; zero-extend to 16-bit in DE
3757  E5            PUSH HL  ; preserve HL
3758  EB            EX DE,HL  ; move that base value into HL
3759  FD 5E 1A      LD E,(IY+26)  ; E = starting sector (IY+26)
375C  16 00         LD D,0x00  ; zero-extend to 16-bit in DE
375E  37            SCF  ; SCF/CCF pair clears carry so the following SBC subtracts cleanly
375F  3F            CCF  ; carry now clear -> SBC HL,DE is a plain 16-bit subtract
3760  ED 52         SBC HL,DE  ; HL = base - start (sector span)
3762  23            INC HL  ; +1 to make span inclusive (sector count)
3763  EB            EX DE,HL  ; move sector count into DE
3764  E1            POP HL  ; restore HL
3765  D5            PUSH DE  ; save sector count on stack for later scaling
3766  FD 7E 02      LD A,(IY+2)  ; A = EOT/last sector (IY+2) as DMA setup arg
3769  CD 89 44      CALL fdc_dma_setup  ; compute DMA byte count for the track -> DE
376C  FD 73 0E      LD (IY+14),E  ; store DMA byte-count low (IY+14)
376F  FD 72 0F      LD (IY+15),D  ; store DMA byte-count high (IY+15)
3772  D1            POP DE  ; recover sector count into DE
3773  CB 23         SLA E  ; DE *= 2 (shift count low)
3775  CB 12         RL D  ; propagate carry into high byte
3777  CB 23         SLA E  ; DE *= 2 again (now count*4)
3779  CB 12         RL D  ; propagate carry into high byte
377B  1B            DEC DE  ; count*4 - 1 (terminal-count value)
377C  FD 73 0A      LD (IY+10),E  ; store DMA terminal count low (IY+10)
377F  FD 72 0B      LD (IY+11),D  ; store DMA terminal count high (IY+11)
3782  D1            POP DE  ; restore caller's DE
3783  C9            RET  ; return

; home head to track 0: pulse ~10 single-steps then step until track-0 sense, confirm via fdc_sense_ready
fdc_home_head:
3784  C5            PUSH BC  ; save BC across head-homing
3785  D5            PUSH DE  ; save DE
3786  E5            PUSH HL  ; save HL
3787  CD 6E 48      CALL panel_bus_on  ; enable panel/drive bus before stepping
378A  CD 0E 37      CALL panel_bit6_on  ; assert control latch line6 (static drive/write enable)
378D  CD 90 49      CALL fdc_sense_ready  ; sense whether the selected drive is ready
3790  20 2F         JR NZ,loc_37C1  ; abort with error if drive not ready
3792  06 0A         LD B,0x0A  ; B=10 outer counter for initial blind step-outs

loc_3794:
3794  3E 0A         LD A,0x0A  ; A = 10 - B
3796  90            SUB B  ; compute descending pass index in A
3797  C5            PUSH BC  ; save loop counter
3798  06 00         LD B,0x00  ; B=0 (direction/param high byte for step)
379A  4F            LD C,A  ; C = step count for this pulse
379B  CD C6 37      CALL fdc_step_pulse  ; issue the step/seek pulse
379E  C1            POP BC  ; restore loop counter
379F  10 F3         DJNZ loc_3794  ; repeat the 10 blind step-out pulses
37A1  06 09         LD B,0x09  ; B=9 max step-in attempts to find track 0

loc_37A3:
37A3  48            LD C,B  ; C = remaining-count as step arg
37A4  C5            PUSH BC  ; save loop counter

loc_37A5:
37A5  06 00         LD B,0x00  ; B=0 direction/high byte for single step
37A7  CD C6 37      CALL fdc_step_pulse  ; single-step the head
37AA  CD 90 49      CALL fdc_sense_ready  ; sense drive ready / track-0 status
37AD  C1            POP BC  ; restore loop counter
37AE  28 11         JR Z,loc_37C1  ; track-0 reached -> success exit
37B0  10 F1         DJNZ loc_37A3  ; otherwise step again up to 9 times
37B2  01 00 00      LD BC,0x0000  ; BC=0 one final single step
37B5  CD C6 37      CALL fdc_step_pulse  ; issue final step pulse
37B8  CD 90 49      CALL fdc_sense_ready  ; re-check ready/track-0
37BB  20 04         JR NZ,loc_37C1  ; still not at track 0 -> error exit
37BD  37            SCF  ; SCF/CCF pair clears carry to signal home success
37BE  3F            CCF  ; carry now clear = success (no error)
37BF  18 01         JR loc_37C2  ; skip the error-flag path

loc_37C1:
37C1  37            SCF  ; set carry = home/step error

loc_37C2:
37C2  E1            POP HL  ; restore HL
37C3  D1            POP DE  ; restore DE
37C4  C1            POP BC  ; restore BC
37C5  C9            RET  ; return (carry set on failure)

; issue one FDC step/seek pulse (fdc_send_seek A=1) and poll for completion
fdc_step_pulse:
37C6  3E 01         LD A,0x01  ; A=1 step-direction/unit arg for seek
37C8  CD 3A 43      CALL fdc_send_seek  ; send one step/seek pulse to the FDC

loc_37CB:
37CB  3E 01         LD A,0x01  ; A=1 poll selector for step completion
37CD  CD 2D 47      CALL fdc_poll_complete  ; poll FDC for seek-complete interrupt
37D0  28 F9         JR Z,loc_37CB  ; keep polling until the step completes
37D2  E5            PUSH HL  ; preserve HL around LCD update
37D3  21 D0 07      LD HL,0x07D0  ; HL=0x07D0 LCD position/data for progress
37D6  CD 22 4C      CALL lcd_setpos  ; set LCD cursor position
37D9  E1            POP HL  ; restore HL
37DA  C9            RET  ; return

; measure spindle index period via index sensor + PIT c1/c2, compare vs min/max (0x4AA2/0x4AA4) to validate RPM
index_period_timer:
37DB  C5            PUSH BC  ; save BC across the drive/format dispatch
37DC  D5            PUSH DE  ; save DE
37DD  E5            PUSH HL  ; save HL
37DE  F5            PUSH AF  ; save AF
37DF  CD 6E 48      CALL panel_bus_on  ; enable panel/drive bus
37E2  78            LD A,B  ; A = drive-type/mode selector from B
37E3  E6 C0         AND 0xC0  ; isolate top two bits (drive-type group)
37E5  FE 00         CP 0x00  ; test for group 0
37E7  28 6D         JR Z,loc_3856  ; handle drive-type group 0
37E9  FE 40         CP 0x40  ; test for group 0x40
37EB  28 3A         JR Z,loc_3827  ; handle drive-type group 0x40
37ED  FE 80         CP 0x80  ; test for group 0x80
37EF  28 00         JR Z,loc_37F1  ; fall through to group 0x80 handler

loc_37F1:
37F1  79            LD A,C  ; A = format/density code from C
37F2  B7            OR A  ; code 0?
37F3  28 1C         JR Z,loc_3811  ; code 0 -> special AND-0x1F path
37F5  FE 04         CP 0x04  ; format code 0x04?
37F7  28 1D         JR Z,loc_3816  ; match -> select descriptor set at 3816
37F9  FE 05         CP 0x05  ; format code 0x05?
37FB  28 19         JR Z,loc_3816  ; match -> select descriptor set at 3816
37FD  FE 06         CP 0x06  ; format code 0x06?
37FF  28 15         JR Z,loc_3816  ; match -> select descriptor set at 3816
3801  FE 0E         CP 0x0E  ; format code 0x0E?
3803  28 11         JR Z,loc_3816  ; match -> select descriptor set at 3816
3805  FE 0F         CP 0x0F  ; format code 0x0F?
3807  28 0D         JR Z,loc_3816  ; match -> select descriptor set at 3816
3809  FE 10         CP 0x10  ; format code 0x10?
380B  28 09         JR Z,loc_3816  ; match -> select descriptor set at 3816
380D  FE 11         CP 0x11  ; format code 0x11?
380F  18 05         JR loc_3816  ; any other code also falls into 3816 selector

loc_3811:
3811  78            LD A,B  ; A = B low bits variant
3812  E6 1F         AND 0x1F  ; mask to low 5 bits (unit/format subfield)
3814  FE 06         CP 0x06  ; compare against 6 to set Z for the branch below

loc_3816:
3816  11 A5 37      LD DE,loc_37A5  ; DE = first pointer (step-table) for matched format
3819  21 87 2D      LD HL,loc_2D87  ; HL = second pointer (message/param block)
381C  28 6B         JR Z,loc_3889  ; if code matched (Z) commit this pair
381E  11 C6 42      LD DE,loc_42C6  ; else DE = alternate pointer at 42C6
3821  21 16 36      LD HL,0x3616  ; HL = alternate pointer 0x3616
3824  C3 89 38      JP loc_3889  ; commit the alternate pair

loc_3827:
3827  79            LD A,C  ; A = format/density code from C (group 0x40)
3828  B7            OR A  ; code 0?
3829  28 23         JR Z,loc_384E  ; code 0 -> default pair at 384E
382B  FE 04         CP 0x04  ; format code 0x04?
382D  28 16         JR Z,loc_3845  ; match -> select pair at 3845
382F  FE 05         CP 0x05  ; format code 0x05?
3831  28 12         JR Z,loc_3845  ; match -> select pair at 3845
3833  FE 06         CP 0x06  ; format code 0x06?
3835  28 0E         JR Z,loc_3845  ; match -> select pair at 3845
3837  FE 0E         CP 0x0E  ; format code 0x0E?
3839  28 0A         JR Z,loc_3845  ; match -> select pair at 3845
383B  FE 0F         CP 0x0F  ; format code 0x0F?
383D  28 06         JR Z,loc_3845  ; match -> select pair at 3845
383F  FE 10         CP 0x10  ; format code 0x10?
3841  28 02         JR Z,loc_3845  ; match -> select pair at 3845
3843  FE 11         CP 0x11  ; format code 0x11? (fall through, sets Z on match)

loc_3845:
3845  11 BE 5C      LD DE,0x5CBE  ; DE = pointer 0x5CBE for this format
3848  21 E1 4B      LD HL,loc_4BE1  ; HL = pointer loc_4BE1
384B  CA 89 38      JP Z,loc_3889  ; commit pair if a format code matched

loc_384E:
384E  11 4A 6F      LD DE,0x6F4A  ; DE = default pointer 0x6F4A
3851  21 0E 5B      LD HL,0x5B0E  ; HL = default pointer 0x5B0E
3854  18 33         JR loc_3889  ; commit the default pair

loc_3856:
3856  79            LD A,C  ; A = format/density code from C (group 0)
3857  B7            OR A  ; code 0?
3858  28 1C         JR Z,loc_3876  ; code 0 -> AND-0x1F special path at 3876
385A  FE 04         CP 0x04  ; format code 0x04?
385C  28 1D         JR Z,loc_387B  ; match -> select pair at 387B
385E  FE 05         CP 0x05  ; format code 0x05?
3860  28 19         JR Z,loc_387B  ; match -> select pair at 387B
3862  FE 06         CP 0x06  ; format code 0x06?
3864  28 15         JR Z,loc_387B  ; match -> select pair at 387B
3866  FE 0E         CP 0x0E  ; format code 0x0E?
3868  28 11         JR Z,loc_387B  ; match -> select pair at 387B
386A  FE 0F         CP 0x0F  ; format code 0x0F?
386C  28 0D         JR Z,loc_387B  ; match -> select pair at 387B
386E  FE 10         CP 0x10  ; format code 0x10?
3870  28 09         JR Z,loc_387B  ; match -> select pair at 387B
3872  FE 11         CP 0x11  ; format code 0x11?
3874  18 05         JR loc_387B  ; any other code also uses 387B selector

loc_3876:
3876  78            LD A,B  ; A = B low bits variant
3877  E6 1F         AND 0x1F  ; mask to low 5 bits
3879  FE 06         CP 0x06  ; compare against 6 to set Z for branch

loc_387B:
387B  11 4A 6F      LD DE,0x6F4A  ; DE = pointer 0x6F4A for matched format
387E  21 0E 5B      LD HL,0x5B0E  ; HL = pointer 0x5B0E
3881  28 06         JR Z,loc_3889  ; commit this pair if matched
3883  11 8C 85      LD DE,0x858C  ; else DE = alternate pointer 0x858C
3886  21 2C 6C      LD HL,0x6C2C  ; HL = alternate pointer 0x6C2C

loc_3889:
3889  F1            POP AF  ; recover AF (original flags/entry value)
388A  08            EX AF,AF'  ; stash it in the alternate accumulator
388B  ED 53 A2 4A   LD (fdc_result_save+0x1),DE  ; save selected DE pointer to fdc_result_save+1
388F  22 A4 4A      LD (fdc_result_save+0x3),HL  ; save selected HL pointer to fdc_result_save+3
3892  F5            PUSH AF  ; re-save AF for the poll loop
3893  3E 04         LD A,0x04  ; A=4 drive-state = busy/step-in-progress
3895  32 59 4A      LD (fdc_drv_state),A  ; record drive state code
3898  F1            POP AF  ; restore AF

loc_3899:
3899  01 FF FF      LD BC,0xFFFF  ; BC=0xFFFF panel-poll timeout counter

loc_389C:
389C  DB F0         IN A,(0xF0)  ; panel — read panel port 0xF0 (button/EEPROM lines)
389E  08            EX AF,AF'  ; stash panel byte in alternate accumulator
389F  CB 47         BIT 0,A  ; test panel bit 0 (button/data line)
38A1  28 08         JR Z,loc_38AB  ; bit0 clear -> check bit1 path
38A3  08            EX AF,AF'  ; recover panel byte
38A4  CB 47         BIT 0,A  ; re-test panel bit 0
38A6  28 10         JR Z,loc_38B8  ; bit0 clear -> exit at loc_38B8
38A8  C3 B0 38      JP loc_38B0  ; bit0 set -> jump to loc_38B0 handler

loc_38AB:
38AB  08            EX AF,AF'  ; recover panel byte
38AC  CB 4F         BIT 1,A  ; test panel bit 1
38AE  28 08         JR Z,loc_38B8  ; bit1 clear -> exit at loc_38B8

loc_38B0:
38B0  0B            DEC BC  ; decrement outer retry/dwell counter
38B1  79            LD A,C  ; test BC for zero (A=C)
38B2  B0            OR B  ; OR in B: sets Z when counter reached 0
38B3  CA 45 39      JP Z,loc_3945  ; counter exhausted -> exit path (returns result 0)
38B6  18 E4         JR loc_389C  ; loop back to continue waiting

loc_38B8:
38B8  08            EX AF,AF'  ; swap in caller's flags/A saved in AF'
38B9  47            LD B,A  ; keep mode flags in B for repeated bit tests
38BA  CB 47         BIT 0,A  ; test bit0: which index-sensor/counter to use
38BC  28 0C         JR Z,loc_38CA  ; bit0 clear -> use PIT counter 2 path
38BE  3E 74         LD A,0x74  ; PIT ctrl: counter1, mode2, binary, LSB+MSB
38C0  D3 AC         OUT (0xAC),A  ; pit_ctrl — program PIT control word -> pit_ctrl
38C2  3E FF         LD A,0xFF  ; reload value 0xFFFF (max count)
38C4  D3 A4         OUT (0xA4),A  ; pit_c1 — load counter1 LSB
38C6  D3 A4         OUT (0xA4),A  ; pit_c1 — load counter1 MSB
38C8  18 0A         JR loc_38D4  ; skip counter2 setup

loc_38CA:
38CA  3E B4         LD A,0xB4  ; PIT ctrl: counter2, mode2, binary, LSB+MSB
38CC  D3 AC         OUT (0xAC),A  ; pit_ctrl — program PIT control word -> pit_ctrl
38CE  3E FF         LD A,0xFF  ; reload value 0xFFFF (max count)
38D0  D3 A8         OUT (0xA8),A  ; pit_c2 — load counter2 LSB
38D2  D3 A8         OUT (0xA8),A  ; pit_c2 — load counter2 MSB

loc_38D4:
38D4  57            LD D,A  ; seed DE high byte = 0xFF
38D5  5F            LD E,A  ; seed DE low byte = 0xFF (DE=0xFFFF)

loc_38D6:
38D6  DB F0         IN A,(0xF0)  ; panel — read panel/index-sensor lines
38D8  CB 40         BIT 0,B  ; select which sensor bit per mode flag
38DA  28 06         JR Z,loc_38E2  ; bit0 mode -> test sensor bit1 branch
38DC  CB 47         BIT 0,A  ; test index pulse bit0
38DE  28 F6         JR Z,loc_38D6  ; spin until index bit0 asserts
38E0  18 04         JR loc_38E6  ; index seen -> start timed measurement

loc_38E2:
38E2  CB 4F         BIT 1,A  ; test alternate index bit1
38E4  28 F0         JR Z,loc_38D6  ; spin until index bit1 asserts

loc_38E6:
38E6  21 00 4B      LD HL,drive_blk_a+0x15  ; load timeout counter (~0x4B00 iterations)

loc_38E9:
38E9  2B            DEC HL  ; decrement wait-timeout counter
38EA  7D            LD A,L  ; test HL for zero (low byte)
38EB  B4            OR H  ; OR high byte: Z when timeout hit 0
38EC  CA 45 39      JP Z,loc_3945  ; timeout expired -> exit path (result 0)
38EF  DB F0         IN A,(0xF0)  ; panel — read panel/index-sensor lines
38F1  CB 40         BIT 0,B  ; select which sensor bit per mode flag
38F3  28 06         JR Z,loc_38FB  ; bit0 mode -> test sensor bit1 branch
38F5  CB 47         BIT 0,A  ; test index pulse bit0
38F7  20 F0         JR NZ,loc_38E9  ; wait while index still high
38F9  18 04         JR loc_38FF  ; index gone low -> capture count

loc_38FB:
38FB  CB 4F         BIT 1,A  ; test alternate index bit1
38FD  20 EA         JR NZ,loc_38E9  ; wait while index bit1 still high

loc_38FF:
38FF  CB 40         BIT 0,B  ; select capture source per mode flag
3901  28 05         JR Z,loc_3908  ; bit0 clear -> read PIT counter2 directly
3903  CD DE 48      CALL read_timer_c1  ; read PIT counter1 elapsed count
3906  18 0A         JR loc_3912  ; join with captured count in HL

loc_3908:
3908  3E 84         LD A,0x84  ; PIT latch command for counter2
390A  D3 AC         OUT (0xAC),A  ; pit_ctrl — issue counter-latch -> pit_ctrl
390C  DB A8         IN A,(0xA8)  ; pit_c2 — read latched counter2 LSB
390E  6F            LD L,A  ; counter2 LSB into L
390F  DB A8         IN A,(0xA8)  ; pit_c2 — read latched counter2 MSB
3911  67            LD H,A  ; store as H (HL=current count)

loc_3912:
3912  EB            EX DE,HL  ; swap so DE=count, HL=start 0xFFFF
3913  ED 53 9F 31   LD (rpm_residual),DE  ; save current count as rpm_residual
3917  ED 52         SBC HL,DE  ; HL = elapsed ticks = 0xFFFF - count
3919  ED 5B A2 4A   LD DE,(fdc_result_save+0x1)  ; load low RPM-window threshold
391D  E5            PUSH HL  ; preserve elapsed count
391E  ED 52         SBC HL,DE  ; compare elapsed vs low threshold
3920  E1            POP HL  ; restore elapsed count
3921  30 0C         JR NC,loc_392F  ; elapsed >= low threshold -> in-window check
3923  ED 5B A4 4A   LD DE,(fdc_result_save+0x3)  ; load high RPM-window threshold
3927  ED 52         SBC HL,DE  ; compare elapsed vs high threshold
3929  30 1D         JR NC,loc_3948  ; within window -> success return
392B  3E 02         LD A,0x02  ; out of window: result code 2 (speed error)
392D  18 18         JR loc_3947  ; go set carry and return code 2

loc_392F:
392F  3A 59 4A      LD A,(fdc_drv_state)  ; load remaining measurement-retry count
3932  3D            DEC A  ; decrement retry count
3933  32 59 4A      LD (fdc_drv_state),A  ; store back retry count
3936  28 05         JR Z,loc_393D  ; retries exhausted -> result code 1
3938  78            LD A,B  ; reload mode flags from B
3939  08            EX AF,AF'  ; stash flags in AF' for retry
393A  C3 99 38      JP loc_3899  ; loop back to re-measure

loc_393D:
393D  3E 01         LD A,0x01  ; result code 1 (retries used up)
393F  18 06         JR loc_3947  ; go set carry and return
3941  3E 02         LD A,0x02  ; result code 2 (alt entry)
3943  18 02         JR loc_3947  ; go set carry and return

loc_3945:
3945  3E 00         LD A,0x00  ; result code 0 (timeout/aborted)

loc_3947:
3947  37            SCF  ; set carry = error/result flag

loc_3948:
3948  E1            POP HL  ; restore HL
3949  D1            POP DE  ; restore DE
394A  C1            POP BC  ; restore BC
394B  C9            RET  ; return with result in A, carry set

; prep recal/seek step params: pick step-rate C by drive index (unit_sel) & 0x4A58 cfg, DE=target track per side
fdc_recal_seek:
394C  C5            PUSH BC  ; save BC
394D  D5            PUSH DE  ; save DE
394E  E5            PUSH HL  ; save HL
394F  E6 7F         AND 0x7F  ; mask off high bit of arg
3951  08            EX AF,AF'  ; stash masked arg in AF'
3952  3A 37 31      LD A,(unit_sel)  ; read current drive/unit index
3955  E6 0F         AND 0x0F  ; keep low nibble (drive number)
3957  FE 04         CP 0x04  ; drive index < 4?
3959  0E 05         LD C,0x05  ; default step rate = 5
395B  38 0D         JR C,loc_396A  ; drives 0-3 -> use default step rate
395D  4F            LD C,A  ; stash drive index in C across panel read
395E  3A 58 4A      LD A,(panel_shadow)  ; read panel config shadow
3961  CB 77         BIT 6,A  ; test config bit6 (drive-type/datarate)
3963  79            LD A,C  ; restore drive index to A (bit6 picks C=6 or 3)
3964  0E 06         LD C,0x06  ; candidate step rate = 6
3966  28 02         JR Z,loc_396A  ; bit6 clear -> use step rate 6
3968  0E 03         LD C,0x03  ; bit6 set -> step rate 3

loc_396A:
396A  ED 5B 1E 4B   LD DE,(drive_blk_b+0x18)  ; default target-track word = drive B block
396E  08            EX AF,AF'  ; restore masked arg
396F  FE 01         CP 0x01  ; selected drive == 1?
3971  20 04         JR NZ,loc_3977  ; not drive1 -> keep drive B target
3973  ED 5B 03 4B   LD DE,(drive_blk_a+0x18)  ; drive1 -> use drive A target track

loc_3977:
3977  D5            PUSH DE  ; save target-track DE
3978  F5            PUSH AF  ; save drive arg
3979  CD 9E 39      CALL fdc_recal_wrap  ; issue recalibrate/specify to FDC pair
397C  F1            POP AF  ; restore drive arg
397D  F5            PUSH AF  ; re-save drive arg

loc_397E:
397E  CD 2D 47      CALL fdc_poll_complete  ; poll FDC for command completion
3981  28 FB         JR Z,loc_397E  ; wait until FDC signals done
3983  F1            POP AF  ; restore drive arg
3984  D1            POP DE  ; restore target-track DE
3985  FE 01         CP 0x01  ; selected drive == 1?
3987  20 06         JR NZ,loc_398F  ; not drive1 -> use drive B step rate
3989  08            EX AF,AF'  ; swap to alt flags
398A  3A 02 4B      LD A,(drive_blk_a+0x17)  ; load drive A configured step rate
398D  18 04         JR loc_3993  ; apply step rate

loc_398F:
398F  08            EX AF,AF'  ; swap to alt flags
3990  3A 1D 4B      LD A,(drive_blk_b+0x17)  ; load drive B configured step rate

loc_3993:
3993  4F            LD C,A  ; C = step rate value
3994  08            EX AF,AF'  ; restore flags
3995  06 00         LD B,0x00  ; B=0 (drive-select offset)
3997  CD D5 44      CALL fdc_set_steprate  ; program FDC step/head timing
399A  E1            POP HL  ; restore HL
399B  D1            POP DE  ; restore DE
399C  C1            POP BC  ; restore BC
399D  C9            RET  ; return

; FDC specify wrapper: set step rate, issue specify (0x07); folds in bit0 of drv_active_cfg (const enable, not precomp — real write-precomp is FDC port 0xC2)
fdc_recal_wrap:
399E  C5            PUSH BC  ; save BC
399F  E5            PUSH HL  ; save HL

; build+issue FDC RECALIBRATE (opcode 0x07) to both drives of a pair
fdc_recalibrate:
39A0  CD 6E 48      CALL panel_bus_on  ; assert drive/write bus enable (0x9C line6)
39A3  06 01         LD B,0x01  ; B=1: request step-rate config
39A5  CD 90 45      CALL key_decode  ; decode key/config -> step params in A
39A8  06 00         LD B,0x00  ; B=0: normal offset
39AA  F5            PUSH AF  ; save decoded flags
39AB  CD D5 44      CALL fdc_set_steprate  ; program FDC step/head timing
39AE  F1            POP AF  ; restore decoded flags
39AF  CB 47         BIT 0,A  ; test bit0: which FDC pair (0x10 vs 0x30)
39B1  28 1D         JR Z,loc_39D0  ; bit0 clear -> FDC at port base 0x30
39B3  0E 10         LD C,0x10  ; C = FDC #1 port base 0x10
39B5  21 6A 4A      LD HL,fdc_cmd_buf1  ; point at RECALIBRATE command buffer 1
39B8  06 02         LD B,0x02  ; 2-byte command length
39BA  36 07         LD (HL),0x07  ; store RECALIBRATE opcode 0x07
39BC  23            INC HL  ; advance to unit-select byte
39BD  3A 1E 31      LD A,(drv_active_cfg)  ; load active drive-select config
39C0  E6 01         AND 0x01  ; keep drive-select bit0
39C2  CB C7         SET 0,A  ; force enable bit (const drive enable)
39C4  77            LD (HL),A  ; store unit-select byte
39C5  2B            DEC HL  ; back to command start
39C6  CD 7F 45      CALL fdc_write_bytes  ; write RECALIBRATE to FDC #1
39C9  0E 00         LD C,0x00  ; C = FDC #0 port base 0x00
39CB  21 61 4A      LD HL,fdc_cmd_buf  ; point at RECALIBRATE command buffer 0
39CE  18 1B         JR loc_39EB  ; jump to shared 2nd-drive dispatch

loc_39D0:
39D0  0E 30         LD C,0x30  ; C = FDC #3 port base 0x30
39D2  21 7C 4A      LD HL,fdc_cmd_buf3  ; point at RECALIBRATE command buffer 3
39D5  06 02         LD B,0x02  ; 2-byte command length
39D7  36 07         LD (HL),0x07  ; store RECALIBRATE opcode 0x07
39D9  23            INC HL  ; advance to unit-select byte
39DA  3A 1E 31      LD A,(drv_active_cfg)  ; load active drive-select config
39DD  E6 01         AND 0x01  ; keep drive-select bit0
39DF  CB C7         SET 0,A  ; force enable bit (const drive enable)
39E1  77            LD (HL),A  ; store unit-select byte
39E2  2B            DEC HL  ; back to command start
39E3  CD 7F 45      CALL fdc_write_bytes  ; write RECALIBRATE to FDC #3
39E6  0E 20         LD C,0x20  ; C = FDC #2 port base 0x20
39E8  21 73 4A      LD HL,fdc_cmd_buf2  ; point at RECALIBRATE command buffer 2

loc_39EB:
39EB  06 02         LD B,0x02  ; 2-byte command length
39ED  36 07         LD (HL),0x07  ; store RECALIBRATE opcode 0x07
39EF  23            INC HL  ; advance to unit-select byte
39F0  3A 1E 31      LD A,(drv_active_cfg)  ; load active drive-select config
39F3  E6 01         AND 0x01  ; keep drive-select bit0
39F5  CB C7         SET 0,A  ; force enable bit (const drive enable)
39F7  77            LD (HL),A  ; store unit-select byte
39F8  2B            DEC HL  ; back to command start
39F9  CD 7F 45      CALL fdc_write_bytes  ; write RECALIBRATE to second FDC of pair
39FC  FB            EI  ; re-enable interrupts
39FD  E1            POP HL  ; restore HL
39FE  C1            POP BC  ; restore BC
39FF  C9            RET  ; return
3A00  F5            PUSH AF  ; save A (drive arg)
3A01  CD 18 3A      CALL fdc_send_dma  ; arm single-FDC DMA transfer

loc_3A04:
3A04  F1            POP AF  ; restore A
3A05  CD 48 48      CALL timeout_start  ; start command timeout timer

loc_3A08:
3A08  F5            PUSH AF  ; save A across poll
3A09  CD 2D 47      CALL fdc_poll_complete  ; poll FDC for completion
3A0C  20 07         JR NZ,loc_3A15  ; FDC done -> discard saved A and return
3A0E  F1            POP AF  ; restore A
3A0F  CD 57 48      CALL timeout_check  ; check if timeout elapsed
3A12  30 F4         JR NC,loc_3A08  ; not timed out -> keep polling
3A14  C9            RET  ; return (timeout expired)

loc_3A15:
3A15  33            INC SP  ; pop the saved AF off stack
3A16  33            INC SP  ; finish discarding saved AF
3A17  C9            RET  ; return (FDC completed)

; arm single-FDC DMA read (4 desc, cnt 0x0C): pick blk A/B by A==1, set bank/drive latch, exec via SP-swap
fdc_send_dma:
3A18  C5            PUSH BC  ; save BC
3A19  D5            PUSH DE  ; save DE
3A1A  E5            PUSH HL  ; save HL
3A1B  E6 7F         AND 0x7F  ; mask off high bit of drive arg

loc_3A1D:
3A1D  DD E5         PUSH IX  ; Save IX before selecting a drive block
3A1F  F5            PUSH AF  ; Preserve A = requested FDC/drive index
3A20  DD 21 06 4B   LD IX,drive_blk_b  ; Default to drive block B
3A24  0E C6         LD C,0xC6  ; Default C = drive_sel_b latch port 0xC6
3A26  FE 01         CP 0x01  ; Is FDC/drive A (index 1) requested?
3A28  20 06         JR NZ,loc_3A30  ; If not A, keep block B
3A2A  DD 21 EB 4A   LD IX,drive_blk_a  ; Select drive block A instead
3A2E  0E B0         LD C,0xB0  ; C = dram_bank latch port 0xB0 for A

loc_3A30:
3A30  DD 46 07      LD B,(IX+7)  ; Fetch bank/drive-select byte from block (+7)
3A33  ED 41         OUT (C),B  ; Write it to the bank/drive-select latch
3A35  06 04         LD B,0x04  ; B = 4 DMA descriptors to arm
3A37  21 0C 00      LD HL,0x000C  ; HL = 12-byte descriptor stride
3A3A  CD EC 43      CALL dma_arm_desc  ; Program the FDC's DMA channel for the read
3A3D  F1            POP AF  ; Restore requested FDC index into A
3A3E  F3            DI  ; Disable ints for the SP-swap critical section
3A3F  ED 73 54 4A   LD (fdc_saved_sp),SP  ; Save real stack pointer
3A43  DD F9         LD SP,IX  ; Point SP at drive block to bulk-load regs
3A45  C1            POP BC  ; Bulk-load FDC cmd params: BC from block via SP
3A46  D1            POP DE  ; DE (track/head/sector) from block
3A47  E1            POP HL  ; HL (sector/EOT cmd bytes) from block
3A48  08            EX AF,AF'  ; Stash main AF while computing head byte
3A49  DD 7E 1A      LD A,(IX+26)  ; Fetch side/head bit from block (+26)
3A4C  CB 27         SLA A  ; Shift side bit into head-register position
3A4E  B4            OR H  ; Merge side bit into H
3A4F  67            LD H,A  ; Store combined head byte in H
3A50  08            EX AF,AF'  ; Restore main AF after head calc
3A51  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; Restore real stack pointer
3A55  FB            EI  ; Re-enable interrupts
3A56  DD E1         POP IX  ; Restore IX
3A58  CD 04 3B      CALL fdc_read_cmd  ; Issue the FDC read command
3A5B  E1            POP HL  ; Restore HL
3A5C  D1            POP DE  ; Restore DE
3A5D  C1            POP BC  ; Restore BC
3A5E  C9            RET  ; Return to caller
3A5F  CD 83 3A      CALL fdc_read_dual  ; Kick off dual-drive read of both FDCs

loc_3A62:
3A62  CD 48 48      CALL timeout_start  ; Start the completion timeout window

loc_3A65:
3A65  3E 01         LD A,0x01  ; A = FDC/drive index 1
3A67  CD 2D 47      CALL fdc_poll_complete  ; Poll whether drive 1 result is ready
3A6A  20 06         JR NZ,loc_3A72  ; Branch out once drive 1 completes
3A6C  CD 57 48      CALL timeout_check  ; Check if timeout has expired
3A6F  30 F4         JR NC,loc_3A65  ; Loop back to poll until timeout
3A71  C9            RET  ; Timed out: return

loc_3A72:
3A72  08            EX AF,AF'  ; Stash drive 1 result flag in shadow

loc_3A73:
3A73  3E 02         LD A,0x02  ; A = FDC/drive index 2
3A75  CD 2D 47      CALL fdc_poll_complete  ; Poll whether drive 2 result is ready
3A78  20 06         JR NZ,loc_3A80  ; Branch out once drive 2 completes
3A7A  CD 57 48      CALL timeout_check  ; Check if timeout has expired
3A7D  30 F4         JR NC,loc_3A73  ; Loop back to poll until timeout
3A7F  C9            RET  ; Timed out: return

loc_3A80:
3A80  D8            RET C  ; Return early if carry (error) set
3A81  08            EX AF,AF'  ; Restore saved drive 1 result flag
3A82  C9            RET  ; Return with combined result

; read both drives at once: set dram_bank+drive_sel_b, arm DMA ch1(blkA)/ch2(blkB) reads, exec via SP-swap
fdc_read_dual:
3A83  C5            PUSH BC  ; Save BC for dual read
3A84  D5            PUSH DE  ; Save DE
3A85  E5            PUSH HL  ; Save HL

loc_3A86:
3A86  3A 0D 4B      LD A,(drive_blk_b+0x7)  ; Fetch block B drive-select byte
3A89  D3 C6         OUT (0xC6),A  ; drive_sel_b — Set drive_sel_b latch
3A8B  3A F2 4A      LD A,(drive_blk_a+0x7)  ; Fetch block A bank byte
3A8E  D3 B0         OUT (0xB0),A  ; dram_bank — Select the DRAM image bank
3A90  DD E5         PUSH IX  ; Save IX
3A92  DD 21 EB 4A   LD IX,drive_blk_a  ; Point IX at drive block A
3A96  06 04         LD B,0x04  ; B = 4 DMA descriptors
3A98  21 0C 00      LD HL,0x000C  ; HL = 12-byte descriptor stride
3A9B  3E 01         LD A,0x01  ; A = DMA channel 1 (block A)
3A9D  CD EC 43      CALL dma_arm_desc  ; Arm DMA read for FDC A
3AA0  DD 21 06 4B   LD IX,drive_blk_b  ; Point IX at drive block B
3AA4  06 04         LD B,0x04  ; B = 4 DMA descriptors
3AA6  21 0C 00      LD HL,0x000C  ; HL = 12-byte descriptor stride
3AA9  3E 02         LD A,0x02  ; A = DMA channel 2 (block B)
3AAB  CD EC 43      CALL dma_arm_desc  ; Arm DMA read for FDC B
3AAE  F3            DI  ; Disable ints for SP-swap section
3AAF  ED 73 54 4A   LD (fdc_saved_sp),SP  ; Save real stack pointer
3AB3  DD F9         LD SP,IX  ; Point SP at block B to load its regs
3AB5  C1            POP BC  ; Load BC from block B
3AB6  D1            POP DE  ; Load DE from block B
3AB7  E1            POP HL  ; Load HL from block B
3AB8  08            EX AF,AF'  ; Stash main AF while computing head byte
3AB9  DD 7E 1A      LD A,(IX+26)  ; Fetch block B side/head bit (+26)
3ABC  CB 27         SLA A  ; Shift side bit into head-register position
3ABE  B4            OR H  ; Merge side bit into H
3ABF  67            LD H,A  ; Store combined head byte for block B
3AC0  08            EX AF,AF'  ; Restore main AF after head calc
3AC1  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; Restore real stack pointer
3AC5  C5            PUSH BC  ; Stash block B's loaded BC
3AC6  D5            PUSH DE  ; Stash block B's loaded DE
3AC7  E5            PUSH HL  ; Stash block B's loaded HL
3AC8  DD 21 EB 4A   LD IX,drive_blk_a  ; Point IX at drive block A
3ACC  ED 73 54 4A   LD (fdc_saved_sp),SP  ; Save real stack pointer
3AD0  DD F9         LD SP,IX  ; Point SP at block A to load its regs
3AD2  C1            POP BC  ; Load BC from block A
3AD3  D1            POP DE  ; Load DE from block A
3AD4  E1            POP HL  ; Load HL from block A
3AD5  08            EX AF,AF'  ; Stash main AF while computing head byte
3AD6  DD 7E 1A      LD A,(IX+26)  ; Fetch block A side/head bit (+26)
3AD9  CB 27         SLA A  ; Shift side bit into head-register position
3ADB  B4            OR H  ; Merge side bit into H
3ADC  67            LD H,A  ; Store combined head byte for block A
3ADD  08            EX AF,AF'  ; Restore main AF after head calc
3ADE  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; Restore real stack pointer
3AE2  FB            EI  ; Re-enable interrupts
3AE3  3E 01         LD A,0x01  ; A = FDC index 1 (block A)
3AE5  CD 04 3B      CALL fdc_read_cmd  ; Issue FDC A read command
3AE8  3E 02         LD A,0x02  ; A = FDC index 2 (block B)
3AEA  E1            POP HL  ; Restore block B HL cmd bytes
3AEB  D1            POP DE  ; Restore block B DE
3AEC  C1            POP BC  ; Restore block B BC
3AED  CD 04 3B      CALL fdc_read_cmd  ; Issue FDC B read command
3AF0  DD E1         POP IX  ; Restore IX
3AF2  E1            POP HL  ; Restore HL
3AF3  D1            POP DE  ; Restore DE
3AF4  C1            POP BC  ; Restore BC
3AF5  C9            RET  ; Return to caller

; entry into fdc_send_dma (single-FDC DMA read) with command bit (0x80) masked off A
fdc_dma_read2:
3AF6  C5            PUSH BC  ; Save BC
3AF7  D5            PUSH DE  ; Save DE
3AF8  E5            PUSH HL  ; Save HL
3AF9  E6 7F         AND 0x7F  ; Strip command bit 0x80 from A
3AFB  C3 1D 3A      JP loc_3A1D  ; Enter single-FDC DMA read body

; dual-drive DMA read entry: jumps into fdc_read_dual body (both FDCs simultaneously)
fdc_read_dual2:
3AFE  C5            PUSH BC  ; Save BC
3AFF  D5            PUSH DE  ; Save DE
3B00  E5            PUSH HL  ; Save HL
3B01  C3 86 3A      JP loc_3A86  ; Enter dual-drive read body

; begin FDC read: enable panel bus, select side1, set cmd tag 0x26 (read-data MFM) in 0x4AEA, build R/W cmd block
fdc_read_cmd:
3B04  CD 6E 48      CALL panel_bus_on  ; Enable the panel/drive bus
3B07  CD 8B 48      CALL panel_sel_hi  ; Select disk side 1 (high)
3B0A  08            EX AF,AF'  ; Save A = FDC index in shadow
3B0B  3E 26         LD A,0x26  ; A = 0x26 read-data MFM opcode base
3B0D  32 EA 4A      LD (fdc_opcode_base),A  ; Store FDC opcode base for R/W cmd
3B10  08            EX AF,AF'  ; Restore A = FDC index
3B11  C3 FB 3B      JP fdc_build_rw_cmd  ; Build and issue the R/W command block
3B14  CD 6E 48      CALL panel_bus_on  ; Enable the panel/drive bus
3B17  CD 8B 48      CALL panel_sel_hi  ; Select disk side 1 (high)
3B1A  08            EX AF,AF'  ; Save A = FDC index in shadow
3B1B  3E 0A         LD A,0x0A  ; A = 0x0A alternate opcode base
3B1D  32 EA 4A      LD (fdc_opcode_base),A  ; Store FDC opcode base for R/W cmd
3B20  08            EX AF,AF'  ; Restore A = FDC index
3B21  C3 FB 3B      JP fdc_build_rw_cmd  ; Build and issue the R/W command block

; issue FDC write via DMA then wait for completion
fdc_write_poll:
3B24  F5            PUSH AF  ; Preserve A = FDC index
3B25  CD 2B 3B      CALL fdc_write_dma  ; Arm and start the FDC DMA write
3B28  C3 04 3A      JP loc_3A04  ; Jump to poll for write completion

; arm single-FDC DMA write (8 desc): pick blk A/B by A==1, set bank/drive latch, exec via SP-swap
fdc_write_dma:
3B2B  C5            PUSH BC  ; Save BC
3B2C  D5            PUSH DE  ; Save DE
3B2D  E5            PUSH HL  ; Save HL
3B2E  E6 7F         AND 0x7F  ; Strip command bit 0x80 from A
3B30  DD E5         PUSH IX  ; Save IX
3B32  F5            PUSH AF  ; Preserve A = FDC index
3B33  DD 21 06 4B   LD IX,drive_blk_b  ; Default to drive block B
3B37  0E C6         LD C,0xC6  ; Default C = drive_sel_b port 0xC6
3B39  FE 01         CP 0x01  ; Is FDC/drive A (index 1) requested?
3B3B  20 06         JR NZ,loc_3B43  ; If not A, keep block B
3B3D  DD 21 EB 4A   LD IX,drive_blk_a  ; Select drive block A instead
3B41  0E B0         LD C,0xB0  ; C = dram_bank latch port 0xB0 for A

loc_3B43:
3B43  DD 46 07      LD B,(IX+7)  ; fetch DMA bank/page byte from descriptor (IX+7)
3B46  ED 41         OUT (C),B  ; write it to the DMA port selected in C
3B48  06 08         LD B,0x08  ; 8 descriptor bytes to stream to the DMA controller
3B4A  21 0C 00      LD HL,0x000C  ; HL=0x000C, DMA transfer byte count
3B4D  CD EC 43      CALL dma_arm_desc  ; arm the DMA channel with this write descriptor
3B50  F1            POP AF  ; restore saved AF from before the arm
3B51  F3            DI  ; disable interrupts for the SP-swap trick
3B52  ED 73 54 4A   LD (fdc_saved_sp),SP  ; stash real SP so we can borrow it as a data pointer
3B56  DD F9         LD SP,IX  ; point SP at descriptor block (IX) to pop params fast
3B58  C1            POP BC  ; pull BC field from the descriptor
3B59  D1            POP DE  ; pull DE field from the descriptor
3B5A  E1            POP HL  ; pull HL field from the descriptor
3B5B  08            EX AF,AF'  ; swap to alt AF to preserve main A
3B5C  DD 7E 1A      LD A,(IX+26)  ; load side/head flag byte from descriptor (IX+26)
3B5F  CB 27         SLA A  ; shift head bit into position
3B61  B4            OR H  ; merge with H (cylinder/head accumulator)
3B62  67            LD H,A  ; store combined value back into H
3B63  08            EX AF,AF'  ; swap main AF back
3B64  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore the real stack pointer
3B68  FB            EI  ; re-enable interrupts
3B69  DD E1         POP IX  ; restore caller's saved IX from the real stack
3B6B  CD EE 3B      CALL fdc_wr_side1  ; issue the FDC write command for side 1
3B6E  E1            POP HL  ; restore caller HL
3B6F  D1            POP DE  ; restore caller DE
3B70  C1            POP BC  ; restore caller BC
3B71  C9            RET  ; return to caller

; write both drives via DMA then wait for completion
fdc_write_dual:
3B72  CD 78 3B      CALL fdc_write_both  ; perform the dual-drive DMA write
3B75  C3 62 3A      JP loc_3A62  ; jump to shared completion/wait handler

; write both drives at once: set dram_bank+drive_sel_b, arm DMA ch1(blkA)/ch2(blkB) writes (8 desc), exec
fdc_write_both:
3B78  C5            PUSH BC  ; save caller BC
3B79  D5            PUSH DE  ; save caller DE
3B7A  E5            PUSH HL  ; save caller HL
3B7B  DD E5         PUSH IX  ; save caller IX
3B7D  3A F2 4A      LD A,(drive_blk_a+0x7)  ; get drive-A image bank number from descriptor
3B80  D3 B0         OUT (0xB0),A  ; dram_bank — select that 32KB DRAM image bank
3B82  3A 0D 4B      LD A,(drive_blk_b+0x7)  ; get drive-B select value from descriptor
3B85  D3 C6         OUT (0xC6),A  ; drive_sel_b — latch drive-B select on PPI port 0xC6
3B87  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX at drive-A DMA descriptor block
3B8B  06 08         LD B,0x08  ; 8 descriptor bytes for the DMA arm
3B8D  21 0C 00      LD HL,0x000C  ; HL=0x000C transfer count
3B90  E5            PUSH HL  ; save count for reuse on channel 2
3B91  3E 01         LD A,0x01  ; channel 1 = drive-A DMA write
3B93  CD EC 43      CALL dma_arm_desc  ; arm DMA channel 1 for drive-A write
3B96  DD 21 06 4B   LD IX,drive_blk_b  ; point IX at drive-B DMA descriptor block
3B9A  06 08         LD B,0x08  ; 8 descriptor bytes again
3B9C  E1            POP HL  ; recover the transfer count
3B9D  3E 02         LD A,0x02  ; channel 2 = drive-B DMA write
3B9F  CD EC 43      CALL dma_arm_desc  ; arm DMA channel 2 for drive-B write
3BA2  F3            DI  ; disable interrupts for the SP-swap
3BA3  ED 73 54 4A   LD (fdc_saved_sp),SP  ; save real SP
3BA7  DD F9         LD SP,IX  ; borrow SP as pointer into descriptor (IX)
3BA9  C1            POP BC  ; pop BC descriptor field (drive B)
3BAA  D1            POP DE  ; pop DE descriptor field (drive B)
3BAB  E1            POP HL  ; pop HL descriptor field (drive B)
3BAC  08            EX AF,AF'  ; swap to alt AF
3BAD  DD 7E 1A      LD A,(IX+26)  ; load side/head flag from descriptor (IX+26)
3BB0  CB 27         SLA A  ; shift head bit into place
3BB2  B4            OR H  ; merge into H
3BB3  67            LD H,A  ; store back to H
3BB4  08            EX AF,AF'  ; restore main AF
3BB5  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore real SP
3BB9  C5            PUSH BC  ; push drive-B BC to reuse after the drive-A write
3BBA  D5            PUSH DE  ; push drive-B DE
3BBB  E5            PUSH HL  ; push drive-B HL
3BBC  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX at drive-A descriptor block
3BC0  ED 73 54 4A   LD (fdc_saved_sp),SP  ; save SP once more
3BC4  DD F9         LD SP,IX  ; borrow SP as descriptor pointer
3BC6  C1            POP BC  ; pop BC field (drive A)
3BC7  D1            POP DE  ; pop DE field (drive A)
3BC8  E1            POP HL  ; pop HL field (drive A)
3BC9  08            EX AF,AF'  ; swap to alt AF
3BCA  DD 7E 1A      LD A,(IX+26)  ; load side/head flag (IX+26)
3BCD  CB 27         SLA A  ; shift head bit into position
3BCF  B4            OR H  ; merge into H
3BD0  67            LD H,A  ; store back to H
3BD1  08            EX AF,AF'  ; restore main AF
3BD2  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore real SP
3BD6  3E 01         LD A,0x01  ; drive tag 0x01 for drive A
3BD8  CD EE 3B      CALL fdc_wr_side1  ; issue FDC write-side1 command for drive A
3BDB  E1            POP HL  ; recover drive-B HL
3BDC  D1            POP DE  ; recover drive-B DE
3BDD  C1            POP BC  ; recover drive-B BC
3BDE  3E 02         LD A,0x02  ; drive tag 0x02 for drive B
3BE0  CD EE 3B      CALL fdc_wr_side1  ; issue FDC write-side1 command for drive B
3BE3  DD E1         POP IX  ; restore caller IX
3BE5  E1            POP HL  ; restore caller HL
3BE6  D1            POP DE  ; restore caller DE
3BE7  C1            POP BC  ; restore caller BC
3BE8  C9            RET  ; return to caller

; begin FDC write side0: select side lo, set cmd tag 0x05 (write-data), decode drive to result buf, save SP
fdc_wr_side0:
3BE9  CD 83 48      CALL panel_sel_lo  ; select drive side 0 (low) on the panel bus
3BEC  18 03         JR loc_3BF1  ; skip the side-hi select, join common path

; begin FDC write side1: select side hi, set cmd tag 0x05 (write-data), decode drive to result buf
fdc_wr_side1:
3BEE  CD 8B 48      CALL panel_sel_hi  ; select drive side 1 (high) on the panel bus

loc_3BF1:
3BF1  CD 6E 48      CALL panel_bus_on  ; enable the drive bus/output
3BF4  08            EX AF,AF'  ; stash A (drive tag) in alt AF across setup

; FDC write-command core: set cmd tag 0x05, decode drive via key_decode, select fdc0/1/2/3 result buffer
fdc_write_cmd:
3BF5  3E 05         LD A,0x05  ; cmd tag 0x05 = FDC write-data opcode
3BF7  32 EA 4A      LD (fdc_opcode_base),A  ; store into fdc_opcode_base for command build
3BFA  08            EX AF,AF'  ; recover the drive tag from alt AF

; build 9-byte FDC READ/WRITE command {cmd,HD,C,H,R,N,EOT,GPL,DTL} and stream it
fdc_build_rw_cmd:
3BFB  F5            PUSH AF  ; save A (drive tag)
3BFC  C5            PUSH BC  ; save BC
3BFD  06 01         LD B,0x01  ; B=1: decode a single drive
3BFF  CD 90 45      CALL key_decode  ; decode drive number -> A selects fdc/result buffer
3C02  C1            POP BC  ; restore BC
3C03  F3            DI  ; disable interrupts for SP-swap command build
3C04  ED 73 54 4A   LD (fdc_saved_sp),SP  ; save real SP
3C08  CB 7F         BIT 7,A  ; test bit7 of decoded drive code
3C0A  28 0D         JR Z,loc_3C19  ; if clear, handle drives 0/1 path
3C0C  FE 81         CP 0x81  ; compare 0x81 to distinguish drive 2 vs 3
3C0E  D9            EXX  ; swap to alt registers
3C0F  21 85 4A      LD HL,fdc_result_buf  ; HL -> fdc_result_buf (drive 3)
3C12  20 10         JR NZ,loc_3C24  ; if not 0x81 (drive 3), use result buf
3C14  21 73 4A      LD HL,fdc_cmd_buf2  ; else HL -> fdc_cmd_buf2 (drive 2)
3C17  18 0B         JR loc_3C24  ; join common build path

loc_3C19:
3C19  FE 01         CP 0x01  ; compare 0x01 to distinguish drive 0 vs 1
3C1B  D9            EXX  ; swap to alt registers
3C1C  21 7C 4A      LD HL,fdc_cmd_buf3  ; HL -> fdc_cmd_buf3 (drive 1)
3C1F  20 03         JR NZ,loc_3C24  ; if not 0x01 (drive 1), keep buf3
3C21  21 6A 4A      LD HL,fdc_cmd_buf1  ; else HL -> fdc_cmd_buf1 (drive 0)

loc_3C24:
3C24  F9            LD SP,HL  ; point SP at chosen command buffer to build via push
3C25  D9            EXX  ; swap back to main registers
3C26  7C            LD A,H  ; A = high byte of command-buffer address
3C27  26 FF         LD H,0xFF  ; H=0xFF for program-RAM bank pointer
3C29  E5            PUSH HL  ; push 0xFF-high pointer (DTL/GPL area)
3C2A  67            LD H,A  ; restore H from A (buffer high byte)
3C2B  08            EX AF,AF'  ; swap to alt AF for field math
3C2C  CB 3C         SRL H  ; shift head bit right for N/EOT field
3C2E  7C            LD A,H  ; A = shifted H value
3C2F  15            DEC D  ; decrement D (sector/EOT counter)
3C30  82            ADD A,D  ; add D into the computed field
3C31  57            LD D,A  ; store result back to D
3C32  D5            PUSH DE  ; push DE (R/N command bytes)
3C33  78            LD A,B  ; A = B (raw drive/cyl byte)
3C34  E6 7F         AND 0x7F  ; mask off top bit -> cylinder value
3C36  6F            LD L,A  ; L = cylinder byte
3C37  E5            PUSH HL  ; push HL (C/H command bytes)
3C38  78            LD A,B  ; A = B again
3C39  E6 80         AND 0x80  ; isolate top bit (side/head flag)
3C3B  CB 07         RLC A  ; rotate head bit toward HD position
3C3D  CB 07         RLC A  ; rotate again
3C3F  CB 07         RLC A  ; rotate again into HD field
3C41  41            LD B,C  ; B = C (preserve for buffer)
3C42  4F            LD C,A  ; C = assembled HD byte
3C43  3A 1E 31      LD A,(drv_active_cfg)  ; read active drive config flags
3C46  E6 01         AND 0x01  ; keep only bit0 (unit-select low)
3C48  CB C7         SET 0,A  ; force bit0 set (drive unit select)
3C4A  B1            OR C  ; merge with HD/head field
3C4B  4F            LD C,A  ; C = final unit/head select byte
3C4C  C5            PUSH BC  ; push BC (HD + drive-select command byte)
3C4D  08            EX AF,AF'  ; swap to alt AF for opcode assembly
3C4E  E6 01         AND 0x01  ; keep bit0 of drive tag (MT/side)
3C50  0F            RRCA  ; rotate into top bits
3C51  0F            RRCA  ; rotate again for MFM/MT position
3C52  6F            LD L,A  ; L = MT/MFM flag bits
3C53  3A EA 4A      LD A,(fdc_opcode_base)  ; load write-data opcode base (0x05)
3C56  B5            OR L  ; OR in the MT/MFM flags -> full command byte
3C57  21 00 00      LD HL,0x0000  ; HL=0, prep to read current SP
3C5A  39            ADD HL,SP  ; HL = current SP (top of built buffer)
3C5B  2B            DEC HL  ; back up one byte to command-byte slot
3C5C  77            LD (HL),A  ; store the assembled FDC command opcode
3C5D  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore the real stack pointer
3C61  FB            EI  ; re-enable interrupts
3C62  06 09         LD B,0x09  ; 9 command bytes to stream to the FDC

loc_3C64:
3C64  F1            POP AF  ; pop next drive-code word (A/flags) from buffer
3C65  CB 7F         BIT 7,A  ; test bit7 to pick FDC port group
3C67  28 0A         JR Z,loc_3C73  ; if clear, handle drives 0/1
3C69  FE 81         CP 0x81  ; compare 0x81 for drive 2 vs 3
3C6B  0E 30         LD C,0x30  ; C=0x30, FDC port base 0x30 (drive 3)
3C6D  20 0C         JR NZ,loc_3C7B  ; if not 0x81, keep port 0x30
3C6F  0E 10         LD C,0x10  ; else C=0x10, FDC port base 0x10 (drive 2)
3C71  18 08         JR loc_3C7B  ; join port-selected path

loc_3C73:
3C73  0E 20         LD C,0x20  ; C=0x20, FDC port base 0x20 (drive 1)
3C75  FE 01         CP 0x01  ; compare 0x01 for drive 0 vs 1
3C77  20 02         JR NZ,loc_3C7B  ; if not 0x01, keep port 0x20
3C79  0E 00         LD C,0x00  ; else C=0x00, FDC port base 0x00 (drive 0)

loc_3C7B:
3C7B  CD 7F 45      CALL fdc_write_bytes  ; stream the 9 command bytes to selected FDC
3C7E  C9            RET  ; return to caller

; format-command entry for drive-pair (B=2), falls into fdc_format_cmd
fdc_format_cmd2:
3C7F  F5            PUSH AF  ; save AF (drive tag)
3C80  C5            PUSH BC  ; save BC
3C81  06 02         LD B,0x02  ; B=2: format the drive pair
3C83  C3 8A 3C      JP loc_3C8A  ; jump into shared format-command body

; issue FDC format-track: decode drive (B), enable bus+select side0, exec via SP-swap into result buf
fdc_format_cmd:
3C86  F5            PUSH AF  ; save AF (drive tag)
3C87  C5            PUSH BC  ; save BC
3C88  06 01         LD B,0x01  ; B=1: format a single drive

loc_3C8A:
3C8A  CD 90 45      CALL key_decode  ; decode drive number(s) for the format op
3C8D  C1            POP BC  ; restore BC
3C8E  CD 6E 48      CALL panel_bus_on  ; enable the drive bus/output
3C91  CD 83 48      CALL panel_sel_lo  ; select drive side 0 (low)
3C94  F3            DI  ; disable interrupts for the SP-swap build
3C95  ED 73 54 4A   LD (fdc_saved_sp),SP  ; save real SP
3C99  CB 47         BIT 0,A  ; test bit0 of decoded drive code
3C9B  D9            EXX  ; swap to alt registers
3C9C  21 79 4A      LD HL,fdc_cmd_buf2+0x6  ; HL -> fdc_cmd_buf2 format-param area (bit0 clear, even drive)
3C9F  28 03         JR Z,loc_3CA4  ; if bit0 clear, keep even-drive buffer (buf2)
3CA1  21 67 4A      LD HL,fdc_cmd_buf+0x6  ; else HL -> fdc_cmd_buf format-param area (odd drive)

loc_3CA4:
3CA4  F9            LD SP,HL  ; restore stack pointer from HL (SP-swap FDC exec return path)
3CA5  D9            EXX  ; switch to alternate register set
3CA6  7C            LD A,H  ; grab H (high byte of prior context)
3CA7  61            LD H,C  ; move drive-select byte C into H
3CA8  E5            PUSH HL  ; save HL context on stack
3CA9  D5            PUSH DE  ; save DE context on stack
3CAA  08            EX AF,AF'  ; swap in alternate AF for status byte
3CAB  78            LD A,B  ; fetch B (FDC status/flag byte)
3CAC  E6 80         AND 0x80  ; isolate bit7 (busy/terminal flag)
3CAE  CB 07         RLC A  ; rotate bit7 up toward result-code position
3CB0  CB 07         RLC A  ; continue rotating bit7 into place
3CB2  CB 07         RLC A  ; third rotate: bit7 now at bit2
3CB4  47            LD B,A  ; stash shifted flag into B
3CB5  08            EX AF,AF'  ; restore main AF
3CB6  0F            RRCA  ; rotate A right (repack rate/side bits)
3CB7  0F            RRCA  ; second right-rotate for field alignment
3CB8  F6 0D         OR 0x0D  ; OR-in fixed irq/enable bits 0x0D
3CBA  4F            LD C,A  ; save assembled control byte into C
3CBB  3A 1E 31      LD A,(drv_active_cfg)  ; load active drive config flags
3CBE  E6 01         AND 0x01  ; keep bit0 (drive A/B select)
3CC0  CB C7         SET 0,A  ; force bit0 set (enable selected drive)
3CC2  B0            OR B  ; merge in shifted flag from B
3CC3  47            LD B,A  ; store combined command byte back into B
3CC4  C5            PUSH BC  ; push assembled BC command word
3CC5  21 00 00      LD HL,0x0000  ; clear HL to zero
3CC8  39            ADD HL,SP  ; HL = current SP (capture stack top)
3CC9  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore FDC saved stack pointer
3CCD  FB            EI  ; re-enable interrupts
3CCE  06 06         LD B,0x06  ; B=6: FDC command byte count
3CD0  C3 64 3C      JP loc_3C64  ; jump to shared FDC exec loop

; build FDC specify/step params for both drives from step-rate/HUT state into per-side cmd blocks, set irq bits 0x0F
fdc_specify_dor:
3CD3  FD E5         PUSH IY  ; save IY (per-side cmd-block pointer)
3CD5  CD 6E 48      CALL panel_bus_on  ; assert panel/drive bus enable
3CD8  CD 83 48      CALL panel_sel_lo  ; drive panel select line low
3CDB  3E 0F         LD A,0x0F  ; A=0x0F: irq-enable bit pattern
3CDD  32 A1 4A      LD (fdc_result_save),A  ; seed FDC result-save byte with 0x0F
3CE0  ED 5B ED 4A   LD DE,(drive_blk_a+0x2)  ; DE = drive A step-rate/HUT word (blk+2)
3CE4  3A FB 4A      LD A,(drive_blk_a+0x10)  ; load drive A side/unit byte (blk+0x10)
3CE7  6F            LD L,A  ; L = drive A side/unit byte
3CE8  3A F0 4A      LD A,(drive_blk_a+0x5)  ; load drive A SPECIFY param (blk+5)
3CEB  D9            EXX  ; switch to alternate regs for drive B
3CEC  08            EX AF,AF'  ; stash drive A param byte in AF'
3CED  ED 5B 08 4B   LD DE,(drive_blk_b+0x2)  ; DE = drive B step-rate/HUT word (blk+2)
3CF1  3A 16 4B      LD A,(drive_blk_b+0x10)  ; load drive B side/unit byte (blk+0x10)
3CF4  6F            LD L,A  ; L = drive B side/unit byte
3CF5  3A 0B 4B      LD A,(drive_blk_b+0x5)  ; load drive B SPECIFY param (blk+5)
3CF8  DD 21 61 4A   LD IX,fdc_cmd_buf  ; IX -> drive A FDC command buffer
3CFC  FD 21 73 4A   LD IY,fdc_cmd_buf2  ; IY -> drive B FDC command buffer
3D00  F6 34         OR 0x34  ; OR-in HUT/mode bits 0x34 for SPECIFY
3D02  0F            RRCA  ; rotate right to align param field
3D03  0F            RRCA  ; second right-rotate for alignment
3D04  FD 77 00      LD (IY+0),A  ; store SPECIFY byte into drive B cmd buf
3D07  22 77 4A      LD (fdc_cmd_buf2+0x4),HL  ; write side/unit word into buf2+4
3D0A  ED 53 75 4A   LD (fdc_cmd_buf2+0x2),DE  ; write step-rate/HUT word into buf2+2
3D0E  D9            EXX  ; back to main regs for drive A
3D0F  08            EX AF,AF'  ; recover drive A param from AF'
3D10  F6 34         OR 0x34  ; OR-in HUT/mode bits 0x34 for SPECIFY
3D12  0F            RRCA  ; rotate right to align param field
3D13  0F            RRCA  ; second right-rotate for alignment
3D14  DD 77 00      LD (IX+0),A  ; store SPECIFY byte into drive A cmd buf
3D17  22 65 4A      LD (fdc_cmd_buf+0x4),HL  ; write side/unit word into buf+4
3D1A  ED 53 63 4A   LD (fdc_cmd_buf+0x2),DE  ; write step-rate/HUT word into buf+2
3D1E  3A 1E 31      LD A,(drv_active_cfg)  ; load active drive config flags
3D21  E6 01         AND 0x01  ; keep bit0 (drive select)
3D23  CB C7         SET 0,A  ; force bit0 set
3D25  DD 77 01      LD (IX+1),A  ; store unit byte into drive A cmd buf+1
3D28  F6 04         OR 0x04  ; OR-in bit2 (side/head select) for drive B
3D2A  FD 77 01      LD (IY+1),A  ; store unit byte into drive B cmd buf+1
3D2D  21 61 4A      LD HL,fdc_cmd_buf  ; HL -> drive A FDC command buffer
3D30  06 06         LD B,0x06  ; B=6: SPECIFY command byte count
3D32  0E 00         LD C,0x00  ; C=0x00: drive A FDC port base
3D34  CD 7F 45      CALL fdc_write_bytes  ; write 6-byte cmd block to drive A FDC
3D37  21 73 4A      LD HL,fdc_cmd_buf2  ; HL -> drive B FDC command buffer
3D3A  06 06         LD B,0x06  ; B=6: SPECIFY command byte count
3D3C  0E 20         LD C,0x20  ; C=0x20: drive B FDC port base
3D3E  CD 7F 45      CALL fdc_write_bytes  ; write 6-byte cmd block to drive B FDC
3D41  FD E1         POP IY  ; restore IY
3D43  C9            RET  ; return

; issue seek via DMA then wait for completion
fdc_seek_write_wrap:
3D44  F5            PUSH AF  ; save AF (drive-index arg) across seek
3D45  CD 4B 3D      CALL fdc_seek_dma  ; issue the seek via DMA setup
3D48  C3 04 3A      JP loc_3A04  ; jump to seek-completion wait routine

; arm FDC seek via DMA (8 desc): pick blk A/B by A bit0, set bank/drive latch, exec via SP-swap
fdc_seek_dma:
3D4B  C5            PUSH BC  ; save BC
3D4C  D5            PUSH DE  ; save DE
3D4D  E5            PUSH HL  ; save HL
3D4E  E6 7F         AND 0x7F  ; mask off top bit (keep drive index bits)
3D50  DD E5         PUSH IX  ; save IX
3D52  CB 47         BIT 0,A  ; test bit0: select drive A vs B block
3D54  DD 21 06 4B   LD IX,drive_blk_b  ; default IX -> drive B block
3D58  0E C6         LD C,0xC6  ; C=0xC6: drive B bank/latch port
3D5A  28 06         JR Z,loc_3D62  ; if bit0 clear keep drive B path
3D5C  DD 21 EB 4A   LD IX,drive_blk_a  ; bit0 set: IX -> drive A block
3D60  0E B0         LD C,0xB0  ; C=0xB0: drive A image-bank select port

loc_3D62:
3D62  DD 46 07      LD B,(IX+7)  ; load bank/drive latch value (blk+7)
3D65  ED 41         OUT (C),B  ; output bank/drive select to latch port
3D67  F5            PUSH AF  ; save AF (drive-index status)
3D68  21 08 00      LD HL,0x0008  ; HL=8: DMA descriptor count
3D6B  45            LD B,L  ; B=8: descriptor loop counter
3D6C  CD EC 43      CALL dma_arm_desc  ; arm the 8 DMA seek descriptors
3D6F  F3            DI  ; disable interrupts around SP-swap exec
3D70  ED 73 54 4A   LD (fdc_saved_sp),SP  ; save current SP
3D74  DD F9         LD SP,IX  ; point SP at drive block (pop params)
3D76  C1            POP BC  ; pop BC from drive block
3D77  D1            POP DE  ; pop DE from drive block
3D78  E1            POP HL  ; pop HL from drive block
3D79  3A 16 4B      LD A,(drive_blk_b+0x10)  ; load drive B side/unit byte
3D7C  6F            LD L,A  ; L = drive B side/unit byte
3D7D  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore saved SP
3D81  FB            EI  ; re-enable interrupts
3D82  F1            POP AF  ; pop AF (drive-index status)
3D83  F5            PUSH AF  ; re-save AF for later test
3D84  FE 01         CP 0x01  ; compare drive index against 1
3D86  C2 8F 3D      JP NZ,loc_3D8F  ; skip drive-A patch if not drive 1
3D89  08            EX AF,AF'  ; swap in alternate AF
3D8A  3A FB 4A      LD A,(drive_blk_a+0x10)  ; load drive A side/unit byte
3D8D  6F            LD L,A  ; L = drive A side/unit byte
3D8E  08            EX AF,AF'  ; restore main AF

loc_3D8F:
3D8F  CD 86 3C      CALL fdc_format_cmd  ; issue FDC seek/format command
3D92  C3 E7 3E      JP loc_3EE7  ; jump to post-command handler

; read a full track: prep DMA read then poll completion in a timeout-guarded loop
fdc_read_track:
3D95  CD B9 3D      CALL fdc_read_dma_prep  ; prep DMA read of the full track

loc_3D98:
3D98  CD 48 48      CALL timeout_start  ; start the completion timeout timer

loc_3D9B:
3D9B  3E 01         LD A,0x01  ; A=1: poll phase 1 (exec/data)
3D9D  CD 2D 47      CALL fdc_poll_complete  ; poll FDC for completion
3DA0  20 06         JR NZ,loc_3DA8  ; if complete, go read result phase
3DA2  CD 57 48      CALL timeout_check  ; check whether timeout elapsed
3DA5  30 F4         JR NC,loc_3D9B  ; not timed out: keep polling
3DA7  C9            RET  ; timed out: return

loc_3DA8:
3DA8  08            EX AF,AF'  ; swap in alternate AF (save phase-1 status)

loc_3DA9:
3DA9  3E 02         LD A,0x02  ; A=2: poll phase 2 (result)
3DAB  CD 04 47      CALL fdc_poll_result  ; poll FDC result phase
3DAE  20 06         JR NZ,loc_3DB6  ; if result ready, finish up
3DB0  CD 57 48      CALL timeout_check  ; check whether timeout elapsed
3DB3  30 F4         JR NC,loc_3DA9  ; not timed out: keep polling result
3DB5  C9            RET  ; timed out: return

loc_3DB6:
3DB6  D8            RET C  ; propagate carry (error) to caller
3DB7  08            EX AF,AF'  ; restore phase-1 status from AF'
3DB8  C9            RET  ; return

; prep FDC DMA read: verify drive ready, OR-in irq bits 0xF0, reset all 4 fdc result buffers
fdc_read_dma_prep:
3DB9  C5            PUSH BC  ; save BC
3DBA  D5            PUSH DE  ; save DE
3DBB  E5            PUSH HL  ; save HL
3DBC  CD 74 49      CALL fdc_drive_ready  ; verify selected drive is ready
3DBF  28 30         JR Z,loc_3DF1  ; bail out if drive not ready

loc_3DC1:
3DC1  DD E5         PUSH IX  ; save IX
3DC3  DD 21 A1 4A   LD IX,fdc_result_save  ; IX -> FDC result-save byte
3DC7  DD 7E 00      LD A,(IX+0)  ; read current result-save byte
3DCA  F6 F0         OR 0xF0  ; OR-in irq/enable bits 0xF0
3DCC  DD 77 00      LD (IX+0),A  ; store updated result-save byte
3DCF  DD 21 85 4A   LD IX,fdc_result_buf  ; IX -> FDC result buffer 0
3DD3  CD D2 49      CALL fdc_result_reset  ; clear result buffer 0
3DD6  DD 21 93 4A   LD IX,fdc_result_buf2  ; IX -> FDC result buffer 2
3DDA  CD D2 49      CALL fdc_result_reset  ; clear result buffer 2
3DDD  DD 21 8C 4A   LD IX,fdc_result_buf1  ; IX -> FDC result buffer 1
3DE1  CD D2 49      CALL fdc_result_reset  ; clear result buffer 1
3DE4  DD 21 9A 4A   LD IX,fdc_result_buf3  ; IX -> FDC result buffer 3
3DE8  CD D2 49      CALL fdc_result_reset  ; clear result buffer 3
3DEB  DD E1         POP IX  ; restore IX
3DED  E1            POP HL  ; restore HL
3DEE  D1            POP DE  ; restore DE
3DEF  C1            POP BC  ; restore BC
3DF0  C9            RET  ; return

loc_3DF1:
3DF1  3A F2 4A      LD A,(drive_blk_a+0x7)  ; Fetch drive A image bank number from its drive block
3DF4  D3 B0         OUT (0xB0),A  ; dram_bank — Select 32 KB DRAM image bank for drive A transfer
3DF6  3A 0D 4B      LD A,(drive_blk_b+0x7)  ; Fetch drive B bank/select byte from its drive block
3DF9  D3 C6         OUT (0xC6),A  ; drive_sel_b — Latch drive B select via 0xC6
3DFB  DD E5         PUSH IX  ; Save caller's IX before DMA setup
3DFD  CD 57 44      CALL dma_setup  ; Program the uPD8237A DMA for this transfer

; seek+write both drives: send specify, arm DMA ch1(0x81)/ch2(0x82) 8 desc, exec via SP-swap
fdc_seek_write_dma:
3E00  CD D3 3C      CALL fdc_specify_dor  ; Issue FDC SPECIFY and set up the DOR
3E03  DD 21 EB 4A   LD IX,drive_blk_a  ; Point IX at drive A block for descriptor build
3E07  3E 81         LD A,0x81  ; DMA channel-1 arm value (0x81) for drive A
3E09  21 0C 00      LD HL,0x000C  ; Descriptor byte offset 0x0C within the block
3E0C  06 08         LD B,0x08  ; Arm 8 descriptor bytes
3E0E  CD EC 43      CALL dma_arm_desc  ; Build/arm the drive A DMA channel-1 descriptor
3E11  DD 21 06 4B   LD IX,drive_blk_b  ; Point IX at drive B block
3E15  3E 82         LD A,0x82  ; DMA channel-2 arm value (0x82) for drive B
3E17  21 0C 00      LD HL,0x000C  ; Descriptor byte offset 0x0C within the block
3E1A  06 08         LD B,0x08  ; Arm 8 descriptor bytes
3E1C  CD EC 43      CALL dma_arm_desc  ; Build/arm the drive B DMA channel-2 descriptor
3E1F  F3            DI  ; Disable interrupts around SP-swap command feed
3E20  ED 73 54 4A   LD (fdc_saved_sp),SP  ; Stash real SP so we can borrow SP as a fast pointer
3E24  DD F9         LD SP,IX  ; Point SP at drive block to POP the FDC command bytes
3E26  C1            POP BC  ; Pull first pair of command params via POP
3E27  D1            POP DE  ; Pull next command param pair
3E28  E1            POP HL  ; Pull next command param pair into HL
3E29  08            EX AF,AF'  ; Swap in alt AF to preserve running value
3E2A  DD 7E 1A      LD A,(IX+26)  ; Load side/head flag byte from block+26
3E2D  CB 27         SLA A  ; Shift head bit into position
3E2F  B4            OR H  ; Merge with H (cylinder byte)
3E30  67            LD H,A  ; Store combined byte back into H
3E31  08            EX AF,AF'  ; Restore main AF
3E32  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; Restore the real stack pointer
3E36  C5            PUSH BC  ; Push assembled command params back onto real stack
3E37  D5            PUSH DE  ; Push next command pair
3E38  E5            PUSH HL  ; Push HL command pair
3E39  DD 21 EB 4A   LD IX,drive_blk_a  ; Re-point IX at drive A block for its command feed
3E3D  ED 73 54 4A   LD (fdc_saved_sp),SP  ; Stash real SP again for second SP-swap
3E41  DD F9         LD SP,IX  ; Borrow SP as pointer into drive A block
3E43  C1            POP BC  ; POP drive A command param pair
3E44  D1            POP DE  ; POP next drive A command pair
3E45  E1            POP HL  ; POP drive A command pair into HL
3E46  08            EX AF,AF'  ; Swap in alt AF
3E47  DD 7E 1A      LD A,(IX+26)  ; Load drive A side/head flag from block+26
3E4A  CB 27         SLA A  ; Shift head bit into position
3E4C  B4            OR H  ; Merge with cylinder byte in H
3E4D  67            LD H,A  ; Store combined byte back into H
3E4E  08            EX AF,AF'  ; Restore main AF
3E4F  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; Restore the real stack pointer
3E53  FB            EI  ; Re-enable interrupts
3E54  3E 81         LD A,0x81  ; DMA channel-1 select (0x81) for drive A write
3E56  CD E9 3B      CALL fdc_wr_side0  ; Issue FDC WRITE side-0 command for drive A
3E59  E1            POP HL  ; Recover drive A command params from stack
3E5A  D1            POP DE  ; Recover next param pair
3E5B  C1            POP BC  ; Recover param pair
3E5C  3E 82         LD A,0x82  ; DMA channel-2 select (0x82) for drive B write
3E5E  CD E9 3B      CALL fdc_wr_side0  ; Issue FDC WRITE side-0 command for drive B
3E61  C3 E8 3E      JP loc_3EE8  ; Jump to shared exit/cleanup

; arm FDC DMA read then wait for completion
fdc_dma_exec:
3E64  F5            PUSH AF  ; Preserve command byte in AF across the DMA read
3E65  CD 6B 3E      CALL fdc_dma_arm2  ; Arm the FDC DMA read
3E68  C3 04 3A      JP loc_3A04  ; Continue into DMA-read wait/completion path

; arm FDC DMA read: check drive ready, if ready reset result buffers then proceed
fdc_dma_arm2:
3E6B  C5            PUSH BC  ; Save BC across the read arm
3E6C  D5            PUSH DE  ; Save DE
3E6D  E5            PUSH HL  ; Save HL
3E6E  F5            PUSH AF  ; Save AF (drive/command byte)
3E6F  CD 74 49      CALL fdc_drive_ready  ; Poll whether the target drive is ready
3E72  28 04         JR Z,loc_3E78  ; If drive ready, proceed to reset result buffers
3E74  F1            POP AF  ; Drive not ready: recover AF
3E75  C3 C1 3D      JP loc_3DC1  ; Bail out to not-ready error handler

loc_3E78:
3E78  F1            POP AF  ; Recover drive/command byte
3E79  E6 7F         AND 0x7F  ; Mask off top bit to isolate drive index
3E7B  DD E5         PUSH IX  ; Save caller's IX
3E7D  CB 47         BIT 0,A  ; Test bit0 to pick which drive
3E7F  DD 21 06 4B   LD IX,drive_blk_b  ; Default IX to drive B block
3E83  0E C6         LD C,0xC6  ; Default port to drive B select (0xC6)
3E85  28 06         JR Z,loc_3E8D  ; If bit0 clear, keep drive B selection
3E87  DD 21 EB 4A   LD IX,drive_blk_a  ; Otherwise point IX at drive A block
3E8B  0E B0         LD C,0xB0  ; Use DRAM bank port (0xB0) for drive A

loc_3E8D:
3E8D  DD 46 07      LD B,(IX+7)  ; Load this drive's bank/select byte from block+7
3E90  ED 41         OUT (C),B  ; Latch bank/select to the chosen port
3E92  F5            PUSH AF  ; Preserve command byte
3E93  21 08 00      LD HL,0x0008  ; Descriptor offset 0x0008 within block
3E96  45            LD B,L  ; Arm 8 descriptor bytes (B=L=8)
3E97  CD EC 43      CALL dma_arm_desc  ; Build/arm the read descriptor
3E9A  F1            POP AF  ; Recover command byte
3E9B  F5            PUSH AF  ; Preserve it again
3E9C  F6 80         OR 0x80  ; Set DMA read direction bit (0x80)
3E9E  21 0C 00      LD HL,0x000C  ; Descriptor offset 0x000C within block
3EA1  06 08         LD B,0x08  ; Arm 8 descriptor bytes
3EA3  CD EC 43      CALL dma_arm_desc  ; Build/arm the second read descriptor
3EA6  F1            POP AF  ; Recover command byte
3EA7  F5            PUSH AF  ; Preserve it
3EA8  F6 80         OR 0x80  ; Set DMA read direction bit (0x80)
3EAA  F3            DI  ; Disable interrupts around SP-swap feed
3EAB  ED 73 54 4A   LD (fdc_saved_sp),SP  ; Stash real SP
3EAF  DD F9         LD SP,IX  ; Borrow SP as pointer into drive block
3EB1  C1            POP BC  ; POP command param pair
3EB2  D1            POP DE  ; POP next param pair
3EB3  E1            POP HL  ; POP param pair into HL
3EB4  08            EX AF,AF'  ; Swap in alt AF
3EB5  DD 7E 1A      LD A,(IX+26)  ; Load side/head flag from block+26
3EB8  CB 27         SLA A  ; Shift head bit into position
3EBA  B4            OR H  ; Merge with cylinder byte in H
3EBB  67            LD H,A  ; Store combined byte back into H
3EBC  08            EX AF,AF'  ; Restore main AF
3EBD  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; Restore real SP
3EC1  FB            EI  ; Re-enable interrupts
3EC2  CD E9 3B      CALL fdc_wr_side0  ; Issue FDC READ side-0 command
3EC5  F3            DI  ; Disable interrupts for result-collect SP-swap
3EC6  ED 73 54 4A   LD (fdc_saved_sp),SP  ; Stash real SP
3ECA  DD F9         LD SP,IX  ; Borrow SP as pointer into drive block
3ECC  C1            POP BC  ; POP result pair
3ECD  D1            POP DE  ; POP result pair
3ECE  E1            POP HL  ; POP result pair
3ECF  3A 16 4B      LD A,(drive_blk_b+0x10)  ; Load drive B result/status byte from block+0x10
3ED2  6F            LD L,A  ; Keep it in L
3ED3  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; Restore real SP
3ED7  FB            EI  ; Re-enable interrupts
3ED8  F1            POP AF  ; Recover drive/command byte
3ED9  F5            PUSH AF  ; Preserve it
3EDA  FE 01         CP 0x01  ; Compare drive selector to 1 (drive A?)
3EDC  20 06         JR NZ,loc_3EE4  ; If not drive A, skip drive A status load
3EDE  08            EX AF,AF'  ; Swap to alt AF
3EDF  3A FB 4A      LD A,(drive_blk_a+0x10)  ; Load drive A result/status byte from block+0x10
3EE2  6F            LD L,A  ; Keep it in L
3EE3  08            EX AF,AF'  ; Restore main AF

loc_3EE4:
3EE4  CD 7F 3C      CALL fdc_format_cmd2  ; Finalize/issue the follow-up format command

loc_3EE7:
3EE7  F1            POP AF  ; Discard saved command byte

loc_3EE8:
3EE8  DD E1         POP IX  ; Restore caller's IX
3EEA  E1            POP HL  ; Restore HL
3EEB  D1            POP DE  ; Restore DE
3EEC  C1            POP BC  ; Restore BC
3EED  C9            RET  ; Return to caller

; write both drives via DMA then poll completion with timeout
fdc_write_both_wrap:
3EEE  CD F4 3E      CALL fdc_write_dma_both  ; Kick off DMA write to both drives
3EF1  C3 98 3D      JP loc_3D98  ; Then poll for completion with timeout

; write both drives via DMA: set dram_bank+drive_sel_b, arm ch1/ch2 8-desc writes, exec via SP-swap
fdc_write_dma_both:
3EF4  C5            PUSH BC  ; Save BC
3EF5  D5            PUSH DE  ; Save DE
3EF6  E5            PUSH HL  ; Save HL
3EF7  3A F2 4A      LD A,(drive_blk_a+0x7)  ; Fetch drive A image bank number
3EFA  D3 B0         OUT (0xB0),A  ; dram_bank — Select DRAM image bank for drive A
3EFC  3A 0D 4B      LD A,(drive_blk_b+0x7)  ; Fetch drive B bank/select byte
3EFF  D3 C6         OUT (0xC6),A  ; drive_sel_b — Latch drive B select via 0xC6
3F01  DD E5         PUSH IX  ; Save caller's IX
3F03  DD 21 EB 4A   LD IX,drive_blk_a  ; Point IX at drive A block
3F07  21 08 00      LD HL,0x0008  ; Descriptor offset 0x0008 within block
3F0A  45            LD B,L  ; Arm 8 descriptor bytes (B=L=8)
3F0B  3E 01         LD A,0x01  ; DMA channel-1 select (0x01) for drive A
3F0D  CD EC 43      CALL dma_arm_desc  ; Build/arm drive A write descriptor
3F10  DD 21 06 4B   LD IX,drive_blk_b  ; Point IX at drive B block
3F14  21 08 00      LD HL,0x0008  ; Descriptor offset 0x0008 within block
3F17  45            LD B,L  ; Arm 8 descriptor bytes
3F18  3E 02         LD A,0x02  ; DMA channel-2 select (0x02) for drive B
3F1A  CD EC 43      CALL dma_arm_desc  ; Build/arm drive B write descriptor
3F1D  F3            DI  ; Disable interrupts around SP-swap feed
3F1E  ED 73 54 4A   LD (fdc_saved_sp),SP  ; Stash real SP
3F22  DD F9         LD SP,IX  ; Borrow SP as pointer into drive B block
3F24  C1            POP BC  ; POP command param pair
3F25  D1            POP DE  ; POP next param pair
3F26  E1            POP HL  ; POP param pair
3F27  3A 16 4B      LD A,(drive_blk_b+0x10)  ; Load drive B result/status byte from block+0x10
3F2A  6F            LD L,A  ; Keep it in L
3F2B  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; Restore real SP
3F2F  3E 02         LD A,0x02  ; DMA channel-2 select (0x02) for drive B
3F31  CD 86 3C      CALL fdc_format_cmd  ; Issue FDC FORMAT command for drive B
3F34  DD 21 EB 4A   LD IX,drive_blk_a  ; Point IX at drive A block
3F38  ED 73 54 4A   LD (fdc_saved_sp),SP  ; Stash real SP for second SP-swap
3F3C  DD F9         LD SP,IX  ; Borrow SP as pointer into drive A block
3F3E  C1            POP BC  ; POP command param pair
3F3F  D1            POP DE  ; POP param pair
3F40  E1            POP HL  ; POP param pair
3F41  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; Restore real SP
3F45  FB            EI  ; Re-enable interrupts
3F46  3A FB 4A      LD A,(drive_blk_a+0x10)  ; Load drive A result/status byte from block+0x10
3F49  6F            LD L,A  ; Keep it in L
3F4A  3E 01         LD A,0x01  ; DMA channel-1 select (0x01) for drive A
3F4C  F5            PUSH AF  ; Preserve select byte
3F4D  CD 86 3C      CALL fdc_format_cmd  ; Issue FDC FORMAT command for drive A
3F50  C3 E7 3E      JP loc_3EE7  ; Jump to shared cleanup/exit

; read from source drive then latch its bank/track pointers from format_desc (0x52E9..0x52ED) for copy
fdc_read_src:
3F53  E5            PUSH HL  ; Save HL across the read
3F54  E6 7F         AND 0x7F  ; Mask off top bit to isolate drive index
3F56  F5            PUSH AF  ; Preserve masked drive selector
3F57  CD 64 3E      CALL fdc_dma_exec  ; Execute the FDC DMA read from source drive

loc_3F5A:
3F5A  38 4A         JR C,loc_3FA6  ; On read error (carry), jump to error handler
3F5C  F1            POP AF  ; Recover drive selector
3F5D  6F            LD L,A  ; Keep it in L
3F5E  08            EX AF,AF'  ; Swap to alt AF
3F5F  7D            LD A,L  ; Reload drive selector into A
3F60  FE 01         CP 0x01  ; Compare to 1 (drive A source?)
3F62  28 0E         JR Z,loc_3F72  ; If drive A, take that branch
3F64  2A ED 52      LD HL,(format_desc+0x10)  ; Load track pointer from format_desc+0x10
3F67  3A EC 52      LD A,(format_desc+0xF)  ; Load source bank byte from format_desc+0xF
3F6A  32 0D 4B      LD (drive_blk_b+0x7),A  ; Latch source bank into drive B block+7
3F6D  22 12 4B      LD (drive_blk_b+0xC),HL  ; Latch source track pointer into drive B block+0xC
3F70  18 0C         JR loc_3F7E  ; Skip past the drive A variant

loc_3F72:
3F72  2A EA 52      LD HL,(format_desc+0xD)  ; Load track pointer from format_desc+0xD
3F75  3A E9 52      LD A,(format_desc+0xC)  ; Load source bank byte from format_desc+0xC
3F78  32 F2 4A      LD (drive_blk_a+0x7),A  ; Latch source bank into drive A block+7
3F7B  22 F7 4A      LD (drive_blk_a+0xC),HL  ; Latch source track pointer into drive A block+0xC

loc_3F7E:
3F7E  08            EX AF,AF'  ; swap to alternate AF to hold caller status flags
3F7F  F5            PUSH AF  ; save AF (return code) across the branch
3F80  3A E9 4A      LD A,(fdc_op_flags)  ; load FDC operation-mode flags (0=copy/DMA, nonzero=dual-read)
3F83  B7            OR A  ; test whether op-flag is zero
3F84  28 02         JR Z,loc_3F88  ; if zero, take the source-DMA path
3F86  18 07         JR loc_3F8F  ; otherwise take the dual-read path

loc_3F88:
3F88  F1            POP AF  ; restore AF (drive selector)
3F89  CD AA 3F      CALL fdc_src_dma  ; arm source-drive DMA transfer
3F8C  C3 A8 3F      JP loc_3FA8  ; join common exit

loc_3F8F:
3F8F  F1            POP AF  ; restore AF selector
3F90  F5            PUSH AF  ; re-save AF for the poll loop
3F91  CD F6 3A      CALL fdc_dma_read2  ; issue dual-FDC DMA read
3F94  F1            POP AF  ; restore AF selector
3F95  CD 48 48      CALL timeout_start  ; start the completion timeout timer

loc_3F98:
3F98  F5            PUSH AF  ; save selector across poll call
3F99  CD 2D 47      CALL fdc_poll_complete  ; poll FDC for transfer completion
3F9C  20 08         JR NZ,loc_3FA6  ; if complete (NZ), jump to discard-save exit
3F9E  F1            POP AF  ; restore selector
3F9F  CD 57 48      CALL timeout_check  ; check whether timeout has elapsed
3FA2  30 F4         JR NC,loc_3F98  ; not timed out yet, keep polling
3FA4  18 02         JR loc_3FA8  ; timed out, go to exit

loc_3FA6:
3FA6  33            INC SP  ; drop the saved AF from stack (2 bytes)
3FA7  33            INC SP  ; second half of discarding saved word

loc_3FA8:
3FA8  E1            POP HL  ; restore HL saved by caller
3FA9  C9            RET  ; return to caller

; arm source-drive DMA: set bank or drive latch by A==1, load ptr, compute byte length
fdc_src_dma:
3FAA  C5            PUSH BC  ; save BC across DMA setup
3FAB  D5            PUSH DE  ; save DE
3FAC  E5            PUSH HL  ; save HL
3FAD  DD E5         PUSH IX  ; save IX
3FAF  F5            PUSH AF  ; save the A selector value
3FB0  FE 01         CP 0x01  ; is this the primary drive-block (A==1)?
3FB2  20 0D         JR NZ,loc_3FC1  ; no, handle drive-block B
3FB4  3A F2 4A      LD A,(drive_blk_a+0x7)  ; load bank byte from drive block A
3FB7  D3 B0         OUT (0xB0),A  ; dram_bank — select DRAM image bank for source drive
3FB9  2A F7 4A      LD HL,(drive_blk_a+0xC)  ; load buffer pointer from drive block A
3FBC  22 21 4B      LD (dma_ptr_save),HL  ; stash pointer into DMA descriptor save area
3FBF  18 0B         JR loc_3FCC  ; skip block-B setup

loc_3FC1:
3FC1  3A 0D 4B      LD A,(drive_blk_b+0x7)  ; load drive-select byte from drive block B
3FC4  D3 C6         OUT (0xC6),A  ; drive_sel_b — latch drive-B select via PPI port 0xC6
3FC6  2A 12 4B      LD HL,(drive_blk_b+0xC)  ; load buffer pointer from drive block B
3FC9  22 25 4B      LD (dma_ptr_save+0x4),HL  ; stash B pointer into second DMA save slot

loc_3FCC:
3FCC  F1            POP AF  ; restore A selector
3FCD  2A F9 4A      LD HL,(drive_blk_a+0xE)  ; load end-address (drive_blk_a+0xE)
3FD0  ED 5B FF 4A   LD DE,(drive_blk_a+0x14)  ; load start-address (drive_blk_a+0x14)
3FD4  08            EX AF,AF'  ; swap in alternate AF
3FD5  AF            XOR A  ; clear A and carry for the subtract
3FD6  ED 52         SBC HL,DE  ; HL = end - start = byte length
3FD8  08            EX AF,AF'  ; swap AF back
3FD9  FE 01         CP 0x01  ; which slot did we fill (A==1 primary)?
3FDB  C2 EA 3F      JP NZ,loc_3FEA  ; not primary, use slot B
3FDE  F5            PUSH AF  ; save A selector
3FDF  22 23 4B      LD (dma_ptr_save+0x2),HL  ; store computed length into DMA save +2
3FE2  DD 21 21 4B   LD IX,dma_ptr_save  ; point IX at primary DMA descriptor
3FE6  3E 01         LD A,0x01  ; mark selector as primary (1)
3FE8  18 0A         JR loc_3FF4  ; join descriptor-arming

loc_3FEA:
3FEA  F5            PUSH AF  ; save A selector
3FEB  22 27 4B      LD (dma_ptr_save+0x6),HL  ; store length into DMA save +6 (slot B)
3FEE  DD 21 25 4B   LD IX,dma_ptr_save+0x4  ; point IX at slot-B DMA descriptor
3FF2  3E 02         LD A,0x02  ; mark selector as B (2)

loc_3FF4:
3FF4  06 04         LD B,0x04  ; arm all 4 DMA channels/bytes of descriptor
3FF6  21 00 00      LD HL,0x0000  ; zero offset for descriptor arming
3FF9  CD EC 43      CALL dma_arm_desc  ; program the uPD8237A DMA descriptor
3FFC  F1            POP AF  ; restore selector
3FFD  F5            PUSH AF  ; re-save selector
3FFE  FE 01         CP 0x01  ; primary drive (A==1)?
4000  C2 0B 40      JP NZ,loc_400B  ; no, use drive block B
4003  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX at drive block A parameters
4007  3E 01         LD A,0x01  ; mark selector primary
4009  18 06         JR loc_4011  ; proceed to command build

loc_400B:
400B  DD 21 06 4B   LD IX,drive_blk_b  ; point IX at drive block B parameters
400F  3E 02         LD A,0x02  ; mark selector B

loc_4011:
4011  F3            DI  ; disable interrupts around SP swap
4012  ED 73 54 4A   LD (fdc_saved_sp),SP  ; save real SP
4016  DD F9         LD SP,IX  ; point SP at drive-block for fast POP fetch
4018  C1            POP BC  ; pop cmd bytes into BC
4019  D1            POP DE  ; pop next params into DE
401A  E1            POP HL  ; pop cylinder/head into HL
401B  08            EX AF,AF'  ; swap in alt AF
401C  DD 7E 1A      LD A,(IX+26)  ; load head/side byte from block (IX+26)
401F  3C            INC A  ; increment it
4020  CB 27         SLA A  ; shift left (align head bit)
4022  B4            OR H  ; merge with H
4023  67            LD H,A  ; store combined value back to H
4024  08            EX AF,AF'  ; swap AF back
4025  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore real SP
4029  FB            EI  ; re-enable interrupts
402A  CD 04 3B      CALL fdc_read_cmd  ; issue FDC READ command sequence
402D  CD 48 48      CALL timeout_start  ; start completion timeout
4030  F1            POP AF  ; restore selector
4031  FE 01         CP 0x01  ; primary drive?
4033  26 01         LD H,0x01  ; set drive tag H=1 for primary
4035  28 02         JR Z,loc_4039  ; if primary, keep tag
4037  26 02         LD H,0x02  ; else drive tag H=2

loc_4039:
4039  7C            LD A,H  ; A = drive tag for poll
403A  E5            PUSH HL  ; save tag across poll
403B  CD 2D 47      CALL fdc_poll_complete  ; poll FDC for command completion
403E  E1            POP HL  ; restore tag
403F  20 08         JR NZ,loc_4049  ; if complete (NZ), branch to second-half read
4041  7C            LD A,H  ; A = drive tag
4042  CD 57 48      CALL timeout_check  ; check timeout elapsed
4045  30 F2         JR NC,loc_4039  ; not timed out, keep polling
4047  18 74         JR loc_40BD  ; timed out, jump to exit

loc_4049:
4049  7C            LD A,H  ; A = drive tag
404A  38 71         JR C,loc_40BD  ; if carry (error/timeout), exit
404C  2A FF 4A      LD HL,(drive_blk_a+0x14)  ; load start-address for second transfer
404F  2B            DEC HL  ; decrement to make it a length/end value
4050  22 23 4B      LD (dma_ptr_save+0x2),HL  ; store into DMA save +2
4053  22 27 4B      LD (dma_ptr_save+0x6),HL  ; store into DMA save +6
4056  F5            PUSH AF  ; save selector
4057  FE 01         CP 0x01  ; primary drive?
4059  20 08         JR NZ,loc_4063  ; no, use slot B
405B  DD 21 21 4B   LD IX,dma_ptr_save  ; point IX at primary DMA descriptor
405F  3E 01         LD A,0x01  ; mark selector primary
4061  18 06         JR loc_4069  ; proceed

loc_4063:
4063  DD 21 25 4B   LD IX,dma_ptr_save+0x4  ; point IX at slot-B DMA descriptor
4067  3E 02         LD A,0x02  ; mark selector B

loc_4069:
4069  06 04         LD B,0x04  ; arm all 4 DMA descriptor entries
406B  21 00 00      LD HL,0x0000  ; zero offset
406E  CD EC 43      CALL dma_arm_desc  ; program the DMA descriptor for 2nd half
4071  F1            POP AF  ; restore selector
4072  F5            PUSH AF  ; re-save selector
4073  FE 01         CP 0x01  ; primary drive?
4075  20 08         JR NZ,loc_407F  ; no, drive block B
4077  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX at drive block A params
407B  3E 01         LD A,0x01  ; mark selector primary
407D  18 06         JR loc_4085  ; proceed to command build

loc_407F:
407F  DD 21 06 4B   LD IX,drive_blk_b  ; point IX at drive block B params
4083  3E 02         LD A,0x02  ; mark selector B

loc_4085:
4085  F3            DI  ; disable interrupts around SP swap
4086  ED 73 54 4A   LD (fdc_saved_sp),SP  ; save real SP
408A  DD F9         LD SP,IX  ; point SP at drive-block params
408C  C1            POP BC  ; pop cmd bytes into BC
408D  D1            POP DE  ; pop params into DE
408E  16 01         LD D,0x01  ; force D=1 (2nd-half read flag)
4090  E1            POP HL  ; pop cylinder/head into HL
4091  08            EX AF,AF'  ; swap in alt AF
4092  DD 7E 1A      LD A,(IX+26)  ; load head/side byte from block (IX+26)
4095  CB 27         SLA A  ; shift left to align head bit
4097  B4            OR H  ; merge with H
4098  67            LD H,A  ; store combined value to H
4099  08            EX AF,AF'  ; swap AF back
409A  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore real SP
409E  FB            EI  ; re-enable interrupts
409F  CD 04 3B      CALL fdc_read_cmd  ; issue FDC READ command
40A2  CD 48 48      CALL timeout_start  ; start completion timeout
40A5  F1            POP AF  ; restore selector
40A6  FE 01         CP 0x01  ; primary drive?
40A8  26 01         LD H,0x01  ; set drive tag H=1
40AA  28 02         JR Z,loc_40AE  ; if primary keep tag
40AC  26 02         LD H,0x02  ; else drive tag H=2

loc_40AE:
40AE  7C            LD A,H  ; A = drive tag for poll
40AF  E5            PUSH HL  ; save tag
40B0  CD 2D 47      CALL fdc_poll_complete  ; poll FDC for completion
40B3  E1            POP HL  ; restore tag
40B4  20 07         JR NZ,loc_40BD  ; if complete, exit
40B6  CD 57 48      CALL timeout_check  ; check timeout
40B9  30 F3         JR NC,loc_40AE  ; not timed out, keep polling
40BB  18 00         JR loc_40BD  ; fall through to exit

loc_40BD:
40BD  DD E1         POP IX  ; restore IX
40BF  E1            POP HL  ; restore HL
40C0  D1            POP DE  ; restore DE
40C1  C1            POP BC  ; restore BC
40C2  C9            RET  ; return to caller

; copy one track: read source track, latch dest geometry from format_desc, write to dest drive if enabled
fdc_copy_track:
40C3  E5            PUSH HL  ; save HL across track copy
40C4  CD 95 3D      CALL fdc_read_track  ; read one track from the source drive

loc_40C7:
40C7  38 4C         JR C,loc_4115  ; on error (carry) skip to exit
40C9  2A ED 52      LD HL,(format_desc+0x10)  ; load dest buffer pointer from format descriptor
40CC  3A EC 52      LD A,(format_desc+0xF)  ; load dest bank/select byte from format descriptor
40CF  32 0D 4B      LD (drive_blk_b+0x7),A  ; store dest select into drive block B
40D2  22 12 4B      LD (drive_blk_b+0xC),HL  ; store dest pointer into drive block B
40D5  2A EA 52      LD HL,(format_desc+0xD)  ; load source buffer pointer from format descriptor
40D8  3A E9 52      LD A,(format_desc+0xC)  ; load source bank byte from format descriptor
40DB  32 F2 4A      LD (drive_blk_a+0x7),A  ; store source bank into drive block A
40DE  22 F7 4A      LD (drive_blk_a+0xC),HL  ; store source pointer into drive block A
40E1  3A E9 4A      LD A,(fdc_op_flags)  ; load FDC op-mode flags
40E4  B7            OR A  ; test op-flag zero
40E5  28 02         JR Z,loc_40E9  ; if zero, take write-track path
40E7  18 06         JR loc_40EF  ; else take dual-read path

loc_40E9:
40E9  CD 17 41      CALL fdc_write_track  ; write the track to the destination drive
40EC  C3 15 41      JP loc_4115  ; jump to exit

loc_40EF:
40EF  CD FE 3A      CALL fdc_read_dual2  ; issue dual-drive read (compare/verify path)
40F2  CD 48 48      CALL timeout_start  ; start completion timeout

loc_40F5:
40F5  3E 01         LD A,0x01  ; A=1: poll primary drive
40F7  CD 2D 47      CALL fdc_poll_complete  ; poll FDC completion
40FA  20 07         JR NZ,loc_4103  ; if complete, branch to second-drive poll
40FC  CD 57 48      CALL timeout_check  ; check timeout
40FF  30 F4         JR NC,loc_40F5  ; not timed out, keep polling primary
4101  18 12         JR loc_4115  ; timed out, exit

loc_4103:
4103  08            EX AF,AF'  ; save flags in alt AF

loc_4104:
4104  3E 02         LD A,0x02  ; A=2: poll second drive
4106  CD 04 47      CALL fdc_poll_result  ; read FDC result phase
4109  20 07         JR NZ,loc_4112  ; if done, branch to result check
410B  CD 57 48      CALL timeout_check  ; check timeout
410E  30 F4         JR NC,loc_4104  ; not timed out, keep polling second drive
4110  18 03         JR loc_4115  ; timed out, exit

loc_4112:
4112  38 01         JR C,loc_4115  ; if carry (error), exit
4114  08            EX AF,AF'  ; restore flags from alt AF

loc_4115:
4115  E1            POP HL  ; restore caller HL saved earlier
4116  C9            RET  ; return to caller

; write full track to dest drive: set latches, copy DMA base ptrs, compute length, arm 4-desc DMA descriptors
fdc_write_track:
4117  C5            PUSH BC  ; save BC across the track write
4118  D5            PUSH DE  ; save DE across the track write
4119  E5            PUSH HL  ; save HL across the track write
411A  3A 0D 4B      LD A,(drive_blk_b+0x7)  ; fetch dest drive-select byte from drive block B
411D  D3 C6         OUT (0xC6),A  ; drive_sel_b — write dest drive-select byte to drive_sel_b latch (0xC6)
411F  3A F2 4A      LD A,(drive_blk_a+0x7)  ; fetch source DRAM bank byte from drive block A
4122  D3 B0         OUT (0xB0),A  ; dram_bank — select 32 KB image bank for this track
4124  CD 61 42      CALL dma_set_ptrs  ; copy src/dest DMA base pointers into active descriptor slots
4127  2A F9 4A      LD HL,(drive_blk_a+0xE)  ; load track end pointer (drive A geometry)
412A  ED 5B FF 4A   LD DE,(drive_blk_a+0x14)  ; load track start pointer (drive A geometry)
412E  AF            XOR A  ; clear A and carry for the subtraction
412F  ED 52         SBC HL,DE  ; HL = end - start = track byte length
4131  22 23 4B      LD (dma_ptr_save+0x2),HL  ; store length into source DMA descriptor count
4134  22 27 4B      LD (dma_ptr_save+0x6),HL  ; store length into dest DMA descriptor count
4137  DD E5         PUSH IX  ; save IX before using it as DMA descriptor base
4139  DD 21 21 4B   LD IX,dma_ptr_save  ; point IX at the source DMA descriptor block
413D  06 04         LD B,0x04  ; 4 descriptor bytes to program
413F  21 00 00      LD HL,0x0000  ; start DMA channel address accumulator at 0
4142  3E 01         LD A,0x01  ; select DMA channel 1 (source FDC)
4144  CD EC 43      CALL dma_arm_desc  ; arm the 4-word source DMA descriptor
4147  DD 21 25 4B   LD IX,dma_ptr_save+0x4  ; point IX at the dest DMA descriptor block
414B  06 04         LD B,0x04  ; 4 descriptor bytes to program
414D  21 00 00      LD HL,0x0000  ; reset DMA channel address accumulator
4150  3E 02         LD A,0x02  ; select DMA channel 2 (dest FDC)
4152  CD EC 43      CALL dma_arm_desc  ; arm the 4-word dest DMA descriptor
4155  DD 21 06 4B   LD IX,drive_blk_b  ; point IX/SP trick at drive block B command area
4159  F3            DI  ; no interrupts during SP-swap command load
415A  ED 73 54 4A   LD (fdc_saved_sp),SP  ; stash real SP so we can borrow it
415E  DD F9         LD SP,IX  ; repurpose SP to pop from the drive-B block
4160  C1            POP BC  ; pull drive-B FDC command bytes into BC
4161  D1            POP DE  ; pull next command bytes into DE
4162  E1            POP HL  ; pull cylinder/head words into HL
4163  08            EX AF,AF'  ; swap to alt AF to preserve flags
4164  DD 7E 1A      LD A,(IX+26)  ; read side/head byte from drive block B (IX+26)
4167  3C            INC A  ; bump to form head number
4168  CB 27         SLA A  ; shift head bit into command position
416A  B4            OR H  ; merge head bit into H command word
416B  67            LD H,A  ; write patched head byte back into H
416C  08            EX AF,AF'  ; restore main AF
416D  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore the real stack pointer
4171  C5            PUSH BC  ; push assembled drive-B command word set (BC)
4172  D5            PUSH DE  ; push assembled command word (DE)
4173  E5            PUSH HL  ; push assembled command word (HL)
4174  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX/SP trick at drive block A command area
4178  ED 73 54 4A   LD (fdc_saved_sp),SP  ; stash real SP again for drive-A load
417C  DD F9         LD SP,IX  ; repurpose SP to pop from the drive-A block
417E  C1            POP BC  ; pull drive-A FDC command bytes into BC
417F  D1            POP DE  ; pull next command bytes into DE
4180  E1            POP HL  ; pull cylinder/head words into HL
4181  08            EX AF,AF'  ; swap to alt AF to preserve flags
4182  DD 7E 1A      LD A,(IX+26)  ; read side/head byte from drive block A (IX+26)
4185  3C            INC A  ; bump to form head number
4186  CB 27         SLA A  ; shift head bit into command position
4188  B4            OR H  ; merge head bit into H command word
4189  67            LD H,A  ; write patched head byte back into H
418A  08            EX AF,AF'  ; restore main AF
418B  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore the real stack pointer
418F  FB            EI  ; re-enable interrupts after command load
4190  3E 01         LD A,0x01  ; select FDC 1 (source drive)
4192  CD 04 3B      CALL fdc_read_cmd  ; issue queued command bytes to source FDC
4195  3E 02         LD A,0x02  ; select FDC 2 (dest drive)
4197  E1            POP HL  ; recover drive-A HL command words
4198  D1            POP DE  ; recover drive-A DE command words
4199  C1            POP BC  ; recover drive-A BC command words
419A  CD 04 3B      CALL fdc_read_cmd  ; issue queued command bytes to dest FDC
419D  CD 48 48      CALL timeout_start  ; start the operation timeout window

loc_41A0:
41A0  3E 01         LD A,0x01  ; select FDC 1 for completion poll
41A2  CD 2D 47      CALL fdc_poll_complete  ; poll source FDC for command completion
41A5  20 08         JR NZ,loc_41AF  ; completed -> go read its result phase
41A7  CD 57 48      CALL timeout_check  ; not done yet, check timeout
41AA  30 F4         JR NC,loc_41A0  ; still within timeout, keep polling
41AC  C3 5B 42      JP loc_425B  ; timed out -> abort track write

loc_41AF:
41AF  08            EX AF,AF'  ; save source-side status flags in alt AF

loc_41B0:
41B0  3E 02         LD A,0x02  ; select FDC 2 for result poll
41B2  CD 04 47      CALL fdc_poll_result  ; poll dest FDC for result phase
41B5  20 08         JR NZ,loc_41BF  ; result ready -> evaluate both drives
41B7  CD 57 48      CALL timeout_check  ; not ready, check timeout
41BA  30 F4         JR NC,loc_41B0  ; still within timeout, keep polling
41BC  C3 5B 42      JP loc_425B  ; timed out -> abort track write

loc_41BF:
41BF  DA 5B 42      JP C,loc_425B  ; dest FDC error flagged -> abort
41C2  08            EX AF,AF'  ; restore source-side status flags
41C3  DA 5B 42      JP C,loc_425B  ; source FDC error flagged -> abort
41C6  2A FF 4A      LD HL,(drive_blk_a+0x14)  ; reload track start pointer (drive A)
41C9  2B            DEC HL  ; back up one for the second-pass length
41CA  22 23 4B      LD (dma_ptr_save+0x2),HL  ; store into source DMA descriptor count
41CD  22 27 4B      LD (dma_ptr_save+0x6),HL  ; store into dest DMA descriptor count
41D0  DD 21 21 4B   LD IX,dma_ptr_save  ; point IX at source DMA descriptor block
41D4  06 04         LD B,0x04  ; 4 descriptor bytes to program
41D6  21 00 00      LD HL,0x0000  ; reset DMA address accumulator
41D9  3E 01         LD A,0x01  ; select DMA channel 1 (source FDC)
41DB  CD EC 43      CALL dma_arm_desc  ; arm the source DMA descriptor (second pass)
41DE  DD 21 25 4B   LD IX,dma_ptr_save+0x4  ; point IX at dest DMA descriptor block
41E2  06 04         LD B,0x04  ; 4 descriptor bytes to program
41E4  21 00 00      LD HL,0x0000  ; reset DMA address accumulator
41E7  3E 02         LD A,0x02  ; select DMA channel 2 (dest FDC)
41E9  CD EC 43      CALL dma_arm_desc  ; arm the dest DMA descriptor (second pass)
41EC  DD 21 06 4B   LD IX,drive_blk_b  ; point IX/SP trick at drive block B command area
41F0  F3            DI  ; no interrupts during SP-swap command load
41F1  ED 73 54 4A   LD (fdc_saved_sp),SP  ; stash real SP so we can borrow it
41F5  DD F9         LD SP,IX  ; repurpose SP to pop from the drive-B block
41F7  C1            POP BC  ; pull drive-B FDC command bytes into BC
41F8  D1            POP DE  ; pull next command bytes into DE
41F9  16 01         LD D,0x01  ; force D=1 (second-pass head/side selector)
41FB  E1            POP HL  ; pull cylinder/head words into HL
41FC  08            EX AF,AF'  ; swap to alt AF to preserve flags
41FD  DD 7E 1A      LD A,(IX+26)  ; read side/head byte from drive block B (IX+26)
4200  CB 27         SLA A  ; shift head bit into command position
4202  B4            OR H  ; merge head bit into H command word
4203  67            LD H,A  ; write patched head byte back into H
4204  08            EX AF,AF'  ; restore main AF
4205  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore the real stack pointer
4209  C5            PUSH BC  ; push assembled drive-B command word set (BC)
420A  D5            PUSH DE  ; push assembled command word (DE)
420B  E5            PUSH HL  ; push assembled command word (HL)
420C  DD 21 EB 4A   LD IX,drive_blk_a  ; point IX/SP trick at drive block A command area
4210  ED 73 54 4A   LD (fdc_saved_sp),SP  ; stash real SP again for drive-A load
4214  DD F9         LD SP,IX  ; repurpose SP to pop from the drive-A block
4216  C1            POP BC  ; pull drive-A FDC command bytes into BC
4217  D1            POP DE  ; pull next command bytes into DE
4218  16 01         LD D,0x01  ; force D=1 (second-pass head/side selector)
421A  E1            POP HL  ; pull cylinder/head words into HL
421B  08            EX AF,AF'  ; swap to alt AF to preserve flags
421C  DD 7E 1A      LD A,(IX+26)  ; read side/head byte from drive block A (IX+26)
421F  CB 27         SLA A  ; shift head bit into command position
4221  B4            OR H  ; merge head bit into H command word
4222  67            LD H,A  ; write patched head byte back into H
4223  08            EX AF,AF'  ; restore main AF
4224  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore the real stack pointer
4228  FB            EI  ; re-enable interrupts after command load
4229  3E 01         LD A,0x01  ; select FDC 1 (source drive)
422B  CD 04 3B      CALL fdc_read_cmd  ; issue second-pass command to source FDC
422E  3E 02         LD A,0x02  ; select FDC 2 (dest drive)
4230  E1            POP HL  ; recover drive-A HL command words
4231  D1            POP DE  ; recover drive-A DE command words
4232  C1            POP BC  ; recover drive-A BC command words
4233  CD 04 3B      CALL fdc_read_cmd  ; issue second-pass command to dest FDC
4236  CD 48 48      CALL timeout_start  ; start the operation timeout window

loc_4239:
4239  3E 01         LD A,0x01  ; select FDC 1 for completion poll
423B  CD 2D 47      CALL fdc_poll_complete  ; poll source FDC for command completion
423E  20 08         JR NZ,loc_4248  ; completed -> go read its result phase
4240  CD 57 48      CALL timeout_check  ; not done yet, check timeout
4243  30 F4         JR NC,loc_4239  ; still within timeout, keep polling
4245  C3 5B 42      JP loc_425B  ; timed out -> abort track write

loc_4248:
4248  08            EX AF,AF'  ; save source-side status flags in alt AF

loc_4249:
4249  3E 02         LD A,0x02  ; select FDC 2 for result poll
424B  CD 04 47      CALL fdc_poll_result  ; poll dest FDC for result phase
424E  20 08         JR NZ,loc_4258  ; result ready -> finish up
4250  CD 57 48      CALL timeout_check  ; not ready, check timeout
4253  30 F4         JR NC,loc_4249  ; still within timeout, keep polling
4255  C3 5B 42      JP loc_425B  ; timed out -> abort track write

loc_4258:
4258  38 01         JR C,loc_425B  ; dest FDC error flagged -> abort
425A  08            EX AF,AF'  ; restore source-side status flags

loc_425B:
425B  DD E1         POP IX  ; restore caller IX
425D  E1            POP HL  ; restore caller HL
425E  D1            POP DE  ; restore caller DE
425F  C1            POP BC  ; restore caller BC
4260  C9            RET  ; return to caller

; copy source(0x4AF7)/dest(0x4B12) DMA base pointers into active descriptor slots 0x4B21/0x4B25
dma_set_ptrs:
4261  2A F7 4A      LD HL,(drive_blk_a+0xC)  ; load source DMA base pointer (drive A)
4264  22 21 4B      LD (dma_ptr_save),HL  ; store into source descriptor slot
4267  2A 12 4B      LD HL,(drive_blk_b+0xC)  ; load dest DMA base pointer (drive B)
426A  22 25 4B      LD (dma_ptr_save+0x4),HL  ; store into dest descriptor slot
426D  C9            RET  ; return to caller
426E  E5            PUSH HL  ; save HL for the wrapper
426F  CD EE 3E      CALL fdc_write_both_wrap  ; write both sides with wrap handling
4272  C3 C7 40      JP loc_40C7  ; continue at shared post-write path
4275  E5            PUSH HL  ; save HL for the wrapper
4276  E6 7F         AND 0x7F  ; mask off high bit of track/side arg
4278  F5            PUSH AF  ; preserve masked arg on stack
4279  CD 44 3D      CALL fdc_seek_write_wrap  ; seek then write with wrap handling
427C  C3 5A 3F      JP loc_3F5A  ; return to shared write dispatcher

; write side via DMA (fdc_write_poll) then latch source geometry
fdc_read_src_b:
427F  E5            PUSH HL  ; save HL for the wrapper
4280  E6 7F         AND 0x7F  ; mask off high bit of track/side arg
4282  F5            PUSH AF  ; preserve masked arg on stack
4283  CD 24 3B      CALL fdc_write_poll  ; write side via DMA then poll for completion
4286  C3 5A 3F      JP loc_3F5A  ; return to shared write dispatcher

loc_4289:
4289  E5            PUSH HL  ; save HL for the wrapper
428A  CD 72 3B      CALL fdc_write_dual  ; write both drives in a single dual pass
428D  C3 C7 40      JP loc_40C7  ; continue at shared post-write path
4290  ED 4B 06 4B   LD BC,(drive_blk_b)  ; load drive-B block header into BC (default)
4294  FE 01         CP 0x01  ; is the requested drive index 1?
4296  20 04         JR NZ,loc_429C  ; not drive 1 -> keep drive-B block
4298  ED 4B EB 4A   LD BC,(drive_blk_a)  ; drive 1 -> load drive-A block header instead

loc_429C:
429C  CD A0 42      CALL fdc_op_poll_keys  ; poll keys and refresh FDC step rate for the selected side
429F  C9            RET  ; return to caller

; set FDC step rate from per-side track state (A selects side: 0x4B03 vs 0x4B1E), enable panel bus
fdc_op_poll_keys:
42A0  CD 6E 48      CALL panel_bus_on  ; enable the panel/FDC bus before touching drive state
42A3  F5            PUSH AF  ; save side selector in A across the routine
42A4  C5            PUSH BC  ; preserve BC
42A5  D5            PUSH DE  ; preserve DE
42A6  E5            PUSH HL  ; preserve HL
42A7  FE 01         CP 0x01  ; side A selected?
42A9  20 14         JR NZ,loc_42BF  ; no -> use side B / zero step params
42AB  08            EX AF,AF'  ; stash side selector in AF'
42AC  ED 5B 03 4B   LD DE,(drive_blk_a+0x18)  ; load side-A seek/step word from drive_blk_a
42B0  3A 02 4B      LD A,(drive_blk_a+0x17)  ; load side-A precomp/step byte
42B3  4F            LD C,A  ; -> C = step param for fdc_set_steprate
42B4  18 0C         JR loc_42C2  ; go program the step rate
42B6  08            EX AF,AF'  ; stash side selector in AF' (side-B path)
42B7  ED 5B 1E 4B   LD DE,(drive_blk_b+0x18)  ; load side-B seek/step word from drive_blk_b
42BB  3A 1D 4B      LD A,(drive_blk_b+0x17)  ; load side-B precomp/step byte
42BE  4F            LD C,A  ; -> C = step param for fdc_set_steprate

loc_42BF:
42BF  06 00         LD B,0x00  ; clear B (no side-specific step word)
42C1  08            EX AF,AF'  ; restore side selector from AF'

loc_42C2:
42C2  CD D5 44      CALL fdc_set_steprate  ; program FDC step/data rate from DE/BC
42C5  E1            POP HL  ; restore HL

loc_42C6:
42C6  D1            POP DE  ; restore DE
42C7  C1            POP BC  ; restore BC
42C8  F1            POP AF  ; restore AF (side selector)
42C9  E6 7F         AND 0x7F  ; mask off high bit -> drive index only
42CB  DD E5         PUSH IX  ; preserve IX
42CD  C5            PUSH BC  ; preserve BC
42CE  06 01         LD B,0x01  ; request one key/drive decode pass
42D0  CD 90 45      CALL key_decode  ; decode selected drive -> B holds drive-select bits
42D3  C1            POP BC  ; restore BC
42D4  08            EX AF,AF'  ; swap in alt accumulator
42D5  78            LD A,B  ; grab decoded flags byte from B
42D6  E6 80         AND 0x80  ; isolate the ready/side bit 7
42D8  07            RLCA  ; 1st RLCA: shift isolated bit7 toward FDC head-select bit2 (0x80->0x01)
42D9  07            RLCA  ; 2nd RLCA (0x01->0x02)
42DA  07            RLCA  ; 3rd RLCA -> head-select bit now at position 2 (0x04)
42DB  47            LD B,A  ; -> B = repositioned head-select bit for SEEK cmd byte1
42DC  08            EX AF,AF'  ; swap alt accumulator back

; build+issue FDC SEEK (opcode 0x0F, target cyl in C)
fdc_seek:
42DD  DD 21 73 4A   LD IX,fdc_cmd_buf2  ; default seek cmd buffer = fdc_cmd_buf2
42E1  FE 01         CP 0x01  ; side A selected?
42E3  20 04         JR NZ,loc_42E9  ; no -> keep buf2
42E5  DD 21 61 4A   LD IX,fdc_cmd_buf  ; side A -> use fdc_cmd_buf

loc_42E9:
42E9  DD 36 00 0F   LD (IX+0),0x0F  ; store SEEK opcode 0x0F in cmd byte 0
42ED  3A 1E 31      LD A,(drv_active_cfg)  ; read active drive config
42F0  E6 01         AND 0x01  ; keep unit-select bit
42F2  CB C7         SET 0,A  ; force drive-select bit 0 set
42F4  B0            OR B  ; OR in the head/side bit from B
42F5  47            LD B,A  ; -> B = SEEK parameter byte (drive+head)
42F6  DD 70 01      LD (IX+1),B  ; store drive/head byte in cmd byte 1
42F9  DD 71 02      LD (IX+2),C  ; store target cylinder (C) in cmd byte 2
42FC  DD E5         PUSH IX  ; copy IX (cmd buf) ...
42FE  E1            POP HL  ; ... into HL for fdc_write_bytes
42FF  DD E1         POP IX  ; restore IX
4301  06 03         LD B,0x03  ; 3-byte SEEK command length
4303  0E 20         LD C,0x20  ; default FDC port base 0x20 (drive 2)
4305  FE 01         CP 0x01  ; side A?
4307  F5            PUSH AF  ; save side selector
4308  20 02         JR NZ,loc_430C  ; no -> keep port 0x20
430A  0E 00         LD C,0x00  ; side A -> FDC port base 0x00 (drive 0)

loc_430C:
430C  CD 7F 45      CALL fdc_write_bytes  ; send the SEEK command to the FDC
430F  F1            POP AF  ; restore side selector
4310  C5            PUSH BC  ; preserve BC
4311  D5            PUSH DE  ; preserve DE
4312  E5            PUSH HL  ; preserve HL
4313  FE 01         CP 0x01  ; side A?
4315  ED 5B 1E 4B   LD DE,(drive_blk_b+0x18)  ; load side-B step word (default)
4319  20 04         JR NZ,loc_431F  ; no -> keep side-B word
431B  ED 5B 03 4B   LD DE,(drive_blk_a+0x18)  ; side A -> load side-A step word

loc_431F:
431F  06 00         LD B,0x00  ; clear B
4321  0E 01         LD C,0x01  ; C=1 minimal step param
4323  CD D5 44      CALL fdc_set_steprate  ; reprogram FDC step/data rate post-seek
4326  E1            POP HL  ; restore HL
4327  D1            POP DE  ; restore DE
4328  C1            POP BC  ; restore BC
4329  C9            RET  ; return to caller

; select FDC block (A==1->blkA else blkB) into BC and issue seek command
fdc_seek_sel:
432A  ED 4B 06 4B   LD BC,(drive_blk_b)  ; default BC = drive_blk_b descriptor
432E  FE 01         CP 0x01  ; side A selected?
4330  20 04         JR NZ,loc_4336  ; no -> keep block B
4332  ED 4B EB 4A   LD BC,(drive_blk_a)  ; side A -> BC = drive_blk_a descriptor

loc_4336:
4336  CD 3A 43      CALL fdc_send_seek  ; issue the seek using the selected block
4339  C9            RET  ; return to caller

; issue FDC seek: enable bus, decode drive, write specify (0x0F)+precomp into cmd block, select result buf
fdc_send_seek:
433A  CD 6E 48      CALL panel_bus_on  ; enable the panel/FDC bus
433D  E6 7F         AND 0x7F  ; mask off high bit -> drive index only
433F  DD E5         PUSH IX  ; preserve IX
4341  C5            PUSH BC  ; preserve BC
4342  06 01         LD B,0x01  ; request one drive decode pass
4344  CD 90 45      CALL key_decode  ; decode selected drive -> B = drive-select bits
4347  C1            POP BC  ; restore BC
4348  08            EX AF,AF'  ; swap in alt accumulator
4349  78            LD A,B  ; grab decoded flags byte from B
434A  E6 80         AND 0x80  ; isolate the ready/side bit 7
434C  07            RLCA  ; 1st RLCA: shift bit7 toward FDC head-select bit2 (0x80->0x01)
434D  07            RLCA  ; 2nd RLCA (0x01->0x02)
434E  07            RLCA  ; 3rd RLCA -> head-select bit now at position 2 (0x04)
434F  47            LD B,A  ; -> B = repositioned head-select bit for SEEK cmd
4350  08            EX AF,AF'  ; swap alt accumulator back
4351  DD 21 73 4A   LD IX,fdc_cmd_buf2  ; default seek cmd buffer = fdc_cmd_buf2
4355  FE 01         CP 0x01  ; side A selected?
4357  20 04         JR NZ,loc_435D  ; no -> keep buf2
4359  DD 21 61 4A   LD IX,fdc_cmd_buf  ; side A -> use fdc_cmd_buf

loc_435D:
435D  DD 36 00 0F   LD (IX+0),0x0F  ; store SEEK opcode 0x0F in cmd byte 0
4361  3A 1E 31      LD A,(drv_active_cfg)  ; read active drive config
4364  E6 01         AND 0x01  ; keep unit-select bit
4366  CB C7         SET 0,A  ; force drive-select bit 0 set
4368  B0            OR B  ; OR in head/side bit from B
4369  47            LD B,A  ; -> B = SEEK parameter byte (drive+head)
436A  DD 70 01      LD (IX+1),B  ; store drive/head byte in cmd byte 1
436D  DD 71 02      LD (IX+2),C  ; store target cylinder (C) in cmd byte 2
4370  DD E5         PUSH IX  ; copy IX (cmd buf) ...
4372  E1            POP HL  ; ... into HL for the writer
4373  DD E1         POP IX  ; restore IX
4375  06 03         LD B,0x03  ; 3-byte SEEK command length
4377  C3 73 3C      JP loc_3C73  ; tail-jump into shared FDC command-write path

; seek both drives to track 45 (0x2D) for alignment test: write specify+seek to FDC 0x10/0x30, wait panel ready
fdc_seek45_both:
437A  F5            PUSH AF  ; preserve AF
437B  C5            PUSH BC  ; preserve BC
437C  E5            PUSH HL  ; preserve HL
437D  DD E5         PUSH IX  ; preserve IX
437F  DD 21 6A 4A   LD IX,fdc_cmd_buf1  ; point IX at fdc_cmd_buf1
4383  DD 36 00 0F   LD (IX+0),0x0F  ; SEEK opcode 0x0F -> cmd byte 0
4387  DD 36 01 01   LD (IX+1),0x01  ; drive/head param 0x01 -> cmd byte 1
438B  DD 36 02 2D   LD (IX+2),0x2D  ; target cylinder 45 (0x2D) -> cmd byte 2
438F  0E 10         LD C,0x10  ; FDC port base 0x10 (drive 1)
4391  06 03         LD B,0x03  ; 3-byte SEEK length
4393  DD E5         PUSH IX  ; copy IX ...
4395  E1            POP HL  ; ... into HL for writer
4396  CD 7F 45      CALL fdc_write_bytes  ; send SEEK track 45 to FDC 0x10
4399  0E 30         LD C,0x30  ; FDC port base 0x30 (drive 3)
439B  06 03         LD B,0x03  ; 3-byte SEEK length
439D  DD E5         PUSH IX  ; copy IX ...
439F  E1            POP HL  ; ... into HL for writer
43A0  CD 7F 45      CALL fdc_write_bytes  ; send SEEK track 45 to FDC 0x30

loc_43A3:
43A3  DB F0         IN A,(0xF0)  ; panel — read panel status port
43A5  E6 0C         AND 0x0C  ; isolate both seek-complete bits
43A7  FE 0C         CP 0x0C  ; both drives done seeking?
43A9  20 F8         JR NZ,loc_43A3  ; no -> keep polling
43AB  3E 08         LD A,0x08  ; SENSE INTERRUPT opcode 0x08
43AD  21 6A 4A      LD HL,fdc_cmd_buf1  ; point HL at fdc_cmd_buf1
43B0  77            LD (HL),A  ; store SENSE INT opcode
43B1  0E 10         LD C,0x10  ; FDC port base 0x10
43B3  06 01         LD B,0x01  ; 1-byte command
43B5  CD 7F 45      CALL fdc_write_bytes  ; send SENSE INT to FDC 0x10
43B8  3E 08         LD A,0x08  ; SENSE INTERRUPT opcode 0x08
43BA  21 7C 4A      LD HL,fdc_cmd_buf3  ; point HL at fdc_cmd_buf3
43BD  0E 30         LD C,0x30  ; FDC port base 0x30
43BF  77            LD (HL),A  ; store SENSE INT opcode
43C0  06 01         LD B,0x01  ; 1-byte command
43C2  CD 7F 45      CALL fdc_write_bytes  ; send SENSE INT to FDC 0x30
43C5  0E 10         LD C,0x10  ; FDC port base 0x10
43C7  06 07         LD B,0x07  ; read 7 result bytes
43C9  21 8C 4A      LD HL,fdc_result_buf1  ; point HL at fdc_result_buf1
43CC  CD F1 46      CALL fdc_read_result  ; read SENSE INT result from FDC 0x10
43CF  0E 30         LD C,0x30  ; FDC port base 0x30
43D1  06 07         LD B,0x07  ; read 7 result bytes
43D3  21 9A 4A      LD HL,fdc_result_buf3  ; point HL at fdc_result_buf3
43D6  CD F1 46      CALL fdc_read_result  ; read SENSE INT result from FDC 0x30
43D9  DD E1         POP IX  ; restore IX
43DB  E1            POP HL  ; restore HL
43DC  C1            POP BC  ; restore BC
43DD  F1            POP AF  ; restore AF
43DE  C9            RET  ; return to caller
43DF  F5            PUSH AF  ; preserve AF
43E0  3E 0F         LD A,0x0F  ; DMA master-clear/write-mask value 0x0F
43E2  D3 8D         OUT (0x8D),A  ; dma_mclr — master-clear the 8237 DMA
43E4  D3 8F         OUT (0x8F),A  ; dma_wrmask — write-all-mask 0x0F: set all 4 channel mask bits (DMA disabled)
43E6  3E A0         LD A,0xA0  ; DMA command-register value 0xA0
43E8  D3 88         OUT (0x88),A  ; dma_cmd — program 8237 command register
43EA  F1            POP AF  ; restore AF
43EB  C9            RET  ; return to caller

; read {addr,count} descriptor from low-RAM table, arm the DMA channel (0x4401)
dma_arm_desc:
43EC  F3            DI  ; block interrupts while switching stacks
43ED  ED 73 54 4A   LD (fdc_saved_sp),SP  ; save real SP
43F1  DD E5         PUSH IX  ; get IX (base offset) ...
43F3  D1            POP DE  ; ... into DE
43F4  19            ADD HL,DE  ; HL = descriptor table + offset
43F5  F9            LD SP,HL  ; point SP at the descriptor
43F6  E1            POP HL  ; pop descriptor addr word -> HL
43F7  D1            POP DE  ; pop descriptor count word -> DE
43F8  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore real SP
43FC  FB            EI  ; re-enable interrupts
43FD  CD 01 44      CALL dma_arm_channel  ; arm the DMA channel from HL/DE
4400  C9            RET  ; return to caller

; program one 8237 DMA channel (addr/count/mode) from a descriptor
dma_arm_channel:
4401  C5            PUSH BC  ; preserve BC
4402  F5            PUSH AF  ; preserve AF
4403  CB 7F         BIT 7,A  ; test bit7 of DMA channel-selector code
4405  CA 1B 44      JP Z,loc_441B  ; bit7 clear -> low channel group (0/1)
4408  0E 86         LD C,0x86  ; default chan 3 DMA addr-reg port 0x86 (base+6)
440A  FE 81         CP 0x81  ; channel selector 0x81?
440C  C2 16 44      JP NZ,loc_4416  ; not 0x81 -> channel 3 path
440F  3E 02         LD A,0x02  ; DMA mode byte 0x02 for channel 2
4411  0E 84         LD C,0x84  ; chan 2 DMA addr-reg port 0x84 (base+4)
4413  C3 2E 44      JP loc_442E  ; go program addr/count

loc_4416:
4416  3E 03         LD A,0x03  ; DMA mode byte 0x03 for channel 3
4418  C3 2E 44      JP loc_442E  ; go program addr/count

loc_441B:
441B  0E 82         LD C,0x82  ; default chan 1 DMA addr-reg port 0x82 (base+2)
441D  FE 01         CP 0x01  ; channel 0x01?
441F  D3 8C         OUT (0x8C),A  ; dma_clrff — clear DMA byte-pointer flip-flop
4421  C2 2A 44      JP NZ,loc_442A  ; not 0x01 -> channel 1 path
4424  AF            XOR A  ; A=0: DMA mode byte 0x00 for channel 0
4425  0E 80         LD C,0x80  ; chan 0 DMA addr-reg port 0x80 (base+0)
4427  C3 2E 44      JP loc_442E  ; go program addr/count

loc_442A:
442A  3E 01         LD A,0x01  ; seed with channel-1 select bit (0x01)
442C  0E 82         LD C,0x82  ; point port C at 8237 ch-1 address register (0x82)

loc_442E:
442E  B0            OR B  ; merge in caller's read/write direction bits from B
442F  D3 8A         OUT (0x8A),A  ; dma_mask1 — arm DMA mask for this channel
4431  D3 8B         OUT (0x8B),A  ; dma_mode — program the DMA transfer mode
4433  7D            LD A,L  ; grab low byte of memory address
4434  ED 79         OUT (C),A  ; write ch-1 address low via port C
4436  7C            LD A,H  ; grab high byte of memory address
4437  ED 79         OUT (C),A  ; write ch-1 address high
4439  0C            INC C  ; advance port C to the count register (0x83)
443A  7B            LD A,E  ; grab low byte of transfer count
443B  ED 79         OUT (C),A  ; write ch-1 count low
443D  7A            LD A,D  ; grab high byte of transfer count
443E  ED 79         OUT (C),A  ; write ch-1 count high
4440  C1            POP BC  ; restore caller's flags word from stack into BC
4441  CB 78         BIT 7,B  ; test flag bit7: single vs dual-channel setup
4443  CA 4F 44      JP Z,loc_444F  ; if clear, skip the datarate-dependent branch
4446  CB 40         BIT 0,B  ; test flag bit0: pick between two mask values
4448  06 03         LD B,0x03  ; default mask value 0x03 (both channels)
444A  CA 51 44      JP Z,loc_4451  ; if bit0 clear keep 0x03 and continue
444D  06 04         LD B,0x04  ; otherwise use mask value 0x04

loc_444F:
444F  CB 38         SRL B  ; halve mask -> single-channel unmask value

loc_4451:
4451  AF            XOR A  ; clear A to build final unmask value
4452  B0            OR B  ; fold in the computed channel bits
4453  D3 8A         OUT (0x8A),A  ; dma_mask1 — unmask the selected DMA channel(s)
4455  C1            POP BC  ; restore caller BC
4456  C9            RET  ; return

; reset+reload 8237 channels 0/1 from the drive-block DMA descriptors
dma_setup:
4457  C5            PUSH BC  ; save BC across the reset
4458  3E 0F         LD A,0x0F  ; master-clear value for the 8237
445A  D3 8F         OUT (0x8F),A  ; dma_wrmask — issue DMA master clear
445C  3E 08         LD A,0x08  ; set channel-0 base DMA mode value (0x08)
445E  D3 8B         OUT (0x8B),A  ; dma_mode — program channel-0 mode
4460  3C            INC A  ; bump to channel-1 mode selector (0x09)
4461  D3 8B         OUT (0x8B),A  ; dma_mode — program channel-1 mode
4463  D3 8C         OUT (0x8C),A  ; dma_clrff — clear the byte-pointer flip-flop
4465  21 F3 4A      LD HL,drive_blk_a+0x8  ; point at drive-A DMA descriptor (addr+count words)
4468  0E 80         LD C,0x80  ; port C = ch-0 address register (0x80)
446A  06 02         LD B,0x02  ; 2 bytes: address low/high
446C  ED B3         OTIR  ; block-write ch-0 address
446E  0C            INC C  ; advance to ch-0 count register (0x81)
446F  06 02         LD B,0x02  ; 2 bytes: count low/high
4471  ED B3         OTIR  ; block-write ch-0 count
4473  D3 8C         OUT (0x8C),A  ; dma_clrff — reset byte-pointer flip-flop again
4475  21 0E 4B      LD HL,drive_blk_b+0x8  ; point at drive-B DMA descriptor
4478  0E 82         LD C,0x82  ; port C = ch-1 address register (0x82)
447A  06 02         LD B,0x02  ; 2 bytes: address low/high
447C  ED B3         OTIR  ; block-write ch-1 address
447E  0C            INC C  ; advance to ch-1 count register (0x83)
447F  06 02         LD B,0x02  ; 2 bytes: count low/high
4481  ED B3         OTIR  ; block-write ch-1 count
4483  3E 0C         LD A,0x0C  ; write-mask value to unmask channels 0/1
4485  D3 8F         OUT (0x8F),A  ; dma_wrmask — enable DMA channels 0 and 1
4487  C1            POP BC  ; restore BC
4488  C9            RET  ; return

; compute DMA transfer count: index sector-size table 0x4AA6[A*2], 16-bit multiply by BC, return count-1 in DE
fdc_dma_setup:
4489  F5            PUSH AF  ; save A (sector-size index)
448A  DD E5         PUSH IX  ; save IX
448C  C5            PUSH BC  ; save BC (C reused as loop scratch)
448D  E5            PUSH HL  ; save HL
448E  D5            PUSH DE  ; save DE (16-bit multiplier operand)
448F  DD 21 A6 4A   LD IX,sector_size_tbl  ; point IX at sector-size lookup table
4493  07            RLCA  ; A*2 for word-sized table index
4494  5F            LD E,A  ; index low byte into E
4495  16 00         LD D,0x00  ; clear D (high byte of index)
4497  DD 19         ADD IX,DE  ; IX = &sector_size_tbl[A*2]
4499  DD 6E 00      LD L,(IX+0)  ; fetch table entry low byte -> L
449C  DD 66 01      LD H,(IX+1)  ; fetch table entry high byte -> H
449F  D1            POP DE  ; restore original DE multiplier
44A0  06 10         LD B,0x10  ; 16 iterations for the shift-add multiply
44A2  4A            LD C,D  ; C = multiplier high byte
44A3  7B            LD A,E  ; A = multiplier low byte
44A4  EB            EX DE,HL  ; DE = sector-size multiplicand
44A5  21 00 00      LD HL,0x0000  ; clear HL accumulator

loc_44A8:
44A8  CB 39         SRL C  ; shift multiplier bit out (high half)
44AA  CB 1F         RR A  ; rotate low half, carry = current bit
44AC  30 01         JR NC,loc_44AF  ; if bit clear, skip the add
44AE  19            ADD HL,DE  ; accumulate multiplicand into product

loc_44AF:
44AF  EB            EX DE,HL  ; swap product into DE to shift multiplicand
44B0  29            ADD HL,HL  ; double the multiplicand
44B1  EB            EX DE,HL  ; swap product back to HL
44B2  10 F4         DJNZ loc_44A8  ; loop for all 16 bits
44B4  2B            DEC HL  ; product-1 = DMA transfer count
44B5  54            LD D,H  ; return count-1 high in D
44B6  5D            LD E,L  ; return count-1 low in E
44B7  E1            POP HL  ; restore HL
44B8  C1            POP BC  ; restore BC
44B9  DD E1         POP IX  ; restore IX
44BB  F1            POP AF  ; restore A
44BC  C9            RET  ; return with count-1 in DE
44BD  F5            PUSH AF  ; save A (latch base value)
44BE  C5            PUSH BC  ; save BC
44BF  3E 0A         LD A,0x0A  ; latch value 0x0A: drive control, reset asserted
44C1  D3 40         OUT (0x40),A  ; drv_lat0 — drive latch 0 (drives 0/1)
44C3  D3 60         OUT (0x60),A  ; drv_lat2 — drive latch 2 (drives 2/3)
44C5  F5            PUSH AF  ; keep value for the second write
44C6  06 0C         LD B,0x0C  ; short reset-pulse delay count
44C8  CD DB 48      CALL delay_djnz  ; busy-wait the reset pulse width
44CB  F1            POP AF  ; recover latch base value
44CC  F6 04         OR 0x04  ; set bit2 to deassert reset
44CE  D3 40         OUT (0x40),A  ; drv_lat0 — drive latch 0 (drives 0/1)
44D0  D3 60         OUT (0x60),A  ; drv_lat2 — drive latch 2 (drives 2/3)
44D2  C1            POP BC  ; restore BC
44D3  F1            POP AF  ; restore A
44D4  C9            RET  ; return

; pack FDC specify bytes: SRT|E->0x4A5C, D<<1|B bit0->0x4A5D; A bit0 selects alt path
fdc_set_steprate:
44D5  F5            PUSH AF  ; save A (path-select flags)
44D6  79            LD A,C  ; C = head-load/step-rate field
44D7  ED 44         NEG  ; negate to 2's-complement SRT nibble
44D9  E6 0F         AND 0x0F  ; keep low nibble only
44DB  4F            LD C,A  ; stash into C
44DC  CB 21         SLA C  ; shift SRT into high nibble bit4
44DE  CB 21         SLA C  ; ...bit5
44E0  CB 21         SLA C  ; ...bit6
44E2  CB 21         SLA C  ; ...bit7 (SRT now top nibble)
44E4  7B            LD A,E  ; E = head-unload time
44E5  E6 0F         AND 0x0F  ; keep low nibble
44E7  B1            OR C  ; combine SRT<<4 | HUT
44E8  32 5C 4A      LD (fdc_drv_state+0x3),A  ; store as SPECIFY byte1 in drive state
44EB  CB 22         SLA D  ; shift head-load time left, bit0 = ND flag slot
44ED  78            LD A,B  ; A = non-DMA flag from B
44EE  E6 01         AND 0x01  ; isolate bit0 (ND)
44F0  B2            OR D  ; combine HLT<<1 | ND
44F1  32 5D 4A      LD (fdc_drv_state+0x4),A  ; store as SPECIFY byte2 in drive state
44F4  F1            POP AF  ; restore path-select flags
44F5  CB 47         BIT 0,A  ; test bit0: which FDC pair to program
44F7  28 1A         JR Z,loc_4513  ; if clear, use drives-2/3 path
44F9  0E 00         LD C,0x00  ; FDC 0 base port (0x00)
44FB  21 5B 4A      LD HL,fdc_drv_state+0x2  ; point at SPECIFY command+params
44FE  06 03         LD B,0x03  ; 3 bytes: SPECIFY + 2 param bytes
4500  C5            PUSH BC  ; save count/port for second FDC
4501  E5            PUSH HL  ; save param pointer
4502  CD 7F 45      CALL fdc_write_bytes  ; send SPECIFY to FDC 0
4505  E1            POP HL  ; restore param pointer
4506  C1            POP BC  ; restore count/port
4507  0E 10         LD C,0x10  ; FDC 1 base port (0x10)
4509  CD 7F 45      CALL fdc_write_bytes  ; send same SPECIFY to FDC 1
450C  3A 01 4B      LD A,(drive_blk_a+0x16)  ; load drive-A datarate latch value
450F  D3 50         OUT (0x50),A  ; drv_lat1 — program drive latch 1 (datarate)
4511  18 18         JR loc_452B  ; join the common tail

loc_4513:
4513  0E 20         LD C,0x20  ; FDC 2 base port (0x20)
4515  21 5B 4A      LD HL,fdc_drv_state+0x2  ; point at SPECIFY command+params
4518  06 03         LD B,0x03  ; 3 bytes: SPECIFY + 2 params
451A  C5            PUSH BC  ; save count/port
451B  E5            PUSH HL  ; save param pointer
451C  CD 7F 45      CALL fdc_write_bytes  ; send SPECIFY to FDC 2
451F  E1            POP HL  ; restore param pointer
4520  C1            POP BC  ; restore count/port
4521  0E 30         LD C,0x30  ; FDC 3 base port (0x30)
4523  CD 7F 45      CALL fdc_write_bytes  ; send same SPECIFY to FDC 3
4526  3A 1C 4B      LD A,(drive_blk_b+0x16)  ; load drive-B datarate latch value
4529  D3 70         OUT (0x70),A  ; drv_lat3 — program drive latch 3 (datarate)

loc_452B:
452B  C9            RET  ; return to caller

; issue Sense-Interrupt-Status (0x08) to all 4 FDCs and read their 7-byte result phases
fdc_senseint_all:
452C  C5            PUSH BC  ; save BC across the routine
452D  E5            PUSH HL  ; save HL across the routine
452E  0E 00         LD C,0x00  ; C = FDC0 base port 0x00
4530  21 61 4A      LD HL,fdc_cmd_buf  ; point HL at FDC0 command buffer
4533  CD 71 45      CALL fdc_senseint_send  ; send Sense-Interrupt to FDC0
4536  0E 10         LD C,0x10  ; C = FDC1 base port 0x10
4538  21 6A 4A      LD HL,fdc_cmd_buf1  ; point HL at FDC1 command buffer
453B  CD 71 45      CALL fdc_senseint_send  ; send Sense-Interrupt to FDC1
453E  0E 20         LD C,0x20  ; C = FDC2 base port 0x20
4540  21 73 4A      LD HL,fdc_cmd_buf2  ; point HL at FDC2 command buffer
4543  CD 71 45      CALL fdc_senseint_send  ; send Sense-Interrupt to FDC2
4546  0E 30         LD C,0x30  ; C = FDC3 base port 0x30
4548  21 7C 4A      LD HL,fdc_cmd_buf3  ; point HL at FDC3 command buffer
454B  CD 71 45      CALL fdc_senseint_send  ; send Sense-Interrupt to FDC3
454E  0E 00         LD C,0x00  ; C = FDC0 base port 0x00
4550  21 85 4A      LD HL,fdc_result_buf  ; point HL at FDC0 result buffer
4553  CD 79 45      CALL fdc_result_read7  ; read 7 result bytes from FDC0
4556  0E 10         LD C,0x10  ; C = FDC1 base port 0x10
4558  21 8C 4A      LD HL,fdc_result_buf1  ; point HL at FDC1 result buffer
455B  CD 79 45      CALL fdc_result_read7  ; read 7 result bytes from FDC1
455E  0E 20         LD C,0x20  ; C = FDC2 base port 0x20
4560  21 93 4A      LD HL,fdc_result_buf2  ; point HL at FDC2 result buffer
4563  CD 79 45      CALL fdc_result_read7  ; read 7 result bytes from FDC2
4566  0E 30         LD C,0x30  ; C = FDC3 base port 0x30
4568  21 9A 4A      LD HL,fdc_result_buf3  ; point HL at FDC3 result buffer
456B  CD 79 45      CALL fdc_result_read7  ; read 7 result bytes from FDC3
456E  E1            POP HL  ; restore HL
456F  C1            POP BC  ; restore BC
4570  C9            RET  ; return to caller

; write Sense-Interrupt (0x08) command byte to FDC at port C
fdc_senseint_send:
4571  06 01         LD B,0x01  ; B = 1 byte to send
4573  36 08         LD (HL),0x08  ; store SENSE-INT command 0x08 into buffer
4575  CD 7F 45      CALL fdc_write_bytes  ; stream the command byte to the FDC
4578  C9            RET  ; return to caller

; read 7 result-phase bytes from an FDC into buffer HL
fdc_result_read7:
4579  06 07         LD B,0x07  ; B = 7 result-phase bytes to read
457B  CD F1 46      CALL fdc_read_result  ; read the result bytes into buffer HL
457E  C9            RET  ; return to caller

; stream B command/data bytes to an FDC (poll MSR RQM/DIO before each)
fdc_write_bytes:
457F  ED 78         IN A,(C)  ; read FDC main status register (MSR)
4581  E6 C0         AND 0xC0  ; isolate RQM (bit7) and DIO (bit6)
4583  FE 80         CP 0x80  ; test for RQM=1,DIO=0 (ready to accept a byte)
4585  C2 7F 45      JP NZ,fdc_write_bytes  ; spin until FDC ready to accept a byte
4588  0C            INC C  ; point C at data register (base+1)
4589  ED A3         OUTI  ; write (HL) to FDC data reg, HL++, B--
458B  0D            DEC C  ; restore C to MSR port (base+0)
458C  04            INC B  ; undo OUTI's B-- so DJNZ counts bytes correctly
458D  10 F0         DJNZ fdc_write_bytes  ; loop back over remaining bytes
458F  C9            RET  ; return to caller

; build FDC IRQ/DMA enable mask in fdc_irq_bits from drive-select (A bit0, B bit0, side L bit7)
key_decode:
4590  F5            PUSH AF  ; save AF (holds drive-select A)
4591  E5            PUSH HL  ; save HL
4592  CB 47         BIT 0,A  ; test drive bit0 of the select byte
4594  6F            LD L,A  ; L = copy of select byte (side flag in bit7)
4595  3A A1 4A      LD A,(fdc_result_save)  ; A = current IRQ/DMA enable mask (fdc_result_save)
4598  28 1F         JR Z,loc_45B9  ; drive bit0 clear -> handle drives 0/1 group
459A  CB 18         RR B  ; rotate B carry to pick sub-drive
459C  CB 7D         BIT 7,L  ; test side flag (bit7 of L)
459E  28 09         JR Z,loc_45A9  ; side clear -> loc_45A9
45A0  30 10         JR NC,loc_45B2  ; no carry -> combined-drive path loc_45B2
45A2  F6 02         OR 0x02  ; set drive-3 IRQ/DMA enable (bit1)
45A4  E6 DF         AND 0xDF  ; clear conflicting bit5 in mask
45A6  C3 D5 45      JP loc_45D5  ; store updated mask

loc_45A9:
45A9  30 07         JR NC,loc_45B2  ; no carry -> combined-drive path loc_45B2
45AB  F6 08         OR 0x08  ; set drive select bit3 in mask
45AD  E6 7D         AND 0x7D  ; clear conflicting bits (0x82)
45AF  C3 D5 45      JP loc_45D5  ; store updated mask

loc_45B2:
45B2  F6 0A         OR 0x0A  ; set drive bits 1+3 (0x0A) in mask
45B4  E6 5F         AND 0x5F  ; clear conflicting bits (0xA0)
45B6  C3 D5 45      JP loc_45D5  ; store updated mask

loc_45B9:
45B9  CB 18         RR B  ; rotate B carry to pick sub-drive
45BB  CB 7D         BIT 7,L  ; test side flag (bit7 of L)
45BD  28 09         JR Z,loc_45C8  ; side clear -> loc_45C8
45BF  30 10         JR NC,loc_45D1  ; no carry -> combined path loc_45D1
45C1  F6 01         OR 0x01  ; set drive-0 enable bit0 in mask
45C3  E6 EF         AND 0xEF  ; clear conflicting bit4 in mask
45C5  C3 D5 45      JP loc_45D5  ; store updated mask

loc_45C8:
45C8  30 07         JR NC,loc_45D1  ; no carry -> combined path loc_45D1
45CA  F6 04         OR 0x04  ; set drive-2 enable bit2 in mask
45CC  E6 BE         AND 0xBE  ; clear conflicting bits (0x41) in mask
45CE  C3 D5 45      JP loc_45D5  ; store updated mask

loc_45D1:
45D1  F6 05         OR 0x05  ; set drive bits 0+2 (0x05) in mask
45D3  E6 AF         AND 0xAF  ; clear conflicting bits (0x50)

loc_45D5:
45D5  32 A1 4A      LD (fdc_result_save),A  ; commit new IRQ/DMA enable mask to fdc_result_save
45D8  E1            POP HL  ; restore HL
45D9  F1            POP AF  ; restore AF
45DA  C9            RET  ; return to caller

; IM1 handler: read which FDC interrupted (0x94/0xF0), pull 4x 7-byte result phases
fdc_isr:
45DB  F5            PUSH AF  ; save AF
45DC  C5            PUSH BC  ; save BC
45DD  D5            PUSH DE  ; save DE
45DE  E5            PUSH HL  ; save HL
45DF  DD E5         PUSH IX  ; save IX
45E1  DD 21 A1 4A   LD IX,fdc_result_save  ; IX -> fdc_result_save flag byte
45E5  DB 94         IN A,(0x94)  ; status_in — read status_in latch (which FDC IRQ'd)
45E7  E6 30         AND 0x30  ; isolate IRQ status bits 4/5
45E9  FE 30         CP 0x30  ; both FDC groups (all 4) IRQ pending?
45EB  C2 29 46      JP NZ,loc_4629  ; not the dual case -> loc_4629
45EE  DB F0         IN A,(0xF0)  ; panel — read panel/config port 0xF0
45F0  E6 0C         AND 0x0C  ; isolate panel bits 2/3
45F2  FE 0C         CP 0x0C  ; both FDC1+FDC3 present? (panel bits 2/3)
45F4  28 33         JR Z,loc_4629  ; both present -> skip fast path to loc_4629
45F6  0E 20         LD C,0x20  ; C = FDC2 base port 0x20
45F8  06 07         LD B,0x07  ; B = 7 result bytes
45FA  21 93 4A      LD HL,fdc_result_buf2  ; point HL at FDC2 result buffer
45FD  CD F1 46      CALL fdc_read_result  ; read FDC2 result phase
4600  0E 30         LD C,0x30  ; C = FDC3 base port 0x30
4602  06 07         LD B,0x07  ; B = 7 result bytes
4604  21 9A 4A      LD HL,fdc_result_buf3  ; point HL at FDC3 result buffer
4607  CD F1 46      CALL fdc_read_result  ; read FDC3 result phase
460A  0E 00         LD C,0x00  ; C = FDC0 base port 0x00
460C  06 07         LD B,0x07  ; B = 7 result bytes
460E  21 85 4A      LD HL,fdc_result_buf  ; point HL at FDC0 result buffer
4611  CD F1 46      CALL fdc_read_result  ; read FDC0 result phase
4614  0E 10         LD C,0x10  ; C = FDC1 base port 0x10
4616  06 07         LD B,0x07  ; B = 7 result bytes
4618  21 8C 4A      LD HL,fdc_result_buf1  ; point HL at FDC1 result buffer
461B  CD F1 46      CALL fdc_read_result  ; read FDC1 result phase
461E  DD 7E 00      LD A,(IX+0)  ; A = flags byte (fdc_result_save)
4621  F6 F0         OR 0xF0  ; mark all 4 FDCs serviced (set bits 4-7)
4623  DD 77 00      LD (IX+0),A  ; store back the flags byte
4626  C3 E9 46      JP loc_46E9  ; jump to ISR exit

loc_4629:
4629  CB 67         BIT 4,A  ; test IRQ bit4 (FDC0/FDC1 group)
462B  20 60         JR NZ,loc_468D  ; bit4 set -> FDC0/1 handler loc_468D

; ISR seek-complete path: if FDC2 result pending re-issue Sense-Int to 0x20 (and 0x30 if panel bit3), read results
fdc_isr_sense_int:
462D  3A 73 4A      LD A,(fdc_cmd_buf2)  ; A = last command sent to FDC2
4630  FE 07         CP 0x07  ; was it RECALIBRATE (0x07)?
4632  28 04         JR Z,loc_4638  ; yes -> re-issue Sense-Int loc_4638
4634  FE 0F         CP 0x0F  ; was it SEEK (0x0F)?
4636  20 2F         JR NZ,loc_4667  ; no -> just read result loc_4667

loc_4638:
4638  3E 08         LD A,0x08  ; A = SENSE-INT command 0x08
463A  21 73 4A      LD HL,fdc_cmd_buf2  ; point HL at FDC2 command buffer
463D  77            LD (HL),A  ; store the command byte
463E  0E 20         LD C,0x20  ; C = FDC2 base port 0x20
4640  06 01         LD B,0x01  ; B = 1 byte to send
4642  CD 7F 45      CALL fdc_write_bytes  ; send Sense-Int to FDC2
4645  DB F0         IN A,(0xF0)  ; panel — read panel/config port 0xF0
4647  CB 5F         BIT 3,A  ; test FDC3 present/enable bit3
4649  CA 67 46      JP Z,loc_4667  ; FDC3 absent -> loc_4667
464C  3E 08         LD A,0x08  ; A = SENSE-INT command 0x08
464E  21 7C 4A      LD HL,fdc_cmd_buf3  ; point HL at FDC3 command buffer
4651  77            LD (HL),A  ; store the command byte
4652  0E 30         LD C,0x30  ; C = FDC3 base port 0x30
4654  06 01         LD B,0x01  ; B = 1 byte to send
4656  CD 7F 45      CALL fdc_write_bytes  ; send Sense-Int to FDC3
4659  0E 30         LD C,0x30  ; C = FDC3 base port 0x30
465B  06 07         LD B,0x07  ; B = 7 result bytes
465D  21 9A 4A      LD HL,fdc_result_buf3  ; point HL at FDC3 result buffer
4660  CD F1 46      CALL fdc_read_result  ; read FDC3 result phase
4663  DD CB 00 E6   SET 4,(IX+0)  ; mark FDC3 serviced (bit4)

loc_4667:
4667  0E 20         LD C,0x20  ; C = FDC2 base port 0x20
4669  06 07         LD B,0x07  ; B = 7 result bytes
466B  21 93 4A      LD HL,fdc_result_buf2  ; point HL at FDC2 result buffer
466E  CD F1 46      CALL fdc_read_result  ; read FDC2 result phase
4671  DD CB 00 F6   SET 6,(IX+0)  ; mark FDC2 serviced (bit6)
4675  DD CB 00 46   BIT 0,(IX+0)  ; was FDC0 also flagged (bit0)?
4679  CA E9 46      JP Z,loc_46E9  ; no -> ISR exit loc_46E9
467C  0E 30         LD C,0x30  ; C = FDC3 base port 0x30
467E  06 07         LD B,0x07  ; B = 7 result bytes
4680  21 9A 4A      LD HL,fdc_result_buf3  ; point HL at FDC3 result buffer
4683  CD F1 46      CALL fdc_read_result  ; read FDC3 result phase
4686  DD CB 00 E6   SET 4,(IX+0)  ; mark FDC3 serviced (bit4)
468A  C3 E9 46      JP loc_46E9  ; jump to ISR exit

loc_468D:
468D  3A 61 4A      LD A,(fdc_cmd_buf)  ; A = last command sent to FDC0
4690  FE 07         CP 0x07  ; was it RECALIBRATE (0x07)?
4692  28 04         JR Z,loc_4698  ; yes -> re-issue Sense-Int loc_4698
4694  FE 0F         CP 0x0F  ; was it SEEK (0x0F)?
4696  20 2F         JR NZ,loc_46C7  ; no -> just read result loc_46C7

loc_4698:
4698  3E 08         LD A,0x08  ; A = SENSE-INT command 0x08
469A  21 61 4A      LD HL,fdc_cmd_buf  ; point HL at FDC0 command buffer
469D  77            LD (HL),A  ; store the command byte
469E  0E 00         LD C,0x00  ; C = FDC0 base port 0x00
46A0  06 01         LD B,0x01  ; B = 1 byte to send
46A2  CD 7F 45      CALL fdc_write_bytes  ; send Sense-Int to FDC0
46A5  DB F0         IN A,(0xF0)  ; panel — read panel/config port 0xF0
46A7  CB 57         BIT 2,A  ; test FDC1 present/enable bit2
46A9  CA C7 46      JP Z,loc_46C7  ; FDC1 absent -> loc_46C7
46AC  3E 08         LD A,0x08  ; A = SENSE-INT command 0x08
46AE  21 6A 4A      LD HL,fdc_cmd_buf1  ; point HL at FDC1 command buffer
46B1  77            LD (HL),A  ; store the command byte
46B2  0E 10         LD C,0x10  ; C = FDC1 base port 0x10
46B4  06 01         LD B,0x01  ; B = 1 byte to send
46B6  CD 7F 45      CALL fdc_write_bytes  ; send Sense-Int to FDC1
46B9  0E 10         LD C,0x10  ; C = FDC1 base port 0x10
46BB  06 07         LD B,0x07  ; B = 7 result bytes
46BD  21 8C 4A      LD HL,fdc_result_buf1  ; point HL at FDC1 result buffer
46C0  CD F1 46      CALL fdc_read_result  ; read FDC1 result phase
46C3  DD CB 00 EE   SET 5,(IX+0)  ; mark FDC1 serviced (bit5)

loc_46C7:
46C7  0E 00         LD C,0x00  ; C = FDC0 base port 0x00
46C9  06 07         LD B,0x07  ; B = 7 result bytes
46CB  21 85 4A      LD HL,fdc_result_buf  ; point HL at FDC0 result buffer
46CE  CD F1 46      CALL fdc_read_result  ; read FDC0 result phase
46D1  DD CB 00 FE   SET 7,(IX+0)  ; mark FDC0 serviced (bit7)
46D5  DD CB 00 4E   BIT 1,(IX+0)  ; was FDC1 also flagged (bit1)?
46D9  28 0E         JR Z,loc_46E9  ; no -> ISR exit loc_46E9
46DB  0E 10         LD C,0x10  ; C = FDC1 base port 0x10
46DD  06 07         LD B,0x07  ; B = 7 result bytes
46DF  21 8C 4A      LD HL,fdc_result_buf1  ; point HL at FDC1 result buffer
46E2  CD F1 46      CALL fdc_read_result  ; read FDC1 result phase
46E5  DD CB 00 EE   SET 5,(IX+0)  ; mark FDC1 serviced (bit5)

loc_46E9:
46E9  DD E1         POP IX  ; restore saved IX from stack
46EB  E1            POP HL  ; restore HL
46EC  D1            POP DE  ; restore DE
46ED  C1            POP BC  ; restore BC
46EE  F1            POP AF  ; restore AF
46EF  FB            EI  ; re-enable interrupts before returning
46F0  C9            RET  ; return to caller

; read FDC result phase (poll RQM/DIO), up to B bytes
fdc_read_result:
46F1  ED 78         IN A,(C)  ; read FDC main status register (port in C)
46F3  CB 7F         BIT 7,A  ; test RQM (bit7): controller ready for byte transfer?
46F5  CA F1 46      JP Z,fdc_read_result  ; spin until RQM set
46F8  CB 77         BIT 6,A  ; test DIO (bit6): direction FDC->CPU (result byte available)?
46FA  28 07         JR Z,loc_4703  ; DIO clear -> no more result bytes, done
46FC  0C            INC C  ; point C at FDC data register (status+1)
46FD  ED A2         INI  ; read one result byte into (HL), advance HL
46FF  0D            DEC C  ; restore C to status register port
4700  04            INC B  ; undo INI's B decrement (keep B as remaining count)
4701  10 EE         DJNZ fdc_read_result  ; loop for up to B result bytes

loc_4703:
4703  C9            RET  ; return

; poll FDC done flag (irq_bits bit7 drive0 / bit6 drive2 per A bit0), dispatch to result read
fdc_poll_result:
4704  DD E5         PUSH IX  ; save IX
4706  FD E5         PUSH IY  ; save IY
4708  E5            PUSH HL  ; save HL
4709  DD 21 A1 4A   LD IX,fdc_result_save  ; point IX at FDC result-status save area
470D  CB 47         BIT 0,A  ; test A bit0: drive0 group (set) vs drive2 group (clear)?
470F  28 0E         JR Z,loc_471F  ; handle drive2/3 group
4711  FD 21 85 4A   LD IY,fdc_result_buf  ; point IY at drive0 result buffer
4715  DD CB 00 7E   BIT 7,(IX+0)  ; check done-flag bit7 (drive0 complete)?
4719  CA 18 48      JP Z,loc_4818  ; not done -> exit path
471C  C3 87 47      JP loc_4787  ; done -> process drive0 result

loc_471F:
471F  FD 21 93 4A   LD IY,fdc_result_buf2  ; point IY at drive2 result buffer
4723  DD CB 00 76   BIT 6,(IX+0)  ; check done-flag bit6 (drive2 complete)?
4727  CA 18 48      JP Z,loc_4818  ; not done -> exit path
472A  C3 F6 47      JP loc_47F6  ; done -> process drive2 result

; poll for FDC operation complete (or timeout)
fdc_poll_complete:
472D  DD E5         PUSH IX  ; save IX
472F  FD E5         PUSH IY  ; save IY
4731  E5            PUSH HL  ; save HL
4732  DD 21 A1 4A   LD IX,fdc_result_save  ; point IX at FDC result-status save area
4736  CB 47         BIT 0,A  ; test A bit0: select drive0 vs drive2 group
4738  28 70         JR Z,loc_47AA  ; handle drive2/3 group
473A  FD 21 85 4A   LD IY,fdc_result_buf  ; point IY at drive0 result buffer
473E  DD CB 00 4E   BIT 1,(IX+0)  ; test op-in-progress bit1 for this drive?
4742  CA 80 47      JP Z,loc_4780  ; not in progress -> alternate done check
4745  DB F0         IN A,(0xF0)  ; panel — read panel/status port 0xF0
4747  CB 57         BIT 2,A  ; test disk-change/index bit2
4749  CA 18 48      JP Z,loc_4818  ; if clear, bail to exit
474C  21 5A 4A      LD HL,fdc_drv_state+0x1  ; point HL at drive1 state byte
474F  CB 56         BIT 2,(HL)  ; test drive1 state bit2 (write-enable/ready?)
4751  20 07         JR NZ,loc_475A  ; if set, skip error report
4753  3E 19         LD A,0x19  ; load error code 0x19 (drive fault)
4755  CD F5 4B      CALL error_report  ; report the error
4758  18 04         JR loc_475E  ; continue past latch pulse

loc_475A:
475A  CB 46         BIT 0,(HL)  ; test drive1 state bit0
475C  20 0E         JR NZ,loc_476C  ; if set, skip write-protect strobe

loc_475E:
475E  3E 0E         LD A,0x0E  ; ctrl_latch 0x0E: drive line7 (result strobe) low
4760  D3 9C         OUT (0x9C),A  ; ctrl_latch — pulse control latch line
4762  00            NOP  ; settle delay
4763  00            NOP  ; settle delay
4764  00            NOP  ; settle delay
4765  00            NOP  ; settle delay
4766  00            NOP  ; settle delay
4767  00            NOP  ; settle delay
4768  3E 0F         LD A,0x0F  ; ctrl_latch 0x0F: drive line7 high (strobe end)
476A  D3 9C         OUT (0x9C),A  ; ctrl_latch — complete the latch strobe

loc_476C:
476C  DD CB 00 7E   BIT 7,(IX+0)  ; poll done-flag bit7 in result-save byte
4770  C2 9D 47      JP NZ,loc_479D  ; if done, go read result phase
4773  CD 57 48      CALL timeout_check  ; tick the command timeout timer
4776  38 02         JR C,loc_477A  ; timeout expired (carry) -> abort
4778  18 F2         JR loc_476C  ; keep polling for completion

loc_477A:
477A  AF            XOR A  ; clear A
477B  D6 01         SUB 0x01  ; SUB 1 -> A=0xFF, carry set to flag timeout error
477D  C3 09 48      JP loc_4809  ; jump into error-handling tail

loc_4780:
4780  DD CB 00 7E   BIT 7,(IX+0)  ; poll done-flag bit7 (alternate path)
4784  CA 18 48      JP Z,loc_4818  ; if not done, bail to exit

loc_4787:
4787  DD CB 00 4E   BIT 1,(IX+0)  ; test op-in-progress bit1?
478B  20 0A         JR NZ,loc_4797  ; if set, use combined-result path

loc_478D:
478D  FD 7E 00      LD A,(IY+0)  ; load drive's first result byte
4790  07            RLCA  ; rotate result bit7 into carry (IC/error?)
4791  DA 09 48      JP C,loc_4809  ; if error bit set, go decode result
4794  07            RLCA  ; rotate next status bit into carry
4795  18 72         JR loc_4809  ; proceed to result decode

loc_4797:
4797  DD CB 00 6E   BIT 5,(IX+0)  ; test result-valid bit5?
479B  28 7B         JR Z,loc_4818  ; if clear, bail to exit

loc_479D:
479D  3A 8C 4A      LD A,(fdc_result_buf1)  ; load FDC result buffer byte 1 (ST0/ST1)

loc_47A0:
47A0  FD B6 00      OR (IY+0)  ; OR in drive's result byte for combined status
47A3  07            RLCA  ; rotate top status bit into carry
47A4  38 63         JR C,loc_4809  ; if error, go decode result
47A6  07            RLCA  ; rotate next status bit into carry
47A7  C3 09 48      JP loc_4809  ; proceed to result decode

loc_47AA:
47AA  FD 21 93 4A   LD IY,fdc_result_buf2  ; point IY at drive2 result buffer (drive2/3 group)
47AE  DD CB 00 46   BIT 0,(IX+0)  ; test op-in-progress bit0 for this drive?
47B2  CA F0 47      JP Z,loc_47F0  ; not in progress -> alternate done check
47B5  DB F0         IN A,(0xF0)  ; panel — read panel/status port 0xF0
47B7  CB 5F         BIT 3,A  ; test disk-change/index bit3 (drive2/3)
47B9  CA 18 48      JP Z,loc_4818  ; if clear, bail to exit
47BC  21 5A 4A      LD HL,fdc_drv_state+0x1  ; point HL at drive1 state byte
47BF  CB 5E         BIT 3,(HL)  ; test drive1 state bit3?
47C1  20 07         JR NZ,loc_47CA  ; if set, skip error report
47C3  3E 19         LD A,0x19  ; load error code 0x19 (drive fault)
47C5  CD F5 4B      CALL error_report  ; report the error
47C8  18 04         JR loc_47CE  ; continue past latch pulse

loc_47CA:
47CA  CB 4E         BIT 1,(HL)  ; test drive1 state bit1
47CC  20 0D         JR NZ,loc_47DB  ; if set, skip write-protect strobe

loc_47CE:
47CE  3E 0E         LD A,0x0E  ; ctrl_latch 0x0E: drive line7 (result strobe) low
47D0  D3 9C         OUT (0x9C),A  ; ctrl_latch — pulse control latch line
47D2  00            NOP  ; settle delay
47D3  00            NOP  ; settle delay
47D4  00            NOP  ; settle delay
47D5  00            NOP  ; settle delay
47D6  00            NOP  ; settle delay
47D7  00            NOP  ; settle delay
47D8  3C            INC A  ; INC A -> 0x0F: drive line7 high (strobe end)
47D9  D3 9C         OUT (0x9C),A  ; ctrl_latch — complete the latch strobe

loc_47DB:
47DB  DD CB 00 76   BIT 6,(IX+0)  ; poll done-flag bit6 in result-save byte
47DF  C2 04 48      JP NZ,loc_4804  ; if done, go read combined result
47E2  CD 57 48      CALL timeout_check  ; tick the command timeout timer
47E5  38 03         JR C,loc_47EA  ; timeout expired (carry) -> abort
47E7  C3 DB 47      JP loc_47DB  ; keep polling for completion

loc_47EA:
47EA  AF            XOR A  ; clear A
47EB  D6 01         SUB 0x01  ; SUB 1 -> A=0xFF, carry set to flag timeout error
47ED  C3 09 48      JP loc_4809  ; jump into error-handling tail

loc_47F0:
47F0  DD CB 00 76   BIT 6,(IX+0)  ; poll done-flag bit6 (alternate path)
47F4  28 22         JR Z,loc_4818  ; if not done, bail to exit

loc_47F6:
47F6  DD CB 00 46   BIT 0,(IX+0)  ; test result bit0 for drive2/3?
47FA  20 02         JR NZ,loc_47FE  ; if set, use combined-result path
47FC  18 8F         JR loc_478D  ; else decode single result byte

loc_47FE:
47FE  DD CB 00 66   BIT 4,(IX+0)  ; test result-valid bit4?
4802  28 14         JR Z,loc_4818  ; if clear, bail to exit

loc_4804:
4804  3A 9A 4A      LD A,(fdc_result_buf3)  ; load FDC result buffer byte 3 (drive2/3 status)
4807  18 97         JR loc_47A0  ; merge and decode combined result

loc_4809:
4809  3E 01         LD A,0x01  ; A=1 (immediately overwritten); carry from caller flags error
480B  3C            INC A  ; INC A does not touch carry on Z80; carry still reflects error state
480C  3E 00         LD A,0x00  ; A=0: default no-error return value
480E  30 08         JR NC,loc_4818  ; no carry (no error) -> skip decode and exit
4810  D5            PUSH DE  ; preserve DE across decode
4811  F5            PUSH AF  ; preserve error code in AF
4812  CD 93 48      CALL fdc_error_decode  ; decode FDC error status into message
4815  F1            POP AF  ; restore error code
4816  7B            LD A,E  ; return decoded error in A (from E)
4817  D1            POP DE  ; restore DE

loc_4818:
4818  E1            POP HL  ; restore HL
4819  FD E1         POP IY  ; restore IY
481B  DD E1         POP IX  ; restore IX
481D  C9            RET  ; return

; fast-fill banked DRAM (bank B via 0xB0, addr 0x8000|HL+4*D) via SP-swap block writes, count A&0x7F
dram_stack_fill:
481E  C5            PUSH BC  ; save BC (bank arg in B)
481F  0E B0         LD C,0xB0  ; port 0xB0 = image-bank select register
4821  ED 41         OUT (C),B  ; select DRAM image bank B
4823  4A            LD C,D  ; C = drive index D
4824  CB 21         SLA C  ; C *= 2
4826  CB 21         SLA C  ; C *= 2 again (D*4 = per-drive offset)
4828  06 00         LD B,0x00  ; clear high byte for 16-bit add
482A  09            ADD HL,BC  ; HL += 4*D (per-drive base offset)
482B  CB FC         SET 7,H  ; set bit15 of address -> map into 0x8000 image window
482D  C1            POP BC  ; restore BC
482E  E6 7F         AND 0x7F  ; mask count to 0..127
4830  47            LD B,A  ; B = fill count
4831  7B            LD A,E  ; stash E in A for D<->E swap
4832  5A            LD E,D  ; E = old D
4833  57            LD D,A  ; D = old E (DE now holds swapped fill word)
4834  F3            DI  ; disable interrupts (SP hijack coming)
4835  ED 73 54 4A   LD (fdc_saved_sp),SP  ; save real stack pointer
4839  F9            LD SP,HL  ; point SP at DRAM fill target for PUSH-based writes
483A  60            LD H,B  ; reuse HL as 2nd fill word: H = count
483B  69            LD L,C  ; L = C (low byte of 2nd fill word)
483C  43            LD B,E  ; B = inner loop count (from E)

loc_483D:
483D  D5            PUSH DE  ; PUSH DE: store first fill word to DRAM (SP walks down)
483E  E5            PUSH HL  ; PUSH HL: store second fill word (4 bytes per iteration)
483F  1D            DEC E  ; DEC E: decrement low fill byte for next word
4840  10 FB         DJNZ loc_483D  ; loop inner fill
4842  ED 7B 54 4A   LD SP,(fdc_saved_sp)  ; restore real stack pointer
4846  FB            EI  ; re-enable interrupts
4847  C9            RET  ; return

; start command timeout timer (8253 counter 2)
timeout_start:
4848  F5            PUSH AF  ; save AF
4849  3E B4         LD A,0xB4  ; 8253 control: counter2, mode2, 16-bit, binary (0xB4)
484B  D3 AC         OUT (0xAC),A  ; pit_ctrl — write to PIT control port
484D  3E FF         LD A,0xFF  ; timeout reload low = 0xFF
484F  D3 A8         OUT (0xA8),A  ; pit_c2 — load counter2 low byte
4851  3E FF         LD A,0xFF  ; timeout reload high = 0xFF (max count)
4853  D3 A8         OUT (0xA8),A  ; pit_c2 — load counter2 high byte
4855  F1            POP AF  ; restore AF
4856  C9            RET  ; return

; check/tick the command timeout timer
timeout_check:
4857  C5            PUSH BC  ; save BC
4858  47            LD B,A  ; stash A in B
4859  3E 80         LD A,0x80  ; 8253 latch command for counter2 (0x80)
485B  D3 AC         OUT (0xAC),A  ; pit_ctrl — write to PIT control port
485D  DB A8         IN A,(0xA8)  ; pit_c2 — read counter2 low byte
485F  DB A8         IN A,(0xA8)  ; pit_c2 — read counter2 high byte
4861  D6 01         SUB 0x01  ; SUB 1 sets carry when counter reached 0 (timeout)
4863  78            LD A,B  ; restore original A
4864  C1            POP BC  ; restore BC
4865  C9            RET  ; return (carry = timed out)

; save data-rate (A) and precomp (B) values to 0x4B89/0x4B8A
store_rate_precomp:
4866  32 89 4B      LD (fdc_rate_reg),A  ; save current data-rate value
4869  78            LD A,B  ; A = precompensation value (B)
486A  32 8A 4B      LD (fdc_precomp_reg),A  ; save write-precompensation value
486D  C9            RET  ; return

; enable FDC data bus: set panel port 0xF0 bit0, update shadow 0x4A58
panel_bus_on:
486E  F5            PUSH AF  ; save AF
486F  3A 58 4A      LD A,(panel_shadow)  ; load panel port shadow copy
4872  F6 01         OR 0x01  ; set bit0 to enable FDC data bus

loc_4874:
4874  32 58 4A      LD (panel_shadow),A  ; Save new panel-latch state into panel_shadow copy
4877  D3 F0         OUT (0xF0),A  ; panel — Push updated byte to panel port 0xF0
4879  F1            POP AF  ; Restore caller's A/flags
487A  C9            RET  ; Return to caller
487B  F5            PUSH AF  ; Preserve A/flags across panel update
487C  3A 58 4A      LD A,(panel_shadow)  ; Fetch current panel shadow byte
487F  E6 FE         AND 0xFE  ; Clear bit0 (drive/panel line low)
4881  18 F1         JR loc_4874  ; Merge back and re-output via loc_4874

; select head/side 0: clear panel bit7 (0x4A58), output to 0xF0
panel_sel_lo:
4883  F5            PUSH AF  ; Preserve A/flags before head-select
4884  3A 58 4A      LD A,(panel_shadow)  ; Fetch current panel shadow byte
4887  E6 7F         AND 0x7F  ; Clear bit7 -> select head/side 0
4889  18 E9         JR loc_4874  ; Store and output via loc_4874

; select head/side 1: set panel bit7 (0x4A58), output to 0xF0
panel_sel_hi:
488B  F5            PUSH AF  ; Preserve A/flags before head-select
488C  3A 58 4A      LD A,(panel_shadow)  ; Fetch current panel shadow byte
488F  F6 80         OR 0x80  ; Set bit7 -> select head/side 1
4891  18 E1         JR loc_4874  ; Store and output via loc_4874

; decode ST0/ST1/ST2 -> error class (CRC/writeprot/seek/notready/overrun)
fdc_error_decode:
4893  1E 80         LD E,0x80  ; Default error code 0x80 (highest severity bit)
4895  FD CB 01 6E   BIT 5,(IY+1)  ; Test ST1 bit5 (CRC/data error)
4899  C0            RET NZ  ; Return with 0x80 if CRC error present
489A  FD CB 01 56   BIT 2,(IY+1)  ; Test ST1 bit2 (no data / sector not found)
489E  C0            RET NZ  ; Return if that error flagged
489F  FD CB 01 46   BIT 0,(IY+1)  ; Test ST1 bit0 (missing address mark)
48A3  C0            RET NZ  ; Return if that error flagged
48A4  FD CB 02 6E   BIT 5,(IY+2)  ; Test ST2 bit5 (data-field CRC error)
48A8  C0            RET NZ  ; Return if that error flagged
48A9  CB 3B         SRL E  ; Shift error code down to next class
48AB  FD CB 02 76   BIT 6,(IY+2)  ; Test ST2 bit6 (control mark / deleted DAM)
48AF  C0            RET NZ  ; Return if that error flagged
48B0  CB 3B         SRL E  ; Shift error code down to next class
48B2  FD CB 01 66   BIT 4,(IY+1)  ; Test ST1 bit4 (overrun)
48B6  C0            RET NZ  ; Return if overrun flagged
48B7  CB 3B         SRL E  ; Shift error code down to next class
48B9  FD CB 01 4E   BIT 1,(IY+1)  ; Test ST1 bit1 (write protect)
48BD  C0            RET NZ  ; Return if write-protect flagged
48BE  CB 3B         SRL E  ; Shift error code down to next class
48C0  FD CB 02 66   BIT 4,(IY+2)  ; Test ST2 bit4 (wrong cylinder / seek error)
48C4  C0            RET NZ  ; Return if seek error flagged
48C5  FD CB 02 4E   BIT 1,(IY+2)  ; Test ST2 bit1 (bad cylinder)
48C9  C0            RET NZ  ; Return if bad-cylinder flagged
48CA  CB 3B         SRL E  ; Shift error code down to next class
48CC  FD CB 01 7E   BIT 7,(IY+1)  ; Test ST1 bit7 (end of cylinder)
48D0  C0            RET NZ  ; Return if end-of-cylinder flagged
48D1  CB 3B         SRL E  ; Shift error code down to next class
48D3  FD CB 00 66   BIT 4,(IY+0)  ; Test ST0 bit4 (equipment/not-ready check)
48D7  C0            RET NZ  ; Return if that error flagged
48D8  1E FF         LD E,0xFF  ; No decoded error -> return code 0xFF (OK)
48DA  C9            RET  ; Return to caller

; busy-wait delay: DJNZ loop for B iterations
delay_djnz:
48DB  10 FE         DJNZ delay_djnz  ; Spin down B counter (busy-wait delay loop)
48DD  C9            RET  ; Return after delay elapses

; read 8253 counter-1 16-bit (latch cmd 0x44 to 0xAC, read lo/hi from 0xA4), returns HL
read_timer_c1:
48DE  F5            PUSH AF  ; Preserve A/flags across timer read
48DF  3E 44         LD A,0x44  ; Latch-counter-1 command byte for 8253
48E1  D3 AC         OUT (0xAC),A  ; pit_ctrl — Send latch command to PIT control port 0xAC
48E3  DB A4         IN A,(0xA4)  ; pit_c1 — Read counter-1 low byte from 0xA4
48E5  6F            LD L,A  ; Store as HL low
48E6  DB A4         IN A,(0xA4)  ; pit_c1 — Read counter-1 high byte from 0xA4
48E8  67            LD H,A  ; Store as HL high
48E9  F1            POP AF  ; Restore A/flags
48EA  C9            RET  ; Return with 16-bit timer count in HL

; set FDC command-mode flags in 0x4A5A bits0-3 from op_word nibble & rd_submode/unit_sel
fdc_set_cmdmode:
48EB  E5            PUSH HL  ; Preserve HL across cmd-mode setup
48EC  21 5A 4A      LD HL,fdc_drv_state+0x1  ; Point HL at fdc_drv_state+1 (cmd-mode flags)
48EF  CB D6         SET 2,(HL)  ; Set flag bit2
48F1  CB DE         SET 3,(HL)  ; Set flag bit3
48F3  08            EX AF,AF'  ; Switch to alt reg set to compute op nibble there
48F4  3A 34 31      LD A,(op_word)  ; Load full op_word command
48F7  E6 0F         AND 0x0F  ; Isolate low nibble (operation code)
48F9  08            EX AF,AF'  ; Swap back; op nibble now held in alt A for later
48FA  FE 01         CP 0x01  ; Compare input selector A (which flag bits) to 1
48FC  38 22         JR C,loc_4920  ; Selector 0 -> loc_4920 (sets bit0 only)
48FE  28 3E         JR Z,loc_493E  ; Selector 1 -> loc_493E (sets bit1 only)
4900  08            EX AF,AF'  ; Recover op nibble from alternate A
4901  F5            PUSH AF  ; Preserve op nibble
4902  3A 37 31      LD A,(unit_sel)  ; Load unit_sel selection byte
4905  E6 C0         AND 0xC0  ; Isolate drive-select bits[7:6]
4907  FE 80         CP 0x80  ; Compare against 0x80 (unit 2 selected)
4909  20 00         JR NZ,loc_490B  ; Branch (both targets fall through to loc_490B)

loc_490B:
490B  F1            POP AF  ; Recover op nibble
490C  FE 07         CP 0x07  ; Compare op nibble to 7 (read variant)
490E  C2 14 49      JP NZ,loc_4914  ; Skip submode fetch if not op 7
4911  3A 4F 31      LD A,(rd_submode)  ; For op 7, use rd_submode as effective op

loc_4914:
4914  FE 05         CP 0x05  ; Compare effective op to 5
4916  CB C6         SET 0,(HL)  ; Set flag bit0
4918  CB CE         SET 1,(HL)  ; Set flag bit1
491A  20 3E         JR NZ,loc_495A  ; If op != 5, keep both bits -> loc_495A
491C  CB 86         RES 0,(HL)  ; Op 5: clear bit0
491E  18 38         JR loc_4958  ; Continue to clear bit1 at loc_4958

loc_4920:
4920  08            EX AF,AF'  ; Recover op nibble from alternate A
4921  F5            PUSH AF  ; Preserve op nibble
4922  3A 37 31      LD A,(unit_sel)  ; Load unit_sel selection byte
4925  E6 C0         AND 0xC0  ; Isolate drive-select bits[7:6]
4927  FE 80         CP 0x80  ; Compare against 0x80 (unit 2 selected)
4929  20 00         JR NZ,loc_492B  ; Branch (both targets fall through to loc_492B)

loc_492B:
492B  F1            POP AF  ; Recover op nibble
492C  FE 07         CP 0x07  ; Compare op nibble to 7 (read variant)
492E  C2 34 49      JP NZ,loc_4934  ; Skip submode fetch if not op 7
4931  3A 4F 31      LD A,(rd_submode)  ; For op 7, use rd_submode as effective op

loc_4934:
4934  FE 05         CP 0x05  ; Compare effective op to 5
4936  CB C6         SET 0,(HL)  ; Set flag bit0
4938  20 20         JR NZ,loc_495A  ; If op != 5, done -> loc_495A
493A  CB 86         RES 0,(HL)  ; Op 5: clear bit0
493C  18 1C         JR loc_495A  ; Done -> loc_495A

loc_493E:
493E  08            EX AF,AF'  ; Recover op nibble from alternate A
493F  F5            PUSH AF  ; Preserve op nibble
4940  3A 37 31      LD A,(unit_sel)  ; Load unit_sel selection byte
4943  E6 C0         AND 0xC0  ; Isolate drive-select bits[7:6]
4945  FE 80         CP 0x80  ; Compare against 0x80 (unit 2 selected)
4947  20 00         JR NZ,loc_4949  ; Branch (both targets fall through to loc_4949)

loc_4949:
4949  F1            POP AF  ; Recover op nibble
494A  FE 07         CP 0x07  ; Compare op nibble to 7 (read variant)
494C  C2 52 49      JP NZ,loc_4952  ; Skip submode fetch if not op 7
494F  3A 4F 31      LD A,(rd_submode)  ; For op 7, use rd_submode as effective op

loc_4952:
4952  FE 05         CP 0x05  ; Compare effective op to 5
4954  CB CE         SET 1,(HL)  ; Set flag bit1
4956  20 02         JR NZ,loc_495A  ; If op != 5, done -> loc_495A

loc_4958:
4958  CB 8E         RES 1,(HL)  ; Clear flag bit1

loc_495A:
495A  E1            POP HL  ; Restore HL
495B  C9            RET  ; Return with cmd-mode flags set
495C  37            SCF  ; Set carry flag
495D  3F            CCF  ; Complement carry -> clear carry for clean subtract
495E  ED 42         SBC HL,BC  ; HL -= BC (compute target delta, sets carry)
4960  E5            PUSH HL  ; Save target value HL
4961  30 08         JR NC,loc_496B  ; If no borrow, skip initial wait -> loc_496B

loc_4963:
4963  CD DE 48      CALL read_timer_c1  ; Read current 16-bit timer into HL
4966  3F            CCF  ; Clear carry before subtract
4967  ED 52         SBC HL,DE  ; HL -= DE (compare timer to threshold)
4969  38 F8         JR C,loc_4963  ; Loop until timer passes threshold

loc_496B:
496B  D1            POP DE  ; Recover target value into DE

loc_496C:
496C  CD DE 48      CALL read_timer_c1  ; Read current 16-bit timer into HL
496F  ED 52         SBC HL,DE  ; HL -= DE (compare timer against target)
4971  30 F9         JR NC,loc_496C  ; Spin until timer reaches/exceeds target
4973  C9            RET  ; Return once delay elapsed

; check drive ready: sense drive status, test status bit6 (ready line)
fdc_drive_ready:
4974  E5            PUSH HL  ; Preserve HL across ready check
4975  C5            PUSH BC  ; Preserve BC
4976  D5            PUSH DE  ; Preserve DE
4977  CD 9E 49      CALL fdc_sense_drive  ; Sense drive status (ST3) into A
497A  CB 77         BIT 6,A  ; Test ST3 bit6 (drive ready line)
497C  7B            LD A,E  ; Load E (drive index) into A as return value
497D  D1            POP DE  ; Restore DE
497E  C1            POP BC  ; Restore BC
497F  E1            POP HL  ; Restore HL
4980  C9            RET  ; Return with ready flag in Z

; report drive-not-ready error (code 0x96) then re-sense drive status
fdc_err_notready:
4981  E5            PUSH HL  ; Preserve HL
4982  D5            PUSH DE  ; Preserve DE
4983  C5            PUSH BC  ; Preserve BC
4984  3E 96         LD A,0x96  ; Error code 0x96 (drive not ready)
4986  CD F5 4B      CALL error_report  ; Report the not-ready error
4989  CD 90 49      CALL fdc_sense_ready  ; Re-sense drive ready state
498C  C1            POP BC  ; Restore BC
498D  D1            POP DE  ; Restore DE
498E  E1            POP HL  ; Restore HL
498F  C9            RET  ; Return to caller

; sense drive ready: read status, XOR 0x10, test bit4; Z=ready
fdc_sense_ready:
4990  E5            PUSH HL  ; Preserve HL
4991  C5            PUSH BC  ; Preserve BC
4992  D5            PUSH DE  ; Preserve DE
4993  CD 9E 49      CALL fdc_sense_drive  ; Sense drive status (ST3) into A
4996  EE 10         XOR 0x10  ; Toggle bit4 so ready state shows as Z
4998  CB 67         BIT 4,A  ; Test bit4 (ready) -> Z if ready
499A  D1            POP DE  ; Restore DE
499B  C1            POP BC  ; Restore BC
499C  E1            POP HL  ; Restore HL
499D  C9            RET  ; Return with Z=ready

; FDC Sense Drive Status (cmd 0x04): build unit byte from bit0 of drv_active_cfg, exec, read ST3
fdc_sense_drive:
499E  5F            LD E,A  ; Save incoming A (drive index) in E
499F  3A 1E 31      LD A,(drv_active_cfg)  ; Load active-drive config byte
49A2  E6 01         AND 0x01  ; Keep only bit0 (drive select LSB)
49A4  CB 47         BIT 0,A  ; Test that select bit
49A6  20 04         JR NZ,loc_49AC  ; If already set, skip normalization
49A8  CB C7         SET 0,A  ; Force bit0 set
49AA  CB 27         SLA A  ; Shift left to form unit number field

loc_49AC:
49AC  0E 00         LD C,0x00  ; Default result-slot base C=0
49AE  CB 47         BIT 0,A  ; Test unit bit0
49B0  20 02         JR NZ,loc_49B4  ; If set, keep C=0
49B2  0E 20         LD C,0x20  ; Else offset C=0x20

loc_49B4:
49B4  C5            PUSH BC  ; Save BC (unit/slot) across command
49B5  32 5F 4A      LD (fdc_drv_state+0x6),A  ; Store unit byte as SENSE-DRIVE parameter
49B8  3E 04         LD A,0x04  ; SENSE DRIVE STATUS command 0x04
49BA  32 5E 4A      LD (fdc_drv_state+0x5),A  ; Store command byte in cmd buffer
49BD  21 5E 4A      LD HL,fdc_drv_state+0x5  ; Point HL at 2-byte cmd (cmd+unit)
49C0  06 02         LD B,0x02  ; Send 2 command bytes
49C2  CD 7F 45      CALL fdc_write_bytes  ; Write command sequence to FDC
49C5  C1            POP BC  ; Restore BC
49C6  06 07         LD B,0x07  ; Expect up to 7 result bytes
49C8  21 60 4A      LD HL,fdc_drv_state+0x7  ; Point HL at result buffer
49CB  CD F1 46      CALL fdc_read_result  ; Read FDC result phase (ST3)
49CE  3A 60 4A      LD A,(fdc_drv_state+0x7)  ; Load ST3 result byte into A
49D1  C9            RET  ; Return with ST3 in A

; init 4-byte FDC cmd/DMA descriptor at IX to {0x41,0x02,0x00,0x00}
fdc_result_reset:
49D2  DD 36 00 41   LD (IX+0),0x41  ; Init descriptor byte0 = 0x41 (cmd/DMA flags)
49D6  DD 36 01 02   LD (IX+1),0x02  ; Init descriptor byte1 = 0x02
49DA  DD 36 02 00   LD (IX+2),0x00  ; Init descriptor byte2 = 0x00
49DE  DD 36 03 00   LD (IX+3),0x00  ; Init descriptor byte3 = 0x00
49E2  C9            RET  ; Return with descriptor initialized

; beep the piezo buzzer A times (port 0xF0 bit3, active-low), ~13ms delay between (via buzzer_pulse)
buzzer_beep:
49E3  F5            PUSH AF  ; Preserve A (beep count)
49E4  C5            PUSH BC  ; Preserve BC
49E5  47            LD B,A  ; Load beep repeat count into B

loc_49E6:
49E6  CD FC 49      CALL buzzer_pulse  ; Emit one buzzer pulse (~13ms)
49E9  10 02         DJNZ loc_49ED  ; Loop for next beep if count remains
49EB  18 0C         JR loc_49F9  ; All beeps done -> exit at loc_49F9

loc_49ED:
49ED  C5            PUSH BC  ; Save beep counter across inter-beep gap
49EE  01 00 68      LD BC,0x6800  ; Load inter-beep delay count 0x6800

loc_49F1:
49F1  0B            DEC BC  ; delay loop: decrement 16-bit counter
49F2  79            LD A,C  ; test BC==0: low byte into A
49F3  B0            OR B  ; OR high byte -> Z when BC exhausted
49F4  20 FB         JR NZ,loc_49F1  ; keep spinning until counter hits zero
49F6  C1            POP BC  ; restore caller BC
49F7  18 ED         JR loc_49E6  ; back to outer loop head

loc_49F9:
49F9  C1            POP BC  ; restore BC
49FA  F1            POP AF  ; restore AF
49FB  C9            RET  ; return

; one buzzer pulse: drive 0xF0 bit3 low ~13ms then high (audible click), keep shadow 0x4A58 in sync
buzzer_pulse:
49FC  C5            PUSH BC  ; save BC
49FD  F5            PUSH AF  ; save AF
49FE  CD 16 4A      CALL buzzer_off  ; ensure buzzer bit3 high first
4A01  E6 F7         AND 0xF7  ; clear panel bit3 -> buzzer drive low (audible)
4A03  D3 F0         OUT (0xF0),A  ; panel — drive panel port F0 low
4A05  32 58 4A      LD (panel_shadow),A  ; keep 0x4A58 shadow in sync
4A08  01 00 68      LD BC,0x6800  ; ~13ms pulse-width delay count

loc_4A0B:
4A0B  0B            DEC BC  ; delay loop: decrement
4A0C  79            LD A,C  ; test BC==0: low byte
4A0D  B0            OR B  ; OR high byte
4A0E  20 FB         JR NZ,loc_4A0B  ; spin until delay done
4A10  CD 16 4A      CALL buzzer_off  ; raise bit3 high again -> end click
4A13  F1            POP AF  ; restore AF
4A14  C1            POP BC  ; restore BC
4A15  C9            RET  ; return

; set panel port F0 bit3 high, keeping 0x4A58 shadow in sync
buzzer_off:
4A16  3A 58 4A      LD A,(panel_shadow)  ; read current panel shadow
4A19  F6 08         OR 0x08  ; set bit3 (buzzer off)
4A1B  D3 F0         OUT (0xF0),A  ; panel — write panel port F0
4A1D  32 58 4A      LD (panel_shadow),A  ; sync shadow
4A20  C9            RET  ; return
4A21  F5            PUSH AF  ; save A (clear-panel-bit1 helper)
4A22  3A 58 4A      LD A,(panel_shadow)  ; read panel shadow
4A25  E6 FD         AND 0xFD  ; clear bit1

loc_4A27:
4A27  D3 F0         OUT (0xF0),A  ; panel — write panel port F0
4A29  32 58 4A      LD (panel_shadow),A  ; sync shadow
4A2C  F1            POP AF  ; restore A
4A2D  C9            RET  ; return
4A2E  F5            PUSH AF  ; save A (clear-panel-bit2 helper)
4A2F  3A 58 4A      LD A,(panel_shadow)  ; read panel shadow
4A32  E6 FB         AND 0xFB  ; clear bit2
4A34  18 F1         JR loc_4A27  ; write+sync+return via loc_4A27
4A36  F5            PUSH AF  ; save A (set-panel-bit1 helper)
4A37  3A 58 4A      LD A,(panel_shadow)  ; read panel shadow
4A3A  F6 02         OR 0x02  ; set bit1
4A3C  18 E9         JR loc_4A27  ; write+sync+return via loc_4A27
4A3E  F5            PUSH AF  ; save A (set-panel-bit2 helper)
4A3F  3A 58 4A      LD A,(panel_shadow)  ; read panel shadow
4A42  F6 04         OR 0x04  ; set bit2
4A44  18 E1         JR loc_4A27  ; write+sync+return via loc_4A27
4A46  E5            PUSH HL  ; save HL (toggle-panel-bit1 helper)
4A47  F5            PUSH AF  ; save A
4A48  21 58 4A      LD HL,panel_shadow  ; point at panel shadow
4A4B  7E            LD A,(HL)  ; read current shadow value
4A4C  EE 02         XOR 0x02  ; flip bit1
4A4E  D3 F0         OUT (0xF0),A  ; panel — write panel port F0
4A50  77            LD (HL),A  ; sync shadow
4A51  F1            POP AF  ; restore A
4A52  E1            POP HL  ; restore HL
4A53  C9            RET  ; return

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

; fmt_geom_recs: "Special format" per-head data-rate zone tables (default set) = variable-rate zoned formatting. 4 formats x 2 records (.a=head0, .b=head1); each = 6 zone entries { start cyl : low byte, data-rate : high byte, 0/1/2 = N/L/H }. CONFIRMED data-rate: range_table_lookup(cyl) @0x092A scans these 6 bands -> fdc_rate_a/b -> update_ctrl_latch (0x9C datarate lines 4/5 + drv-latch bit2). Copied to 0x31A1, edited by hrd_edit_head_pair. Read-only defaults
fmt_geom_recs:
4B29  00 00 21 01 28 00 28 00 28 00 28 00             |..!.(.(.(.(.|   ; fmt0 head0  cyl/rate: 0/N  33/L  40/N  40/N  40/N  40/N
4B35  00 00 1E 01 28 00 28 00 28 00 28 00             |....(.(.(.(.|   ; fmt0 head1  cyl/rate: 0/N  30/L  40/N  40/N  40/N  40/N
4B41  00 00 12 01 2C 00 36 01 4B 02 50 00             |....,.6.K.P.|   ; fmt1 head0  cyl/rate: 0/N  18/L  44/N  54/L  75/H  80/N
4B4D  00 00 12 01 27 02 2C 01 43 02 50 00             |....'.,.C.P.|   ; fmt1 head1  cyl/rate: 0/N  18/L  39/H  44/L  67/H  80/N
4B59  00 00 50 00 50 00 50 00 50 00 50 00             |..P.P.P.P.P.|   ; fmt2 head0  cyl/rate: 0/N  80/N  80/N  80/N  80/N  80/N
4B65  00 00 50 00 50 00 50 00 50 00 50 00             |..P.P.P.P.P.|   ; fmt2 head1  cyl/rate: 0/N  80/N  80/N  80/N  80/N  80/N
4B71  00 00 37 01 47 02 50 00 50 00 50 00             |..7.G.P.P.P.|   ; fmt3 head0  cyl/rate: 0/N  55/L  71/H  80/N  80/N  80/N
4B7D  00 00 33 01 46 02 50 00 50 00 50 00             |..3.F.P.P.P.|   ; fmt3 head1  cyl/rate: 0/N  51/L  70/H  80/N  80/N  80/N

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
4B99  3E 30         LD A,0x30  ; HD44780 first function-set (8-bit) 0x30
4B9B  D3 E0         OUT (0xE0),A  ; lcd_cmd — issue to lcd_cmd port
4B9D  21 00 03      LD HL,0x0300  ; power-on delay count (>4.1ms)
4BA0  CD 22 4C      CALL lcd_setpos  ; busy-loop delay
4BA3  D3 E0         OUT (0xE0),A  ; lcd_cmd — repeat function-set 0x30
4BA5  21 40 00      LD HL,ptr_ver_firmware  ; shorter delay count
4BA8  CD 22 4C      CALL lcd_setpos  ; busy-loop delay
4BAB  D3 E0         OUT (0xE0),A  ; lcd_cmd — third function-set 0x30
4BAD  0E E0         LD C,0xE0  ; target = lcd_cmd register
4BAF  3E 38         LD A,0x38  ; function set: 8-bit, 2-line, 5x8
4BB1  CD 43 4C      CALL lcd_byte_out  ; send command
4BB4  3E 08         LD A,0x08  ; display off
4BB6  CD 43 4C      CALL lcd_byte_out  ; send command
4BB9  3E 01         LD A,0x01  ; clear display
4BBB  CD 43 4C      CALL lcd_byte_out  ; send command
4BBE  3E 06         LD A,0x06  ; entry mode: increment, no shift
4BC0  CD 43 4C      CALL lcd_byte_out  ; send command
4BC3  3E 0C         LD A,0x0C  ; display on, cursor/blink off
4BC5  CD 43 4C      CALL lcd_byte_out  ; send command
4BC8  3E 02         LD A,0x02  ; return home
4BCA  18 77         JR lcd_byte_out  ; tail-call to send the byte
4BCC  0E E8         LD C,0xE8  ; presence check: target lcd_data reg
4BCE  3E 55         LD A,0x55  ; write test pattern 0x55
4BD0  CD 43 4C      CALL lcd_byte_out  ; send to LCD data RAM
4BD3  0E E0         LD C,0xE0  ; back to cmd reg
4BD5  3E 02         LD A,0x02  ; return home to reset address counter
4BD7  CD 43 4C      CALL lcd_byte_out  ; send command
4BDA  CD 2A 4C      CALL lcd_wait_busy  ; wait busy flag clear
4BDD  DB E8         IN A,(0xE8)  ; lcd_data — read back the LCD data byte
4BDF  FE 55         CP 0x55  ; compare to pattern written

loc_4BE1:
4BE1  C8            RET Z  ; LCD present (readback matches) -> return

; mute local I/O: disable input poll and point iovec_out at no-op stub (0x4C4F)
io_mute_local:
4BE2  CD EC 4B      CALL io_disable_poll  ; stub out the input poll vector
4BE5  21 4F 4C      LD HL,loc_4C4F  ; muted no-op output stub
4BE8  22 C9 52      LD (iovec_out),HL  ; redirect iovec_out to stub
4BEB  C9            RET  ; return

; disable input polling: point iovec_poll at stub that returns A=0xFF
io_disable_poll:
4BEC  21 F2 4B      LD HL,loc_4BF2  ; stub returning A=0xFF
4BEF  22 CB 52      LD (iovec_poll),HL  ; redirect iovec_poll to stub

loc_4BF2:
4BF2  3E FF         LD A,0xFF  ; stub: report no input available
4BF4  C9            RET  ; return

; error beep: A*200/13 -> PIT ch1 (0xA4/0xAC) tone, pitch/duration encodes error code
error_report:
4BF5  5F            LD E,A  ; error code -> multiplicand low byte
4BF6  16 00         LD D,0x00  ; high byte 0
4BF8  4A            LD C,D  ; clear C (multiplier high)
4BF9  3E C8         LD A,0xC8  ; multiplier = 200
4BFB  CD 05 4F      CALL mul16  ; A*200 -> PIT tone base
4BFE  0E 0D         LD C,0x0D  ; divisor = 13
4C00  06 00         LD B,0x00  ; high divisor byte 0
4C02  CD CE 4E      CALL div32_16  ; (A*200)/13 -> PIT reload value
4C05  2D            DEC L  ; adjust reload down by 1
4C06  3E 70         LD A,0x70  ; PIT ctrl: counter1, load 16-bit, mode0 countdown
4C08  D3 AC         OUT (0xAC),A  ; pit_ctrl — to pit_ctrl
4C0A  0E A4         LD C,0xA4  ; PIT ch1 data port
4C0C  ED 69         OUT (C),L  ; load reload low byte
4C0E  ED 61         OUT (C),H  ; load reload high byte

loc_4C10:
4C10  3E 40         LD A,0x40  ; PIT ctrl: latch ch1 counter
4C12  D3 AC         OUT (0xAC),A  ; pit_ctrl — to pit_ctrl
4C14  DB A4         IN A,(0xA4)  ; pit_c1 — read latched count low
4C16  47            LD B,A  ; stash low byte
4C17  DB A4         IN A,(0xA4)  ; pit_c1 — read latched count high
4C19  FE FF         CP 0xFF  ; wait until high byte reaches 0xFF (tone duration)
4C1B  20 F3         JR NZ,loc_4C10  ; keep polling counter
4C1D  3E 50         LD A,0x50  ; PIT ctrl: stop/reprogram ch1
4C1F  D3 AC         OUT (0xAC),A  ; pit_ctrl — to pit_ctrl
4C21  C9            RET  ; return

; busy-loop delay (HL iterations)
lcd_setpos:
4C22  F5            PUSH AF  ; save A

loc_4C23:
4C23  2B            DEC HL  ; delay loop: decrement HL
4C24  7C            LD A,H  ; test HL==0: high byte
4C25  B5            OR L  ; OR low byte
4C26  20 FB         JR NZ,loc_4C23  ; spin until HL exhausted
4C28  F1            POP AF  ; restore A
4C29  C9            RET  ; return

; wait for LCD busy flag clear (IN 0xE0 bit7)
lcd_wait_busy:
4C2A  F5            PUSH AF  ; save A

loc_4C2B:
4C2B  DB E0         IN A,(0xE0)  ; lcd_cmd — read LCD status register
4C2D  CB 7F         BIT 7,A  ; test busy flag (bit7)
4C2F  20 FA         JR NZ,loc_4C2B  ; loop while LCD busy
4C31  F1            POP AF  ; restore A
4C32  DD E5         PUSH IX  ; IX push/pop settling delay
4C34  DD E5         PUSH IX  ; settling delay
4C36  DD E5         PUSH IX  ; settling delay
4C38  DD E5         PUSH IX  ; settling delay
4C3A  DD E1         POP IX  ; settling delay
4C3C  DD E1         POP IX  ; settling delay
4C3E  DD E1         POP IX  ; settling delay
4C40  DD E1         POP IX  ; settling delay
4C42  C9            RET  ; return

; write A to LCD via iovec_out (busy-wait then OUT (C),A; C=cmd/data reg)
lcd_byte_out:
4C43  22 57 4C      LD (lcd_byte_hl),HL  ; save caller HL
4C46  2A C9 52      LD HL,(iovec_out)  ; fetch output dispatch vector
4C49  E9            JP (HL)  ; dispatch to byte_out or muted stub

; default iovec_out: wait LCD busy then OUT (C),A; 0x4C4F entry is muted no-op restoring HL
byte_out:
4C4A  CD 2A 4C      CALL lcd_wait_busy  ; wait LCD ready
4C4D  ED 79         OUT (C),A  ; write byte to LCD reg selected by C

loc_4C4F:
4C4F  2A 57 4C      LD HL,(lcd_byte_hl)  ; restore caller HL
4C52  C9            RET  ; return

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
4C59  22 53 4C      LD (lcd_print_hl),HL  ; save caller HL
4C5C  ED 43 55 4C   LD (lcd_print_bc),BC  ; save caller BC
4C60  E1            POP HL  ; pop inline string pointer off the stack

loc_4C61:
4C61  7E            LD A,(HL)  ; fetch next string char
4C62  0E E0         LD C,0xE0  ; default target = cmd reg
4C64  23            INC HL  ; advance string pointer
4C65  B7            OR A  ; test for NUL terminator
4C66  28 62         JR Z,loc_4CCA  ; end of string -> finish
4C68  FE 0B         CP 0x0B  ; control byte 0x0B (home)?
4C6A  20 07         JR NZ,loc_4C73  ; no -> check next control
4C6C  3E 02         LD A,0x02  ; LCD return-home command

loc_4C6E:
4C6E  CD 43 4C      CALL lcd_byte_out  ; send byte to LCD
4C71  18 EE         JR loc_4C61  ; next char

loc_4C73:
4C73  FE 0C         CP 0x0C  ; control byte 0x0C (clear)?
4C75  20 04         JR NZ,loc_4C7B  ; no -> check next control
4C77  3E 01         LD A,0x01  ; LCD clear-display command
4C79  18 F3         JR loc_4C6E  ; send + loop

loc_4C7B:
4C7B  FE 0D         CP 0x0D  ; control byte 0x0D (CR)?
4C7D  20 0B         JR NZ,loc_4C8A  ; no -> check next control
4C7F  CD 2A 4C      CALL lcd_wait_busy  ; wait LCD ready
4C82  DB E0         IN A,(0xE0)  ; lcd_cmd — read current address counter
4C84  E6 40         AND 0x40  ; keep line bit only
4C86  F6 80         OR 0x80  ; form set-DDRAM-address command
4C88  18 E4         JR loc_4C6E  ; send + loop

loc_4C8A:
4C8A  FE 0A         CP 0x0A  ; control byte 0x0A (LF)?
4C8C  20 10         JR NZ,loc_4C9E  ; no -> check next control
4C8E  CD 2A 4C      CALL lcd_wait_busy  ; wait LCD ready
4C91  DB E0         IN A,(0xE0)  ; lcd_cmd — read address counter
4C93  CB 77         BIT 6,A  ; already on line 2?
4C95  C4 D3 4C      CALL NZ,lcd_scroll_up  ; if so, scroll display up
4C98  F6 C0         OR 0xC0  ; set-DDRAM to line 2 command
4C9A  0E E0         LD C,0xE0  ; cmd reg
4C9C  18 D0         JR loc_4C6E  ; send + loop

loc_4C9E:
4C9E  FE 1B         CP 0x1B  ; control byte 0x1B (position)?
4CA0  20 04         JR NZ,loc_4CA6  ; no -> printable char
4CA2  7E            LD A,(HL)  ; fetch position/DDRAM byte
4CA3  23            INC HL  ; advance past it
4CA4  18 C8         JR loc_4C6E  ; send as cmd + loop

loc_4CA6:
4CA6  F5            PUSH AF  ; printable char: save it
4CA7  CD 2A 4C      CALL lcd_wait_busy  ; wait LCD ready
4CAA  DB E0         IN A,(0xE0)  ; lcd_cmd — read address counter
4CAC  E6 7F         AND 0x7F  ; mask off busy flag
4CAE  FE 14         CP 0x14  ; at column 20 (end of line 1)?
4CB0  20 0F         JR NZ,loc_4CC1  ; no -> just print char

loc_4CB2:
4CB2  3E C0         LD A,0xC0  ; wrap: set-DDRAM to line 2
4CB4  0E E0         LD C,0xE0  ; cmd reg
4CB6  CD 43 4C      CALL lcd_byte_out  ; issue line-2 wrap

loc_4CB9:
4CB9  F1            POP AF  ; recover the char
4CBA  0E E8         LD C,0xE8  ; data reg
4CBC  CD 43 4C      CALL lcd_byte_out  ; write char to LCD
4CBF  18 A0         JR loc_4C61  ; next char

loc_4CC1:
4CC1  FE 54         CP 0x54  ; cursor past end of line 2 (DDRAM 0x54 = 0x40+20)?
4CC3  CC D3 4C      CALL Z,lcd_scroll_up  ; at line-2 wrap: scroll display up one line
4CC6  20 F1         JR NZ,loc_4CB9  ; not at wrap point: continue emitting the next char
4CC8  18 E8         JR loc_4CB2  ; loop back to process another output char

loc_4CCA:
4CCA  E5            PUSH HL  ; save HL before restoring saved cursor context
4CCB  2A 53 4C      LD HL,(lcd_print_hl)  ; reload saved LCD print HL pointer
4CCE  ED 4B 55 4C   LD BC,(lcd_print_bc)  ; reload saved LCD print BC (count/attr)
4CD2  C9            RET  ; return with restored print state

; scroll LCD display up one line: read line-2 chars and rewrite shifted, blank last
lcd_scroll_up:
4CD3  F5            PUSH AF  ; preserve AF across scroll routine
4CD4  D5            PUSH DE  ; preserve DE (D used as column index)
4CD5  16 00         LD D,0x00  ; start at column 0

loc_4CD7:
4CD7  7A            LD A,D  ; A = current column index
4CD8  F6 C0         OR 0xC0  ; set DDRAM addr bit for line 2 (0xC0 base)
4CDA  0E E0         LD C,0xE0  ; target LCD command register (0xE0)
4CDC  CD 43 4C      CALL lcd_byte_out  ; send set-DDRAM-address command
4CDF  CD 2A 4C      CALL lcd_wait_busy  ; wait for LCD not busy
4CE2  DB E8         IN A,(0xE8)  ; lcd_data — read char from line 2 at this column
4CE4  F5            PUSH AF  ; stash the read char
4CE5  7A            LD A,D  ; A = same column index again
4CE6  F6 C0         OR 0xC0  ; line-2 DDRAM address for read-back write
4CE8  0E E0         LD C,0xE0  ; LCD command register
4CEA  CD 43 4C      CALL lcd_byte_out  ; position cursor at line-2 column
4CED  3E 20         LD A,0x20  ; space char to blank line 2
4CEF  0E E8         LD C,0xE8  ; LCD data register (0xE8)
4CF1  CD 43 4C      CALL lcd_byte_out  ; write blank into line 2 cell
4CF4  7A            LD A,D  ; A = column index
4CF5  F6 80         OR 0x80  ; set DDRAM addr bit for line 1 (0x80 base)
4CF7  0E E0         LD C,0xE0  ; LCD command register
4CF9  CD 43 4C      CALL lcd_byte_out  ; position cursor at line-1 column
4CFC  F1            POP AF  ; recover the char read from line 2
4CFD  0E E8         LD C,0xE8  ; LCD data register
4CFF  CD 43 4C      CALL lcd_byte_out  ; copy that char up into line 1
4D02  14            INC D  ; advance to next column
4D03  7A            LD A,D  ; A = column counter
4D04  FE 14         CP 0x14  ; processed all 20 columns (0x14)?
4D06  20 CF         JR NZ,loc_4CD7  ; no: repeat for next column
4D08  D1            POP DE  ; restore DE
4D09  F1            POP AF  ; restore AF
4D0A  C9            RET  ; done scrolling up one line

; scan the 4-key keypad matrix (ports 0x98/0x94)
keypad_scan:
4D0B  CD 9B 4D      CALL poll_host_remote  ; first service any pending host remote command
4D0E  DB 98         IN A,(0x98)  ; key_scan — read keypad scan port
4D10  E6 FC         AND 0xFC  ; clear the two low column-select bits
4D12  F6 02         OR 0x02  ; drive column 1 (bit1) active
4D14  D3 98         OUT (0x98),A  ; key_scan — write column selection back to scan port
4D16  CD 29 4D      CALL keypad_row_read  ; read that column's row lines
4D19  28 01         JR Z,loc_4D1C  ; if no key in this column, try the other
4D1B  C9            RET  ; return: key found in column 1 (code as-is)

loc_4D1C:
4D1C  DB 98         IN A,(0x98)  ; key_scan — re-read keypad scan port
4D1E  EE 03         XOR 0x03  ; toggle both column-select bits to column 2
4D20  D3 98         OUT (0x98),A  ; key_scan — drive second keypad column active
4D22  CD 29 4D      CALL keypad_row_read  ; read second column's row lines
4D25  C8            RET Z  ; return 0 if no key pressed at all
4D26  C6 80         ADD A,0x80  ; set high bit to mark column-2 key code
4D28  C9            RET  ; return the column-2 key code

; read keypad row: IN status 0x94, invert low nibble, return single-key code or 0
keypad_row_read:
4D29  DB 94         IN A,(0x94)  ; status_in — read row status inputs
4D2B  2F            CPL  ; invert (rows are active-low)
4D2C  E6 0F         AND 0x0F  ; keep the 4 row bits
4D2E  C8            RET Z  ; return 0 (Z) if no row asserted
4D2F  FE 01         CP 0x01  ; row bit 0 set?
4D31  28 0E         JR Z,loc_4D41  ; single valid key -> normalize
4D33  FE 02         CP 0x02  ; row bit 1 set?
4D35  28 0A         JR Z,loc_4D41  ; single valid key -> normalize
4D37  FE 04         CP 0x04  ; row bit 2 set?
4D39  28 06         JR Z,loc_4D41  ; single valid key -> normalize
4D3B  FE 08         CP 0x08  ; row bit 3 set?
4D3D  28 02         JR Z,loc_4D41  ; single valid key -> normalize
4D3F  AF            XOR A  ; no single clean key: return 0
4D40  C9            RET  ; return with Z set (invalid/multi)

loc_4D41:
4D41  B7            OR A  ; set NZ to flag a valid single key in A
4D42  C9            RET  ; return key bitmask (NZ = valid)

; debounced key read with auto-repeat + key-click beep
keypad_debounce:
4D43  CD 49 4D      CALL keypad_wait  ; block until a debounced keypress
4D46  E6 7F         AND 0x7F  ; strip the column-2 high-bit marker
4D48  C9            RET  ; return the raw key code

; wait for a debounced keypress: poll keypad_scan with LCD-timed delays and panel busy pulse
keypad_wait:
4D49  E5            PUSH HL  ; save HL
4D4A  DD E5         PUSH IX  ; save IX
4D4C  DD 21 58 4A   LD IX,panel_shadow  ; point IX at the panel latch shadow byte

loc_4D50:
4D50  CD 0B 4D      CALL keypad_scan  ; poll keypad until a key is down
4D53  28 FB         JR Z,loc_4D50  ; no key yet: keep polling
4D55  21 64 00      LD HL,0x0064  ; delay count 100 (LCD-timed settle)
4D58  CD 22 4C      CALL lcd_setpos  ; run timed delay via lcd_setpos
4D5B  CD 0B 4D      CALL keypad_scan  ; re-scan keypad after settle
4D5E  28 F0         JR Z,loc_4D50  ; key released during settle: back to wait
4D60  F5            PUSH AF  ; save the confirmed key code
4D61  DD CB 00 9E   RES 3,(IX+0)  ; clear panel bit 3 (start key-click beep)
4D65  DD 7E 00      LD A,(IX+0)  ; load updated panel shadow byte
4D68  D3 F0         OUT (0xF0),A  ; panel — drive panel latch (beep on)
4D6A  21 E8 03      LD HL,0x03E8  ; delay count 1000 (beep duration)
4D6D  CD 22 4C      CALL lcd_setpos  ; run timed delay
4D70  DD CB 00 DE   SET 3,(IX+0)  ; set panel bit 3 (end key-click beep)
4D74  DD 7E 00      LD A,(IX+0)  ; load updated panel shadow byte
4D77  D3 F0         OUT (0xF0),A  ; panel — drive panel latch (beep off)

loc_4D79:
4D79  CD 0B 4D      CALL keypad_scan  ; poll keypad until the key is released
4D7C  20 FB         JR NZ,loc_4D79  ; still held: keep waiting for release
4D7E  F1            POP AF  ; recover the key code
4D7F  21 00 40      LD HL,0x4000  ; delay count 0x4000 (post-release debounce)
4D82  CD 22 4C      CALL lcd_setpos  ; run timed delay
4D85  DD E1         POP IX  ; restore IX
4D87  E1            POP HL  ; restore HL
4D88  C9            RET  ; return debounced key code

; get key / dispatch input (indirect via iovec_poll 0x52CB: keypad or host)
get_key:
4D89  E5            PUSH HL  ; save HL for indirect input dispatch
4D8A  2A CB 52      LD HL,(iovec_poll)  ; load current input-source vector
4D8D  E9            JP (HL)  ; jump to selected input handler (keypad/host)

; poll-input tail: if A=0 scan keypad and discard caller return; else return current value
get_key_dispatch:
4D8E  B7            OR A  ; test A: blocking vs non-blocking request?
4D8F  20 05         JR NZ,loc_4D96  ; A!=0: do a debounced blocking read
4D91  CD 0B 4D      CALL keypad_scan  ; A==0: non-blocking single keypad scan
4D94  E1            POP HL  ; discard caller's return addr (tail dispatch)
4D95  C9            RET  ; return scanned key

loc_4D96:
4D96  CD 43 4D      CALL keypad_debounce  ; blocking: wait for debounced keypress
4D99  E1            POP HL  ; discard caller's return addr
4D9A  C9            RET  ; return key

; poll host UART (0xDC) during key scan; if byte ready fetch remote word, flag cmd 0x0C
poll_host_remote:
4D9B  DB DC         IN A,(0xDC)  ; host_stat — read host UART status
4D9D  CB 47         BIT 0,A  ; RxRDY (bit0) set?
4D9F  C8            RET Z  ; no byte: return
4DA0  CD 01 1E      CALL host_rx_word  ; receive a remote command word
4DA3  C0            RET NZ  ; return on RX error/timeout
4DA4  7A            LD A,D  ; A = command byte (D)
4DA5  FE 0C         CP 0x0C  ; is it the 0x0C 'enter remote' command?
4DA7  28 02         JR Z,loc_4DAB  ; yes: switch to remote-control mode
4DA9  AF            XOR A  ; otherwise clear A (no action)
4DAA  C9            RET  ; return

loc_4DAB:
4DAB  CD AD 4E      CALL host_rx  ; consume remote handshake byte 1
4DAE  CD AD 4E      CALL host_rx  ; consume remote handshake byte 2
4DB1  06 58         LD B,0x58  ; reply byte 0x58
4DB3  CD 9D 4E      CALL host_tx  ; send ack to host
4DB6  06 00         LD B,0x00  ; reply byte 0x00
4DB8  CD 9D 4E      CALL host_tx  ; send second ack byte
4DBB  CD 59 4C      CALL lcd_print  ; show status message on LCD
4DBE  0C 52 65 6D 6F 74 +  DB \f, "Remote controll", 0  ; inline string: form-feed + 'Remote controll'
4DCF  CD E2 4B      CALL io_mute_local  ; mute local panel I/O during remote mode
4DD2  C3 0B 1E      JP host_dispatch  ; jump into the host command dispatch loop

padding:
4DD5  00 00 00 00                                     |....|

; init 8253 (baud c0, timers c1/c2) and both SIO channels; drain receivers
timer_uart_init:
4DD9  ED 56         IM 1  ; select interrupt mode 1
4DDB  3E 16         LD A,0x16  ; 8253 ctrl: counter0 mode3 (baud gen)
4DDD  D3 AC         OUT (0xAC),A  ; pit_ctrl — program PIT control word
4DDF  3E 0D         LD A,0x0D  ; baud divisor low byte (0x0D)
4DE1  D3 A0         OUT (0xA0),A  ; pit_c0 — load counter0 (baud clock)
4DE3  3E 50         LD A,0x50  ; 8253 ctrl: counter1 setup word
4DE5  D3 AC         OUT (0xAC),A  ; pit_ctrl — program PIT control word
4DE7  3E 90         LD A,0x90  ; 8253 ctrl: counter2 setup word
4DE9  D3 AC         OUT (0xAC),A  ; pit_ctrl — program PIT control word
4DEB  F5            PUSH AF  ; hold the counter value
4DEC  D3 A4         OUT (0xA4),A  ; pit_c1 — load counter1 (timer)
4DEE  F1            POP AF  ; recover counter value
4DEF  D3 A8         OUT (0xA8),A  ; pit_c2 — load counter2 (timer)
4DF1  3E 0F         LD A,0x0F  ; ctrl-latch data 0x0F
4DF3  D3 9C         OUT (0x9C),A  ; ctrl_latch — write to addressable control latch
4DF5  3E 0E         LD A,0x0E  ; drive-latch value 0x0E
4DF7  D3 40         OUT (0x40),A  ; drv_lat0 — init drive select latch 0
4DF9  D3 60         OUT (0x60),A  ; drv_lat2 — init drive select latch 2
4DFB  21 28 4E      LD HL,al_ser_blob  ; source = autoloader SIO init blob
4DFE  01 D4 0D      LD BC,0x0DD4  ; B=0x0D bytes, C=0xD4 (al ctrl port)
4E01  ED B3         OTIR  ; block-out init sequence to autoloader SIO
4E03  21 35 4E      LD HL,host_ser_blob2  ; source = host SIO init blob
4E06  01 DC 0D      LD BC,0x0DDC  ; B=0x0D bytes, C=0xDC (host ctrl port)
4E09  ED B3         OTIR  ; block-out init sequence to host SIO
4E0B  DB D0         IN A,(0xD0)  ; al_data — flush autoloader RX (dummy read)
4E0D  DB D0         IN A,(0xD0)  ; al_data — flush autoloader RX (dummy read)
4E0F  DB D0         IN A,(0xD0)  ; al_data — flush autoloader RX (dummy read)
4E11  DB D0         IN A,(0xD0)  ; al_data — flush autoloader RX (dummy read)
4E13  DB D8         IN A,(0xD8)  ; host_data — flush host RX (dummy read)
4E15  DB D8         IN A,(0xD8)  ; host_data — flush host RX (dummy read)
4E17  DB D8         IN A,(0xD8)  ; host_data — flush host RX (dummy read)
4E19  DB D8         IN A,(0xD8)  ; host_data — flush host RX (dummy read)
4E1B  CD 91 4E      CALL al_cmd_reset  ; reset autoloader SIO command state
4E1E  CD 95 4E      CALL host_cmd_reset  ; reset host SIO command state
4E21  CD 99 4B      CALL lcd_init  ; initialize the LCD
4E24  CD 2C 45      CALL fdc_senseint_all  ; issue SENSE INTERRUPT to all 4 FDCs
4E27  C9            RET  ; return from timer/UART init

al_ser_blob:
4E28  18 03 C0 04 44 05 E0 01 80 03 C1 05 EA          |....D........|

host_ser_blob2:
4E35  18 03 C0 04 45 05 E0 01 80 03 C1 05 EA          |....E........|

; SIO TX: wait TxRDY (status bit2), OUT data
uart_tx:
4E42  ED 78         IN A,(C)  ; read SIO status (port in C)
4E44  CB 57         BIT 2,A  ; TxRDY (bit2) set?
4E46  28 FA         JR Z,uart_tx  ; not ready: keep polling
4E48  CB 91         RES 2,C  ; select data register (C bit2 low)
4E4A  ED 41         OUT (C),B  ; write TX byte from B
4E4C  CB D1         SET 2,C  ; restore C to status/ctrl register
4E4E  C9            RET  ; return after TX

; test host SIO RxRDY: C=0xDC, IN B, bit0 = byte available
host_rx_ready:
4E4F  0E DC         LD C,0xDC  ; select host SIO base port 0xDC
4E51  18 02         JR loc_4E55  ; go do the RxRDY test

; test autoloader SIO RxRDY: C=0xD4, IN B, bit0 = byte available
al_rx_ready:
4E53  0E D4         LD C,0xD4  ; select autoloader SIO base port 0xD4

loc_4E55:
4E55  ED 40         IN B,(C)  ; read SIO status into B
4E57  CB 40         BIT 0,B  ; isolate RxRDY (bit0)
4E59  C9            RET  ; return (Z = no byte ready)

; SIO RX with timeout: wait RxRDY (bit0); return Z=byte / NZ=timeout|err
uart_rx:
4E5A  E5            PUSH HL  ; save HL (timeout counter)
4E5B  D5            PUSH DE  ; save DE (retry counter)
4E5C  1E 14         LD E,0x14  ; outer retry count 0x14 (default)
4E5E  3E DC         LD A,0xDC  ; port == host UART (0xDC)?
4E60  B9            CP C  ; compare against C
4E61  20 02         JR NZ,loc_4E65  ; not host: keep default retry count
4E63  1E 01         LD E,0x01  ; host UART: use single retry pass

loc_4E65:
4E65  21 00 00      LD HL,0x0000  ; inner timeout counter = 0

loc_4E68:
4E68  ED 40         IN B,(C)  ; read SIO status into B
4E6A  CB 40         BIT 0,B  ; RxRDY (bit0) set?
4E6C  20 0D         JR NZ,loc_4E7B  ; byte ready: go fetch it
4E6E  2B            DEC HL  ; decrement inner timeout counter
4E6F  7D            LD A,L  ; A = HL low byte
4E70  B4            OR H  ; HL reached zero?
4E71  20 F5         JR NZ,loc_4E68  ; not yet: keep polling
4E73  1D            DEC E  ; one retry pass expired: decrement outer
4E74  20 F2         JR NZ,loc_4E68  ; more retries left: poll again
4E76  F6 01         OR 0x01  ; set NZ (timeout error flag)
4E78  7D            LD A,L  ; A = 0 result byte
4E79  18 0E         JR loc_4E89  ; jump to common exit (return timeout)

loc_4E7B:
4E7B  CB 91         RES 2,C  ; point C at SIO status register (clear select bit2)
4E7D  ED 40         IN B,(C)  ; read SIO status into B
4E7F  CB D1         SET 2,C  ; restore bit2 -> back to command/data register
4E81  3E 01         LD A,0x01  ; control byte 0x01: select SIO error-status register
4E83  ED 79         OUT (C),A  ; issue the control byte to the SIO
4E85  ED 78         IN A,(C)  ; read back SIO status word
4E87  E6 70         AND 0x70  ; mask error bits (0x70 = framing/overrun/parity)

loc_4E89:
4E89  D1            POP DE  ; restore DE saved by caller
4E8A  E1            POP HL  ; restore HL saved by caller
4E8B  C9            RET  ; return

; send SIO command 0x30 to port C (reset error flags / enter hunt)
uart_send_reset:
4E8C  3E 30         LD A,0x30  ; SIO command 0x30 = reset error flags / enter hunt mode
4E8E  ED 79         OUT (C),A  ; write reset command to the SIO port in C
4E90  C9            RET  ; return

; reset autoloader SIO (C=0xD4) via command 0x30
al_cmd_reset:
4E91  0E D4         LD C,0xD4  ; select autoloader SIO (SIO chan A = 0xD4)
4E93  18 F7         JR uart_send_reset  ; tail into uart_send_reset

; reset host SIO (C=0xDC) via command 0x30
host_cmd_reset:
4E95  0E DC         LD C,0xDC  ; select host SIO (SIO chan B = 0xDC)
4E97  18 F3         JR uart_send_reset  ; tail into uart_send_reset

; transmit byte A to autoloader SIO (C=0xD4, via uart_tx)
al_tx:
4E99  0E D4         LD C,0xD4  ; select autoloader SIO (0xD4)
4E9B  18 A5         JR uart_tx  ; tail into uart_tx to send byte A

; transmit byte A to host SIO (C=0xDC, via uart_tx)
host_tx:
4E9D  0E DC         LD C,0xDC  ; select host SIO (0xDC)
4E9F  18 A1         JR uart_tx  ; tail into uart_tx to send byte A

; receive byte from autoloader SIO (C=0xD4); on data, clear SIO errors
al_rx:
4EA1  0E D4         LD C,0xD4  ; select autoloader SIO (0xD4)

loc_4EA3:
4EA3  CD 5A 4E      CALL uart_rx  ; poll SIO for a received byte (Z=none)
4EA6  C8            RET Z  ; bail out if no byte available
4EA7  F5            PUSH AF  ; save received byte
4EA8  CD 8C 4E      CALL uart_send_reset  ; clear SIO error flags after successful read
4EAB  F1            POP AF  ; restore received byte
4EAC  C9            RET  ; return with byte in A

; receive byte from host SIO (C=0xDC); on data, clear SIO errors
host_rx:
4EAD  0E DC         LD C,0xDC  ; select host SIO (0xDC)
4EAF  18 F2         JR loc_4EA3  ; share the autoloader receive path
4EB1  C9            RET  ; return (unreached tail)

; 32-bit binary (DE:HL) -> decimal ASCII, right-justified in buffer at 0x4F38 down
bin2dec_clear:
4EB2  CD 1D 4F      CALL clear_dec_buf  ; space-fill decimal output buffer first

; binary -> decimal ASCII conversion
bin2dec:
4EB5  DD 21 38 4F   LD IX,lcd_dec_tmpl+0x9  ; IX -> last digit slot of decimal template

loc_4EB9:
4EB9  CD CB 4E      CALL div_by_10  ; divide DE:HL by 10, remainder digit in C
4EBC  79            LD A,C  ; grab remainder digit
4EBD  C6 30         ADD A,0x30  ; convert to ASCII '0'-'9'
4EBF  DD 77 00      LD (IX+0),A  ; store digit into buffer
4EC2  DD 2B         DEC IX  ; step buffer pointer left one digit
4EC4  7D            LD A,L  ; test running quotient for zero...
4EC5  B4            OR H  ; ...OR in H
4EC6  B3            OR E  ; ...OR in E
4EC7  B2            OR D  ; ...OR in D (full 32-bit zero test)
4EC8  20 EF         JR NZ,loc_4EB9  ; loop until quotient exhausted
4ECA  C9            RET  ; return, digits written right-justified

; divide 32-bit DE:HL by 10 (BC=10 wrapper over div32_16), remainder in C for digits
div_by_10:
4ECB  01 0A 00      LD BC,0x000A  ; divisor = 10

; 32/16 unsigned divide (DE:HL / BC)
div32_16:
4ECE  DD E5         PUSH IX  ; save caller IX
4ED0  DD 21 00 00   LD IX,0x0000  ; clear remainder accumulator (IX)
4ED4  3E 21         LD A,0x21  ; 33-bit loop counter (0x21 = 32 bits + priming)
4ED6  B7            OR A  ; clear carry to start shift-subtract divide

loc_4ED7:
4ED7  ED 6A         ADC HL,HL  ; shift dividend low word left, carry in
4ED9  EB            EX DE,HL  ; swap to high word
4EDA  ED 6A         ADC HL,HL  ; shift dividend high word left, carry through
4EDC  EB            EX DE,HL  ; swap back
4EDD  3D            DEC A  ; decrement bit counter
4EDE  28 1F         JR Z,loc_4EFF  ; done -> finish and return quotient
4EE0  E5            PUSH HL  ; save dividend HL
4EE1  DD E5         PUSH IX  ; load remainder accumulator into HL
4EE3  E1            POP HL  ; (via stack)
4EE4  ED 6A         ADC HL,HL  ; shift remainder left, bringing in dividend MSB
4EE6  E5            PUSH HL  ; write remainder back to IX
4EE7  DD E1         POP IX  ; (via stack)
4EE9  30 08         JR NC,loc_4EF3  ; no overflow -> try normal subtract
4EEB  A7            AND A  ; clear carry
4EEC  ED 42         SBC HL,BC  ; remainder overflowed: subtract divisor
4EEE  E5            PUSH HL  ; store reduced remainder
4EEF  DD E1         POP IX  ; (via stack)
4EF1  18 09         JR loc_4EFC  ; quotient bit = 1, continue

loc_4EF3:
4EF3  A7            AND A  ; clear carry
4EF4  ED 42         SBC HL,BC  ; trial subtract divisor from remainder
4EF6  38 03         JR C,loc_4EFB  ; underflow -> remainder too small, bit stays 0
4EF8  E5            PUSH HL  ; keep the subtracted remainder
4EF9  DD E1         POP IX  ; (via stack)

loc_4EFB:
4EFB  3F            CCF  ; complement carry -> quotient bit into dividend

loc_4EFC:
4EFC  E1            POP HL  ; restore dividend HL
4EFD  18 D8         JR loc_4ED7  ; next division step

loc_4EFF:
4EFF  DD E5         PUSH IX  ; move remainder accumulator...
4F01  C1            POP BC  ; ...into BC (remainder result)
4F02  DD E1         POP IX  ; restore caller IX
4F04  C9            RET  ; return: DE:HL=quotient, BC=remainder

; 16x16 unsigned multiply
mul16:
4F05  06 10         LD B,0x10  ; 16 shift-add iterations
4F07  21 00 00      LD HL,0x0000  ; clear product low word

loc_4F0A:
4F0A  CB 25         SLA L  ; shift product/multiplier left one bit
4F0C  CB 14         RL H  ; carry through product high byte
4F0E  CB 17         RL A  ; carry through A
4F10  CB 11         RL C  ; carry out multiplier MSB into carry
4F12  30 04         JR NC,loc_4F18  ; MSB was 0 -> skip add
4F14  19            ADD HL,DE  ; add multiplicand DE to partial product
4F15  30 01         JR NC,loc_4F18  ; no carry -> skip high-byte bump
4F17  3C            INC A  ; propagate carry into product high byte

loc_4F18:
4F18  10 F0         DJNZ loc_4F0A  ; repeat for all 16 bits
4F1A  51            LD D,C  ; assemble product high word D=C
4F1B  5F            LD E,A  ; and E=A
4F1C  C9            RET  ; return 32-bit product in DE:HL

; fill 8-byte decimal-conversion buffer at 0x4F31 with spaces
clear_dec_buf:
4F1D  DD 21 31 4F   LD IX,lcd_dec_tmpl+0x2  ; IX -> start of 8-digit field in template
4F21  06 08         LD B,0x08  ; 8 characters to blank

loc_4F23:
4F23  DD 36 00 20   LD (IX+0),0x20  ; store space (0x20)
4F27  DD 23         INC IX  ; advance pointer
4F29  10 F8         DJNZ loc_4F23  ; loop over all 8 slots
4F2B  C9            RET  ; return

; print the decimal-conversion buffer string to LCD (via lcd_print)
lcd_print_number:
4F2C  CD 59 4C      CALL lcd_print  ; send decimal template string to LCD

lcd_dec_tmpl:
4F2F  1B C0 2E 2E 2E 2E +  DB ESC(0xC0), "........", 0  ; LCD template: goto line2 (ESC 0xC0), 8-digit field, terminator
4F3A  C9            RET  ; return

; monitor hex-dump: clear LCD (cmd 0x01) then print a hex row of bytes from (HL)
lcd_dump_hex:
4F3B  F5            PUSH AF  ; save A (byte count)
4F3C  C5            PUSH BC  ; save BC
4F3D  47            LD B,A  ; stash count in B
4F3E  3E 01         LD A,0x01  ; LCD command 0x01 = clear display
4F40  0E E0         LD C,0xE0  ; C -> LCD command port 0xE0
4F42  CD 43 4C      CALL lcd_byte_out  ; issue clear-display to LCD
4F45  78            LD A,B  ; recover byte count
4F46  A7            AND A  ; count == 0?
4F47  20 06         JR NZ,loc_4F4F  ; nonzero -> print that many bytes
4F49  CD 5C 4F      CALL mon_hexrow  ; zero -> print default full hex row

loc_4F4C:
4F4C  C1            POP BC  ; restore BC
4F4D  F1            POP AF  ; restore AF
4F4E  C9            RET  ; return

loc_4F4F:
4F4F  47            LD B,A  ; use count as DJNZ loop counter

loc_4F50:
4F50  C5            PUSH BC  ; save loop counter
4F51  CD 7A 4F      CALL mon_hexbyte  ; print byte at (HL) as two hex digits
4F54  CD 6F 4F      CALL mon_hex_space  ; print field-separator space
4F57  C1            POP BC  ; restore loop counter
4F58  10 F6         DJNZ loc_4F50  ; loop for remaining bytes
4F5A  18 F0         JR loc_4F4C  ; done -> restore and return

; print a full 2-line monitor hex row (mon_hex4 group + line-2 home)
mon_hexrow:
4F5C  CD 5F 4F      CALL mon_hexrow_b  ; print a hex group then home to line 2

; print monitor hex group then home to LCD line 2
mon_hexrow_b:
4F5F  CD 66 4F      CALL mon_hex4  ; print 4-byte hex group from (HL)
4F62  CD C4 4F      CALL lcd_line2_home  ; reposition LCD cursor to line 2 start
4F65  C9            RET  ; return

; monitor hex-row segment: print 4 hex bytes from (HL) plus trailing space
mon_hex4:
4F66  CD 69 4F      CALL mon_hex3  ; print byte #1 then chain 3 more

; monitor hex-row segment: print 3 hex bytes from (HL) plus trailing space
mon_hex3:
4F69  CD 6C 4F      CALL mon_hex2  ; print byte then chain 2 more

; monitor hex-row segment: print 2 hex bytes from (HL) plus trailing space
mon_hex2:
4F6C  CD 77 4F      CALL mon_hex2b  ; print byte then chain 1 more

; print a single space char to LCD data (0xE8) - monitor field separator
mon_hex_space:
4F6F  3E 20         LD A,0x20  ; space character
4F71  0E E8         LD C,0xE8  ; C -> LCD data port 0xE8
4F73  CD 43 4C      CALL lcd_byte_out  ; write space to LCD
4F76  C9            RET  ; return

; print 2 hex bytes from (HL) to LCD, advancing HL (monitor)
mon_hex2b:
4F77  CD 7A 4F      CALL mon_hexbyte  ; print two hex bytes (first via mon_hexbyte)

; print byte at (HL) as 2 hex digits to LCD, advance HL (monitor)
mon_hexbyte:
4F7A  7E            LD A,(HL)  ; fetch byte at (HL)
4F7B  E5            PUSH HL  ; save data pointer
4F7C  21 AB 4F      LD HL,mon_hexbuf+0x2  ; HL -> hex scratch byte
4F7F  32 AB 4F      LD (mon_hexbuf+0x2),A  ; stash byte into scratch for RLD nibble printing
4F82  CD AC 4F      CALL mon_hexpair  ; emit both hex nibbles to LCD
4F85  E1            POP HL  ; restore data pointer
4F86  23            INC HL  ; advance to next source byte
4F87  C9            RET  ; return
4F88  F5            PUSH AF  ; save A
4F89  E5            PUSH HL  ; save HL (address to show)
4F8A  CD 59 4C      CALL lcd_print  ; print label string to LCD
4F8D  0C 41 64 72 65 73 +  DB \f, "Adresa = ", 0  ; LCD string: form-feed/clear, "Adresa = " (Czech 'Address'), terminator
4F98  E1            POP HL  ; recover address
4F99  E5            PUSH HL  ; re-save it
4F9A  7C            LD A,H  ; byte-swap H<->L to print big-endian...
4F9B  65            LD H,L  ; ...H = old L
4F9C  6F            LD L,A  ; ...L = old H
4F9D  22 A9 4F      LD (mon_hexbuf),HL  ; store swapped address into hex buffer
4FA0  21 A9 4F      LD HL,mon_hexbuf  ; HL -> that buffer
4FA3  CD 77 4F      CALL mon_hex2b  ; print the 2-byte address as 4 hex digits
4FA6  E1            POP HL  ; restore HL
4FA7  F1            POP AF  ; restore A
4FA8  C9            RET  ; return

mon_hexbuf:
4FA9  00 00 01                                        |...|

; print two hex nibbles of buffered byte (0x4FAB) via RLD, ASCII-adjust, to LCD
mon_hexpair:
4FAC  CD AF 4F      CALL mon_hexnib  ; print high nibble first, then chain low nibble

; print one hex nibble via RLD to ASCII (0-9/A-F) to LCD data (0xE8)
mon_hexnib:
4FAF  ED 6F         RLD  ; rotate next nibble of scratch byte into A
4FB1  F5            PUSH AF  ; save rotated byte
4FB2  E6 0F         AND 0x0F  ; isolate the 4-bit nibble
4FB4  C6 30         ADD A,0x30  ; convert to ASCII, assuming 0-9
4FB6  FE 3A         CP 0x3A  ; past '9'?
4FB8  FA BD 4F      JP M,loc_4FBD  ; no -> already correct digit
4FBB  C6 07         ADD A,0x07  ; yes -> adjust to 'A'-'F'

loc_4FBD:
4FBD  0E E8         LD C,0xE8  ; C -> LCD data port 0xE8
4FBF  CD 43 4C      CALL lcd_byte_out  ; write hex digit to LCD
4FC2  F1            POP AF  ; restore byte
4FC3  C9            RET  ; return

; home LCD to line 2 (via lcd_print control sequence)
lcd_line2_home:
4FC4  CD 59 4C      CALL lcd_print  ; send cursor-positioning string to LCD
4FC7  1B C0 00      DB ESC(0xC0), 0  ; LCD control: ESC 0xC0 = move to line 2, terminator
4FCA  C9            RET  ; return

; assemble FDC format command block: geometry + sector map + interleave + DMA/bank params from 0x3130
build_format_block:
4FCB  CD 01 51      CALL init_format_geom  ; set up format geometry (C/H/N, bytes/sector)
4FCE  CD 43 50      CALL format_sector_map  ; build the sector-ID map for FORMAT
4FD1  FD 22 F2 52   LD (cksum_ref+0x2),IY  ; save IY (map end) into checksum reference
4FD5  CD 7E 50      CALL build_interleave_tbl  ; build sector interleave table
4FD8  3A 30 31      LD A,(dram_bank_count)  ; load DRAM image bank count
4FDB  DD 77 0C      LD (IX+12),A  ; descriptor+12 = bank count
4FDE  DD 36 0D 00   LD (IX+13),0x00  ; descriptor+13 = 0x00 (DMA addr low)
4FE2  DD 36 0E 80   LD (IX+14),0x80  ; descriptor+14 = 0x80 (image_buf high byte)
4FE6  DD 77 0F      LD (IX+15),A  ; descriptor+15 = bank count (repeat)
4FE9  DD 36 10 00   LD (IX+16),0x00  ; descriptor+16 = 0x00
4FED  DD 36 11 C0   LD (IX+17),0xC0  ; descriptor+17 = 0xC0 (DMA/bank param)
4FF1  C9            RET  ; return with format block assembled

; logical block -> CHS + DMA descriptor (uses format_desc geometry)
block_to_chs:
4FF2  C5            PUSH BC  ; save BC
4FF3  DD E5         PUSH IX  ; save IX
4FF5  79            LD A,C  ; get low block byte
4FF6  07            RLCA  ; RLCA: bring block-low top bit down into bit0 for head select
4FF7  E6 01         AND 0x01  ; keep just the head bit (0 or 1)
4FF9  4F            LD C,A  ; C = head number (0 or 1)
4FFA  DD 21 DD 52   LD IX,format_desc  ; IX -> format geometry descriptor
4FFE  DD 7E 01      LD A,(IX+1)  ; load number of heads
5001  3D            DEC A  ; single-sided (1 head)?
5002  28 02         JR Z,loc_5006  ; yes -> skip cylinder doubling
5004  CB 20         SLA B  ; double-sided: shift block high byte for CHS calc

loc_5006:
5006  78            LD A,B  ; A = B: start the index calc from counter B
5007  81            ADD A,C  ; A += C: combine the two running counters
5008  4F            LD C,A  ; C = B+C: keep the folded index
5009  06 56         LD B,0x56  ; B = 0x56 (86): entries in the interleave/sector table
500B  DD 7E 01      LD A,(IX+1)  ; A = descriptor field (IX+1): sectors-per-track count
500E  3D            DEC A  ; A-1: make it a zero-based index
500F  05            DEC B  ; decrement table counter B alongside
5010  A7            AND A  ; test A for zero (index landed on first sector?)
5011  28 02         JR Z,loc_5015  ; if zero, skip the doubling step
5013  CB 20         SLA B  ; B <<= 1: double the table stride for this entry

loc_5015:
5015  80            ADD A,B  ; A += B: apply the doubled offset
5016  91            SUB C  ; A -= C: subtract the folded checksum index -> logical id
5017  DD 2A F2 52   LD IX,(cksum_ref+0x2)  ; IX = cksum_ref+2 base pointer for the descriptor array
501B  6F            LD L,A  ; L = computed index
501C  26 00         LD H,0x00  ; H = 0: zero-extend index to 16-bit
501E  29            ADD HL,HL  ; HL *= 2: 2-byte entry stride
501F  EB            EX DE,HL  ; move the byte offset into DE
5020  DD 19         ADD IX,DE  ; IX += DE: point at the selected array entry
5022  DD 7E 01      LD A,(IX+1)  ; A = entry byte (IX+1)
5025  87            ADD A,A  ; A *= 2
5026  87            ADD A,A  ; A *= 4 total: scale to 4-byte record stride
5027  5F            LD E,A  ; E = scaled offset low
5028  16 00         LD D,0x00  ; D = 0: zero-extend offset
502A  FD 21 F4 52   LD IY,cksum_ref+0x4  ; IY = cksum_ref+4: base of the 4-byte record table
502E  FD 19         ADD IY,DE  ; IY += DE: select the target 4-byte record
5030  FD 6E 00      LD L,(IY+0)  ; load record byte 0 into L
5033  FD 66 01      LD H,(IY+1)  ; load record byte 1 into H
5036  FD 5E 02      LD E,(IY+2)  ; load record byte 2 into E
5039  FD 56 03      LD D,(IY+3)  ; load record byte 3 into D: HL/DE = 32-bit field
503C  DD 7E 00      LD A,(IX+0)  ; A = descriptor byte (IX+0): the return value
503F  DD E1         POP IX  ; restore caller IX
5041  C1            POP BC  ; restore caller BC
5042  C9            RET  ; return with A/HL/DE holding the looked-up record

; generate per-track sector-ID (interleave) list for FORMAT
format_sector_map:
5043  FD 21 F4 52   LD IY,cksum_ref+0x4  ; IY = cksum_ref+4: destination 4-byte record table
5047  DD 21 DD 52   LD IX,format_desc  ; IX = format_desc geometry block
504B  21 00 80      LD HL,image_buf  ; HL = image_buf: running LBA/byte pointer
504E  DD 5E 07      LD E,(IX+7)  ; E = format_desc+7: track byte-count low
5051  DD 7E 08      LD A,(IX+8)  ; A = format_desc+8: track byte-count high
5054  F6 80         OR 0x80  ; set bit7: mark high byte / flag the count
5056  57            LD D,A  ; D = flagged high byte -> DE = per-track increment
5057  DD 46 05      LD B,(IX+5)  ; B = format_desc+5 = sectors-per-track: loop count

loc_505A:
505A  FD 75 00      LD (IY+0),L  ; store pointer low into record byte 0
505D  FD 74 01      LD (IY+1),H  ; store pointer high into record byte 1
5060  FD 73 02      LD (IY+2),E  ; store increment low into record byte 2
5063  FD 72 03      LD (IY+3),D  ; store increment high into record byte 3
5066  DD 6E 06      LD L,(IX+6)  ; L = format_desc+6: sector size code / gap value
5069  26 00         LD H,0x00  ; H = 0: zero-extend
506B  19            ADD HL,DE  ; HL += DE: advance pointer by one sector
506C  E5            PUSH HL  ; save the advanced pointer
506D  DD 5E 09      LD E,(IX+9)  ; E = format_desc+9: total-length low
5070  DD 56 0A      LD D,(IX+10)  ; D = format_desc+10: total-length high
5073  19            ADD HL,DE  ; HL += DE: add image total length
5074  11 04 00      LD DE,0x0004  ; DE = 4: record stride
5077  FD 19         ADD IY,DE  ; IY += 4: advance to next 4-byte record
5079  EB            EX DE,HL  ; DE = new running increment for next iteration
507A  E1            POP HL  ; HL = restored sector pointer
507B  10 DD         DJNZ loc_505A  ; loop over all sectors of the track
507D  C9            RET  ; return with record table populated

; build sector interleave table at IY (0x52F2): fill physical->logical sector ids via sector_lba
build_interleave_tbl:
507E  DD 21 DD 52   LD IX,format_desc  ; IX = format_desc geometry block
5082  FD 2A F2 52   LD IY,(cksum_ref+0x2)  ; IY = interleave table base at cksum_ref+2 (0x52F2)
5086  06 56         LD B,0x56  ; B = 0x56 (86): outer loop over max sectors

loc_5088:
5088  C5            PUSH BC  ; save outer sector counter
5089  DD 46 01      LD B,(IX+1)  ; B = format_desc+1 = sectors-per-track: inner loop count

loc_508C:
508C  78            LD A,B  ; A = physical sector number (from inner counter)
508D  68            LD L,B  ; L = save physical sector number
508E  3D            DEC A  ; A-1: zero-based physical index
508F  C1            POP BC  ; restore outer BC (recover outer counter)
5090  C5            PUSH BC  ; re-save outer counter
5091  05            DEC B  ; B-- : advance outer position for the LBA calc
5092  4D            LD C,L  ; C = saved physical sector number
5093  CD AB 50      CALL sector_lba  ; compute interleaved logical id via sector_lba
5096  41            LD B,C  ; B = C: restore loop count from result C
5097  FD 77 01      LD (IY+1),A  ; store logical id (A) into table entry byte 1
509A  7D            LD A,L  ; A = physical sector L
509B  3C            INC A  ; A+1: back to 1-based sector number
509C  2F            CPL  ; one's-complement it (stored inverted as marker)
509D  FD 77 00      LD (IY+0),A  ; store inverted physical id into table entry byte 0
50A0  11 02 00      LD DE,0x0002  ; DE = 2: 2-byte entry stride
50A3  FD 19         ADD IY,DE  ; IY += 2: advance to next interleave entry
50A5  10 E5         DJNZ loc_508C  ; inner loop over sectors-per-track
50A7  C1            POP BC  ; restore outer counter
50A8  10 DE         DJNZ loc_5088  ; outer loop over the 86 slots
50AA  C9            RET  ; return with interleave table filled

; compute interleaved logical sector id from position: div32_16 by sectors-per-track (format_desc+5)
sector_lba:
50AB  C5            PUSH BC  ; save BC
50AC  DD E5         PUSH IX  ; save IX
50AE  DD 21 DD 52   LD IX,format_desc  ; IX = format_desc geometry block
50B2  DD 4E 01      LD C,(IX+1)  ; C = format_desc+1 = sectors-per-track
50B5  0D            DEC C  ; C-- : test for single-sector case
50B6  28 02         JR Z,loc_50BA  ; if one sector, skip doubling
50B8  CB 20         SLA B  ; B <<= 1: double position for interleave spread

loc_50BA:
50BA  80            ADD A,B  ; A += B: apply interleave offset to position
50BB  6F            LD L,A  ; L = position low
50BC  26 00         LD H,0x00  ; H = 0: zero-extend to 16-bit dividend
50BE  5C            LD E,H  ; E = 0 (from H): clear DE high word
50BF  54            LD D,H  ; D = 0: 32-bit dividend high = 0
50C0  44            LD B,H  ; B = 0: clear divisor high
50C1  DD 4E 05      LD C,(IX+5)  ; C = format_desc+5 = sectors-per-track divisor
50C4  CD CE 4E      CALL div32_16  ; div32_16: position / spt, remainder = logical sector id
50C7  79            LD A,C  ; A = C = remainder (interleaved logical sector id)
50C8  DD E1         POP IX  ; restore IX
50CA  C1            POP BC  ; restore BC
50CB  C9            RET  ; return logical id in A

; lay out per-sector format descriptors (C/H/R/N) for whole track via block_to_chs
layout_sectors:
50CC  DD 21 DD 52   LD IX,format_desc  ; IX = format_desc geometry block
50D0  06 56         LD B,0x56  ; B = 0x56 (86): outer loop over track slots

loc_50D2:
50D2  C5            PUSH BC  ; save outer counter
50D3  DD 46 01      LD B,(IX+1)  ; B = format_desc+1 = sectors-per-track: inner count

loc_50D6:
50D6  78            LD A,B  ; A = physical sector number
50D7  68            LD L,B  ; L = save physical sector number
50D8  3D            DEC A  ; A-1: zero-based sector index
50D9  0F            RRCA  ; rotate right: carry = LSB -> selects head/side
50DA  C1            POP BC  ; restore outer BC
50DB  C5            PUSH BC  ; re-save outer counter
50DC  05            DEC B  ; B-- : advance outer track position
50DD  4F            LD C,A  ; C = shifted index (sector position for CHS calc)
50DE  E5            PUSH HL  ; save HL (sector number)
50DF  3E 00         LD A,0x00  ; A = 0: default head/side 0
50E1  30 03         JR NC,loc_50E6  ; if carry clear, keep head 0
50E3  3A 63 31      LD A,(side_sel)  ; A = side_sel: use configured side for odd sectors

loc_50E6:
50E6  F5            PUSH AF  ; save head/side value
50E7  CD F2 4F      CALL block_to_chs  ; block_to_chs: convert block index to cylinder/head/sector
50EA  EB            EX DE,HL  ; DE <-> HL: move block_to_chs result into DE
50EB  57            LD D,A  ; D = A: cylinder byte
50EC  3A ED 4A      LD A,(drive_blk_a+0x2)  ; A = drive_blk_a+2: drive/geometry parameter
50EF  5F            LD E,A  ; E = that parameter
50F0  48            LD C,B  ; C = B: sector byte for descriptor
50F1  42            LD B,D  ; B = D = cylinder
50F2  DD 56 02      LD D,(IX+2)  ; D = format_desc+2 = sector-size code (N)
50F5  F1            POP AF  ; restore head/side into A
50F6  CD 1E 48      CALL dram_stack_fill  ; dram_stack_fill: write C/H/R/N descriptor to DRAM buffer
50F9  E1            POP HL  ; restore HL (sector number)
50FA  45            LD B,L  ; B = L: restore inner sector counter
50FB  10 D9         DJNZ loc_50D6  ; inner loop over sectors-per-track
50FD  C1            POP BC  ; restore outer counter
50FE  10 D2         DJNZ loc_50D2  ; outer loop over the 86 slots
5100  C9            RET  ; return with per-sector CHS/N descriptors laid out

; init format_desc geometry: copy 5 disk params from 0x4AFC, compute sectors-per-track and totals
init_format_geom:
5101  21 FC 4A      LD HL,drive_blk_a+0x11  ; HL = drive_blk_a+0x11 (0x4AFC): source disk params
5104  11 DD 52      LD DE,format_desc  ; DE = format_desc destination
5107  D5            PUSH DE  ; save DE
5108  DD E1         POP IX  ; IX = format_desc (via DE) for field access
510A  01 05 00      LD BC,0x0005  ; BC = 5: copy 5 geometry bytes
510D  ED B0         LDIR  ; LDIR: copy the 5 disk-parameter bytes into format_desc
510F  DD 5E 03      LD E,(IX+3)  ; E = format_desc+3: track/cyl count low
5112  DD 56 04      LD D,(IX+4)  ; D = format_desc+4: track/cyl count high
5115  21 04 00      LD HL,0x0004  ; HL = 4: track-overhead constant to add
5118  19            ADD HL,DE  ; HL = tracks + 4 (fudge/overhead sectors)
5119  DD 7E 02      LD A,(IX+2)  ; A = format_desc+2 = sector-size code
511C  0E 00         LD C,0x00  ; C = 0: clear multiplier high
511E  EB            EX DE,HL  ; DE = (tracks+4) multiplicand
511F  CD 05 4F      CALL mul16  ; mul16: (tracks+4) * size-code
5122  44            LD B,H  ; B = H: move product high into divisor high
5123  4D            LD C,L  ; C = L: product low
5124  21 00 80      LD HL,image_buf  ; HL = image_buf as 32-bit dividend base
5127  CD CE 4E      CALL div32_16  ; div32_16: total-bytes / product -> sectors-per-track
512A  DD 75 05      LD (IX+5),L  ; store sectors-per-track into format_desc+5
512D  DD 7E 02      LD A,(IX+2)  ; A = format_desc+2 = sector-size code
5130  0E 00         LD C,0x00  ; C = 0: clear multiplier high
5132  DD 56 04      LD D,(IX+4)  ; D = format_desc+4: track count high
5135  DD 5E 03      LD E,(IX+3)  ; E = format_desc+3: track count low
5138  CD 05 4F      CALL mul16  ; mul16: tracks * size-code = total sectors
513B  DD 75 09      LD (IX+9),L  ; store total low into format_desc+9
513E  DD 74 0A      LD (IX+10),H  ; store total high into format_desc+10
5141  DD 75 07      LD (IX+7),L  ; mirror total low into format_desc+7
5144  DD 74 08      LD (IX+8),H  ; mirror total high into format_desc+8
5147  DD 7E 02      LD A,(IX+2)  ; A = format_desc+2 = sector-size code
514A  CB 27         SLA A  ; A <<= 1
514C  CB 27         SLA A  ; A <<= 2 total: size-code * 4 = gap/bytes value
514E  DD 77 06      LD (IX+6),A  ; store into format_desc+6
5151  3E 0C         LD A,0x0C  ; A = 0x0C: ctrl_latch select for line6 (datarate) set
5153  DD CB 0B 66   BIT 4,(IX+11)  ; test format_desc+11 bit4: high vs low density flag
5157  20 01         JR NZ,loc_515A  ; if set, keep A (leave data bit clear)
5159  3C            INC A  ; A = 0x0D: set the datarate control bit instead

loc_515A:
515A  D3 9C         OUT (0x9C),A  ; ctrl_latch — drive the 0x9C addressable latch: set per-drive datarate
515C  C9            RET  ; return, geometry initialized

; checksum every loaded DRAM image bank: set image_present, LCD progress, loop banks via set_bank_checksum
checksum_all_banks:
515D  3E 01         LD A,0x01  ; A = 1: value for the image_present flag
515F  32 C8 52      LD (image_present),A  ; set image_present flag = 1 (image loaded)
5162  3A 34 31      LD A,(op_word)  ; A = op_word (current operation mode)
5165  E6 0F         AND 0x0F  ; isolate low nibble = operation code
5167  FE 07         CP 0x07  ; compare to 0x07
5169  28 21         JR Z,loc_518C  ; if op 7, skip the RAM-check banner
516B  CD 70 06      CALL lcd_clear_line2  ; clear LCD line 2 for the progress message
516E  CD 59 4C      CALL lcd_print  ; print the following inline string via lcd_print
5171  1B C0 52 41 4D 20 +  DB ESC(0xC0), "RAM checking - wait", 0  ; inline string: ESC 0xC0 (LCD line-2 addr), "RAM checking - wait", NUL
5187  3E FF         LD A,0xFF  ; A = 0xFF: checksum-in-progress marker value
5189  32 C7 52      LD (menu_scratch+0x5),A  ; menu_scratch+5 = 0xFF: mark checksum pass in progress

loc_518C:
518C  DD 21 DD 52   LD IX,format_desc  ; IX = format_desc geometry block
5190  DD 7E 0C      LD A,(IX+12)  ; A = format_desc+12: starting bank number - 1

loc_5193:
5193  3C            INC A  ; next bank: ++A
5194  FE FF         CP 0xFF  ; compare to 0xFF (past last image bank?)
5196  C8            RET Z  ; return when all banks checksummed
5197  CD 9C 51      CALL set_bank_checksum  ; checksum this DRAM image bank via set_bank_checksum
519A  18 F7         JR loc_5193  ; loop to next bank

; select DRAM bank A (OUT 0xB0), compute image_checksum, store two's-complement at 0xFFFF so bank sums to 0
set_bank_checksum:
519C  D3 B0         OUT (0xB0),A  ; dram_bank — OUT 0xB0: select DRAM image bank A
519E  47            LD B,A  ; B = A: save the bank number
519F  CD A9 51      CALL image_checksum  ; sum the whole 32 KB image via image_checksum
51A2  ED 44         NEG  ; A = -sum: two's-complement of the checksum
51A4  32 FF FF      LD (image_buf+0x7FFF),A  ; store at 0xFFFF so the bank's byte-sum becomes 0
51A7  78            LD A,B  ; A = B: restore bank number for caller
51A8  C9            RET  ; return

; checksum the whole DRAM image (sum 0x8000..0xFFFF)
image_checksum:
51A9  3E 00         LD A,0x00  ; A = 0: clear the running checksum accumulator
51AB  21 00 80      LD HL,image_buf  ; HL = image_buf (0x8000): start of the 32 KB image

loc_51AE:
51AE  86            ADD A,(HL)  ; checksum accumulate: add current image byte into A
51AF  2C            INC L  ; advance low byte of pointer through the 256-byte page
51B0  C2 AE 51      JP NZ,loc_51AE  ; keep summing until page wraps (L back to 0)
51B3  24            INC H  ; step to next 256-byte page
51B4  C2 AE 51      JP NZ,loc_51AE  ; loop over all pages until H wraps (whole 32KB bank done)
51B7  2B            DEC HL  ; back up to the final byte just past the range
51B8  96            SUB (HL)  ; subtract stored reference byte to fold it into the sum
51B9  C9            RET  ; return with A = computed bank checksum

; verify next DRAM bank checksum (bank counter 0x52C7): add image_checksum, expect 0; pulses panel busy + LCD
verify_ram_bank:
51BA  E5            PUSH HL  ; save HL across the verify routine
51BB  21 58 4A      LD HL,panel_shadow  ; point at panel LED/output shadow byte
51BE  7E            LD A,(HL)  ; load current panel shadow value
51BF  CB 9F         RES 3,A  ; clear busy bit (bit3) to pulse panel busy indicator off
51C1  D3 F0         OUT (0xF0),A  ; panel — write panel latch via bit-bang port F0
51C3  21 01 00      LD HL,0x0001  ; LCD position arg: row0 col1
51C6  CD 22 4C      CALL lcd_setpos  ; move LCD cursor to that position
51C9  CB DF         SET 3,A  ; re-assert busy bit (bit3) in A
51CB  D3 F0         OUT (0xF0),A  ; panel — write panel latch again to pulse busy back on
51CD  21 C7 52      LD HL,menu_scratch+0x5  ; point at bank counter (menu_scratch+5)
51D0  7E            LD A,(HL)  ; load current bank index
51D1  FE FF         CP 0xFF  ; check for uninitialized sentinel 0xFF
51D3  20 09         JR NZ,loc_51DE  ; if already initialized, skip seeding start bank
51D5  DD 21 DD 52   LD IX,format_desc  ; point IX at active format descriptor
51D9  DD 7E 0C      LD A,(IX+12)  ; read starting bank number (IX+12)
51DC  3C            INC A  ; pre-increment so first INC lands on start bank
51DD  77            LD (HL),A  ; store seeded bank counter

loc_51DE:
51DE  34            INC (HL)  ; advance to next DRAM bank to verify
51DF  D3 B0         OUT (0xB0),A  ; dram_bank — select that image bank in the DRAM window
51E1  CD A9 51      CALL image_checksum  ; compute checksum over the selected 32KB bank
51E4  86            ADD A,(HL)  ; add stored reference byte; expect result 0 if bank good
51E5  E1            POP HL  ; restore HL
51E6  C9            RET  ; return with Z set when bank checksum matches

; build FDC unit-select byte: index cfg table 0x5227 then OR option bits from format_desc IX+11; result stored to unit_sel by callers
fdc_build_unit_sel:
51E7  CD 0A 52      CALL media_cfg_index  ; get media-config table index from format flags
51EA  5F            LD E,A  ; use index as low byte of table offset
51EB  16 00         LD D,0x00  ; high byte zero (table within page)
51ED  21 27 52      LD HL,fdc_flag_tbl  ; base of FDC unit-select flag table
51F0  19            ADD HL,DE  ; point HL at the indexed flag entry
51F1  7E            LD A,(HL)  ; load base unit-select byte from table
51F2  DD CB 0B 66   BIT 4,(IX+11)  ; test format option bit4 (IX+11)
51F6  28 02         JR Z,loc_51FA  ; if clear, skip setting bit5
51F8  CB EF         SET 5,A  ; set bit5 of unit-select per option

loc_51FA:
51FA  DD CB 0B 6E   BIT 5,(IX+11)  ; test format option bit5 (IX+11)
51FE  28 02         JR Z,loc_5202  ; if clear, skip setting bit6
5200  CB F7         SET 6,A  ; set bit6 of unit-select per option

loc_5202:
5202  DD CB 0B 56   BIT 2,(IX+11)  ; test format option bit2 (IX+11)
5206  C8            RET Z  ; return early if that option is off
5207  CB FF         SET 7,A  ; set bit7 of unit-select per option
5209  C9            RET  ; return with assembled unit-select byte in A

; compute media-config table index from format_desc IX+11 density/side/option bits
media_cfg_index:
520A  AF            XOR A  ; clear A to build index bits from scratch
520B  DD 21 DD 52   LD IX,format_desc  ; point IX at active format descriptor
520F  DD CB 0B 5E   BIT 3,(IX+11)  ; test density/side flag bit3 (IX+11)
5213  28 02         JR Z,loc_5217  ; if clear, skip setting index bit2
5215  CB D7         SET 2,A  ; set index bit2

loc_5217:
5217  DD CB 0B 76   BIT 6,(IX+11)  ; test flag bit6 (IX+11)
521B  28 02         JR Z,loc_521F  ; if clear, skip setting index bit1
521D  CB CF         SET 1,A  ; set index bit1

loc_521F:
521F  DD CB 0B 7E   BIT 7,(IX+11)  ; test flag bit7 (IX+11)
5223  C8            RET Z  ; return if that bit clear (bit0 stays 0)
5224  CB C7         SET 0,A  ; set index bit0
5226  C9            RET  ; return with computed table index in A

fdc_flag_tbl:
5227  00 00 05 07 03 00 04 06                         |........|

; generic 4-key menu driver (HL=draw+action ptr lists); see docs
menu_run:
522F  06 00         LD B,0x00  ; init menu entry counter B to 0
5231  E5            PUSH HL  ; save start of draw/action pointer lists

loc_5232:
5232  7E            LD A,(HL)  ; read low byte of next list entry
5233  23            INC HL  ; advance pointer
5234  04            INC B  ; count this menu entry
5235  B6            OR (HL)  ; OR in high byte to test for null terminator
5236  23            INC HL  ; advance pointer
5237  20 F9         JR NZ,loc_5232  ; keep scanning until a null entry ends the list
5239  E5            PUSH HL  ; push list pointer to shuffle into index regs
523A  DD E1         POP IX  ; IX = action-list pointer
523C  FD E1         POP IY  ; IY = draw-list pointer
523E  DD 22 C2 52   LD (menu_scratch),IX  ; save IX (action base) to menu_scratch
5242  FD 22 C4 52   LD (menu_scratch+0x2),IY  ; save IY (draw base) to menu_scratch+2

loc_5246:
5246  0E 01         LD C,0x01  ; reset current selection index C to 1

loc_5248:
5248  21 56 52      LD HL,loc_5256  ; load return address loc_5256 for the draw callback
524B  E5            PUSH HL  ; push it so callback returns into the menu loop
524C  FD 6E 00      LD L,(IY+0)  ; fetch draw handler low byte from IY entry
524F  FD 66 01      LD H,(IY+1)  ; fetch draw handler high byte
5252  22 31 31      LD (phase_handler),HL  ; record current phase handler address
5255  E9            JP (HL)  ; jump into the draw/phase handler

loc_5256:
5256  CD 43 4D      CALL keypad_debounce  ; wait for a debounced keypad key
5259  FE 08         CP 0x08  ; compare against DOWN/next key 0x08
525B  20 19         JR NZ,loc_5276  ; if not next-key, check other keys
525D  DD 23         INC IX  ; advance action pointer to next entry
525F  DD 23         INC IX  ; (2 bytes per entry)
5261  FD 23         INC IY  ; advance draw pointer to next entry
5263  FD 23         INC IY  ; (2 bytes per entry)
5265  0C            INC C  ; bump selection index
5266  78            LD A,B  ; load entry count into A for comparison
5267  B9            CP C  ; compare selection index against entry count
5268  C2 48 52      JP NZ,loc_5248  ; if not past the last entry, redraw at new selection
526B  DD 2A C2 52   LD IX,(menu_scratch)  ; wrap: reload action base from menu_scratch
526F  FD 2A C4 52   LD IY,(menu_scratch+0x2)  ; reload draw base from menu_scratch+2
5273  C3 46 52      JP loc_5246  ; restart menu at first entry

loc_5276:
5276  FE 04         CP 0x04  ; compare key against UP/prev key 0x04
5278  20 1B         JR NZ,loc_5295  ; if not prev-key, check select/exit keys
527A  DD 2B         DEC IX  ; step action pointer back one entry
527C  DD 2B         DEC IX  ; (2 bytes per entry)
527E  FD 2B         DEC IY  ; step draw pointer back one entry
5280  FD 2B         DEC IY  ; (2 bytes per entry)
5282  0D            DEC C  ; decrement selection index
5283  20 C3         JR NZ,loc_5248  ; if not before first entry, redraw at new selection
5285  48            LD C,B  ; wrap up: C = entry count
5286  05            DEC B  ; B = count-1 as loop count to reach last entry

loc_5287:
5287  DD 23         INC IX  ; advance action pointer one entry
5289  DD 23         INC IX  ; (2 bytes per entry)
528B  FD 23         INC IY  ; advance draw pointer one entry
528D  FD 23         INC IY  ; (2 bytes per entry)
528F  10 F6         DJNZ loc_5287  ; loop to walk pointers to the last entry
5291  41            LD B,C  ; restore B = entry count
5292  0D            DEC C  ; C = last-entry index
5293  18 B3         JR loc_5248  ; redraw at wrapped last entry

loc_5295:
5295  FE 02         CP 0x02  ; compare key against EXIT/cancel key 0x02
5297  20 01         JR NZ,loc_529A  ; if not exit key, go invoke the selected entry's action handler
5299  C9            RET  ; exit menu (return to caller)

loc_529A:
529A  DD E5         PUSH IX  ; save action pointer across the selected handler
529C  FD E5         PUSH IY  ; save draw pointer
529E  C5            PUSH BC  ; save entry count and selection index
529F  2A C2 52      LD HL,(menu_scratch)  ; load saved action base
52A2  E5            PUSH HL  ; push it for restore after handler
52A3  2A C4 52      LD HL,(menu_scratch+0x2)  ; load saved draw base
52A6  E5            PUSH HL  ; push it for restore after handler
52A7  21 B2 52      LD HL,loc_52B2  ; push return address loc_52B2
52AA  E5            PUSH HL  ; fetch selected action handler low byte (IX)
52AB  DD 6E 00      LD L,(IX+0)  ; load handler pointer (low byte) from the IX dispatch record
52AE  DD 66 01      LD H,(IX+1)  ; fetch action handler high byte
52B1  E9            JP (HL)  ; invoke the selected menu action handler

loc_52B2:
52B2  E1            POP HL  ; handler returned: pop saved draw base
52B3  22 C4 52      LD (menu_scratch+0x2),HL  ; restore it to menu_scratch+2
52B6  E1            POP HL  ; pop saved action base
52B7  22 C2 52      LD (menu_scratch),HL  ; restore it to menu_scratch
52BA  C1            POP BC  ; restore entry count and selection index
52BB  FD E1         POP IY  ; restore draw pointer
52BD  DD E1         POP IX  ; restore action pointer
52BF  C3 48 52      JP loc_5248  ; resume menu loop redrawing current entry

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

; format_desc: 18-byte active-format + copy descriptor. Bytes 0-11 = disk geometry (init_format_geom copies 5 nominal params -> +0..+4, computes +5..+10); byte +11 = density/side/option flags (+ model-ID); bytes 12-17 = copy-engine bank/pointer scratch (src bank+ptr, dst bank+ptr). See the field map in the internals doc.
format_desc:
52DD  50 02 0F 00 02 04 3C 00 78 00 1E 00 00 00 00 00 |P.....<.x.......|
52ED  00 00                                           |..|
cksum_calc:
52EF  00                                              |.|
cksum_ref:
52F0  C7 AA 00 00 00 00 00 00 00 00 00 00 00 00 98 21 |...............!|

; === equates: banked DRAM window >= 0x8000 (no ROM home; refined later) ===
image_buf    = 0x8000
