#!/usr/bin/env python3
# Minimal-but-complete Z80 disassembler for firmware analysis.
# Emits readable labels for known functions/variables and annotates I/O ports,
# and handles the CALL 0x4C59 inline-string print convention (see render_string).
import sys, re, os

# Per-instruction inline comments live in a sibling data module so this file
# stays focused on disassembly logic. Address -> comment; rendered as a trailing
# "; ..." on the matching line (merged with any I/O-port annotation).
try:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from inline_comments import ILINE
except Exception:
    ILINE = {}

# Register/operand tables
r = ['B','C','D','E','H','L','(HL)','A']
rp = ['BC','DE','HL','SP']
rp2 = ['BC','DE','HL','AF']
cc = ['NZ','Z','NC','C','PO','PE','P','M']
alu = ['ADD A,','ADC A,','SUB ','SBC A,','AND ','XOR ','OR ','CP ']
rot = ['RLC','RRC','RL','RR','SLA','SRA','SLL','SRL']

def u8(b,i): return b[i]
def s8(b,i): return b[i]-256 if b[i]>127 else b[i]
def u16(b,i): return b[i] | (b[i+1]<<8)

class Ins:
    __slots__=('addr','length','text','target','kind','iobytes')
    def __init__(self,addr,length,text,target=None,kind=None):
        self.addr=addr; self.length=length; self.text=text; self.target=target; self.kind=kind

def disasm_one(b, pc):
    start=pc
    op=b[pc]; pc+=1
    idx=None  # index prefix reg name
    # handle DD/FD prefixes
    if op in (0xDD,0xFD):
        idx = 'IX' if op==0xDD else 'IY'
        op=b[pc]; pc+=1
        # replace (HL)->(idx+d), HL->idx, H/L->IXH/IXL rarely; handle common cases
        # fallthrough with idx set
    def disp(pc):
        d=s8(b,pc)
        return d
    target=None; kind=None
    text='?'
    if op==0xCB:
        sub=b[pc]; pc+=1
        # if idx, there is displacement first (already consumed order differs) - handle idx CB
        if idx:
            d=s8(b,pc-1); # actually for DDCB: DD CB d op
            # real layout: DD CB dd opcode ; sub we read is dd, need real op
            dd=sub
            realop=b[pc]; pc+=1
            x=realop>>6; y=(realop>>3)&7; z=realop&7
            mem='(%s%+d)'%(idx,dd)
            if x==0: text='%s %s'%(rot[y],mem)
            elif x==1: text='BIT %d,%s'%(y,mem)
            elif x==2: text='RES %d,%s'%(y,mem)
            else: text='SET %d,%s'%(y,mem)
        else:
            x=sub>>6; y=(sub>>3)&7; z=sub&7
            if x==0: text='%s %s'%(rot[y],r[z])
            elif x==1: text='BIT %d,%s'%(y,r[z])
            elif x==2: text='RES %d,%s'%(y,r[z])
            else: text='SET %d,%s'%(y,r[z])
        return Ins(start,pc-start,text,target,kind)
    if op==0xED:
        sub=b[pc]; pc+=1
        x=sub>>6; y=(sub>>3)&7; z=sub&7; p=y>>1; q=y&1
        if sub==0x44: text='NEG'
        elif sub==0x45: text='RETN'; kind='ret'
        elif sub==0x4D: text='RETI'; kind='ret'
        elif sub in (0x46,0x66): text='IM 0'
        elif sub in (0x56,0x76): text='IM 1'
        elif sub in (0x5E,0x7E): text='IM 2'
        elif sub==0x47: text='LD I,A'
        elif sub==0x4F: text='LD R,A'
        elif sub==0x57: text='LD A,I'
        elif sub==0x5F: text='LD A,R'
        elif sub==0x67: text='RRD'
        elif sub==0x6F: text='RLD'
        elif sub==0xA0: text='LDI'
        elif sub==0xA1: text='CPI'
        elif sub==0xA2: text='INI'
        elif sub==0xA3: text='OUTI'
        elif sub==0xA8: text='LDD'
        elif sub==0xA9: text='CPD'
        elif sub==0xAA: text='IND'
        elif sub==0xAB: text='OUTD'
        elif sub==0xB0: text='LDIR'
        elif sub==0xB1: text='CPIR'
        elif sub==0xB2: text='INIR'
        elif sub==0xB3: text='OTIR'
        elif sub==0xB8: text='LDDR'
        elif sub==0xB9: text='CPDR'
        elif sub==0xBA: text='INDR'
        elif sub==0xBB: text='OTDR'
        elif x==1 and z==0: text='IN %s,(C)'%(r[y] if y!=6 else 'F')
        elif x==1 and z==1: text='OUT (C),%s'%(r[y] if y!=6 else '0')
        elif x==1 and z==2 and q==0: text='SBC HL,%s'%rp[p]
        elif x==1 and z==2 and q==1: text='ADC HL,%s'%rp[p]
        elif x==1 and z==3 and q==0: nn=u16(b,pc); pc+=2; text='LD (0x%04X),%s'%(nn,rp[p]); target=nn; kind='data'
        elif x==1 and z==3 and q==1: nn=u16(b,pc); pc+=2; text='LD %s,(0x%04X)'%(rp[p],nn); target=nn; kind='data'
        else: text='ED %02X'%sub
        return Ins(start,pc-start,text,target,kind)
    # main
    x=op>>6; y=(op>>3)&7; z=op&7; p=y>>1; q=y&1
    HL = idx if idx else 'HL'
    def rname(i):
        if not idx: return r[i]
        if i==4: return idx+'H'
        if i==5: return idx+'L'
        if i==6:
            return None # (idx+d) handled specially
        return r[i]
    # We'll handle (HL) memory operand with displacement when idx set
    if x==0:
        if z==0:
            if y==0: text='NOP'
            elif y==1: text="EX AF,AF'"
            elif y==2: d=disp(pc); pc+=1; t=start+2+d; text='DJNZ 0x%04X'%t; target=t; kind='jr'
            elif y==3: d=disp(pc); pc+=1; t=start+2+d; text='JR 0x%04X'%t; target=t; kind='jr'
            else: d=disp(pc); pc+=1; t=start+2+d; text='JR %s,0x%04X'%(cc[y-4],t); target=t; kind='jr'
        elif z==1:
            if q==0: nn=u16(b,pc); pc+=2; text='LD %s,0x%04X'%(HL if p==2 else rp[p],nn)
            else: text='ADD %s,%s'%(HL,(HL if p==2 else rp[p]))
        elif z==2:
            if q==0:
                if p==0: text='LD (BC),A'
                elif p==1: text='LD (DE),A'
                elif p==2: nn=u16(b,pc); pc+=2; text='LD (0x%04X),%s'%(nn,HL); target=nn; kind='data'
                else: nn=u16(b,pc); pc+=2; text='LD (0x%04X),A'%nn; target=nn; kind='data'
            else:
                if p==0: text='LD A,(BC)'
                elif p==1: text='LD A,(DE)'
                elif p==2: nn=u16(b,pc); pc+=2; text='LD %s,(0x%04X)'%(HL,nn); target=nn; kind='data'
                else: nn=u16(b,pc); pc+=2; text='LD A,(0x%04X)'%nn; target=nn; kind='data'
        elif z==3:
            if q==0: text='INC %s'%(HL if p==2 else rp[p])
            else: text='DEC %s'%(HL if p==2 else rp[p])
        elif z==4:
            if idx and y==6: d=disp(pc); pc+=1; text='INC (%s%+d)'%(idx,d)
            else: text='INC %s'%(rname(y) or r[y])
        elif z==5:
            if idx and y==6: d=disp(pc); pc+=1; text='DEC (%s%+d)'%(idx,d)
            else: text='DEC %s'%(rname(y) or r[y])
        elif z==6:
            if idx and y==6:
                d=disp(pc); pc+=1; n=u8(b,pc); pc+=1; text='LD (%s%+d),0x%02X'%(idx,d,n)
            else:
                n=u8(b,pc); pc+=1; text='LD %s,0x%02X'%(rname(y) or r[y],n)
        else: # z==7
            t=['RLCA','RRCA','RLA','RRA','DAA','CPL','SCF','CCF'][y]; text=t
    elif x==1:
        if z==6 and y==6: text='HALT'; kind='halt'
        else:
            src=y; dst=z
            # LD r[y],r[z]
            if idx and (y==6 or z==6):
                d=disp(pc); pc+=1; mem='(%s%+d)'%(idx,d)
                sy = mem if y==6 else r[y]
                sz = mem if z==6 else r[z]
                text='LD %s,%s'%(sy,sz)
            else:
                text='LD %s,%s'%(r[y],r[z])
    elif x==2:
        if idx and z==6:
            d=disp(pc); pc+=1; text='%s(%s%+d)'%(alu[y],idx,d)
        else:
            text='%s%s'%(alu[y], rname(z) or r[z])
    else: # x==3
        if z==0: text='RET %s'%cc[y]; kind='cond'
        elif z==1:
            if q==0: text='POP %s'%(HL if p==2 else rp2[p])
            else:
                if p==0: text='RET'; kind='ret'
                elif p==1: text='EXX'
                elif p==2: text='JP (%s)'%HL; kind='ijump'
                else: text='LD SP,%s'%HL
        elif z==2: nn=u16(b,pc); pc+=2; text='JP %s,0x%04X'%(cc[y],nn); target=nn; kind='cjump'
        elif z==3:
            if y==0: nn=u16(b,pc); pc+=2; text='JP 0x%04X'%nn; target=nn; kind='jump'
            elif y==1: text='(CB prefix)'
            elif y==2: n=u8(b,pc); pc+=1; text='OUT (0x%02X),A'%n; kind='out'; target=n
            elif y==3: n=u8(b,pc); pc+=1; text='IN A,(0x%02X)'%n; kind='in'; target=n
            elif y==4: text='EX (SP),%s'%HL
            elif y==5: text='EX DE,HL'
            elif y==6: text='DI'
            else: text='EI'
        elif z==4: nn=u16(b,pc); pc+=2; text='CALL %s,0x%04X'%(cc[y],nn); target=nn; kind='ccall'
        elif z==5:
            if q==0: text='PUSH %s'%(HL if p==2 else rp2[p])
            else:
                if p==0: nn=u16(b,pc); pc+=2; text='CALL 0x%04X'%nn; target=nn; kind='call'
                else: text='(prefix)'
        elif z==6: n=u8(b,pc); pc+=1; text='%s0x%02X'%(alu[y],n)
        else: text='RST 0x%02X'%(y*8); target=y*8; kind='call'
    return Ins(start,pc-start,text,target,kind)

# Inline-string print routine: CALL 0x4C59 is immediately followed by an ASCII
# print-string terminated by the first 0x00 byte; code resumes right after it.
# Control bytes inside the string: 0x0C clear, 0x0D newline, 0x0A linefeed,
# 0x0B home, 0x1B ESC (consumes one following position/command byte so a 0x00
# argument is not mistaken for the terminator).
PRINT_ADDR = 0x4C59
_CTRL = {0x0C:'\\f', 0x0D:'\\r', 0x0A:'\\n', 0x0B:'\\v'}

# Inline strings that lack an early NUL and physically overlap real code
# (reached only via CALL): cap the rendered string at this many bytes so the
# overlapping subroutines disassemble normally right after it.
STRING_LEN = {
    0x0C10: 0x17,  # "BP not available>" default case overlaps read_both_sides @0x0C27
    0x27F9: 0x05,  # self-modified template "ESC,pos,char,char,NUL" (fields patched at runtime)
}

def render_string(b, pc, end):
    """Return (length_including_terminator, 'DB ...' text) for an inline string.
    If pc is in STRING_LEN exactly that many bytes are emitted as one blob, with
    interior 0x00 bytes rendered as data (not treated as the terminator)."""
    toks=[]; buf=[]; i=pc
    capped=pc in STRING_LEN
    cap=min(end, pc+STRING_LEN[pc]) if capped else end
    terminated=False
    def flush():
        if buf: toks.append('"'+''.join(buf)+'"'); buf.clear()
    while i<cap:
        c=b[i]; i+=1
        if c==0x00 and not capped: terminated=True; break
        if c==0x1B:                       # ESC + 1 raw arg byte
            flush()
            if i<cap: toks.append('ESC(0x%02X)'%b[i]); i+=1
            else: toks.append('ESC')
        elif c in _CTRL:
            flush(); toks.append(_CTRL[c])
        elif 0x20<=c<=0x7E:
            s=chr(c)
            buf.append('\\'+s if s in '"\\' else s)
        else:
            flush(); toks.append('\\x%02X'%c)
    flush()
    body=', '.join(toks) if toks else ''
    if terminated:
        text='DB '+(body+', ' if body else '')+'0'
    else:                                  # capped: no terminator byte
        text='DB '+body
    return i-pc, text

