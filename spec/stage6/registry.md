# Loon Package Registry — Stage 6.2 Specification

## Overview

The Loon package registry has two tiers matching the MPLS License values:

**Official tier** — packages maintained by MPLS LLC. Reviewed, versioned, guaranteed to follow MPLS values. Cryptography, HTTP, JSON, standard library extensions.

**Community tier** — packages from the community. Same MPLS License requirement. Indexed but not reviewed by MPLS LLC.

## Package manifest: loon.pkg

```loon
name = "myapp";
version = "0.1.0";
author = "developer";
license = "MPLS-1.0";
main = "src/main.loon";
dependencies = ["crypto:0.2", "http:0.1"];
```

## CLI commands

```bash
loon init           # create new project with loon.pkg
loon add crypto     # add dependency
loon build          # compile with dependencies
loon test           # run tests
loon publish        # publish to registry
loon search json    # search packages
```

## Registry API

```
GET  /api/v1/packages              — list all packages
GET  /api/v1/packages/{name}       — package metadata
GET  /api/v1/packages/{name}/{ver} — specific version
POST /api/v1/packages              — publish (authenticated)
```

## Dependency resolution

Simple version pinning for v1. Each project has a `loon.lock` file with exact versions. Reproducible builds by default.

```
# loon.lock — auto-generated, committed to version control
crypto = "0.2.1"
http = "0.1.3"
json = "0.1.0"
```

## First official packages

1. **crypto** — Argon2id hashing, AES-256 encryption, token generation. Privacy-typed: `hash_password(Sensitive<String>) -> Hashed<String>`.

2. **http** — HTTP client and server. Effect-tracked: `http.get(url) [IO, Network] -> Result<Response, HttpError>`.

3. **json** — JSON parsing and serialization. Type-safe: `json.parse(s) -> Result<JsonValue, ParseError>`.

4. **env** — Environment variable access. Privacy-aware: `env.get("API_KEY") [IO] -> Option<Sensitive<String>>`.

## License enforcement

The registry verifies:
1. Every package declares MPLS-1.0 or compatible license
2. Package names don't conflict with official tier
3. Published packages have a valid loon.pkg manifest
4. Dependencies are all available in the registry

## Implementation Plan

### Phase 1: Registry server

1. Simple HTTP API (can be written in Loon with FFI for HTTP)
2. Package storage on disk (git-based, like crates.io index)
3. Authentication via GitHub OAuth

### Phase 2: CLI tool

1. `loon-pkg` already exists — extend with registry integration
2. `loon add` fetches from registry, stores in `.loon_packages/`
3. `loon publish` uploads to registry with authentication

### Phase 3: Official packages

1. Implement `crypto` with real Argon2id via FFI
2. Implement `http` via FFI to libcurl or native sockets
3. Implement `json` in pure Loon (no FFI needed)
