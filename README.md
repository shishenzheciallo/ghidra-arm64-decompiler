# Ghidra 12.1.4 native decompiler for Linux arm64 / aarch64

Official Ghidra releases ship the native `decompile` and `sleigh` binaries for
`linux_x86_64` and `win_x86_64` **only**. On an arm64 Linux host (or inside an
arm64 container such as proot on Android) `analyzeHeadless` imports and
disassembles fine, but any decompilation request fails with:

```
native_decompiler: executable_missing
Matching native decompiler for linux/arm64 was not found
```

This repository builds that missing piece from the Ghidra 12.1.4 sources.

## Result

`dist/decompile` — 3.8 MB, `ELF 64-bit LSB pie executable, ARM aarch64`,
built from `Ghidra/Features/Decompiler/src/decompile/cpp` at tag
`Ghidra_12.1.4_build`.

Verified end to end:

```
$ rea decompile ./hello --procedure main --provider ghidra
undefined8 main(void)
{
  puts("ok");
  return 0;
}
```

## Install

```bash
GHIDRA=/opt/ghidra_12.1.4_PUBLIC
mkdir -p "$GHIDRA/Ghidra/Features/Decompiler/os/linux_arm_64"
cp dist/decompile "$GHIDRA/Ghidra/Features/Decompiler/os/linux_arm_64/decompile"
chmod +x "$GHIDRA/Ghidra/Features/Decompiler/os/linux_arm_64/decompile"
```

Note the directory name: **`linux_arm_64`** (underscore). Ghidra's own build
layout uses `linux_x86_64`, and tools that look the directory up by the
`uname -m` style name expect `linux_arm_64`.

A JDK 21 is required to run Ghidra (`JAVA_HOME`), and Ghidra needs roughly
1 GB of heap for small binaries — set `GHIDRA_HEADLESS_MAXMEM=1024M` on
low-memory devices instead of the 2 GB default.

## Build from source

```bash
./scripts/build.sh /opt/ghidra-src          # source tree or tarball
```

The script does what is described below; read it before running.
Requirements: `clang` (18 tested), `make`, `bison`, `flex`, `zlib` headers,
and a JDK is *not* needed to build the decompiler itself.

Manual build:

```bash
# 1. get the sources
curl -L -o ghidra.tar.gz \
  https://github.com/NationalSecurityAgency/ghidra/archive/refs/tags/Ghidra_12.1.4_build.tar.gz
tar xzf ghidra.tar.gz
cd ghidra-Ghidra_12.1.4_build/Ghidra/Features/Decompiler/src/decompile/cpp

# 2. raise the stack limit — the default 8 MB is not enough for the template
#    instantiation depth in this codebase (cc1/clang both crash without it)
ulimit -s unlimited

# 3. the Makefile has no aarch64 branch (see "TODO: need to revise to support
#    arm64/aarch64 arch"), so the variables are overridden on the command line
make -j4 ARCH=aarch64 ARCH_TYPE= OSDIR=linux_arm_64 \
     CXX="clang++-18 -std=c++11" ghidra_opt
```

`ghidra_opt` is the release-mode target that produces the `decompile`
executable (the Makefile names the output `ghidra_opt`, not `decompile`).

### Two more things that will bite you

**The `depend` rule dies.** `com_opt/depend` and `com_dbg/depend` feed every
`.cc` file to a single compiler invocation:

```make
com_opt/depend: $(COMMANDLINE_NAMES:%=%.cc)
	$(CXX) -MM $(COMMANDLINE_OPT) $^ > $@.$$$$
```

On aarch64 that call segfaults (compiler ICE while parsing ~80 translation
units in one process). Create empty dependency files first so `make` skips the
rule, then compile file-by-file:

```bash
mkdir -p com_opt com_dbg && : > com_opt/depend && : > com_dbg/depend
for f in $(make -s --eval='p:;@echo $(GHIDRA_NAMES)' p); do
  clang++-18 -std=c++11 -c -O2 "$f.cc" -o "ghi_opt/$f.o" || echo "FAIL $f"
done
make ARCH=aarch64 ARCH_TYPE= OSDIR=linux_arm_64 CXX="clang++-18 -std=c++11" ghidra_opt
```

**Use clang, not GCC 14.** GCC 14.2 in an emulated/proot environment produced
random internal compiler errors (`version.h:48: internal compiler error:
Segmentation fault`) on the same file that succeeded a minute earlier. clang 18
compiled all 78 translation units on the first pass.

## CI

`.github/workflows/build.yml` builds this on a native arm64 runner
(`ubuntu-24.04-arm`), so a new Ghidra release only needs a trigger:

- **workflow_dispatch** — pass any `Ghidra_<version>_build` tag, artifact is
  uploaded to the run
- **push a `v<version>` tag** — builds and attaches the binary to a GitHub
  release automatically

The source tree is cached per tag, so repeat builds skip the ~80 MB download.
Cross-compilation is not an option here: the decompiler links against the host
`libstdc++`/glibc and Ghidra loads it as a native child process of the platform
it runs on, so the build must happen on the same architecture that runs it.

Builds are **not bit-reproducible** across hosts: the binary links against the
toolchain and glibc of the machine that produced it, so a CI artifact and a
locally built one differ in size and hash while behaving identically. Pin the
sha256 from the release you actually deploy.

## License

The decompiler sources are part of Ghidra, Copyright (c) 1999-2026
National Security Agency, licensed under the Apache License 2.0. This
repository redistributes a build product of those sources, so the binaries here
remain under Apache 2.0 — see `LICENSE` and `NOTICE`. No Ghidra source code is
modified; `decompile` is built from the unmodified release tag.