# ------------------------------------------------------------------ symbols
# Curated from the reverse-engineering analysis. Code entry points, key RAM
# variables, and I/O ports. Confidence varies; see the analysis docs.
SYMBOLS = {
    # --- boot / top level ---
    0x0100:'boot_init', 0x0105:'boot_checksum', 0x0161:'run_entry',
    # version-string pointer table (0x0040-0x0045) + its targets
    0x0040:'ptr_ver_firmware', 0x0042:'ptr_ver_loader', 0x0044:'ptr_ver_bootloader',
    0x0053:'ver_firmware', 0x4B8B:'ver_loader', 0x52CF:'ver_bootloader',
    0x0235:'wait_autoloader_loop', 0x024D:'al_connect_probe', 0x033D:'manual_mode',
    0x03B4:'dram_bank_cfg', 0x03DD:'dram_test', 0x0432:'fdd_detect',
    # --- duplication engine ---
    0x0788:'dup_engine_loop', 0x074F:'set_drive_cfg', 0x0757:'drive_cfg_latch',
    0x0709:'motor_ready_wait', 0x0834:'fdc_build_select', 0x0A00:'geom_seek_build',
    0x0E46:'verify_compare', 0x1090:'batch_loop_tail', 0x11B4:'read_source',
    0x1CE2:'format_track', 0x51A9:'image_checksum', 0x51E7:'fdc_build_unit_sel',
    0x520A:'media_cfg_index', 0x1444:'phase_handler_tbl', 0x3305:'fat12_template',
    # --- autoloader client ---
    0x10D2:'al_accept_reject', 0x11A8:'al_present_gate', 0x11FC:'al_insert',
    0x1198:'al_calibrate', 0x126D:'al_reject', 0x1286:'al_status_decode',
    0x13D9:'al_cmd_ack', 0x13FB:'al_cmd_status', 0x0670:'lcd_clear_line2',
    # --- host remote server ---
    0x1DF3:'host_read_packet', 0x1E0B:'host_dispatch', 0x1E37:'host_op_image_dl',
    0x1F9F:'host_op_enter_run', 0x1FC6:'host_op_disk_write', 0x204B:'host_op_ping',
    0x205C:'host_op_start', 0x206F:'host_op_load_exec', 0x2082:'host_op_diag_out',
    0x20E3:'host_op_begin_run', 0x2134:'bulk_read_bytes', 0x2141:'bulk_validate',
    0x216A:'bulk_read_byte', 0x2196:'bulk_sync_aa55', 0x21A9:'code_loader',
    # --- menus / config ---
    0x2267:'config_menu', 0x2735:'eeprom_transfer', 0x2766:'beep',
    0x1540:'hrd_menu', 0x1555:'special_formats_menu',
    0x2ACB:'eeprom_write', 0x2B3E:'eeprom_io',
    # --- HRD diagnostics + 8253 ---
    0x2BD1:'hrd_radial_a', 0x2E25:'hrd_hysteresis', 0x2E72:'hrd_spindle_rpm',
    0x3008:'hrd_find_burst', 0x3084:'hrd_median_filter', 0x30EB:'neg16',
    0x37DB:'index_period_timer',
    # --- FDC command engine ---
    0x39A0:'fdc_recalibrate', 0x3A18:'fdc_send_dma', 0x3BFB:'fdc_build_rw_cmd',
    0x3B04:'fdc_read_cmd', 0x3BF5:'fdc_write_cmd', 0x3CD3:'fdc_specify_dor',
    0x3E00:'fdc_seek_write_dma', 0x42DD:'fdc_seek', 0x457F:'fdc_write_bytes',
    0x45DB:'fdc_isr', 0x462D:'fdc_isr_sense_int', 0x46F1:'fdc_read_result',
    0x472D:'fdc_poll_complete', 0x4857:'timeout_check', 0x4893:'fdc_error_decode',
    0x499E:'fdc_sense_drive', 0x4FF2:'block_to_chs', 0x5043:'format_sector_map',
    0x0940:'fdc_datarate_precomp',
    # --- DMA (8237) ---
    0x43EC:'dma_arm_desc', 0x4401:'dma_arm_channel', 0x4457:'dma_setup',
    # --- LCD / front panel ---
    0x4C22:'lcd_setpos', 0x4C2A:'lcd_wait_busy', 0x4C43:'lcd_byte_out', 0x4C4A:'byte_out',
    0x4C59:'lcd_print', 0x05FC:'num_to_lcd', 0x4590:'key_decode',  # Next/Prev/Enter/Exit
    0x4D0B:'keypad_scan', 0x4D43:'keypad_debounce', 0x4D89:'get_key',
    0x4D8E:'get_key_dispatch', 0x49E3:'buzzer_beep', 0x4BF5:'error_report',
    0x522F:'menu_run',  # generic 4-key menu driver (HL=display+action ptr lists)
    # --- serial (SIO) + timer init ---
    0x4DD9:'timer_uart_init', 0x4E42:'uart_tx', 0x4E5A:'uart_rx', 0x4E91:'al_cmd_reset',
    0x4E99:'al_tx', 0x4EA1:'al_rx', 0x4E9D:'host_tx', 0x4EAD:'host_rx',
    0x4E53:'al_rx_ready', 0x4E4F:'host_rx_ready',
    # --- math ---
    0x4EB5:'bin2dec', 0x4ECE:'div32_16',
    # --- RAM variables ---
    0x311C:'cfg_flags', 0x311D:'cfg_byte', 0x311E:'drv_active_cfg', 0x3131:'phase_handler',
    0x3134:'op_word', 0x3137:'unit_sel', 0x3139:'track_ctr', 0x313B:'pass_ctr',
    0x313D:'run_count', 0x314C:'fmt_mode', 0x314D:'al_status1', 0x314E:'run_status',
    0x314F:'rd_submode', 0x3156:'track_bank_a', 0x3157:'track_bank_b', 0x3158:'track_off',
    0x3162:'al_present', 0x3164:'cyl_head', 0x3167:'hrd_desc_tbl', 0x319F:'rpm_residual',
    0x31A1:'hrd_hd0', 0x31A3:'hrd_hd1', 0x31A5:'hrd_test_idx',
    0x3269:'cycle_cnt_lo', 0x326B:'cycle_cnt_hi', 0x338A:'retry_ctr',
    0x4A85:'fdc0_result', 0x4A8C:'fdc1_result', 0x4A93:'fdc2_result', 0x4A9A:'fdc3_result',
    0x4AA1:'fdc_irq_bits', 0x4AEB:'fdc_block_a', 0x4B06:'fdc_block_b',
    0x52C8:'image_present', 0x52C9:'iovec_out', 0x52CB:'iovec_poll', 0x52CD:'iovec_beep',
    0x52DD:'format_desc', 0x52EF:'cksum_calc', 0x52F0:'cksum_ref',
    # --- phase_handler_tbl targets (0x1444-0x153F two-level dispatch) ---
    0x14AA:'submenu_a', 0x14B8:'submenu_b', 0x14CA:'submenu_c', 0x14E4:'submenu_d', 0x14EE:'submenu_e',
    0x156A:'menu_show_a', 0x1571:'menu_show_b', 0x1578:'menu_show_c', 0x157F:'menu_show_d', 0x1586:'menu_show_e',
    # menu_run tables (HL = draw list + action list, each NUL-terminated)
    0x1454:'spfmt_menu_a', 0x1472:'spfmt_menu_c', 0x1480:'spfmt_menu_d',
    0x148E:'spfmt_menu_b', 0x149C:'spfmt_menu_e',
    0x14FC:'ops_menu', 0x1522:'hrd_test_menu', 0x30F4:'config_fdd_menu',
    # config_fdd_menu items: draw = show current option, action = set bits at (cfg_ptr)
    0x298B:'show_ff_35',        0x2A5E:'set_ff_35',
    0x29A1:'show_ff_525',       0x2A67:'set_ff_525',
    0x29B8:'show_density_dd',   0x2A73:'set_density_dd',
    0x29CC:'show_density_hd',   0x2A7B:'set_density_hd',
    0x29DE:'show_mode_simul',   0x2A85:'set_mode_simul',
    0x29F5:'show_mode_normal',  0x2A8D:'set_mode_normal',
    0x2A1E:'show_spindle_normal',0x2A9F:'set_spindle_normal',
    0x2A06:'show_spindle_high', 0x2A95:'set_spindle_high',
    0x2A38:'show_spindle_double',0x2AA8:'set_spindle_double',
    0x311A:'cfg_ptr',           # pointer to the active config byte (set/reset by the action handlers)
    # disk-format select handlers (display the format descriptor)
    0x16B9:'fmt_35_720k', 0x16E7:'fmt_35_144m', 0x1715:'fmt_525_360k', 0x1743:'fmt_525_180k',
    0x1771:'fmt_525_320k', 0x179F:'fmt_525_160k', 0x17CD:'fmt_525_720k', 0x17FB:'fmt_525_12m',
    0x1829:'fmt_apply_dd', 0x1841:'fmt_apply_hd', 0x1859:'fmt_apply',
    # named models + copy modes
    0x190D:'sel_model_1', 0x1917:'sel_model_2', 0x1921:'sel_model_3', 0x1930:'show_insert_model',
    0x19D2:'show_read_source',
    0x1A25:'show_copy_fwv', 0x1A40:'show_copy_wv', 0x1A58:'show_copy_crc', 0x1A69:'show_copy_fv',
    0x1A82:'show_copy_wd', 0x1D97:'show_copy_bitverify', 0x1A94:'set_error_recovery',
    0x1AF6:'start_copy_fwv', 0x1CC8:'start_copy_wv', 0x1CCD:'start_copy_format',
    0x1CDB:'start_copy_fmtverify', 0x1D92:'start_copy_write', 0x1DAF:'start_copy_verify',
    0x1DB4:'show_clean_fdd', 0x1DC6:'abort_check', 0x25C1:'show_batch', 0x25D7:'start_batch',
    # HRD diagnostics tests (0x1540 hrd_menu, 0x2BD1 hrd_radial_a, 0x2E25/0x2E72 already named)
    0x2BDA:'hrd_radial_b', 0x2BE3:'hrd_radial_c', 0x2C35:'hrd_show_ecc', 0x2C47:'hrd_show_azimuth',
    0x2C59:'hrd_show_positioner', 0x2C76:'hrd_show_spindle',
    0x2CAC:'hrd_run_a', 0x2CB0:'hrd_run_b', 0x2CB4:'hrd_run_c', 0x2CBB:'hrd_run_d', 0x2CC1:'hrd_run_e',
}
# Special-format menu item series in phase_handler_tbl: 16 display + 16 apply handlers.
for _i,_a in enumerate(range(0x158D, 0x158D+5*16, 5)):
    SYMBOLS[_a] = 'spfmt_show_%02d' % (_i+1)
for _i,_a in enumerate([0x166B,0x1677,0x167C,0x1681,0x1686,0x168B,0x1690,0x1695,
                        0x1699,0x169D,0x16A1,0x16A5,0x16A9,0x16AD,0x16B1,0x16B5]):
    SYMBOLS[_a] = 'spfmt_apply_%02d' % (_i+1)

# --- top-down function analysis: names for all reachable functions (agents + trace) ---
SYMBOLS.update({0x3406:'fdc_format_build', 0x068D:'lcd_clear_line1',
    0x0022:'boot_cont', 0x21CE:'dl_code', 0x222D:'dl_boot_entry_a', 0x2236:'dl_boot_entry_b',
    0x0050:'show_model_cycles', 0x01BD:'show_fdd_seek_error', 0x01E1:'reset_seek_state', 0x02B0:'show_al_error',
    0x03A9:'lcd_home3', 0x03D7:'ctrl_latch_load', 0x047B:'fdc_cmd_both_drives', 0x0493:'edit_num_copies',
    0x04C3:'edit_num_field', 0x05E6:'acc32_add', 0x05FA:'num_to_lcd_alt', 0x063B:'show_ok_bad_count',
    0x06A8:'pit_adjust_digits', 0x06D9:'pit_reload_c12', 0x06E2:'fdc_step_to_track', 0x0725:'fdc_wait_unit1',
    0x072D:'seek_both_drives', 0x0760:'update_ctrl_latch', 0x0777:'range_table_lookup', 0x078B:'require_motor_ready',
    0x0811:'show_rpm_low', 0x0C27:'read_both_sides', 0x0C38:'write_both_sides', 0x0C49:'check_double_sided',
    0x0C57:'show_in_progress', 0x0E67:'show_compare_error', 0x0E8C:'wait_read_done', 0x10C8:'al_gate_or_reject',
    0x112D:'al_cmd_reject', 0x11A0:'is_op_mode9', 0x11AD:'al_insert_disk', 0x122B:'show_lost_data',
    0x13E5:'al_rx_response', 0x142B:'ascii_hex_to_nibble', 0x1433:'al_flush_rx', 0x1929:'clear_image_present',
    0x1956:'show_not_available', 0x1AED:'start_run_op', 0x1CA1:'jump_phase_handler', 0x1CA5:'check_cyl_limit',
    0x1CAC:'show_out_of_range', 0x1DCB:'show_abort', 0x1E01:'host_rx_word', 0x203E:'host_rx_echo',
    0x2161:'bulk_read_word', 0x2255:'show_curr_prefix', 0x231E:'config_err_recovery', 0x2369:'config_serialization',
    0x23BF:'config_copy_dir', 0x2409:'config_max_cyl', 0x2453:'show_max_cyl', 0x249E:'config_wprotect',
    0x24EC:'show_wprotect', 0x252C:'show_copy_dir', 0x2569:'show_err_recovery', 0x25A5:'show_serial_batch',
    0x2707:'drive_block_ptr', 0x2716:'drive_index_bits', 0x2725:'drive_block_pos', 0x276A:'hrd_head_edit',
    0x2770:'hrd_row_head1', 0x277C:'hrd_row_head0', 0x27E7:'hrd_fmt_num', 0x27F5:'hrd_emit_num',
    0x2800:'hrd_edit_head_pair', 0x281D:'hrd_edit_head_row', 0x28F4:'save_cfg_block', 0x28F8:'show_media_status',
    0x2946:'show_size_density', 0x2AD4:'eeprom_send_byte', 0x2AEF:'eeprom_clk_idle', 0x2AF5:'eeprom_clk_high',
    0x2B09:'i2c_scl_lo', 0x2B1D:'i2c_sda_hi', 0x2B2B:'i2c_sda_lo', 0x2B39:'i2c_start',
    0x2B4D:'i2c_ack', 0x2B55:'eeprom_read', 0x2B5E:'i2c_read_start', 0x2B66:'i2c_read_byte',
    0x2B83:'fdd_geom_index', 0x2BA5:'track_buf_ptr', 0x2BAB:'track_ptr_scale', 0x2BB7:'geom_sector_calc',
    0x2BEC:'show_radial_align', 0x2C04:'hrd_show_radial', 0x2C1E:'hrd_radial_ptr', 0x2CEE:'hrd_show_scaled',
    # per-test LCD display formatters (hrd_test_tbl handler field; print value + units)
    0x3025:'hrd_disp_radial', 0x3040:'hrd_disp_ecc', 0x304A:'hrd_disp_azimuth',
    0x3060:'hrd_disp_positioner',   # spindle handler is the shared show_rpm_suffix (0x307A)
    0x2D2C:'hrd_rec_ptr', 0x2D5B:'hrd_radial_measure', 0x2EBA:'hrd_seek_read', 0x2FC0:'hrd_read_verify',
    0x2FD4:'hrd_result_verify', 0x2FDC:'chk_fdc_crc', 0x2FF1:'fdc_set_xfer_cnt', 0x307A:'show_rpm_suffix',
    0x33B2:'fdc_op_dispatch', 0x370E:'panel_bit6_on', 0x371B:'clr_ctrl_bit6', 0x3723:'set_fdc_pending',
    0x372B:'clr_fdc_pending', 0x372F:'copy_fdc_params', 0x3751:'fdc_dma_from_blk', 0x3784:'fdc_home_head',
    0x37C6:'fdc_step_pulse', 0x394C:'fdc_recal_seek', 0x399E:'fdc_recal_wrap', 0x3A83:'fdc_read_dual',
    0x3AF6:'fdc_dma_read2', 0x3AFE:'fdc_read_dual2', 0x3B24:'fdc_write_poll', 0x3B2B:'fdc_write_dma',
    0x3B72:'fdc_write_dual', 0x3B78:'fdc_write_both', 0x3BE9:'fdc_wr_side0', 0x3BEE:'fdc_wr_side1',
    0x3C7F:'fdc_format_cmd2', 0x3C86:'fdc_format_cmd', 0x3D44:'fdc_seek_write_wrap',
    0x3D4B:'fdc_seek_dma', 0x3D95:'fdc_read_track', 0x3DB9:'fdc_read_dma_prep', 0x3E64:'fdc_dma_exec',
    0x3E6B:'fdc_dma_arm2', 0x3EEE:'fdc_write_both_wrap', 0x3EF4:'fdc_write_dma_both', 0x3F53:'fdc_read_src',
    0x3FAA:'fdc_src_dma', 0x40C3:'fdc_copy_track', 0x4117:'fdc_write_track', 0x4261:'dma_set_ptrs',
    0x427F:'fdc_read_src_b', 0x42A0:'fdc_op_poll_keys', 0x432A:'fdc_seek_sel', 0x433A:'fdc_send_seek',
    0x437A:'fdc_seek45_both', 0x4489:'fdc_dma_setup', 0x44D5:'fdc_set_steprate', 0x452C:'fdc_senseint_all',
    0x4571:'fdc_senseint_send', 0x4579:'fdc_result_read7', 0x4704:'fdc_poll_result', 0x481E:'dram_stack_fill',
    0x4848:'timeout_start', 0x4866:'store_rate_precomp', 0x486E:'panel_bus_on', 0x4883:'panel_sel_lo',
    0x488B:'panel_sel_hi', 0x48DB:'delay_djnz', 0x48DE:'read_timer_c1', 0x48EB:'fdc_set_cmdmode',
    0x4974:'fdc_drive_ready', 0x4981:'fdc_err_notready', 0x4990:'fdc_sense_ready', 0x49D2:'fdc_result_reset',
    0x49FC:'buzzer_pulse', 0x4A16:'buzzer_off', 0x4B99:'lcd_init', 0x4BE2:'io_mute_local',
    0x4BEC:'io_disable_poll', 0x4CD3:'lcd_scroll_up', 0x4D29:'keypad_row_read', 0x4D49:'keypad_wait',
    0x4D9B:'poll_host_remote', 0x4E8C:'uart_send_reset', 0x4E95:'host_cmd_reset', 0x4EB2:'bin2dec_clear',
    0x4ECB:'div_by_10', 0x4F05:'mul16', 0x4F1D:'clear_dec_buf', 0x4F2C:'lcd_print_number',
    0x4F3B:'lcd_dump_hex', 0x4F5C:'mon_hexrow', 0x4F5F:'mon_hexrow_b', 0x4F66:'mon_hex4',
    0x4F69:'mon_hex3', 0x4F6C:'mon_hex2', 0x4F6F:'mon_hex_space', 0x4F77:'mon_hex2b',
    0x4F7A:'mon_hexbyte', 0x4FAC:'mon_hexpair', 0x4FAF:'mon_hexnib', 0x4FC4:'lcd_line2_home',
    0x4FCB:'build_format_block', 0x507E:'build_interleave_tbl', 0x50AB:'sector_lba', 0x50CC:'layout_sectors',
    0x5101:'init_format_geom', 0x515D:'checksum_all_banks', 0x519C:'set_bank_checksum', 0x51BA:'verify_ram_bank',
})

