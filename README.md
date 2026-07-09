# Textrender

Textrender renders TrueType glyphs into a monospace text atlas for editor-style
rendering.

## Toolchain

Textrender must be built and validated with Alire GNAT 15. The root and tests
crates pin `gnat_native = "=15.2.1"`. Confirm with:

```sh
alr exec -- gnatls --version
```

Do not run plain system `gnat*`, `gnatmake`, `gnatls`, `gnatprove`, or
`gprbuild` in this workspace. Use `alr exec -- ...` for compiler and builder
commands so PATH cannot select a different GNAT installation.

## Build And Test

```sh
alr build
alr exec -- gprbuild -P textrender.gpr
cd tests && alr build
cd tests && ./bin/tests
alr test
```
