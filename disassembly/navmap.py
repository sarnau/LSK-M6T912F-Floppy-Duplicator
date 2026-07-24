#!/usr/bin/env python3
"""Generate navigation aids for the disassembly: a labeled memory map, a routine
index, and a call graph. Parses the (authoritative) sourcecode.s listing and reuses
z80dis.py's COMMENTS / PORTS / DATA_REGIONS tables. Output: navigation.md.

    cd disassembly
    python3 navmap.py sourcecode.s > navigation.md
"""
import sys, re, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import z80dis as z

LST = sys.argv[1] if len(sys.argv) > 1 else "sourcecode.s"
lines = open(LST).read().split("\n")

LABEL = re.compile(r'^([A-Za-z_]\w*):$')
ADDR_LINE = re.compile(r'^([0-9A-F]{4})  ')                 # any addressed line (code or data)
INSN  = re.compile(r'^([0-9A-F]{4})  .{12}  (.+)$')          # exact emit format: addr, bytes(12), text
BRANCH = re.compile(r'^(CALL|JP|JR|DJNZ)\b\s*(.*)$')
is_auto = lambda nm: re.match(r'loc_[0-9A-F]{4}$', nm) is not None

# --- Pass 1: map every label name -> its address (a label line is followed by the
# addressed line it names, which may be code or a data row). ---
label_addr = {}
pending = []
for ln in lines:
    m = LABEL.match(ln)
    if m:
        pending.append(m.group(1)); continue
    ma = ADDR_LINE.match(ln)
    if ma and pending:
        a = int(ma.group(1), 16)
        for nm in pending:
            label_addr[nm] = a
        pending = []

def resolve(tok):
    """Branch operand -> target address (or None). Strips any inline comment,
    a leading 'cc,' condition, and a '+0xNN' label offset."""
    tok = tok.split(';', 1)[0].strip()   # drop inline comment
    if ',' in tok:                        # conditional: NZ,target / Z,target / ...
        tok = tok.split(',', 1)[1].strip()
    if tok.startswith('('):               # JP (HL) etc. - computed, no static target
        return None
    m = re.match(r'([A-Za-z_]\w*)(?:\+0x([0-9A-Fa-f]+))?$', tok)
    if m:
        base = label_addr.get(m.group(1))
        if base is None: return None
        return base + (int(m.group(2), 16) if m.group(2) else 0)
    m = re.match(r'0x([0-9A-Fa-f]{1,4})$', tok)
    if m: return int(m.group(1), 16)
    return None

# --- Pass 2: walk the listing, attribute call/branch edges to the enclosing label. ---
callees = {}   # routine addr -> set(target addr)
callers = {}   # target addr  -> set(routine addr)
cur = None
addr2names = {}
for a, nm in label_addr.items():
    addr2names.setdefault(nm, []).append(a)  # (name->addr map already; reverse below)
# reverse: addr -> preferred (named) label
addr_label = {}
for nm, a in label_addr.items():
    if a not in addr_label or (is_auto(addr_label[a]) and not is_auto(nm)):
        addr_label[a] = nm

cur = None
pending = []
for ln in lines:
    m = LABEL.match(ln)
    if m:
        pending.append(m.group(1)); continue
    if not ADDR_LINE.match(ln):
        continue
    if pending:                            # nearest preceding label = enclosing routine
        cur = label_addr[pending[-1]]
        pending = []
    mi = INSN.match(ln)
    if not mi:                             # data row: advances cur-tracking only
        continue
    mb = BRANCH.match(mi.group(2))
    if mb and cur is not None:
        tgt = resolve(mb.group(2))
        if tgt is not None and 0 <= tgt < 0x8000:
            callees.setdefault(cur, set()).add(tgt)
            callers.setdefault(tgt, set()).add(cur)

def in_data(a):
    return any(s <= a < e for s, e, _ in z.DATA_REGIONS)