PORTS = {
    # 8237A DMA controller (base 0x80): 4 channels of {addr,count}, then control regs
    0x80:'dma0_addr', 0x81:'dma0_cnt', 0x82:'dma1_addr', 0x83:'dma1_cnt',
    0x84:'dma2_addr', 0x85:'dma2_cnt', 0x86:'dma3_addr', 0x87:'dma3_cnt',
    0x88:'dma_cmd',     # W: command  / R: status
    0x89:'dma_req',     # W: software request
    0x8A:'dma_mask1',   # W: set/clear one channel mask bit
    0x8B:'dma_mode',    # W: mode (channel/transfer-type/mode)
    0x8C:'dma_clrff',   # W: clear byte-pointer flip-flop
    0x8D:'dma_mclr',    # W: master clear / R: temp register
    0x8E:'dma_clrmask', # W: clear all mask bits
    0x8F:'dma_wrmask',  # W: write all 4 mask bits at once
    0x9C:'ctrl_latch',
    0xA0:'pit_c0', 0xA4:'pit_c1', 0xA8:'pit_c2', 0xAC:'pit_ctrl',
    0xB0:'dram_bank', 0xB1:'fdc_reg', 0xC2:'fdc_precomp', 0xC3:'fdc_rate', 0xC6:'drive_sel_b',
    0xD0:'al_data', 0xD4:'al_stat', 0xD8:'host_data', 0xDC:'host_stat',
    0xE0:'lcd_cmd', 0xE8:'lcd_data', 0xF0:'panel', 0x90:'bulk_data', 0x94:'status_in', 0x98:'key_scan',
    0x40:'drv_lat0', 0x50:'drv_lat1', 0x60:'drv_lat2', 0x70:'drv_lat3',
}

# Regions that are DATA, not code — emitted as a labeled hex/ASCII dump and skipped.
# (start, end_exclusive, label). Add entries here as data blocks are identified.
DATA_REGIONS = [
    (0x0029, 0x0038, 'padding'),          # zero fill: boot stub .. RST38 vector
    (0x003B, 0x0040, 'padding'),          # zero fill: .. version pointer table
    (0x0046, 0x0050, 'padding'),          # zero fill: .. sign-on
    (0x0084, 0x0100, 'padding'),          # reserved zero fill: .. main entry (0x0100)
    (0x3305, 0x334E, 'fat12_template'),   # x86 FAT12 boot sector written to formatted disks
    (0x4B8B, 0x4B99, 'ver_loader'),      # 14-byte version field "STIBG11 950503"
    (0x311C, 0x3167, 'cfg_flags'),        # config/state variable block (0x311C-0x3166)
    (0x3167, 0x319F, 'hrd_desc_tbl'),     # precomp var + HRD 5-byte format-descriptor records @0x3186 (0x3167-0x319E)
    (0x319F, 0x31A3, 'rpm_residual'),     # HRD rpm/head vars (0x319F-0x31A2)
    (0x31A3, 0x31B9, 'hrd_hd1'),          # HRD head/test vars + parameter records (0x31A3-0x31B8)
    (0x31B9, 0x326E, 'param_tables'),     # data-rate / precomp / work tables (0x31B9-0x326D)
    (0x326E, 0x3305, 'fmt_param_tbl'),    # 8x 19-byte built-in disk-format BPB records (UNREFERENCED)
    (0x334E, 0x335F, 'fmt_buf1'),         # format work buffer (0x334E-0x335E)
    (0x3387, 0x33B2, 'fmt_buf2'),         # format work buffer (0x3387-0x33B1)
    # --- FDC driver RAM state, split into documented blocks (0x4A54-0x4B8A) ---
    (0x4A54, 0x4A58, 'fdc_saved_sp'),     # saved SP (word) for the LD SP,IX command loader; +2 reserved
    (0x4A58, 0x4A59, 'panel_shadow'),     # port-0xF0 output shadow (panel keys drive / buzzer bit3 / LEDs)
    (0x4A59, 0x4A61, 'fdc_drv_state'),    # driver state bytes: mode, scratch ptrs, misc flags
    (0x4A61, 0x4A85, 'fdc_cmd_buf'),      # 4x 9-byte FDC command buffers (byte0 = last opcode)
    (0x4A85, 0x4AA1, 'fdc_result_buf'),   # 4x 7-byte FDC result phase {ST0,ST1,ST2,C,H,R,N}
    (0x4AA1, 0x4AA6, 'fdc_result_save'),  # 4AA1 result-captured bits; 4AA2/4AA4 saved DE/HL
    (0x4AA6, 0x4AB4, 'sector_size_tbl'),  # 7 words: sector size 128<<N (128..8192), N*2 index
    (0x4AB4, 0x4ABC, 'fdc_gap_tbl'),      # 8-byte format -> gap/length byte table
    (0x4ABC, 0x4AE9, 'fdc_param_recs'),   # 9x 5-byte param records consumed by copy_fdc_params
    (0x4AE9, 0x4AEA, 'fdc_op_flags'),     # command build flags byte
    (0x4AEA, 0x4AEB, 'fdc_opcode_base'),  # READ/WRITE opcode base (|0x40 MFM)
    (0x4AEB, 0x4B06, 'drive_blk_a'),      # drive-pair block A (27B): DOR/motor, DMA addr/count, geom
    (0x4B06, 0x4B21, 'drive_blk_b'),      # drive-pair block B (27B)
    (0x4B21, 0x4B29, 'dma_ptr_save'),     # 4x word DMA address/count save
    (0x4B29, 0x4B89, 'fmt_geom_recs'),    # 4 'Special format' zone tables x 24B (head0/head1 recs of 6 {cyl,N/L/H} entries), read-only
    (0x4B89, 0x4B8A, 'fdc_rate_reg'),     # FDC data-rate register bits (OUT 0xB1)
    (0x4B8A, 0x4B8B, 'fdc_precomp_reg'),  # FDC write-precompensation value (OUT 0xC2)
    (0x224F, 0x2255, 'padding'),          # 6 bytes scratch/pad before show_curr_prefix
    (0x4DD5, 0x4DD9, 'padding'),          # zero pad before timer_uart_init
    (0x5227, 0x522F, 'fdc_flag_tbl'),     # 8-byte config->FDC command-flag lookup (used by fdc_build_unit_sel)
    (0x52C2, 0x52C9, 'menu_scratch'),     # menu_run saved IX/IY + image_present flag (0x52C2-0x52C8)
    (0x52CF, 0x52DD, 'ver_bootloader'),        # 14-byte version field "R6R1A   940329" (no NUL)
    (0x52DD, 0x5300, 'format_desc'),      # format descriptor + config defaults + checksums (0x52DD-0x52FF)
    (0x4FA9, 0x4FAC, 'mon_hexbuf'),       # 3-byte hex-print scratch (LD (0x4FA9),HL) before mon_hexpair
    # 13-byte binary payloads streamed inline by OTIR to the serial links
    # (jumped over by a preceding JR / reached only as an OTIR source).
    (0x209C, 0x20A9, 'host_ser_blob0'),   # OTIR -> host 0xDC (tag 'D'); host command 0x0E diag path
    (0x20D6, 0x20E3, 'host_ser_blob1'),   # OTIR -> host 0xDC (tag 'E')
    (0x4E28, 0x4E35, 'al_ser_blob'),      # OTIR -> autoloader 0xD4 (tag 'D'); link (re)init
    (0x4E35, 0x4E42, 'host_ser_blob2'),   # OTIR -> host 0xDC (tag 'E'); link (re)init
]

# Contiguous tables of 16-bit LE pointers — rendered as indexed "DW <target> ; [n]".
# (start, end_exclusive, label).
WORD_TABLES = [
    (0x1444, 0x1540, 'phase_handler_tbl'),  # 126 LE pointers (0x1444-0x153F): two-level dispatch
                                            # (main table -> menu_run tables of draw/action ptrs); code resumes at 0x1540
    (0x30F4, 0x311C, 'config_fdd_menu'),    # menu_run table: FDD config (form factor/density/mode/spindle)
]

def table_at(addr):
    for s,e,name in WORD_TABLES:
        if s <= addr < e: return (s,e,name)
    return None

# Addresses holding a 16-bit little-endian pointer — rendered as "DW <target>".
WORD_PTRS = {
    0x0040,   # -> 0x0054  version string "M6T9I2F 961002"
    0x0042,   # -> 0x4B8B  version string "STIBG11 950503"
    0x0044,   # -> 0x52CF  version string "R6R1A 940329"
    0x52C9,   # iovec_out   default -> 0x4C4A
    0x52CB,   # iovec_poll  default -> 0x4D8E
    0x52CD,   # iovec_beep  default -> 0x49E3 (buzzer_beep)
    0x4C53,   # lcd_print saved caller HL
    0x4C55,   # lcd_print saved caller BC
    0x4C57,   # lcd_byte_out saved caller HL
}

def region_at(addr):
    for s,e,name in DATA_REGIONS:
        if s <= addr < e: return (s,e,name)
    return None

# Data addresses whose table renders as fixed-size records (bytes per row).
RECORD_STRIDE = {
    0x3186: 5,   # hrd_test_tbl: 5 per-test records {scale K:word, handler addr:word, result mask:byte}
    0x4ABC: 5,   # fdc_param_recs: 5-byte records {b0, rate:word, b3, b4}
    0x4B29: 12,  # fmt_geom_recs: 12-byte records (indexed in 24-byte format pairs)
    # fmt_param_tbl: 8x 19-byte DOS BPB records, one per built-in disk format
    0x326E: 0x13, 0x3281: 0x13, 0x3294: 0x13, 0x32A7: 0x13,
    0x32BA: 0x13, 0x32CD: 0x13, 0x32E0: 0x13, 0x32F3: 0x13,
}

# Data addresses laid out as a sequence of variable-length rows (one row per
# group); after the listed groups are consumed any remainder falls back to 16.
RECORD_GROUPS = {
    0x3305: [11, 19, 43],  # fat12_template: jump+OEM 'Jumbo'(11), BPB/fs-type area(19), boot code+message(43)
}

# Inline annotation appended after a data-dump row that STARTS at the given
# address (decodes structured records that are otherwise opaque hex).
ROW_NOTES = {
    # hrd_test_tbl records: {scale K:word, display handler:word, result mask:byte}
    0x3186: 'radial      K=422  handler=hrd_disp_radial      mask=0x0F',
    0x318B: 'eccentric.  K=422  handler=hrd_disp_ecc         mask=0x03',
    0x3190: 'azimuth     K=696  handler=hrd_disp_azimuth     mask=0x0F',
    0x3195: 'positioner  K=422  handler=hrd_disp_positioner  mask=0x0F',
    0x319A: 'spindle     K=1    handler=show_rpm_suffix      mask=0x0F',
    # fmt_param_tbl records: packed 19-byte DOS BPB, one per built-in format
    0x326E: '720K 3.5" DD   1440 sec   9 spt  2h  F9  root 112  spc 2  spf 3',
    0x3281: '1.44M 3.5" HD  2880 sec  18 spt  2h  F0  root 224  spc 1  spf 9',
    0x3294: '720K variant   1440 sec   9 spt  2h  F9  root 144  spc 2  spf 3',
    0x32A7: '1.2M 5.25" HD  2400 sec  15 spt  2h  F9  root 224  spc 1  spf 7',
    0x32BA: '160K 5.25" SS  320 sec    8 spt  1h  FE  root  64  spc 1  spf 1',
    0x32CD: '180K 5.25" SS  360 sec    9 spt  1h  FC  root  64  spc 1  spf 2',
    0x32E0: '320K 5.25" DS  640 sec    8 spt  2h  FF  root 112  spc 2  spf 1',
    0x32F3: '360K 5.25" DS  720 sec    9 spt  2h  FD  root 112  spc 2  spf 2',
    # fmt_geom_recs: per-head zone table = 6 entries { cyl:lo-byte, rate flag:hi-byte 0/1/2=N/L/H }
    0x4B29: 'fmt0 head0  cyl/rate: 0/N  33/L  40/N  40/N  40/N  40/N',
    0x4B35: 'fmt0 head1  cyl/rate: 0/N  30/L  40/N  40/N  40/N  40/N',
    0x4B41: 'fmt1 head0  cyl/rate: 0/N  18/L  44/N  54/L  75/H  80/N',
    0x4B4D: 'fmt1 head1  cyl/rate: 0/N  18/L  39/H  44/L  67/H  80/N',
    0x4B59: 'fmt2 head0  cyl/rate: 0/N  80/N  80/N  80/N  80/N  80/N',
    0x4B65: 'fmt2 head1  cyl/rate: 0/N  80/N  80/N  80/N  80/N  80/N',
    0x4B71: 'fmt3 head0  cyl/rate: 0/N  55/L  71/H  80/N  80/N  80/N',
    0x4B7D: 'fmt3 head1  cyl/rate: 0/N  51/L  70/H  80/N  80/N  80/N',
}

