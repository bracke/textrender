# Agent Instructions

This repository requires Alire GNAT 15. The root and tests crates pin
`gnat_native = "=15.2.1"`.

Do not run plain system `gnat*`, `gnatmake`, `gnatls`, `gnatprove`, or
`gprbuild` in this workspace. Use `alr exec -- ...` for compiler and builder
commands.

Preferred validation:

```sh
alr exec -- gnatls --version
alr build
alr exec -- gprbuild -P textrender.gpr
cd tests && alr build
cd tests && ./bin/tests
alr test
```
