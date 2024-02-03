---
date: 2024-02-01T15:43:00-08:00
tags: cross-compile,rust,go,zig
title: Cross-compiling Rust
---

At $dayjob my team writes a bunch of CLI tools in Rust (and a few various tools in Go) that we need to run in a wide variety of environments:

* x86-64 for Linux (GNU libc), MacOS and Windows (ideally with MinGW)
* aarch64/arm64 for Linux (GNU libc) and MacOS

For a long time this has meant we spin up a whole bunch of CI machines, one for each platform, and compile the tools natively for that platform. However, this is not the best option available for us.  Since we manage our own runner pools (using GitHub Actions), this means we need to maintain sets of these machines, and as far as MacOS and Windows we're relying on the public runner pool infrastructure, which is both more costly and disallows us from accessing internal company systems.  (This has started to become a problem as we need to access Rust crates which are published internally to build some of these tools!). However, Rust and Go are supposed to be pretty good at handling cross-compiling, so lets give this a shot!

We already "cross-compile" some of our work, as we write HTTP Proxy filters in Rust and compile them to WASM based on the [proxy-wasm](https://github.com/proxy-wasm/spec) spec. So, my naïve first attempt was as simple as installing the Rust toolchain for a given platform triple (why it's a triple when there are more than three items in sometimes?) and give it a go. (I'm running this all on an x86_64 Debian machine, so package names will be specific to that platform.)h

```bash
rust up target add x86_64-pc-windows-gnu
cargo build ---target x86_64-pc-windows-gnu

error: failed to run custom build command for `ring v0.17.5`

Caused by:
  process didn't exit successfully: `/root/top-secret-work-project/target/debug/build/ring-9e2d74aa803932bf/build-script-build` (exit status: 1)
  --- stdout
  # output elided...
  running: "x86_64-w64-mingw32-gcc" "-O0" "-ffunction-sections" "-fdata-sections" "-gdwarf-2" "-fno-omit-frame-pointer" "-m64" "-I" "include" "-I" "/root/top-secret-work-project/target/x86_64-pc-windows-gnu/debug/build/ring-8250d53ba97b24ed/out" "-Wall" "-Wextra" "-fvisibility=hidden" "-std=c1x" "-pedantic" "-Wall" "-Wextra" "-Wbad-function-cast" "-Wcast-align" "-Wcast-qual" "-Wconversion" "-Wenum-compare" "-Wfloat-equal" "-Wformat=2" "-Winline" "-Winvalid-pch" "-Wmissing-field-initializers" "-Wmissing-include-dirs" "-Wnested-externs" "-Wredundant-decls" "-Wshadow" "-Wsign-compare" "-Wsign-conversion" "-Wstrict-prototypes" "-Wundef" "-Wuninitialized" "-Wwrite-strings" "-g3" "-DNDEBUG" "-o" "/home/todd/top-secret-work-project/target/x86_64-pc-windows-gnu/debug/build/ring-8250d53ba97b24ed/out/crypto/curve25519/curve25519.o" "-c" "crypto/curve25519/curve25519.c"

  --- stderr


  error occurred: Failed to find tool. Is `x86_64-w64-mingw32-gcc` installed?
```

Oh no! What's this "Is `x86_64-w64-mingw32-gcc` installed?" Wait, why are we calling `gcc`? I thought this was Rust?!

Well, it is rust, but it looks like we're actually compiling some crypto library written in C and then accessing it from Rust. So our Rust toolchain needs to be able to invoke a functional C compiler for our target platform. Well, `clang` is supposed to be cross-platform out of the box right? Lets give that a shot, and tell `cargo` that we want to use `clang` as our C compiler.

```bash
CC=clang cargo build --target x86_64-pc-windows-gnu

# bunch of log lines omitted

  cargo:warning=In file included from crypto/curve25519/curve25519.c:22:
  cargo:warning=In file included from include/ring-core/mem.h:60:
  cargo:warning=In file included from include/ring-core/base.h:64:
  cargo:warning=In file included from /usr/lib/llvm-15/lib/clang/15.0.7/include/stdint.h:52:
  cargo:warning=/usr/include/stdint.h:26:10: fatal error: 'bits/libc-header-start.h' file not found
  cargo:warning=#include <bits/libc-header-start.h>
  cargo:warning=         ^~~~~~~~~~~~~~~~~~~~~~~~~~
  cargo:warning=1 error generated.
```

OK! Well `clang` certainly does invoke and there's no more complaints about missing a gcc compiler, but we are missing some standard libraries, which is going to be a common theme if you're not compiling pure-Rust related software. We could try to figure out to install just the support libraries for our target system, but there are a bunch of packages that supply a full cross-platform toolchain. So lets stop messing around and just install the [`mingw-w64` package](https://packages.debian.org/bookworm/mingw-w64) from Debian (which, if you'll note, has `gcc-mingw-w64` listed as a dependency).

```bash
apt install mingw-w64
cargo build --target x86_64-pc-windows-gnu
#[lots of compiling going on]

todd@cross:~/top-secret-work-project# file target/x86_64-pc-windows-gnu/debug/top-secret-work-project.exe
target/x86_64-pc-windows-gnu/debug/.exe: PE32+ executable (console) x86-64, for MS Windows, 21 sections
```

OMG. That one was really easy -- once we got the right toolchain installed. Lets try something a little closer to home and see if we can `aarch64` for Linux. If we try that old `clang` trick again, we'll see we're missing support libraries for that target as well.  Unfortunately these packages aren't all named similarly or this would be easier, but we'll search the packages for bookworm for `aarch64 gcc` and we'll find out there is a [`gcc-aarch64-linux-gnu`](https://packages.debian.org/bookworm/gcc-aarch64-linux-gnu) package. So lets install that and see what we get!

```bash
apt install gcc-arch64-linux-gnu
cargo build --target aarch64-unknown-linux-gnu
#[again there is a lot of compiling]

          /usr/bin/ld: /root/top-secret-work-project/target/aarch64-unknown-linux-gnu/debug/deps/frontdoor_ops-89e314a14d73e562.105y1p0cy3ffj42o.rcgu.o: error adding symbols: file in wrong format
          collect2: error: ld returned 1 exit status
```

Well, you should have known better when I ended that previous sentence so optimistically that it wasn't going to work right off the bat! It looks like our linker `ld` is not the proper linker for this platform. Why Cargo can figure out to tell `rustc` to use the proper c compiler for the arch, but not the proper linker is beyond me, but we can actually just tell Cargo to tell `rustc` which linker to use with `RUSTFLAGS="-Clinker=[path to linker]"`. Thankfully when we installed the `aarch64` cross compile toolchain, we also got a proper linker for that platform, `aarch64-linux-gnu-ld`, so lets give this a shot.


```bash
RUSTFLAGS="-Clinker=aarch64-linux-gnu-ld" cargo build --target aarch64-unknown-linux-gnu
#[compiler nonsense]
  = note: aarch64-linux-gnu-ld: cannot find -lgcc_s: No such file or directory
```

I have no clue why this happens here, but the problem is that it's trying to find `libgcc_s.so` and its unable to find it because it's not installed in the normal system library search path. Again, why it's able to figure out the compiler but nothing else is annoying, but we can solve this with _another_ flag passed in via `RUSTFLAGS`: `-L [path to directory]`. And, again, when we installed the proper toolchain we actually got these files. On Debian they're in `/usr/lib/gcc-cross/aarch64-linux-gnu/12/`, so we'll try this again!

```bash
RUSTFLAGS="-Clinker=aarch64-linux-gnu-ld -L /usr/lib/gcc-cross/aarch64-linux-gnu/12/" cargo build --target aarch64-unknown-linux-gnu
#[again a lot of messages]
todd@cross:~/top-secret-work-project# file target/aarch64-unknown-linux-gnu/debug/top-secret-work-project
target/aarch64-unknown-linux-gnu/debug/top-secret-work-project: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, with debug_info, not stripped
```

Oh my! Would you look at that! We've got three of our target platforms so far, the last one must be really easy right?

_[laughs in bsd]_

Well, sadly, no. This is where things get really complex. We want to compile for MacOS, but like there's no MacOS toolchain for Debian (or any other linux as far as I can tell?) Thankfully this is where the community comes in with [osxcross](https://github.com/tpoechtrager/osxcross) which is a set of tools for extracting and building a valid toolchain for cross-compiling for MacOS from Linux and BSD! You'll need an Apple account for this and you'll need to ensure you're using your software under the terms of the license Apple provides for it's SDKs. (I am not a lawyer, but I'm pretty sure if you're building software designed to run on their computers with their SDK, that's kind of the point.)

Follow the instructions on that project to build your toolchain. It will take some time. (It's OK, I'll be here when you get back.)

OK?

OK. Done! Great job!

We've now got a lot of tools with a lot of really long names, and thankfully we've already learned how to provide alternatives to `rustc` and `cargo`, however, we're going to need to provide a few more to make this work properly. And since we have to override both the C compiler and the linker, we'll actually alter the path here too so we don't have to type it out several times.

```bash
PATH=[path to osx sdk]/bin:$PATH LD_LIBRARY_PATH=[path to osx sdk]/lib:$LD_LIBRARY_PATH CC=x86_64-apple-darwin22.4-clang RUSTFLAGS="-Clinker=x64_64-apple-darwin22.4-clang -Clink-arg=-undefined -Clink-arg=dynamic_lookup" cargo build --target x86_64-apple-darwin
#[again with the compiling]
todd@cross:~/top-secret-work-project# file target/x86_64-apple-darwin/debug/top-secret-work-project
target/x86_64-apple-darwin/debug/top-secret-work-project: Mach-O 64-bit x86_64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE|HAS_TLV_DESCRIPTORS>
```

You might notice a few things here: we added an `LD_LIBRARY_PATH` -- this is similar to the `-L` we passed into the `RUSTFLAGS` section before, because, once again, we have an entire set of library files that we need to link with for the platform. We also passed in `clang` as both our compiler and our linker because it works. I don't make the rules, but it's pretty easy this way at least. Finally we also passed in some specific `link-arg` flags as well -- these get passed to the linker as additional flags for it. The cool part about the MacOS stuff is that the SDK we build with osxcross has both aarch64 AND x86_64 binaries in it, so we just change the name of the C compiler and linker here to make an `aarch64` version of this library:

```bash
PATH=/root/macos-13.4/bin:$PATH CC=aarch64-apple-darwin22.4-clang LD_LIBRARY_PATH=/root/macos-13.4/lib:$LD_LIBRARY_PATH RUSTFLAGS="-Clinker=aarch64-apple-darwin22.4-clang -Clink-arg=-undefined -Clink-arg=dynamic_lookup" cargo build --target aarch64-apple-darwin
#[come on compile!]
todd@cross:~/top-secret-work-project# file target/aarch64-apple-darwin/debug/top-secret-work-project
target/aarch64-apple-darwin/debug/top-secret-work-projects: Mach-O 64-bit arm64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE|HAS_TLV_DESCRIPTORS>
```

And there we go, our `target/` directory we've now got `arch64-apple-darwin`, `aarch64-unknown-linux-gnu`, `debug`, `x86_64-apple-darwin`, `x86_64-pc-windows-gnu` (where `debug` is our native target).

If you wanted to compile on `aarch64` linux, you'd need the `gcc-x86-64-linux-gnu` package instead, but the rest of the targets and instructions should remain the same.