def dump_data(b, start, end):
    """Hex+ASCII dump of a data region; emit a label at each named symbol and
    lay out rows per RECORD_GROUPS / RECORD_STRIDE (default 16) so record
    structure stays visible."""
    a = start
    while a < end:
        if a != start and a in SYMBOLS:
            if a in COMMENTS: print('; %s'%COMMENTS[a])
            print('%s:'%SYMBOLS[a])
        run_end = end                          # this run spans up to the next symbol
        for s in SYMBOLS:
            if a < s < run_end: run_end = s
        groups = list(RECORD_GROUPS.get(a, []))
        stride = RECORD_STRIDE.get(a, 16)
        x = a
        while x < run_end:
            n = groups.pop(0) if groups else stride
            row = b[x:min(x+n, run_end)]
            hexs = ' '.join('%02X'%y for y in row)
            asc  = ''.join(chr(y) if 0x20<=y<=0x7E else '.' for y in row)
            note = '   ; %s'%ROW_NOTES[x] if x in ROW_NOTES else ''
            print('%04X  %-47s |%s|%s'%(x, hexs, asc, note))
            x += len(row)
        a = run_end

_HEX4 = re.compile(r'0x([0-9A-Fa-f]{4})')
_PORT = re.compile(r'\(0x([0-9A-Fa-f]{2})\)')

def next_special(pc, end):
    """Smallest start address of any declared data/table/pointer region > pc."""
    cands=[a for a in WORD_PTRS if a>pc]
    cands+=[s for s,_,_ in DATA_REGIONS if s>pc]
    cands+=[s for s,_,_ in WORD_TABLES if s>pc]
    return min(cands) if cands else end

# Interior addresses that fall inside a named object (an inline string, etc.):
# rendered as "anchor_label+offset" so no bare interior label is needed.
OFFSET_REFS = {
    0x0054: 0x0053,   # version text -> ver_firmware+1 (skip the leading \f)
    0x0630: 0x062F, 0x0631: 0x062F,          # lcd_num_tmpl fields
    0x4F31: 0x4F2F, 0x4F37: 0x4F2F, 0x4F38: 0x4F2F,  # lcd_dec_tmpl fields
    0x27FA: 0x27F9, 0x27FB: 0x27F9, 0x27FC: 0x27F9,  # lcd_val_tmpl fields
}
# Self-relocated code windows: a runtime address executes from RAM/DRAM but is a
# byte-for-byte copy of ROM, so runtime R in [lo,hi) resolves to the inline ROM
# label at rom_lo+(R-lo) (exact name if one exists, else <anchor>+offset).
RELOC_WINDOWS = [
    (0x7800, 0x7900, 0x21CE),         # host opcode 0x0F copies ROM 0x21CE.. to 0x7800
]

# Map {addr: label} of every label actually emitted in the listing, built from a
# first rendering pass; used to resolve interior addresses as "label+offset".
EMITTED_MAP = {}
FALLBACK_LIMIT = 0x400   # max offset from the nearest label (excludes wild refs)

def _label_off(name, off):
    return name+('+0x%X'%off if off else '')

def resolve_addr(v, mem=False):
    """Return a label / 'label+offset' for operand v, or None to leave it hex.
    mem=True means v is a memory reference (nn) — definitely an address; mem=False
    is an immediate/branch operand, which may just be a constant."""
    if v in SYMBOLS: return SYMBOLS[v]
    if v in OFFSET_REFS:
        a=OFFSET_REFS[v]; return _label_off(SYMBOLS[a], v-a)
    for lo,hi,rom_lo in RELOC_WINDOWS:
        if lo<=v<hi:
            rom=rom_lo+(v-lo)
            if rom in SYMBOLS: return SYMBOLS[rom]        # exact ROM-source label
            if rom_lo in SYMBOLS: return _label_off(SYMBOLS[rom_lo], rom-rom_lo)
    if v>=0x8000 and 0x8000 in SYMBOLS:                    # banked DRAM window (>= 0x8000)
        off=v-0x8000
        # memory refs are certainly addresses; for immediates/branches, only the
        # low boot-sector area (< 0x200) and page-aligned quarter pointers are
        # addresses -- mid-range values (0xAA55, 0xD9B1) are constants.
        if mem or off<0x0200 or (v & 0x1FFF)==0:
            return _label_off(SYMBOLS[0x8000], off)
        return None
    # in-range interior of a labeled object: memory refs always; immediates only
    # when they point into a real (non-padding) data region -> clearly a pointer.
    if EMITTED_MAP:
        r=region_at(v)
        if mem or (r and r[2]!='padding'):
            base=max((a for a in EMITTED_MAP if a<=v), default=None)
            if base is not None and 0<=v-base<=FALLBACK_LIMIT:
                return _label_off(EMITTED_MAP[base], v-base)
    return None

_OPADDR = re.compile(r'(\()?0x([0-9A-Fa-f]{4})(\))?')

def apply_symbols(text):
    """Rewrite 16-bit operand addresses to labels/label+offset and append an
    I/O-port comment. A parenthesised operand (nn) is a memory reference (always
    an address); a bare operand is an immediate (only resolved when known)."""
    def rep(m):
        paren = bool(m.group(1)) and bool(m.group(3))
        r = resolve_addr(int(m.group(2),16), mem=paren)
        if r is None: return m.group(0)
        return '('+r+')' if paren else r
    text = _OPADDR.sub(rep, text)
    m = _PORT.search(text)
    if m:
        p = int(m.group(1),16)
        if p in PORTS: text = text + '  ; ' + PORTS[p]
    return text

def add_iline(addr, text):
    """Append the per-instruction inline comment for `addr`, if any. If the line
    already carries an I/O-port annotation ('  ; port'), the note is joined onto
    it with an em-dash so there is a single trailing comment."""
    note = ILINE.get(addr)
    if not note: return text
    return text + ' — ' + note if '  ; ' in text else text + '  ; ' + note

