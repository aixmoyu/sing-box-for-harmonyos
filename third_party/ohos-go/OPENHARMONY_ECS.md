# OpenHarmony Go 1.25 toolchain for ECS

This branch provides the `openharmony/arm64` target and `c-shared` build mode
needed by ECS HarmonyOS applications while retaining the Go 1.25.12 standard
library and security fixes.

Provenance:

- Go 1.25.12 source release, upstream commit
  `d80d9a98f7047b55cd1e9d1b1018623b03cce59c`;
- OpenHarmony target support ported from OpenHarmony SIG
  `ohos_golang_go`, tag `go1.24.5.ohosv1r1` and its later OpenHarmony network
  fixes;
- ARM64 general-dynamic TLS and OpenHarmony pthread TSD integration required
  for shared libraries loaded after process startup;
- the ARM64 assembler opcode allocation was rebased to avoid the BTI opcode
  introduced by Go 1.25.

Build the host toolchain with:

```bash
cd src
GOTOOLCHAIN=local ./make.bash
```

Then build an OpenHarmony shared library with an OpenHarmony NDK compiler:

```bash
GOROOT="$PWD" GOTOOLCHAIN=local CGO_ENABLED=1 \
  GOOS=openharmony GOARCH=arm64 \
  CC=/path/to/aarch64-unknown-linux-ohos-clang \
  bin/go build -buildmode=c-shared ./path/to/package
```

The upstream Go license remains in `LICENSE`. The cited Go and OpenHarmony SIG
repositories retain the original commit and author history; this maintained
snapshot records their exact source revisions above.
