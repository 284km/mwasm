# PAIN log — mwasm dogfood

Friction hit building a **WASM binary inspector** in Mere. Chosen to attack
binary handling: a .wasm file starts with a NUL byte (`\0asm`), the exact
thing C strings hate. Each entry is a signal for a language / runtime
improvement.

Status legend: 🔴 open · 🟡 worked around · 🟢 fixed upstream

---

## P1 🟢 No way to learn a binary file's length natively (fixed upstream, mere v0.1.21)

Measured first (the surprise): `read_file` on a .wasm is **binary-safe in
the interpreter** (`str_len` = true size, `char_at`/`ord` correct past
NULs), and even on the C backend the *buffer* holds every byte and
`char_at` indexes past the NUL correctly. The one thing that breaks
natively is **length**: `str_len` is `strlen`, which stops at the leading
NUL and answers 0. With no way to know how many bytes were read, a binary
walk can't even bound its loop — and there is no `file_size` either:

```
let n = file_size path in ...   // type error: unbound variable: file_size
```

**Signal (upstream):** add `file_size : str -> int` (stat's `st_size`,
next to the existing `file_mtime`). With (buffer, size) carried explicitly,
the existing NUL-safe `char_at`/`ord` make binary parsing expressible —
no full bytes type needed yet.

**Fixed upstream (mere v0.1.21):** added `file_size : str -> int` (stat's
`st_size`, next to `file_mtime`), interp + C. Carrying `(buffer, size)`
explicitly, the NUL-safe `char_at` / `ord` / `substring` make the whole
inspector expressible.

## (M1/M2) 🟢 positive: binary parsing needed no more language changes

After `file_size`, section walking (LEB128 sizes) and export dumping
(length-prefixed names + kind/index) hit **no further friction**:

- **LEB128 without bit ops**: `b % 128` (low 7 bits) + `b >= 128`
  (continuation) decodes unsigned LEB128 with plain arithmetic — Mere has
  no bitwise operators, and none were needed.
- **NUL-safe throughout**: `char_at` / `ord` / `substring` and building a
  name char-by-char (`acc ++ char_at b i`) all work past embedded NULs, on
  interp and native identically. Verified against `wasm-objdump -h/-x`:
  same 10 sections and same 4 exports (name, kind, index).

A dedicated `bytes` type stays deferred — the honest edge is bitwise ops
(would be nicer than `%`/`/` for flags) and the fact that `str` is
implicitly a byte buffer here rather than validated UTF-8. Neither blocked
this tool.