COMMENTS = {
    0x0100: 'main entry after RAM relocation: checksum RAM, init HW, size DRAM, pick operating mode',
    0x0105: 'sum bytes 0x0100..0x52EF; compare to cksum_ref; mismatch -> CODE TRANSFER ERROR loop',
    0x0161: 'run/duplication mode entry (also target of host 0x0B run vector install)',
    0x01BD: 'draw "FDD seek error", deselect drives, beep code 5, home LCD, then reset seek/format state',
    0x01E1: 'reset seek/format state after error: fmt_mode=0x90, clear flag at 0x3150',
    0x0235: "top idle loop: 'Wait for autoloader', poll autoloader + host serial commands",
    0x024D: 'probe autoloader (ping via R); classify NOT CONNECTED vs COMMUNICATION ERROR',
    0x02B0: 'draw "AL error / Status" line, wait keypress; preserves A across the message (autoloader fault)',
    0x033D: 'MANUAL operation mode top level',
    0x03A9: 'reset LCD cursor to home (0,0), repeated 3x (multi-line addressing workaround)',
    0x03B4: 'select DRAM image bank + latch drive config from cfg block',
    0x03D7: 'restore active DRAM bank (OUT 0x9C) from saved value',
    0x03DD: "size installed DRAM banks (walk via OUT 0xB0, test @0x8000) -> 'Test dram: N kB'",
    0x0432: 'detect FDDs, derive media-config index, install phase_handler from phase_handler_tbl',
    0x047B: 'issue FDC command A to both drives via fdc_op_dispatch; head-select byte from cyl_head bit7',
    0x0493: "'No. of copies' editor",
    0x04C3: 'edit a numeric field on the LCD (cursor on, +/- keys, Enter)',
    0x05E6: 'add 16-bit HL into the 32-bit accumulator at 0x3143/0x3145 (edit-field value builder)',
    0x05FA: 'num_to_lcd variant with extra attribute bit (0xC0) selecting alternate LCD line/position',
    0x05FC: 'render 16-bit value as right-justified decimal on LCD at position A, field width B, pad char C',
    0x063B: 'show run counters on line 2: track_ctr and pass_ctr as two 4-digit decimals (OK/bad tally)',
    0x0670: 'blank LCD line 2 (ESC 0xC0 home + 20 spaces), preserving AF',
    0x068D: 'blank LCD line 1 (ESC 0x80 home + 20 spaces)',
    0x06A8: 'inc/dec an ASCII digit pair (config value at 0x27FC) per cfg_flags bit7 up/down, 0-9 wrap+carry',
    0x06D9: 'reload 8253 counters c1/c2 (control words 0x50,0x90) to restart index timing',
    0x06E2: 'step drive toward target track A, tracking current track at 0x3133, issuing seeks until reached',
    0x0709: 'spin-up/ready wait: recalibrate+seek both drives, retry up to 5x; returns Z when ready',
    0x0725: 'poll FDC unit-1 seek/op completion, looping until done',
    0x072D: 'recalibrate+seek unit1 (and unit2 if double-sided), then flag not-ready error',
    0x074F: 'load drv_active_cfg (0x2D active pattern) into both drive-config latches (ports 0x40/0x60); idle pattern is 0x0E',
    0x0757: 'write 0x0E to both drive latches (0x40/0x60): deselect / motors-off idle state',
    0x0760: 'datarate ctrl-latch helper: set/clear bit2 of (HL), OUT to port C, mirror bit0 into ctrl_latch 0x9C',
    0x0777: 'threshold table lookup: scan B entries at HL, return value C for the band matching input (rate/precomp by cyl)',
    0x0788: 'duplication engine main loop: spin-up, read source, run current phase',
    0x078B: 'ensure motor ready via motor_ready_wait; on failure jump to batch error tail 0x10B0',
    0x0811: 'RPM out-of-range warning: A=1 draws "rpm low", A=2 "rpm high", 0 shows nothing',
    0x0834: 'build FDC drive/head select byte from unit_sel/cyl_head',
    0x0940: 'program FDC data rate & write-precomp from geometry via range tables; OUT fdc_reg/precomp/rate',
    0x0A00: 'geometry: logical block -> CHS via block_to_chs, store into both drive blocks',
    0x0C27: 'process both disk sides for read: single-sided reads side1 only, else side1 then side2',
    0x0C38: 'process both sides for source read into buffer: single reads side1, else both sides',
    0x0C49: 'determine if current format is double-sided (0x3135 nonzero, or cyl_head code 4/0x0E)',
    0x0C57: 'draw "in progress" on line 2 (operation running indicator)',
    0x0E46: 'verify: DMA read-back track into 0x5800 scratch, CPI-compare vs DRAM image',
    0x0E67: 'draw "Compare error", beep code 5, set op_word bit6 (verify-mismatch flag)',
    0x0E8C: 'wait for FDC read/verify done on unit1 (and unit2 if double-sided); set op_word bits 6/5 on fail',
    0x1090: 'end-of-pass tail: dec run_count, on last pass autoloader-accept, deselect, show OK/bad, wait key',
    0x10C8: 'if autoloader present route to accept/reject flow, else beep once (buzzer_pulse) and return A=0',
    0x10D2: 'autoloader ACCEPT (mode9): show "ACCEPT", eject good disk, retry build_select+verify up to 20x',
    0x112D: 'autoloader REJECT: show "REJECT", send reject cmd 0x52, await ack with "timeout" handling',
    0x1198: 'send autoloader calibrate command (0x43) with ack; sets carry (error-exit tail)',
    0x11A0: 'test whether op_word low nibble == 9 (autoloader run mode); returns Z if so',
    0x11A8: 'gate on autoloader-present flag (al_present); returns Z if no autoloader attached',
    0x11AD: 'enter insert/read-source flow with retry_ctr preset to 1 (single-shot insert)',
    0x11B4: 'read source disk (autoloader-aware): command INSERT, spin up, verify bank, retry on rpm-low/lost-data',
    0x11FC: 'send autoloader insert command (0x49), wait ready; "timeout" message on no response',
    0x122B: 'fatal image-lost error: hex-dump 0x52C7, draw "Lost data", then halt (spin forever)',
    0x126D: 'send autoloader reject(0x52)+calibrate(0x43) with ack; on ok re-insert per retry_ctr',
    0x1286: 'decode autoloader status byte -> on-screen message (bit1 seated, hi-nibble class)',
    0x13D9: "send 1-char autoloader command in B, read reply; 'X'=ok/1=timeout/2=other",
    0x13E5: "receive one autoloader response byte into fmt_mode; return 0 if 'X' ack, else error code 1/2",
    0x13FB: 'autoloader S(tatus): read 2 ASCII-hex chars, decode to status byte',
    0x142B: 'convert one ASCII hex character in A to its 0-15 nibble value',
    0x1433: 'drain 3 stale bytes from autoloader SIO RX (0xD0) and reset its status',
    0x1540: 'print "HRD diagnostics" menu title',
    0x1555: 'print "Special formats" menu title',
    0x156A: 'run special-format submenu A (spfmt_menu_a) via menu_run',
    0x1571: 'run special-format submenu B (spfmt_menu_b) via menu_run',
    0x1578: 'run special-format submenu C (spfmt_menu_c) via menu_run',
    0x157F: 'run special-format submenu D (spfmt_menu_d) via menu_run',
    0x1586: 'run special-format submenu E (spfmt_menu_e) via menu_run',
    0x158D: 'display "Special format No. 1" screen (selects number string, stores cyl_head to 0x3165)',
    0x1592: 'display "Special format No. 2" screen (shared No.-N display code)',
    0x1597: 'display "Special format No. 3" screen (shared No.-N display code)',
    0x159C: 'display "Special format No. 4" screen (shared No.-N display code)',
    0x15A1: 'display "Special format No. 5" screen (shared No.-N display code)',
    0x15A6: 'display "Special format No. 6" screen (shared No.-N display code)',
    0x15AB: 'display "Special format No. 7" screen (shared No.-N display code)',
    0x15B0: "draw 'Special format No. 8' menu title, latch cyl_head into 0x3165 (slot 8 of 8-16 chain)",
    0x15B5: "draw 'Special format No. 9' menu title, latch cyl_head into 0x3165",
    0x15BA: "draw 'Special format No.10' menu title, latch cyl_head into 0x3165",
    0x15BF: "draw 'Special format No.11' menu title, latch cyl_head into 0x3165",
    0x15C4: "draw 'Special format No.12' menu title, latch cyl_head into 0x3165",
    0x15C9: "draw 'Special format No.13' menu title, latch cyl_head into 0x3165",
    0x15CE: "draw 'Special format No.14' menu title, latch cyl_head into 0x3165",
    0x15D3: "draw 'Special format No.15' menu title, latch cyl_head into 0x3165",
    0x15D8: "draw 'Special format No.16' menu title, latch cyl_head into 0x3165",
    0x166B: 'apply special-format slot 1 as DD: cyl_head=1, clear density bit, run fmt_apply',
    0x1677: 'apply special-format slot 2 as DD: cyl_head=2, clear density bit, run fmt_apply',
    0x167C: 'apply special-format slot 3 as DD: cyl_head=3, clear density bit, run fmt_apply',
    0x1681: 'apply special-format slot 4 as HD: cyl_head=4, set density bit, run fmt_apply',
    0x1686: 'apply special-format slot 5 as HD: cyl_head=5, set density bit, run fmt_apply',
    0x168B: 'apply special-format slot 6 as HD: cyl_head=6, set density bit, run fmt_apply',
    0x1690: 'apply special-format slot 7 as HD: cyl_head=7, set density bit, run fmt_apply',
    0x1695: 'apply special-format slot 8: set cyl_head=8, run fmt_apply core (no density change)',
    0x1699: 'apply special-format slot 9: set cyl_head=9, run fmt_apply core (no density change)',
    0x169D: 'apply special-format slot 10: set cyl_head=10, run fmt_apply core',
    0x16A1: 'apply special-format slot 11: set cyl_head=11, run fmt_apply core',
    0x16A5: 'apply special-format slot 12: set cyl_head=12, run fmt_apply core',
    0x16A9: 'apply special-format slot 13: set cyl_head=13, run fmt_apply core',
    0x16AD: 'apply special-format slot 14: set cyl_head=14, run fmt_apply core',
    0x16B1: 'apply special-format slot 15: set cyl_head=15, run fmt_apply core',
    0x16B5: 'apply special-format slot 16: set cyl_head=16, run fmt_apply core',
    0x16B9: 'print media spec line \'3.5" 720kB 9sec 80cyl 2h\' for the format-select menu',
    0x16E7: 'print media spec line \'3.5" 1.44MB 18sec 80cyl 2h\' for the format-select menu',
    0x1715: 'print media spec line \'5.25" 360kB 9sec 40cyl 2h\'',
    0x1743: 'print media spec line \'5.25" 180kB 9sec 40cyl 1h\'',
    0x1771: 'print media spec line \'5.25" 320kB 8sec 40cyl 2h\'',
    0x179F: 'print media spec line \'5.25" 160kB 8sec 40cyl 1h\'',
    0x17CD: 'print media spec line \'5.25" 720kB 9sec 80cyl 2h\'',
    0x17FB: 'print media spec line \'5.25" 1.2MB 15sec 80cyl 2h\'',
    0x1829: 'enter fmt_apply selecting DD density: cyl_head=0, clear format_desc[11] bit7, sync image flag',
    0x1841: 'enter fmt_apply selecting HD density: cyl_head=0, set format_desc[11] bit7, sync image flag',
    0x1859: 'format-apply core: program both FDCs, build format block + sector layout, warn on non-std max cyl, run ops_menu',
    0x190D: 'pick drive model 1 (unit_sel low bits=01) then run fmt_apply',
    0x1917: 'pick drive model 2 (unit_sel low bits=10) then run fmt_apply',
    0x1921: 'pick drive model 0/3 (clear unit_sel low bits) then run fmt_apply',
    0x1929: 'invalidate cached RAM disk image by zeroing image_present (AF preserved)',
    0x1930: "draw 'Insert model' prompt; decode model-ID sense (0x52E8) to 528/526/325-400 handler else Not available",
    0x1956: "draw 'Not available' on LCD line 2 and home cursor",
    0x19D2: "draw 'Read source disk'; show 'data image present' or 'insert source disk' per image_present",
    0x1A25: "print 'Format Write Verify' copy-mode menu label",
    0x1A40: "print 'Write and verify' copy-mode menu label",
    0x1A58: "print 'CRC check' copy-mode menu label",
    0x1A69: "print 'Format and verify' copy-mode menu label",
    0x1A82: "print 'Write disk' copy-mode menu label",
    0x1A94: 'force error-recovery mode (0x314A=3), run duplication then image-compare pass, restore, set image_present on success',
    0x1AED: 'set op_word=A and run_count=HL, then enter dup_engine_loop to run the duplication op',
    0x1AF6: "start Format-Write-Verify copy (op_word=1); if no image show 'data image missing', else prompt copy count and run",
    0x1CA1: 'indirect jump through phase_handler vector to the current duplication-phase routine',
    0x1CA5: 'test requested cyl in HL against max-cyl 0x3143; returns in-range via M flag (no carry if OK)',
    0x1CAC: "draw 'Out of range' on LCD line 2, home cursor, set carry to reject the value",
    0x1CC8: 'start Write-and-Verify copy (op_word=2) via the shared start_copy_fwv path',
    0x1CCD: 'start Format-only copy (op_word=3), jump to copy-count prompt and run',
    0x1CDB: 'FORMAT: if cyl_head!=0 skip; else build blank FAT12 image in DRAM bank 0xFE from ROM template, stamp 0x55AA, zero-fill+FAT-init every track',
    0x1CE2: 'FORMAT: build FAT12 boot sector from ROM template, stamp 0x55AA, format tracks',
    0x1D92: "start a 'Copy: write' run (start_run_op with mode 6)",
    0x1D97: "draw the 'Bit per bit verify' status line",
    0x1DAF: "start a 'Copy: verify' run (start_run_op with mode 8)",
    0x1DB4: "draw the 'Cleaning FDD' status line",
    0x1DC6: 'if autoloader disk present launch run op 9, else fall through to show_abort prompt',
    0x1DCB: "show 'Abort' on line2, beep once, reset LCD cursor; returns fmt_mode",
    0x1DF3: 'read 4-byte host command packet (opcode in D)',
    0x1E01: 'read a little-endian 16-bit word from host SIO into E,D (abort on rx error)',
    0x1E0B: 'host remote-control server dispatcher (opcode table)',
    0x1E37: 'host op 0x0A: download disk image over bulk channel - AA55 sync, validate geometry header, stream tracks into DRAM banks, verify checksum, set image_present',
    0x1F9F: 'host op 0x0B: enter interactive run mode - install iovec callbacks (key/out/annun) and JP run_entry',
    0x1FC6: 'host op 0x0D: receive format params from host (each byte echoed via host_rx_echo) - cfg_flags+unit -> unit_sel; write-protect byte -> OUT 0x9C (line 2) + wprot_mode @0x200B; err_recovery byte; then a 24-byte per-head zone table -> hrd_hd0 (remote variable-rate Special format). Programs FDC + builds format block',
    0x203E: 'receive one byte from host and echo it back as ack (returns byte in B, NZ on error)',
    0x204B: 'host op 0x0C: ping - ack with 0x58 then 0x00',
    0x205C: 'host op 0x09: clear op_word, ack, run abort_check gate then execute run',
    0x206F: 'host op 0x0F: ack then code_loader (download+execute code image), loop dispatch',
    0x2082: 'host op 0x0E: diagnostic bridge - relay bytes between host (port DC) and autoloader SIO',
    0x20E3: "start a duplication/blank-check run - ack, show 'FDD', clear fmt_mode; op 0x07 sets up blank-pass ('BP')",
    0x2134: 'read B*2 bytes from the bulk-image channel into (HL++)',
    0x2141: 'compare received image geometry header (0x334F+1/+2) with stored (0x3133/0x3135); update and return NZ if changed',
    0x2161: 'read a little-endian 16-bit word from the bulk-image channel into DE',
    0x216A: 'read one byte from host bulk-image channel (0x90/0x94/0x9C handshake)',
    0x2196: 'wait for 0xAA 0x55 sync word on the bulk-image channel',
    0x21A9: 'code loader: copy 256-byte bootstrap to 0x7800, verify image to 0x8000, JP',
    0x2255: "clear line2 and draw the '(curr.= ' prefix for a config current-value readout",
    0x2267: 'CONFIG menu top level',
    0x231E: 'config menu item: toggle data-error-recovery (0x314A=1 enable / 3 disable) via ENTER/EXIT prompt',
    0x2369: 'config menu item: toggle serialization (hrd_desc_tbl bit1 & cfg_byte bit1) via ENTER/EXIT prompt',
    0x23BF: 'config menu item: toggle copy direction (cfg_flags bit7: in->out / out->in)',
    0x2409: 'config menu item: edit maximal cylinder - edit_num_field, clamp to 0x55, store in cfg_flags preserving bit7',
    0x2453: "render 'Maximal cylinder' header + current value from 0x4AFC/cfg_flags",
    0x249E: 'config menu item: toggle write-protect recognition (ctrl_latch bit0 / 0x3155)',
    0x24EC: "render 'Write protect (curr.= recognize/unrecognize)' from key_scan bit2",
    0x252C: "render 'Copy direction (curr.= in->out/out->in)' from cfg_flags bit7",
    0x2569: "render 'Data error recovery (curr.= enable/disable)' from 0x314A",
    0x25A5: "render 'Serialization (curr.= enable/disable)' from hrd_desc_tbl bit1",
    0x25C1: "draw the 'Batch processing' menu header",
    0x25D7: "batch-processing entry: gate on autoloader-present, else show 'not available'",
    0x2707: "compute pointer to a drive's 0x18-byte record in the table at 0x4B29 (index from unit-select bits)",
    0x2716: 'map unit-select byte bits7,3 to a 0..3 drive index in E',
    0x2725: "compute a drive's record offset (0x18*index + 4), returns low byte in C",
    0x2735: 'bidirectional CAT24C02 EEPROM block transfer (NOT save-only). A=direction (0=load EEPROM->RAM, else save RAM->EEPROM); HL=RAM buffer; B=byte count; C=EEPROM word address. Save = one I2C byte-write per byte (INC addr, honours write cycle); load = single sequential read (ACK..NAK+stop). Map: 0x00 config block (cfg_flags/cfg_byte/drv_active_cfg/cfg_batch), 0x04+ Special-format zone tables (24B/slot), 0xFC 32-bit lifetime cycle counter (shown by show_model_cycles)',
    0x2766: 'beep via the iovec_beep vector (default buzzer_beep); beep count encodes the alert/error code',
    0x276A: 'BC-preserving wrapper to edit the two-head data-rate zone table (per head: 6 entries { start cyl : low byte, data-rate : high byte 0/1/2 = N/L/H }; consumed by range_table_lookup @0x092A -> fdc_rate_a/b)',
    0x2770: "render head-1 row of the head parameter table (sets prefix '1', buffer 0x31AF)",
    0x277C: "render head-0 row: print 'H C-0' grid, then the zone entries - low byte of each word = value (hrd_fmt_num), high byte = N/L/H rate flag",
    0x27E7: 'convert a byte to decimal (bin2dec_clear) and patch the digits into the head-table print buffer',
    0x27F5: 'print a formatted head-table number cell (BC-preserving lcd_print of patched inline bytes)',
    0x2800: 'render both head rows (0 and 1) of the head parameter table with framing escapes',
    0x281D: 'render one head row (0 or 1) computing per-column LCD cursor positions',
    0x28F4: 'persist the 2-byte cfg_flags block to serial EEPROM (eeprom_transfer write mode)',
    0x28F8: 'render media summary from cfg_byte: size, density, S/N and HS/NS/DS; self-patches LCD cursor',
    0x2946: 'print size+density portion of media summary (5.25"/3.5", HD/DD/QD) from cfg_byte bits3,7,6',
    0x298B: 'draw \'Form factor 3.5"\' menu header',
    0x29A1: 'draw \'Form factor 5.25"\' menu header',
    0x29B8: "draw 'Double density' menu header",
    0x29CC: "draw 'High density' menu header",
    0x29DE: "draw 'Simultaneous mode' menu header",
    0x29F5: "draw 'Normal mode' menu header",
    0x2A06: "draw 'High spindle speed' menu header",
    0x2A1E: "draw 'Normal spindle speed' menu header",
    0x2A38: "draw 'Double spindle speed' menu header",
    0x2A5E: 'set config form factor to 3.5" (cfg_ptr: RES bit3, SET bit6, clear bit1)',
    0x2A67: 'media-config toggle: select 5.25" form-factor (cfg flags SET3/RES6/RES1), then refresh LCD',
    0x2A73: 'media-config toggle: select DD/double density (cfg flags RES7), then refresh LCD',
    0x2A7B: 'media-config toggle: select HD/high density (cfg flags SET7/SET6), then refresh LCD',
    0x2A85: 'media-config toggle: enable simultaneous copy mode (cfg flags SET4), refresh LCD',
    0x2A8D: 'media-config toggle: select normal copy mode (cfg flags RES4), refresh LCD',
    0x2A95: 'media-config toggle: high spindle speed (cfg flags RES2/SET5), refresh LCD',
    0x2A9F: 'media-config toggle: normal spindle speed (cfg flags RES2/RES5), refresh LCD',
    0x2AA8: 'media-config toggle: double spindle speed (cfg flags SET2/RES5), refresh LCD',
    0x2ACB: 'bit-bang serial EEPROM: I2C start, control 0xA0 (write), then clock data byte E out MSB-first',
    0x2AD4: 'bit-bang one byte to the serial config EEPROM',
    0x2AEF: 'return bit-banged I2C bus to idle: SCL low, SDA released high, then pulse SCL high w/ settle',
    0x2AF5: 'drive I2C SCL high on panel latch (bit5 of 0x4A58/port F0) with a short settle delay',
    0x2B09: 'drive I2C SCL low (clear bit5 of panel latch 0x4A58, OUT port F0)',
    0x2B1D: 'release I2C SDA high (set bit4 of panel latch 0x4A58, OUT port F0)',
    0x2B2B: 'pull I2C SDA low (clear bit4 of panel latch 0x4A58, OUT port F0)',
    0x2B39: 'I2C start condition (config EEPROM)',
    0x2B3E: 'finish an EEPROM byte transfer: emit ACK clock, release SDA, then delay',
    0x2B4D: 'generate I2C ACK bit: SCL low, SDA low, then pulse SCL high',
    0x2B55: 'EEPROM random read: send word address via eeprom_write, then repeated-start read (0xA1)',
    0x2B5E: 'issue I2C (re)start and send control byte 0xA1 to address EEPROM for reading',
    0x2B66: 'read one byte from the I2C config EEPROM',
    0x2B83: 'map media/geometry config to a drive-geom table index; for cfg==4 add unit 0-3, else code 7/6/3',
    0x2BA5: 'compute track-image buffer pointer: derive head via block_to_chs, then scale by track size',
    0x2BAB: "advance HL by (A-1)*track_size (0x52E0) to reach a track's image slot; returns head in A",
    0x2BB7: 'from the BPB record (IX = installed boot-sector BPB, not format_desc): IX+13/+15 give sectors-per-track/interleave, div32_16 -> sector index',
    0x2BD1: 'HRD radial-alignment test (head variant a)',
    0x2BDA: 'HRD radial-alignment diag: show header, then display drive-B radial reading (index 1)',
    0x2BE3: 'HRD radial-alignment diag: show header, then display radial reading index 2',
    0x2BEC: 'print the radial-alignment test header line on the LCD',
    0x2C04: 'read radial measurement byte (via hrd_radial_ptr[B]) and format it to the LCD',
    0x2C1E: 'return pointer to the radial-measurement record for index B (index 0 -> 0x3179)',
    0x2C35: 'print the ECC diagnostic test header line on the LCD',
    0x2C47: 'print the azimuth-alignment test header line on the LCD',
    0x2C59: 'print the head-positioner test header line on the LCD',
    0x2C76: 'print the spindle-speed test header line on the LCD',
    0x2CAC: 'HRD alignment-run entry (variant A): set test index 1, fall into measure+display tail',
    0x2CB0: 'HRD alignment-run entry (variant B): set test index 2, fall into measure+display tail',
    0x2CB4: 'HRD alignment-run entry (variant C): set test index 0/flag 1, fall into measure+display tail',
    0x2CBB: 'HRD alignment-run entry (variant D): set test index 0/flag 2, fall into measure+display tail',
    0x2CC1: "HRD alignment run: measure radial, print head0/head1 scaled values, then jump to test's handler",
    0x2CEE: 'scale a signed measurement to display units: value * K / 10000, K = hrd_test_tbl[test].scale (ROM const: 422 radial/ecc/positioner um, 696 azimuth, 1 spindle-RPM); print preserving sign',
    0x2D2C: 'index into the per-test result record table (stride 5) selected by hrd_test_idx',
    0x2D5B: 'HRD alignment measure: seek+capture 4 windows (hd0 A/B @ image_buf+0/+0x2000, hd1 A/B @ +0x4000/+0x6000); per-head result = burst-position difference (hrd_find_burst, SBC); 10 samples -> hrd_median_filter -> hrd_hd0/hd1',
    0x2E25: 'HRD positioner hysteresis: step in/out, difference of approach positions (um)',
    0x2E72: 'HRD spindle RPM: time index period (8253 c1/c2), RPM = 9230769/ticks',
    0x2EBA: 'HRD read-back: step both heads to cyl 0x3133, arm per-drive DMA, read all sides, CRC-verify, build 4-bit success mask in op_word',
    0x2FC0: 'wait for FDC read to complete, then CRC/status-check fdc0_result via chk_fdc_crc',
    0x2FD4: 'verify fdc0_result: normal termination (ST0&0xC0==0x40) plus sector/data-mark bits set',
    0x2FDC: 'validate FDC 7-byte result: ST0 top bits==0x40 and bit5 of ST1/ST2 set (good termination)',
    0x2FF1: 'store transfer sector count A into per-drive blocks and derived end-count (0x4AFF-1) fields',
    0x3008: 'scan captured read data for alignment sync bursts, return byte offset',
    0x307A: 'print the RPM units suffix string on the LCD',
    0x3084: 'median filter: bubble-sort B signed 16-bit samples, sum the middle ones and divide (sign-preserved)',
    0x30EB: 'negate 16-bit value in HL (compute 0 - HL)',
    0x33B2: 'top-level FDC op dispatcher: mask op (A&0x7F), pick drive block A/B from B.bit0, decode class B&0xE0 to a handler and JP',
    0x3406: 'build FDC format command parameters (rate/precomp/sector fields)',
    0x370E: 'assert panel latch bit6 (0x40) via port F0 (drive/head control line)',
    0x371B: 'clear panel latch bit6 (0x40) via port F0',
    0x3723: 'set the FDC-command-pending flag (0x4AE9 = 1)',
    0x372B: 'clear the FDC-command-pending flag (0x4AE9 = 0)',
    0x372F: 'copy geometry params (sector/size fields) from IX format descriptor into IY drive block',
    0x3751: 'arm DMA for a track: compute byte count from block sector range, call fdc_dma_setup, store count and count*4-1 back',
    0x3784: 'home head to track 0: pulse ~10 single-steps then step until track-0 sense, confirm via fdc_sense_ready',
    0x37C6: 'issue one FDC step/seek pulse (fdc_send_seek A=1) and poll for completion',
    0x37DB: 'measure spindle index period via index sensor + PIT c1/c2, compare vs min/max (0x4AA2/0x4AA4) to validate RPM',
    0x394C: 'prep recal/seek step params: pick step-rate C by drive index (unit_sel) & 0x4A58 cfg, DE=target track per side',
    0x399E: 'FDC specify wrapper: set step rate, issue specify (0x07); folds in bit0 of drv_active_cfg (const enable, not precomp — real write-precomp is FDC port 0xC2)',
    0x39A0: 'build+issue FDC RECALIBRATE (opcode 0x07) to both drives of a pair',
    0x3A18: 'arm single-FDC DMA read (4 desc, cnt 0x0C): pick blk A/B by A==1, set bank/drive latch, exec via SP-swap',
    0x3A83: 'read both drives at once: set dram_bank+drive_sel_b, arm DMA ch1(blkA)/ch2(blkB) reads, exec via SP-swap',
    0x3AF6: 'entry into fdc_send_dma (single-FDC DMA read) with command bit (0x80) masked off A',
    0x3AFE: 'dual-drive DMA read entry: jumps into fdc_read_dual body (both FDCs simultaneously)',
    0x3B04: 'begin FDC read: enable panel bus, select side1, set cmd tag 0x26 (read-data MFM) in 0x4AEA, build R/W cmd block',
    0x3B24: 'issue FDC write via DMA then wait for completion',
    0x3B2B: 'arm single-FDC DMA write (8 desc): pick blk A/B by A==1, set bank/drive latch, exec via SP-swap',
    0x3B72: 'write both drives via DMA then wait for completion',
    0x3B78: 'write both drives at once: set dram_bank+drive_sel_b, arm DMA ch1(blkA)/ch2(blkB) writes (8 desc), exec',
    0x3BE9: 'begin FDC write side0: select side lo, set cmd tag 0x05 (write-data), decode drive to result buf, save SP',
    0x3BEE: 'begin FDC write side1: select side hi, set cmd tag 0x05 (write-data), decode drive to result buf',
    0x3BF5: 'FDC write-command core: set cmd tag 0x05, decode drive via key_decode, select fdc0/1/2/3 result buffer',
    0x3BFB: 'build 9-byte FDC READ/WRITE command {cmd,HD,C,H,R,N,EOT,GPL,DTL} and stream it',
    0x3C7F: 'format-command entry for drive-pair (B=2), falls into fdc_format_cmd',
    0x3C86: 'issue FDC format-track: decode drive (B), enable bus+select side0, exec via SP-swap into result buf',
    0x3CD3: 'build FDC specify/step params for both drives from step-rate/HUT state into per-side cmd blocks, set irq bits 0x0F',
    0x3D44: 'issue seek via DMA then wait for completion',
    0x3D4B: 'arm FDC seek via DMA (8 desc): pick blk A/B by A bit0, set bank/drive latch, exec via SP-swap',
    0x3D95: 'read a full track: prep DMA read then poll completion in a timeout-guarded loop',
    0x3DB9: 'prep FDC DMA read: verify drive ready, OR-in irq bits 0xF0, reset all 4 fdc result buffers',
    0x3E00: 'seek+write both drives: send specify, arm DMA ch1(0x81)/ch2(0x82) 8 desc, exec via SP-swap',
    0x3E64: 'arm FDC DMA read then wait for completion',
    0x3E6B: 'arm FDC DMA read: check drive ready, if ready reset result buffers then proceed',
    0x3EEE: 'write both drives via DMA then poll completion with timeout',
    0x3EF4: 'write both drives via DMA: set dram_bank+drive_sel_b, arm ch1/ch2 8-desc writes, exec via SP-swap',
    0x3F53: 'read from source drive then latch its bank/track pointers from format_desc (0x52E9..0x52ED) for copy',
    0x3FAA: 'arm source-drive DMA: set bank or drive latch by A==1, load ptr, compute byte length',
    0x40C3: 'copy one track: read source track, latch dest geometry from format_desc, write to dest drive if enabled',
    0x4117: 'write full track to dest drive: set latches, copy DMA base ptrs, compute length, arm 4-desc DMA descriptors',
    0x4261: 'copy source(0x4AF7)/dest(0x4B12) DMA base pointers into active descriptor slots 0x4B21/0x4B25',
    0x427F: 'write side via DMA (fdc_write_poll) then latch source geometry',
    0x42A0: 'set FDC step rate from per-side track state (A selects side: 0x4B03 vs 0x4B1E), enable panel bus',
    0x42DD: 'build+issue FDC SEEK (opcode 0x0F, target cyl in C)',
    0x432A: 'select FDC block (A==1->blkA else blkB) into BC and issue seek command',
    0x433A: 'issue FDC seek: enable bus, decode drive, write specify (0x0F)+precomp into cmd block, select result buf',
    0x437A: 'seek both drives to track 45 (0x2D) for alignment test: write specify+seek to FDC 0x10/0x30, wait panel ready',
    0x43EC: 'read {addr,count} descriptor from low-RAM table, arm the DMA channel (0x4401)',
    0x4401: 'program one 8237 DMA channel (addr/count/mode) from a descriptor',
    0x4457: 'reset+reload 8237 channels 0/1 from the drive-block DMA descriptors',
    0x4489: 'compute DMA transfer count: index sector-size table 0x4AA6[A*2], 16-bit multiply by BC, return count-1 in DE',
    0x44D5: 'pack FDC specify bytes: SRT|E->0x4A5C, D<<1|B bit0->0x4A5D; A bit0 selects alt path',
    0x452C: 'issue Sense-Interrupt-Status (0x08) to all 4 FDCs and read their 7-byte result phases',
    0x4571: 'write Sense-Interrupt (0x08) command byte to FDC at port C',
    0x4579: 'read 7 result-phase bytes from an FDC into buffer HL',
    0x457F: 'stream B command/data bytes to an FDC (poll MSR RQM/DIO before each)',
    0x4590: 'build FDC IRQ/DMA enable mask in fdc_irq_bits from drive-select (A bit0, B bit0, side L bit7)',
    0x45DB: 'IM1 handler: read which FDC interrupted (0x94/0xF0), pull 4x 7-byte result phases',
    0x462D: 'ISR seek-complete path: if FDC2 result pending re-issue Sense-Int to 0x20 (and 0x30 if panel bit3), read results',
    0x46F1: 'read FDC result phase (poll RQM/DIO), up to B bytes',
    0x4704: 'poll FDC done flag (irq_bits bit7 drive0 / bit6 drive2 per A bit0), dispatch to result read',
    0x472D: 'poll for FDC operation complete (or timeout)',
    0x481E: 'fast-fill banked DRAM (bank B via 0xB0, addr 0x8000|HL+4*D) via SP-swap block writes, count A&0x7F',
    0x4848: 'start command timeout timer (8253 counter 2)',
    0x4857: 'check/tick the command timeout timer',
    0x4866: 'save data-rate (A) and precomp (B) values to 0x4B89/0x4B8A',
    0x486E: 'enable FDC data bus: set panel port 0xF0 bit0, update shadow 0x4A58',
    0x4883: 'select head/side 0: clear panel bit7 (0x4A58), output to 0xF0',
    0x488B: 'select head/side 1: set panel bit7 (0x4A58), output to 0xF0',
    0x4893: 'decode ST0/ST1/ST2 -> error class (CRC/writeprot/seek/notready/overrun)',
    0x48DB: 'busy-wait delay: DJNZ loop for B iterations',
    0x48DE: 'read 8253 counter-1 16-bit (latch cmd 0x44 to 0xAC, read lo/hi from 0xA4), returns HL',
    0x48EB: 'set FDC command-mode flags in 0x4A5A bits0-3 from op_word nibble & rd_submode/unit_sel',
    0x4974: 'check drive ready: sense drive status, test status bit6 (ready line)',
    0x4981: 'report drive-not-ready error (code 0x96) then re-sense drive status',
    0x4990: 'sense drive ready: read status, XOR 0x10, test bit4; Z=ready',
    0x499E: 'FDC Sense Drive Status (cmd 0x04): build unit byte from bit0 of drv_active_cfg, exec, read ST3',
    0x49D2: 'init 4-byte FDC cmd/DMA descriptor at IX to {0x41,0x02,0x00,0x00}',
    0x49E3: 'beep the piezo buzzer A times (port 0xF0 bit3, active-low), ~13ms delay between (via buzzer_pulse)',
    0x49FC: 'one buzzer pulse: drive 0xF0 bit3 low ~13ms then high (audible click), keep shadow 0x4A58 in sync',
    0x4A16: 'buzzer_off: set port 0xF0 bit3 high (buzzer idle), keep shadow 0x4A58 in sync',
    0x4A16: 'set panel port F0 bit3 high, keeping 0x4A58 shadow in sync',
    0x4B99: 'HD44780 LCD init: function set 0x38, display/clear/entry/on, presence check',
    0x4BE2: 'mute local I/O: disable input poll and point iovec_out at no-op stub (0x4C4F)',
    0x4BEC: 'disable input polling: point iovec_poll at stub that returns A=0xFF',
    0x4BF5: 'error beep: A*200/13 -> PIT ch1 (0xA4/0xAC) tone, pitch/duration encodes error code',
    0x4C22: 'busy-loop delay (HL iterations)',
    0x4C2A: 'wait for LCD busy flag clear (IN 0xE0 bit7)',
    0x4C43: 'write A to LCD via iovec_out (busy-wait then OUT (C),A; C=cmd/data reg)',
    0x4C4A: 'default iovec_out: wait LCD busy then OUT (C),A; 0x4C4F entry is muted no-op restoring HL',
    0x4C59: 'print inline string to LCD (control bytes 0x0C clr/0x0D nl/0x1B pos/0x00 end)',
    0x4CD3: 'scroll LCD display up one line: read line-2 chars and rewrite shifted, blank last',
    0x4D0B: 'scan the 4-key keypad matrix (ports 0x98/0x94)',
    0x4D29: 'read keypad row: IN status 0x94, invert low nibble, return single-key code or 0',
    0x4D43: 'debounced key read with auto-repeat + key-click beep',
    0x4D49: 'wait for a debounced keypress: poll keypad_scan with LCD-timed delays and panel busy pulse',
    0x4D89: 'get key / dispatch input (indirect via iovec_poll 0x52CB: keypad or host)',
    0x4D8E: 'poll-input tail: if A=0 scan keypad and discard caller return; else return current value',
    0x4D9B: 'poll host UART (0xDC) during key scan; if byte ready fetch remote word, flag cmd 0x0C',
    0x4DD9: 'init 8253 (baud c0, timers c1/c2) and both SIO channels; drain receivers',
    0x4E42: 'SIO TX: wait TxRDY (status bit2), OUT data',
    0x4E4F: 'test host SIO RxRDY: C=0xDC, IN B, bit0 = byte available',
    0x4E53: 'test autoloader SIO RxRDY: C=0xD4, IN B, bit0 = byte available',
    0x4E5A: 'SIO RX with timeout: wait RxRDY (bit0); return Z=byte / NZ=timeout|err',
    0x4E8C: 'send SIO command 0x30 to port C (reset error flags / enter hunt)',
    0x4E91: 'reset autoloader SIO (C=0xD4) via command 0x30',
    0x4E95: 'reset host SIO (C=0xDC) via command 0x30',
    0x4E99: 'transmit byte A to autoloader SIO (C=0xD4, via uart_tx)',
    0x4E9D: 'transmit byte A to host SIO (C=0xDC, via uart_tx)',
    0x4EA1: 'receive byte from autoloader SIO (C=0xD4); on data, clear SIO errors',
    0x4EAD: 'receive byte from host SIO (C=0xDC); on data, clear SIO errors',
    0x4EB2: '32-bit binary (DE:HL) -> decimal ASCII, right-justified in buffer at 0x4F38 down',
    0x4EB5: 'binary -> decimal ASCII conversion',
    0x4ECB: 'divide 32-bit DE:HL by 10 (BC=10 wrapper over div32_16), remainder in C for digits',
    0x4ECE: '32/16 unsigned divide (DE:HL / BC)',
    0x4F05: '16x16 unsigned multiply',
    0x4F1D: 'fill 8-byte decimal-conversion buffer at 0x4F31 with spaces',
    0x4F2C: 'print the decimal-conversion buffer string to LCD (via lcd_print)',
    0x4F3B: 'monitor hex-dump: clear LCD (cmd 0x01) then print a hex row of bytes from (HL)',
    0x4F5C: 'print a full 2-line monitor hex row (mon_hex4 group + line-2 home)',
    0x4F5F: 'print monitor hex group then home to LCD line 2',
    0x4F66: 'monitor hex-row segment: print 4 hex bytes from (HL) plus trailing space',
    0x4F69: 'monitor hex-row segment: print 3 hex bytes from (HL) plus trailing space',
    0x4F6C: 'monitor hex-row segment: print 2 hex bytes from (HL) plus trailing space',
    0x4F6F: 'print a single space char to LCD data (0xE8) - monitor field separator',
    0x4F77: 'print 2 hex bytes from (HL) to LCD, advancing HL (monitor)',
    0x4F7A: 'print byte at (HL) as 2 hex digits to LCD, advance HL (monitor)',
    0x4FAC: 'print two hex nibbles of buffered byte (0x4FAB) via RLD, ASCII-adjust, to LCD',
    0x4FAF: 'print one hex nibble via RLD to ASCII (0-9/A-F) to LCD data (0xE8)',
    0x4FC4: 'home LCD to line 2 (via lcd_print control sequence)',
    0x4FCB: 'assemble FDC format command block: geometry + sector map + interleave + DMA/bank params from 0x3130',
    0x4FF2: 'logical block -> CHS + DMA descriptor (uses format_desc geometry)',
    0x5043: 'generate per-track sector-ID (interleave) list for FORMAT',
    0x507E: 'build sector interleave table at IY (0x52F2): fill physical->logical sector ids via sector_lba',
    0x50AB: 'compute interleaved logical sector id from position: div32_16 by sectors-per-track (format_desc+5)',
    0x50CC: 'lay out per-sector format descriptors (C/H/R/N) for whole track via block_to_chs',
    0x5101: 'init format_desc geometry: copy 5 disk params from 0x4AFC, compute sectors-per-track and totals',
    0x515D: 'checksum every loaded DRAM image bank: set image_present, LCD progress, loop banks via set_bank_checksum',
    0x519C: "select DRAM bank A (OUT 0xB0), compute image_checksum, store two's-complement at 0xFFFF so bank sums to 0",
    0x51A9: 'checksum the whole DRAM image (sum 0x8000..0xFFFF)',
    0x51BA: 'verify next DRAM bank checksum (bank counter 0x52C7): add image_checksum, expect 0; pulses panel busy + LCD',
    0x51E7: 'build FDC unit-select byte: index cfg table 0x5227 then OR option bits from format_desc IX+11; result stored to unit_sel by callers',
    0x520A: 'compute media-config table index from format_desc IX+11 density/side/option bits',
    0x522F: 'generic 4-key menu driver (HL=draw+action ptr lists); see docs',
}