# "Routines" = named code labels: exclude auto loc_*, declared data regions, and
# obvious data labels (version strings / pointer slots) that only decode as code.
DATA_NAME = re.compile(r'^(ver_|ptr_)')
named = sorted(a for a, nm in addr_label.items()
               if not is_auto(nm) and not in_data(a) and not DATA_NAME.match(nm))
def desc(a):
    d = z.COMMENTS.get(a, "")
    return re.sub(r'\s+', ' ', d).strip()

out = []
w = out.append
w("# LSK M6T912F — Disassembly Navigation")
w("")
w("Generated from `sourcecode.s` by `navmap.py` — a labeled memory map, a routine")
w("index, and a static call graph. Addresses are ROM offsets. Regenerate with:")
w("")
w("```sh")
w("cd disassembly && python3 navmap.py sourcecode.s > navigation.md")
w("```")
w("")
w("> Static graph: targets reached only through computed jumps (`JP (HL)`, dispatch")
w("> tables) do not appear as edges, so a routine with **0 callers** may still be a")
w("> jump-table handler. Such tables are called out in the analysis docs.")
w("")

# ---- Memory map ----
w("## 1. Memory map")
w("")
w("| Range | Contents |")
w("|---|---|")
w("| `0x0000–0x7FFF` | Program RAM (EPROM shadow — reset copies the 32 KB image into DRAM bank `0xFF`, maps it here, runs from RAM) |")
w("| `0x0000` / `0x0038` | Reset entry / IM 1 interrupt vector (`fdc_isr`) |")
w("| `0x0100` | `main_entry` — post-relocation init and mode select |")
w("| `0x8000–0xFFFF` | Banked window — DRAM image bank selected by `OUT (0xB0)`; banks `0x00–0xFE` = disk image, `0xFF` = program mirror |")
w("")
w("**Declared data regions** (from the disassembler):")
w("")
w("| Range | Label | Notes |")
w("|---|---|---|")
for s, e, nm in sorted(z.DATA_REGIONS):
    d = desc(s)
    w("| `0x%04X–0x%04X` | `%s` | %s |" % (s, e, nm, d[:90]))
w("")
w("**I/O port map** (from the disassembler's `PORTS` table):")
w("")
w("| Port | Name |")
w("|---|---|")
for p in sorted(z.PORTS):
    w("| `0x%02X` | %s |" % (p, z.PORTS[p]))
w("")

# ---- Routine index ----
w("## 2. Routine index")
w("")
w("%d named routines (auto `loc_*` labels omitted), sorted by address. *Callers* is the" % len(named))
w("count of static call/branch sites into the routine.")
w("")
w("| Addr | Routine | Callers | Purpose |")
w("|---|---|---|---|")
for a in named:
    nm = addr_label[a]
    nc = len(callers.get(a, ()))
    w("| `0x%04X` | `%s` | %d | %s |" % (a, nm, nc, desc(a)[:110]))
w("")

# ---- Call graph ----
w("## 3. Call graph")
w("")
roots = [a for a in named if len(callers.get(a, ())) == 0 and callees.get(a)]
w("**Entry points / roots** (named routines with no static callers — reset, ISR, and")
w("computed-jump handlers):")
w("")
for a in roots:
    w("- `0x%04X` `%s`" % (a, addr_label[a]))
w("")
w("**Adjacency** — each named routine and the named routines it calls or jumps to")
w("(auto labels collapsed to their enclosing named routine where possible):")
w("")
for a in named:
    outs = sorted(callees.get(a, ()))
    names = []
    for t in outs:
        tn = addr_label.get(t)
        if tn and not is_auto(tn) and t != a:
            names.append(tn)
    names = sorted(set(names))
    if names:
        w("- `%s` → %s" % (addr_label[a], ", ".join("`%s`" % x for x in names)))
w("")

sys.stdout.write("\n".join(out) + "\n")
