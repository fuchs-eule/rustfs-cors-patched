# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Custom RustFS Docker build with two patches enabling browser-based S3 uploads via Uppy's `@uppy/aws-s3` plugin. For local dev/test only — production uses AWS S3 directly. Pinned to RustFS `1.0.0-alpha.82` (configurable via `RUSTFS_VERSION` build arg).

## Build & Push

Multi-arch image (arm64 + amd64) built locally on Apple Silicon Mac, pushed to GHCR.

```bash
# Build and push to ghcr.io/fuchs-eule/rustfs-cors-patched
./build-and-push.sh

# Force clean build (no layer cache)
./build-and-push.sh --no-cache

# Run locally for testing (API on :9000, console on :9001, creds: rustfsadmin/rustfsadmin)
docker run -d -p 9000:9000 -p 9001:9001 --name rustfs-test rustfs-cors-patched

# Verbose build output for debugging failures
docker build --progress=plain -t rustfs-cors-patched .

# Cleanup
docker rm -f rustfs-test
```

Prerequisites: Docker Desktop with Rosetta 2 enabled, `gh` CLI authenticated.

See README.md "Verify" section for curl commands testing both patches.

## Architecture

This is a patch-and-build project — no application source code. The Dockerfile clones upstream RustFS, applies two `.patch` files via `git apply`, and compiles a static Rust binary in a multi-stage Alpine build.

### The Two Patches

**Patch 1** (`patches/expose-location-header.patch`) — targets `rustfs/src/server/layer.rs`:
Adds `location` to the hardcoded CORS `Access-Control-Expose-Headers` list so browsers can read the Location header.

**Patch 2** (`patches/post-object-location-header.patch`) — targets `rustfs/src/storage/ecfs.rs`:
Adds a `Location: /{bucket}/{key}` header to POST Object responses (matching AWS S3 spec behavior). Captures the HTTP method before `req.input` is consumed by the handler.

### Why Both Are Needed

Uppy uploads via POST Object, then reads the `Location` response header to know the object URL. RustFS (1) doesn't include `Location` in POST Object responses, and (2) even if it did, the CORS middleware wouldn't expose it to browser JS.

## Updating Patches for a New RustFS Version

If `git apply` fails after bumping `RUSTFS_VERSION`, the surrounding source changed:

1. Clone the target RustFS version
2. Make the equivalent changes manually
3. Regenerate patches with `git diff`
4. Replace files in `patches/`
5. Rebuild and verify