# ---- variable declarations + docs (0x311A-0x3304) ----
SYMBOLS.update({
    0x311F:'cfg_batch',
    0x3120:'fmt_geom_ptr',
    0x3130:'dram_bank_count',
    0x3133:'cur_track',
    0x3135:'datarate_idx',
    0x3136:'precomp_idx',
    0x3141:'copy_count',
    0x3143:'edit_value',
    0x3145:'edit_value_hi',
    0x3147:'dl_rec_count',
    0x3149:'op_flag_49',
    0x314A:'err_recovery',
    0x3150:'edit_ndigits',
    0x3151:'edit_width',
    0x3152:'edit_col',
    0x3153:'edit_min',
    0x3154:'edit_max',
    0x3155:'wprot_mode',
    0x315A:'read_addr',
    0x315F:'fdc_rate_a',
    0x3160:'fdc_rate_b',
    0x3161:'host_mode',
    0x3163:'side_sel',
    0x3165:'spfmt_num',
    0x3166:'precomp_sel',
    0x3168:'serial_num_lo',
    0x316A:'serial_num_hi',
    0x316C:'serial_incr',
    0x316D:'serial_cyl',
    0x316E:'serial_head',
    0x316F:'serial_sector',
    0x3170:'serial_offset',
    0x3172:'serial_bank',
    0x3173:'serial_addr',
    0x3175:'serial_ptr',
    0x3178:'hrd_model_idx',
    0x3186:'hrd_test_tbl',
    0x31C1:'datarate_tbl',
    0x3219:'precomp_tbl',
})
COMMENTS.update({
    0x311A:'pointer to the active config byte (set/reset by the config toggles)',
    0x311C:'config flags word: form-factor/density/mode/spindle + max-cyl (bit7 = copy direction)',
    0x311D:'config byte: density/size + serialization mirror bits',
    0x311E:'drive-active control constant (hardcoded 0x2D @0x01B7; NOT precomp). bit0 (always 1) is the shared enable fanned to drive latches 0x40/0x60 and 0x9C line 6; real write-precomp is FDC port 0xC2',
    0x311F:'config: batch-processing / serialization flag',
    0x3120:'geometry pointer stored by each disk-format select handler',
    0x3130:'number of installed 32KB DRAM banks (counted by dram_test)',
    0x3131:'pointer to the current duplication-phase / menu handler (JP target)',
    0x3133:'current cylinder (stepped during seek; also host image geometry)',
    0x3134:'operation word: phase code (bits3-0), error flags (bit6/5), advance (bit7)',
    0x3135:'media geometry word; low byte indexes the data-rate table (datarate_tbl)',
    0x3136:'index into the write-precomp table (precomp_tbl)',
    0x3137:'drive/unit + head select byte',
    0x3139:'per-disk track/pass counter (good tally)',
    0x313B:'completed-pass counter',
    0x313D:'remaining count for this run (tracks or copies)',
    0x3141:'saved copy count for the current run',
    0x3143:'32-bit numeric edit-field accumulator (low); also holds max-cyl / copy count',
    0x3145:'numeric edit-field accumulator (high word)',
    0x3147:'host image-download record counter',
    0x3149:'op/diag flag set by fdc_build_select & start_batch, read by HRD [purpose uncertain]',
    0x314A:'data-error-recovery mode (1=enable, 3=disable); init 3',
    0x314C:'FDD format/mode index; also holds the autoloader reply/status byte',
    0x314D:'autoloader status low nibble (2nd hex char of S reply)',
    0x314E:'run status code (8 = comparing, etc.)',
    0x314F:'RD+ copy sub-mode (1=FWV, 2=WV, 5=FW, 6=W)',
    0x3150:'numeric edit-field digit count; also an operation/side flag',
    0x3151:'numeric edit-field width (init 8)',
    0x3152:'numeric edit-field LCD column',
    0x3153:'numeric edit-field minimum value',
    0x3154:'numeric edit-field maximum value',
    0x3155:'write-protect recognition flag (config); init 4',
    0x3156:'DRAM image bank for the current track, drive group A',
    0x3157:'DRAM image bank for the current track, drive group B',
    0x3158:'byte offset of the current track within its DRAM bank',
    0x315A:'image read/copy address pointer',
    0x315F:'FDC data-rate register value, drive group A',
    0x3160:'FDC data-rate register value, drive group B',
    0x3161:'host remote-control mode flag (set when host drives the machine)',
    0x3162:'autoloader-present flag (1 = attached)',
    0x3163:'head/side select byte (init 0x81)',
    0x3164:'current cylinder/head + format-select code',
    0x3165:'selected special-format number (1-16)',
    0x3166:'precomp selection index',
    0x3167:'precomp menu value + serialization-enable bit',
    0x3168:'serialization: 32-bit serial number, low word',
    0x316A:'serialization: 32-bit serial number, high word',
    0x316C:'serialization: increment added to the number per copy',
    0x316D:'serialization: target cylinder for the stamp',
    0x316E:'serialization: target head for the stamp',
    0x316F:'serialization: target sector for the stamp',
    0x3170:'serialization: byte offset within the sector',
    0x3172:'serialization: image bank for the stamp (via OUT 0xB0)',
    0x3173:'serialization: computed write address in the image',
    0x3175:'serialization: scaled byte pointer for the stamp',
    0x3178:'HRD head/model index',
    0x3186:'hrd_test_tbl: 5 per-test records { scale K:word, display handler:word, result mask:byte } (idx 0-4 = radial/eccentricity/azimuth/positioner/spindle)',
    0x319F:'spindle index-period timer residual (read back from 8253)',
    0x31A1:'HRD measured value for head 0 (um)',
    0x31A3:'HRD measured value for head 1 (um)',
    0x31A5:'selected HRD diagnostic test index',
    0x31C1:'per-format FDC data-rate register values (indexed by datarate_idx)',
    0x3219:'per-format write-precomp register values (indexed by precomp_idx)',
    0x3269:'32-bit lifetime copy/insert cycle counter (low word)',
    0x326B:'cycle counter (high word)',
})

