# PAIN log — mwasm dogfood

Friction hit building a **WASM binary inspector** in Mere. Chosen to attack
binary handling: a .wasm file starts with a NUL byte (`\0asm`), the exact
thing C strings hate. Each entry is a signal for a language / runtime
improvement.

Status legend: 🔴 open · 🟡 worked around · 🟢 fixed upstream

---

## P1 🔴 No way to learn a binary file's length natively

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
