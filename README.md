# mwasm

A WASM binary inspector written in [Mere](https://github.com/merelang/mere)
and compiled to a native binary (`mere -c | clang`).

```
$ mwasm module.wasm
wasm module: module.wasm (5322 bytes, version 1)
  section 1 (type): 51 bytes
  section 2 (import): 153 bytes
  ...
  section 7 (export): 59 bytes
    exports (4):
      memory memory -> 0
      func main -> 71
  section 10 (code): 4841 bytes
```

It checks the `\0asm` magic + version, lists every section (id, name,
size), and expands the export section (name, kind, index). Output matches
`wasm-objdump -h/-x`.

## Why this exists — and the meta bit

`mwasm` is a dogfood app for Mere, chosen to attack **binary handling**: a
.wasm file starts with a NUL byte, exactly what C strings choke on.
Building it motivated Mere's `file_size` builtin (v0.1.21) — see
[PAIN.md](./PAIN.md).

The meta part: Mere's own compiler emits WebAssembly (`mere -w`), so
`mwasm` reads the binaries Mere produces:

```
mere -w prog.mere | wat2wasm --enable-tail-call - -o prog.wasm
mwasm prog.wasm
```

Notes: LEB128 sizes are decoded with plain arithmetic (`% 128`, `>= 128`) —
Mere has no bitwise operators and needed none. All byte access is NUL-safe
via `char_at` / `ord`, so `str` doubles as a byte buffer here.

## Build

```
mere -c main.mere > m.c && clang -O2 m.c -o mwasm
```

## Roadmap

- [x] M0: magic + version
- [x] M1: section listing (id, name, LEB128 size)
- [x] M2: export section contents (name, kind, index)
- [ ] M3: import section / function-count summary (maybe)