# Banked DRAM window (>= 0x8000): no ROM/RAM home, so image_buf is emitted as an
# equate (see emit_hi_equates); everything in the window resolves to image_buf+off.
SYMBOLS.update({
    0x8000: 'image_buf',   # base of the 32 KB banked disk-image buffer (0x8000-0xFFFF)
})

# FDC command-build handlers dispatched by `JP (HL)` @0x3405; selected by the
# operation-word top bits (B AND 0xE0). Loaded via LD HL,addr so auto_label
# (which only tracks direct branches) can't see them.
SYMBOLS.update({
    0x34A2: 'fdc_build_20',   # sel 0x20
    0x34AA: 'fdc_build_40',   # sel 0x40
    0x34F9: 'fdc_build_60',   # sel 0x60
    0x34FD: 'fdc_build_80',   # sel 0x80
    0x357C: 'fdc_build_A0',   # sel 0xA0
    0x3580: 'fdc_build_C0',   # sel 0xC0/0xE0
    0x35AA: 'fdc_sub_jmptbl', # base of a JP-table, index (C-1); HL=(C-1)*3+base; JP (HL) @0x35A9
    # Self-modified LCD print template = the inline string @0x062F ("ESC,<pos>,
    # 12345678,NUL"); interior fields are referenced as lcd_num_tmpl+offset.
    0x062F: 'lcd_num_tmpl',   # +1 = cursor-pos byte (@0x05FE), +2 = 8-char numeric field
    0x27F9: 'lcd_val_tmpl',   # self-modified "ESC,pos,c1,c2,NUL": +1 pos, +2/+3 two chars
})
COMMENTS.update({
    0x34A2: 'op-word bits7-5=0x20 handler: set FDC pending, H=2, rejoin build at loc_3411',
    0x34AA: 'op-word bits7-5=0x40 handler: build write/verify FDC rate+precomp+gap params',
    0x34F9: 'op-word bits7-5=0x60 handler: H=2, enter the 0x40 build body at loc_34B2',
    0x34FD: 'op-word bits7-5=0x80 handler: build params with unit_sel-dependent pending, alt density',
    0x357C: 'op-word bits7-5=0xA0 handler: H=2, enter the 0x80 build body at loc_3505',
    0x3580: 'op-word bits7-5=0xC0/0xE0 handler: JP fdc_format_build',
    0x35AA: 'JP jump-table indexed by sub-command (C-1): 3-byte JP entries dispatched by JP (HL) @0x35A9',
    0x0022: 'boot continuation: also copied to DRAM 0x8022 and re-entered there after banking',
    0x21CE: 'downloaded-code block (copied to 0x7800 by host opcode 0x0F); runs from RAM, labeled at its ROM source',
    0x222D: 'download entry A (runs at 0x785F after relocation to 0x7800)',
    0x2236: 'download entry B (runs at 0x7868 after relocation to 0x7800)',
})

