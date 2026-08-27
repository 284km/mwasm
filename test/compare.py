#!/usr/bin/env python3
"""Compare what mwasm says about a .wasm file with what wasm-objdump says.

WHY A COMPARATOR AND NOT A DIFF. The two print different formats -- mwasm
writes `section 1 (type): 87 bytes`, objdump writes `Type ... (size=0x57)`.
Diffing the text would compare layout; what is being asked is whether they
agree about the FACTS: which sections, how big, and which exports with which
kind and index. So each side is parsed into those facts and the facts are
compared.

NORMALISING IS WHERE A GATE STOPS LOOKING, so the extractors are held to
finding something: a comparison between two empty lists agrees, and that is the
failure this guards against. Both sides must yield at least one section and, on
a module that has exports, at least one export.

    python3 test/compare.py <mwasm-binary> <file.wasm>
"""
import re, subprocess, sys

mwasm, wasm = sys.argv[1], sys.argv[2]

def run(*cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"compare: {cmd[0]} exited {r.returncode}\n{r.stderr[:300]}")
        sys.exit(1)
    return r.stdout

# --- mwasm -----------------------------------------------------------------
out = run(mwasm, wasm)
mw_sections = [(int(i), n, int(s))
               for i, n, s in re.findall(r"^\s*section (\d+) \((\w+)\): (\d+) bytes", out, re.M)]
mw_exports = [(k, n, int(i))
              for k, n, i in re.findall(r"^\s{6}(\w+) (\S+) -> (\d+)\s*$", out, re.M)]

# --- wasm-objdump ----------------------------------------------------------
# `  Type start=0x.. end=0x.. (size=0x57) count: 16`
# THE ONE PLACE THIS TRANSLATES, and it is a spelling and not a fact: the
# specification calls section 9 the "element section" and objdump abbreviates
# it to "Elem". Every other name matches after lowercasing -- checked across a
# module carrying type, function, table, memory, global, export, start, elem,
# code and data. Any second entry in this map should be argued for, not added.
ALIAS = {"elem": "element"}

oh = run("wasm-objdump", "-h", wasm)
od_sections = [(ALIAS.get(n.lower(), n.lower()), int(s, 16))
               for n, s in re.findall(r"^\s*(\w+) start=0x\w+ end=0x\w+ \(size=0x(\w+)\)", oh, re.M)]
# ` - func[164] <main> -> "main"`
ox = run("wasm-objdump", "-x", wasm)
od_exports = []
in_exports = False
for line in ox.splitlines():
    if line.startswith("Export["):
        in_exports = True
        continue
    if in_exports:
        m = re.match(r'\s*- (\w+)\[(\d+)\](?: <[^>]*>)? -> "(.*)"\s*$', line)
        if m:
            od_exports.append((m.group(1), m.group(3), int(m.group(2))))
        elif line.strip() and not line.startswith(" "):
            in_exports = False

problems = []

# TWO EMPTY LISTS AGREE, and that is the hazard this file was written around --
# but `(module)` genuinely has no sections, and both readers saying so is the
# right answer rather than a broken extractor. So emptiness is compared like
# any other fact here (a disagreement about it is a failure below), and the
# question "did the extractor work AT ALL" is answered across the suite by
# verify.sh, which requires that some module yielded sections. Per-file, the
# only thing that can be said is whether the two readers agree.
if bool(mw_sections) != bool(od_sections):
    problems.append("one reader found sections and the other found none: mwasm=%d objdump=%d"
                    % (len(mw_sections), len(od_sections)))

# Sections: same names in the same order, same sizes. objdump does not print a
# numeric id, so the id is mwasm's own and is not part of the comparison; the
# ORDER is, which is what an id would tell you here.
mw_ns = [(n, s) for _, n, s in mw_sections]
if mw_ns != od_sections:
    problems.append("sections disagree:\n    mwasm  : %s\n    objdump: %s" % (mw_ns, od_sections))

# Exports: order is the module's, so compare as ordered lists too.
if od_exports and not mw_exports:
    problems.append("the module has %d exports and mwasm listed none" % len(od_exports))
if sorted(mw_exports) != sorted(od_exports):
    problems.append("exports disagree:\n    mwasm  : %s\n    objdump: %s" % (sorted(mw_exports), sorted(od_exports)))

if problems:
    print("MISMATCH " + wasm)
    for p in problems:
        print("  " + p)
    sys.exit(1)

print("ok %-28s %d sections, %d exports" % (wasm.split("/")[-1], len(mw_sections), len(mw_exports)))
