---
date: 2024-02-01T15:43:00-08:00
tags: cross-compile,rust,go
title: Cross-compiling Go (and a follow up about Rust)
---

Observant readers may have noticed that the URL for the previous post included a `go` in part of it; I had originally intended to cover this at the end of the previous post. Given how long that post ended up being, here's the follow-up.

We _also_ have a small amount of Go software to maintain, namely, and the reason this is important, a [Fluent-Bit](https://fluentbit.io) output plugin. This plugin needs to be compiled to a shared C library, so again, like our Rust issue being related to the fact that we are consuming undelying C libraries, with this we are emitting a C library, which means we aren't able to use the Go cross-platform functionality as is included out of the box.

This also dovetails nicely with someone pointing out that we could have just used [`cargo-zigbuild`](https://github.com/rust-cross/cargo-zigbuild/) to handle our cross-platform tooling. While I chose to figureout the issues by hand, partly to understand what is required to make all of this work, but also partly to understand how you can interact with the underlying compiler invoked by Cargo, this tool exists and looks to solve many of these issues as well.

This tool relies on the fact that [Zig](https://ziglang.org) includes a complete C and C++ compiler in its toolset, which, like Clang, is already cross-platform aware. (Interestingly they have a specific [workaround to deal with gcc_s](https://github.com/rust-cross/cargo-zigbuild/blob/main/src/zig.rs#L90-L93) replacing it with [libunwind](https://github.com/libunwind/libunwind). Unfortunately replacing specific flags (or omitting them) with the linker invoked via Rust seems to be only possible if you dive into the world of [`build scripts`](https://doc.rust-lang.org/cargo/reference/build-scripts.html)).

This fact about Zig is pretty cool (and in fact one of the earlier attempts I made for Rust substituted `zig cc` for `clang` and `ld` as well). This is also incredibly useful when trying to get Go to output a shared library for a different platform.

Usually when you cross-compile Go for a different arch or platform you use `GOOS` and `GOARCH` to control what it's outputting. If you're not using CGO at all, this is pretty cool. However, if you're using CGO, you're gonna have to do some work. Luckily, just like with Rust we can override the C compiler we want to invoke:

```bash
CGO_ENABLED=1 GOARCH=amd64 GOOS=linux CC="zig cc -target aarch64-linux-gnu" go build -buildmode=c-shared -o top-secret-go-project
```

Thankfully what we're building here has miminal requirements so we're not messing around with linking or anything else.a
