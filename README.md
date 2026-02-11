# RustFS CORS-patched

Custom RustFS build with two patches for browser-based direct-to-S3 uploads (Uppy / `@uppy/aws-s3`). **For local dev/test only** — production uses AWS S3 directly.

Based on RustFS `1.0.0-alpha.82` (pinned in Dockerfile via `RUSTFS_VERSION` build arg).

## Problem

Uppy's `@uppy/aws-s3` plugin uses POST Object (presigned multipart form) to upload files directly from the browser. After upload, it reads the `Location` header from the response to determine the object URL. Two RustFS bugs break this flow:

1. **CORS doesn't expose `Location`** — The system-level CORS middleware (`ConditionalCorsLayer` in `layer.rs`) hardcodes `Access-Control-Expose-Headers` to `x-request-id, content-type, content-length, etag`. The browser can't read `Location`. The bucket-level CORS API (`PutBucketCors`) exists but only applies to GET/HEAD — not PUT/POST (incomplete since alpha.80).

2. **POST Object doesn't return `Location`** — RustFS routes POST Object through the same `put_object` handler as PUT. The response never includes a `Location` header, unlike AWS S3 which returns it per spec.

## Patches

### Patch 1: `patches/expose-location-header.patch`

Adds `location` to the hardcoded CORS expose-headers list in `rustfs/src/server/layer.rs`:

```diff
- HeaderValue::from_static("x-request-id, content-type, content-length, etag"),
+ HeaderValue::from_static("x-request-id, content-type, content-length, etag, location"),
```

### Patch 2: `patches/post-object-location-header.patch`

Adds a `Location` header to POST Object responses in `rustfs/src/storage/ecfs.rs`:

- Imports `Method` from `http` crate
- Captures `is_post = req.method == Method::POST` before `req.input` is moved
- When `is_post`, sets `Location: /{bucket}/{key}` on the response

## Pull the image

```bash
docker pull ghcr.io/fuchs-eule/rustfs-cors-patched:latest
```

## Build and push

Builds a multi-arch image (arm64 + amd64) locally on an Apple Silicon Mac and pushes to GHCR. Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/) with Rosetta 2 enabled and the [GitHub CLI](https://cli.github.com/) (`gh`).

**One-time setup:** Docker Desktop > Settings > General > "Use Rosetta for x86_64/amd64 emulation on Apple Silicon"

```bash
./build-and-push.sh
```

Force a clean build (no layer cache):

```bash
./build-and-push.sh --no-cache
```

To build a different RustFS version, update `RUSTFS_VERSION` in the Dockerfile (patches may need updating). If `git apply` fails during the build, the surrounding source changed and the patches need regenerating.

## Image registry

Public on GHCR: `ghcr.io/fuchs-eule/rustfs-cors-patched`

Tags:
- `:latest` — most recent build
- `:<version>` — matches the `RUSTFS_VERSION` build arg (e.g. `:1.0.0-alpha.82`)

## Verify

Start the patched image and run these curl commands to confirm both patches work.

```bash
# Start RustFS
docker run -d -p 9000:9000 --name rustfs-test rustfs-cors-patched

# Wait for health
for i in $(seq 1 30); do curl -sf http://localhost:9000/health && break; sleep 1; done

# Create a test bucket
curl -s -X PUT http://localhost:9000/test-bucket \
  --user rustfsadmin:rustfsadmin \
  --aws-sigv4 "aws:amz:us-east-1:s3"

# --- Patch 1: CORS expose-headers includes "location" ---
curl -sv -X OPTIONS http://localhost:9000/test-bucket/test.txt \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: POST" \
  2>&1 | grep -i "access-control-expose-headers"
# Expected: access-control-expose-headers: x-request-id, content-type, content-length, etag, location

# --- Patch 2: POST Object returns Location header ---
curl -sv -X POST http://localhost:9000/test-bucket \
  -H "Origin: http://localhost:3000" \
  -F "key=test.txt" \
  -F "file=@/tmp/test-upload.txt" \
  --user rustfsadmin:rustfsadmin \
  --aws-sigv4 "aws:amz:us-east-1:s3" \
  2>&1 | grep -i "^< location:"
# Expected: < location: /test-bucket/test.txt

# Cleanup
docker rm -f rustfs-test
```

