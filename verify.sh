#!/bin/sh
# verify.sh -- mwasm against wasm-objdump, on modules from two different
# producers.
#
# THE README ALREADY MAKES THE CLAIM: "Output matches `wasm-objdump -h/-x`".
# This runs it. The oracle is wabt's objdump -- a different implementation of
# the same reading, written by other people -- so a disagreement is one of the
# two being wrong rather than a change from a recording of mwasm's own past
# output, which could catch a change and never a mistake.
#
# NOT A TEXT DIFF. The two print different formats (`section 1 (type): 87
# bytes` against `Type ... (size=0x57)`), so each side is parsed into the FACTS
# -- which sections, how big, which exports with which kind and index -- and
# the facts are compared. test/compare.py does that, and holds its own
# extractors to finding something, because two empty lists agree.
#
# THE MODULES COME FROM TWO PRODUCERS. Mere's own Wasm backend, because that is
# what mwasm was written to read; and hand-written .wat through wat2wasm, to
# reach sections Mere does not emit -- start, a custom section, a data segment
# without a memory import. One producer would test one shape of module.
#
#   MERE=/path/to/mere sh verify.sh
#
# Needs wasm-objdump and wat2wasm (wabt) and python3. Skips loudly without the
# oracle: a differential with one side missing is not a weaker test.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
MERE="${MERE:-mere}"
CC="${CC:-clang}"
command -v "$MERE" >/dev/null 2>&1 || { echo "verify: no mere -- set MERE=/path/to/mere.exe" >&2; exit 1; }
command -v "$CC"   >/dev/null 2>&1 || { echo "verify: no C compiler -- set CC" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "verify: no python3 (the comparator)" >&2; exit 1; }
command -v wasm-objdump >/dev/null 2>&1 || { echo "verify: SKIP -- no wasm-objdump, and it is the oracle"; exit 0; }
command -v wat2wasm     >/dev/null 2>&1 || { echo "verify: SKIP -- no wat2wasm, and the modules come from it"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$MERE" -c "$ROOT/main.mere" > "$TMP/mw.c" 2>"$TMP/emit.err" \
  || { echo "verify: mere -c failed"; sed -n '1,3p' "$TMP/emit.err"; exit 1; }
"$CC" -O2 -w "$TMP/mw.c" -o "$TMP/mwasm" 2>"$TMP/cc.err" \
  || { echo "verify: the emitted C did not compile"; sed -n '1,3p' "$TMP/cc.err"; exit 1; }
MW="$TMP/mwasm"

pass=0; fail=0; saw_sections=0
check() {
  if out="$(python3 "$ROOT/test/compare.py" "$MW" "$1" 2>&1)"; then
    pass=$((pass + 1)); echo "$out"
    case "$out" in *" 0 sections"*) : ;; *" sections"*) saw_sections=1 ;; esac
  else
    fail=$((fail + 1)); echo "$out"
  fi
}

# --- producer 1: Mere's own Wasm backend ------------------------------------
mk_mere() {  # mk_mere <name> <source>
  printf '%s\n' "$2" > "$TMP/$1.mere"
  if "$MERE" -w "$TMP/$1.mere" > "$TMP/$1.wat" 2>"$TMP/$1.emit.err" \
     && wat2wasm --enable-tail-call --enable-threads "$TMP/$1.wat" -o "$TMP/$1.wasm" 2>"$TMP/$1.w2.err"; then
    check "$TMP/$1.wasm"
  else
    echo "  skip  $1.wasm (Mere backend refused it: $(head -1 "$TMP/$1.emit.err" "$TMP/$1.w2.err" 2>/dev/null | tr '\n' ' ' | cut -c1-60))"
  fi
}
mk_mere tiny     'print "hi"'
mk_mere arith    'let add = fn (a: int) -> fn (b: int) -> a + b;
print (str_of_int (add 2 40))'
mk_mere strings  'let s = str_repeat "ab" 8;
print (s ++ "|" ++ str_of_int (str_len s))'
mk_mere adt      'type t = A | B of int;
let f = fn (x: t) -> match x with | A -> 0 | B n -> n;
print (str_of_int (f (B 7)))'

# --- producer 2: hand-written wat, for sections Mere does not emit -----------
cat > "$TMP/rich.wat" <<'W'
(module
  (type (func (param i32) (result i32)))
  (memory 1)
  (table 2 funcref)
  (global $g (mut i32) (i32.const 7))
  (func $sq (type 0) (local.get 0) (local.get 0) (i32.mul))
  (start $start)
  (func $start)
  (elem (i32.const 0) $sq)
  (data (i32.const 0) "hi")
  (export "sq" (func $sq))
  (export "mem" (memory 0))
  (export "g" (global $g)))
W
wat2wasm "$TMP/rich.wat" -o "$TMP/rich.wasm" && check "$TMP/rich.wasm"

cat > "$TMP/bare.wat" <<'W'
(module)
W
wat2wasm "$TMP/bare.wat" -o "$TMP/bare.wasm" && check "$TMP/bare.wasm"

cat > "$TMP/noexport.wat" <<'W'
(module
  (func $priv (result i32) (i32.const 1)))
W
wat2wasm "$TMP/noexport.wat" -o "$TMP/noexport.wasm" && check "$TMP/noexport.wasm"

# Section 13, the tag section, which exception handling introduced and Wasm 3.0
# standardised. Nothing else here reaches it: Mere's backend does not emit tags,
# and none of the wat above declares one. A reader whose section table stops at
# 12 calls this "unknown" and stays green forever, because no module in the
# corpus ever asked it the question.
cat > "$TMP/tag.wat" <<'W'
(module
  (tag $e (param i32))
  (func (export "f") (try (do (throw $e (i32.const 1))) (catch $e (drop)))))
W
wat2wasm --enable-exceptions "$TMP/tag.wat" -o "$TMP/tag.wasm" && check "$TMP/tag.wasm"

# --- and the two things a reader has to refuse ------------------------------
# A file that is not a module at all. mwasm checks the magic, so it must say so
# rather than reporting sections it invented from whatever bytes were there.
printf 'this is not a wasm module at all, not even close' > "$TMP/notwasm.bin"
if "$MW" "$TMP/notwasm.bin" >"$TMP/nw.out" 2>&1; then
  case "$(cat "$TMP/nw.out")" in
    *section*) echo "  FAIL  magic         listed sections in a file with no wasm header"; fail=$((fail + 1)) ;;
    *)         echo "  ok    magic         refused a non-module"; pass=$((pass + 1)) ;;
  esac
else
  echo "  ok    magic         refused a non-module"; pass=$((pass + 1))
fi

# The per-file comparator can only say whether the two readers AGREE, and two
# empty lists agree. So the suite asks the other half of the question once: at
# least one module has to have yielded sections, or every comparison above was
# between two silences.
if [ "$saw_sections" -eq 0 ]; then
  echo "verify: no module yielded any section -- the extractors saw nothing and agreed about it"
  fail=$((fail + 1))
fi

echo "verify: $pass passed, $fail failed  (oracle: $(wasm-objdump --version))"
[ "$fail" -eq 0 ]