# --- FDC driver RAM state block labels (0x4A54-0x4B8A) + per-FDC sub-labels ---
SYMBOLS.update({
    0x4A54: 'fdc_saved_sp',
    0x4A58: 'panel_shadow',
    0x4A59: 'fdc_drv_state',
    0x4A61: 'fdc_cmd_buf',  0x4A6A: 'fdc_cmd_buf1', 0x4A73: 'fdc_cmd_buf2', 0x4A7C: 'fdc_cmd_buf3',
    0x4A85: 'fdc_result_buf', 0x4A8C: 'fdc_result_buf1', 0x4A93: 'fdc_result_buf2', 0x4A9A: 'fdc_result_buf3',
    0x4AA1: 'fdc_result_save',
    0x4AA6: 'sector_size_tbl',
    0x4AB4: 'fdc_gap_tbl',
    0x4ABC: 'fdc_param_recs',
    0x4AE9: 'fdc_op_flags',
    0x4AEA: 'fdc_opcode_base',
    0x4AEB: 'drive_blk_a',
    0x4B06: 'drive_blk_b',
    0x4B21: 'dma_ptr_save',
    0x4B29: 'fmt_geom_recs',
    0x4B89: 'fdc_rate_reg',
    0x4B8A: 'fdc_precomp_reg',
})
COMMENTS.update({
    0x4A54: 'saved SP for the LD SP,IX rapid command loader (LD (..),SP / LD SP,(..)); +2 reserved',
    0x4A58: 'port-0xF0 output shadow: panel key-column drive, buzzer bit3 (active-low), status LEDs',
    0x4A59: 'FDC driver state: current mode/side byte, scratch pointers and misc flags (0x4A59-0x4A60)',
    0x4A61: '4 command buffers, one per FDC, 9 bytes each; byte0 = last opcode (seek/recal marker for the ISR)',
    0x4A85: '4 result-phase buffers, one per FDC, 7 bytes each: ST0,ST1,ST2,C,H,R,N from the FDC result phase',
    0x4AA1: '0x4AA1 per-FDC "result captured" bits; 0x4AA2/0x4AA4 saved DE/HL across the result-read path',
    0x4AA6: 'sector-size lookup: 7 words 128<<N (128,256,512,1024,2048,4096,8192); fdc_dma_setup indexes [N*2]',
    0x4AB4: 'format -> gap3/length byte table (8 entries), indexed by format id',
    0x4ABC: '9x 5-byte FDC parameter records {b0, rate:word, b3, b4} streamed into an FDC block by copy_fdc_params',
    0x4AE9: 'FDC command-build flags byte',
    0x4AEA: 'READ/WRITE command opcode base (ORed with 0x40 for MFM before issue)',
    0x4AEB: 'drive-pair block A (27 bytes): +7 DOR/motor, +8/9 DMA start address (8237 ch0x80), +10/11 DMA count',
    0x4B06: 'drive-pair block B (27 bytes): same layout, 8237 channel 0x82',
    0x4B21: '4 words: per-FDC DMA start-address / transfer-count save slots',
    0x4B29: 'fmt_geom_recs: "Special format" per-head data-rate zone tables (default set) = variable-rate zoned formatting. 4 formats x 2 records (.a=head0, .b=head1); each = 6 zone entries { start cyl : low byte, data-rate : high byte, 0/1/2 = N/L/H }. CONFIRMED data-rate: range_table_lookup(cyl) @0x092A scans these 6 bands -> fdc_rate_a/b -> update_ctrl_latch (0x9C datarate lines 4/5 + drv-latch bit2). Copied to 0x31A1, edited by hrd_edit_head_pair. Read-only defaults',
    0x4B89: 'current FDC data-rate register bits (ORed then OUT to 0xB1)',
    0x4B8A: 'current FDC write-precompensation value (OUT to 0xC2)',
    0x4A6A: 'FDC1 command buffer',  0x4A73: 'FDC2 command buffer',  0x4A7C: 'FDC3 command buffer',
    0x4A8C: 'FDC1 result phase',    0x4A93: 'FDC2 result phase',    0x4A9A: 'FDC3 result phase',
})

# OTIR serial-payload blob starts, so the LD HL,src operands resolve to the label.
SYMBOLS.update({
    0x209C: 'host_ser_blob0',
    0x20D6: 'host_ser_blob1',
    0x4E28: 'al_ser_blob',
    0x4E35: 'host_ser_blob2',
})

# 8-byte decimal-conversion / display buffer = the inline LCD print template
# @0x4F2F ("ESC,0xC0,........,NUL"): bin2dec writes digits right-justified ending
# at +9, clear_dec_buf space-fills from +2. Fields referenced as lcd_dec_tmpl+off.
SYMBOLS.update({
    0x4F2F: 'lcd_dec_tmpl',   # +2 = buffer start, +8 = low word (@0x27EE), +9 = units digit
})

# Built-in disk-format table: 8x 19-byte DOS BPB records. Field layout (per record):
#  +3/4 bytes/sector · +5/6 root-dir entries · +7/8 total sectors · +9 media
#  descriptor · +10/11 sectors/FAT · +12/13 sectors/track · +14/15 heads. The
#  table is DECLARED here but never read by any code path (no base load exists).
SYMBOLS.update({
    0x3281: 'fmt_1440k',   # rec1
    0x3294: 'fmt_720k_b',  # rec2
    0x32A7: 'fmt_1200k',   # rec3
    0x32BA: 'fmt_160k',    # rec4
    0x32CD: 'fmt_180k',    # rec5
    0x32E0: 'fmt_320k',    # rec6
    0x32F3: 'fmt_360k',    # rec7
})
COMMENTS.update({
    # legend for fmt_param_tbl; per-record geometry is in ROW_NOTES (inline)
    0x326E: 'fmt_param_tbl: 8 built-in disk formats, packed 19-byte BPB { secsz/256, spc, resv:w, nFAT, root:w, total:w, media, spf:w, spt:w, heads:w, hidden:3 }. NOTE: UNREFERENCED by firmware code',
})

# lcd_print / lcd_byte_out caller-register save slots (16-bit RAM words)
SYMBOLS.update({
    0x4C53: 'lcd_print_hl',   # caller HL saved across lcd_print
    0x4C55: 'lcd_print_bc',   # caller BC saved across lcd_print
    0x4C57: 'lcd_byte_hl',    # caller HL saved across lcd_byte_out
})
COMMENTS.update({
    0x4C53: 'saved caller HL across lcd_print (restored at 0x4CCB)',
    0x4C55: 'saved caller BC across lcd_print (restored at 0x4CCE)',
    0x4C57: 'saved caller HL across lcd_byte_out (restored at 0x4C4F)',
})

COMMENTS.update({
    # 18-byte active-format / copy descriptor. Two overlaid halves. Geometry
    # (0..11) is rebuilt by init_format_geom (0x5101): it copies 5 nominal params
    # from the selected drive block into +0..+4, then computes +5..+10 to fill the
    # 32 KB image bank. Copy scratch (12..17) is loaded by the duplication engine
    # (0x3F64/0x40C9) and latched into drive_blk_a/b.
    #   +0    nominal cylinder/track count (copied)          [0x085B,0x0DC4]
    #   +1    nominal sectors-per-track (copied)             [0x5089,0x50B2,0x50D3]
    #   +2    sector-size code N (copied)                    [0x50F2, init math]
    #   +3..4 per-track byte size, 16-bit (copied)           [0x1C5E,0x2BAF]
    #   +5    computed sectors-per-track                     [0x512A;0x5057,0x50C1]
    #   +6    computed N*4 (sector-size/gap value)           [0x514E;0x5066]
    #   +7..8 computed track byte-count (= total, mirror)    [0x5141;0x504E]
    #   +9..10 computed total length (tracks*N)              [0x513B;0x506D]
    #   +11   FORMAT FLAGS / model-ID byte: bit7=HD/DD density, bit4=double-sided,
    #         bits2/3/5/6=media-cfg index + FDC unit-select options
    #         [density 0x1831/0x1849; sides 0x0739; media_cfg_index 0x520A;
    #          fdc_build_unit_sel 0x51E7; model-ID 0x1943/0x1FE2]
    #   +12   source image-bank byte (drive A); also start-bank-1 [0x3F75,0x51D9]
    #   +13..14 source track/buffer pointer, 16-bit           [0x3F72,0x40D5]
    #   +15   destination image-bank byte (drive B)           [0x3F67,0x40CC]
    #   +16..17 destination track/buffer pointer, 16-bit      [0x3F64,0x40C9]
    0x52DD: 'format_desc: 18-byte active-format + copy descriptor. Bytes 0-11 = disk'
            ' geometry (init_format_geom copies 5 nominal params -> +0..+4, computes'
            ' +5..+10); byte +11 = density/side/option flags (+ model-ID); bytes 12-17'
            ' = copy-engine bank/pointer scratch (src bank+ptr, dst bank+ptr). See the'
            ' field map in the internals doc.',
})

BRANCH_KINDS = {'jr','jump','cjump','call','ccall'}

_OPREF=re.compile(r'(\()?0x([0-9A-Fa-f]{4})')

def auto_label(b,start,end):
    """Walk the code exactly as main() does. Every CALL/JR/JP target on a real
    instruction boundary gets a 'loc_XXXX' label. Additionally, any operand that
    references a code instruction boundary (a memory ref, or an address-like
    immediate) gets its own label too, so such references render as a clean
    'loc_XXXX' rather than 'nearbyLabel+offset'."""
    code=set(); tgts=set(); refs=set()
    pc=start
    while pc<end:
        if table_at(pc) and pc+1<len(b): pc+=2; continue
        if pc in WORD_PTRS and pc+1<len(b): pc+=2; continue
        reg=region_at(pc)
        if reg:
            pc=min(reg[1],end); continue
        try: ins=disasm_one(b,pc)
        except Exception: ins=Ins(pc,1,'DB',None,None)
        nb=next_special(pc,end)
        if pc<nb<pc+ins.length: pc=nb; continue
        code.add(ins.addr)
        if ins.kind in BRANCH_KINDS and ins.target is not None and start<=ins.target<end:
            tgts.add(ins.target)
        elif ins.kind not in BRANCH_KINDS:                 # non-branch operand addresses
            for pm,hx in _OPREF.findall(ins.text):
                refs.add((int(hx,16), bool(pm)))
        pc+=ins.length
        if ins.kind=='call' and ins.target==PRINT_ADDR and pc<end:
            slen,_=render_string(b,pc,end); pc+=slen
    for t in sorted(tgts):
        if t in code and t not in SYMBOLS:
            SYMBOLS[t]='loc_%04X'%t
    # Operand-referenced code boundaries -> their own clean label. Memory refs are
    # certainly addresses; bare immediates only when address-like (>=0x100 and not
    # a round multiple of 0x100) to avoid labelling constants (0x000A, 0x0200,...).
    for v,is_mem in sorted(refs):
        if not (start<=v<end) or v not in code or v in SYMBOLS: continue
        if region_at(v) is not None: continue
        if is_mem or (v>=0x0100 and (v&0xFF)):
            SYMBOLS[v]='loc_%04X'%v

def main():
    b=open(sys.argv[1],'rb').read()
    start=int(sys.argv[2],0) if len(sys.argv)>2 else 0
    end=int(sys.argv[3],0) if len(sys.argv)>3 else len(b)
    auto_label(b,start,end)
    pc=start
    while pc<end:
        tbl=table_at(pc)
        if tbl and pc+1<len(b):
            s,e,name=tbl
            if pc in SYMBOLS: print('\n%s:'%SYMBOLS[pc])   # sub-menu start label
            elif pc==s: print('\n%s:'%name)
            val=b[pc]|(b[pc+1]<<8); tgt=resolve_addr(val) if val else None
            txt='DW %-16s ; [%d]'%(tgt if tgt else '0x%04X'%val, (pc-s)//2)
            print('%04X  %-12s  %s'%(pc,'%02X %02X'%(b[pc],b[pc+1]),txt))
            pc+=2; continue
        if pc in WORD_PTRS and pc+1<len(b):
            if pc in SYMBOLS:
                print('')
                if pc in COMMENTS: print('; %s'%COMMENTS[pc])
                print('%s:'%SYMBOLS[pc])
            val=b[pc]|(b[pc+1]<<8); tgt=resolve_addr(val) if val else None
            txt='DW %s'%(tgt if tgt else '0x%04X'%val)
            if tgt: txt+='   ; -> 0x%04X'%val
            print('%04X  %-12s  %s'%(pc,'%02X %02X'%(b[pc],b[pc+1]),txt))
            pc+=2; continue
        reg=region_at(pc)
        if reg:
            s,e,name=reg
            if pc==s:
                print('')
                if pc in COMMENTS: print('; %s'%COMMENTS[pc])
                print('%s:'%name)
            dump_data(b,pc,min(e,end))
            pc=min(e,end)
            continue
        try:
            ins=disasm_one(b,pc)
        except Exception:
            ins=Ins(pc,1,'DB 0x%02X'%b[pc])
        # Don't let an instruction straddle a declared boundary — emit the
        # in-between bytes as DB and realign exactly on the region start.
        nb=next_special(pc,end)
        if pc<nb<pc+ins.length:
            n=nb-pc
            bts=' '.join('%02X'%b[pc+i] for i in range(n))
            dbs=', '.join('0x%02X'%b[pc+i] for i in range(n))
            print('%04X  %-12s  %s'%(pc,bts,add_iline(pc,'DB %s'%dbs)))
            pc=nb; continue
        if ins.addr in SYMBOLS:
            print('')
            if ins.addr in COMMENTS: print('; %s'%COMMENTS[ins.addr])
            print('%s:'%SYMBOLS[ins.addr])
        bts=' '.join('%02X'%b[ins.addr+i] for i in range(ins.length))
        print('%04X  %-12s  %s'%(ins.addr,bts,add_iline(ins.addr,apply_symbols(ins.text))))
        pc+=ins.length
        # After the inline-string print call, consume the string and realign.
        if ins.kind=='call' and ins.target==PRINT_ADDR and pc<end:
            if pc in SYMBOLS:              # named inline string -> emit a label
                print('')
                if pc in COMMENTS: print('; %s'%COMMENTS[pc])
                print('%s:'%SYMBOLS[pc])
            slen,stext=render_string(b,pc,end)
            pv=' '.join('%02X'%b[pc+i] for i in range(min(slen,6)))
            if slen>6: pv+=' +'
            print('%04X  %-12s  %s'%(pc,pv,add_iline(pc,stext)))
            pc+=slen

def emit_hi_equates():
    """Addresses >= 0x8000 live in the banked DRAM window with no ROM/RAM home;
    declare them as equates (temporary — to be refined once the image-buffer
    layout is mapped)."""
    hi=sorted((a,n) for a,n in SYMBOLS.items() if a>=0x8000)
    if not hi: return
    print('')
    print('; === equates: banked DRAM window >= 0x8000 (no ROM home; refined later) ===')
    for a,n in hi:
        print('%-12s = 0x%04X'%(n,a))

def check_defined(text):
    """Sanity check: every in-range symbol (< 0x8000) must have a real inline
    'name:' definition line. Anything missing here is a bug to fix (add an inline
    anchor + OFFSET_REFS). Addresses >= 0x8000 are equates (emit_hi_equates)."""
    defined=set(re.findall(r'(?m)^([A-Za-z_]\w*):', text))
    anchors={SYMBOLS[a] for a in OFFSET_REFS.values() if a in SYMBOLS}
    missing=sorted(n for a,n in SYMBOLS.items()
                   if a<0x8000 and n not in defined and n not in anchors)
    if missing:
        sys.stderr.write('WARNING: symbols without an inline definition: %s\n'%missing)

def harvest_labels(text):
    """Build {addr: label} from an emitted listing: each 'name:' line is followed
    by an address line 'XXXX  ...'. Feeds resolve_addr's label+offset fallback."""
    m={}; pend=[]
    for ln in text.splitlines():
        h=re.match(r'^([A-Za-z_]\w*):$', ln)
        if h: pend.append(h.group(1)); continue
        a=re.match(r'^([0-9A-F]{4})  ', ln)
        if a:
            if pend: m[int(a.group(1),16)]=pend[-1]
            pend=[]
    return m

def render():
    import io, contextlib
    buf=io.StringIO()
    with contextlib.redirect_stdout(buf):
        main()
    return buf.getvalue()

if __name__=='__main__':
    text1=render()                            # pass 1: establish label positions
    EMITTED_MAP.update(harvest_labels(text1)) # harvest every emitted label
    text2=render()                            # pass 2: interiors -> label+offset
    sys.stdout.write(text2)
    emit_hi_equates()
    check_defined(text2)
