# FlClash Subscription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Xray-equivalent manual subscription quota metadata and allow the Alpine subscription service to bind low internal ports.

**Architecture:** Keep the existing BusyBox httpd and `sbsub` service. Serve the generated YAML through a token-named CGI that emits validated `Subscription-Userinfo`; store provider plan and manual usage in private state files, and grant only the subscriber service bind capability.

**Tech Stack:** POSIX shell, BusyBox httpd, OpenRC, Alpine 3.23, Python build generator, existing shell/container regression tests.

**Spec:** `docs/superpowers/specs/2026-11-17-flclash-subscription-design.md`

## Global Constraints

- Alpine 3.23+, x86_64, OpenRC, 1 vCPU / 128 MiB target.
- No additional resident service or runtime dependency.
- Preserve `sbsub` privilege drop and private-key isolation.
- Public subscription remains HTTP with token path access control.
- Reset day is stored/displayed server-side; usage is a manually entered snapshot.
- Keep `src/alpine-singbox.sh.in` and generated `alpine-singbox.sh` synchronized.

## Review Focus

- Malformed plan or quota input must be rejected without replacing the active subscription.
- Invalid or absent quota data must not leak shell errors or expose private files.
- CGI must return the same valid YAML body and reject unknown token paths.
- Low-port binding must work as `sbsub` with only `CAP_NET_BIND_SERVICE`.
- Existing high-port installs and reruns must preserve keys, token, and public rules.

### Task 1: Plan and quota header

**Files:**
- Modify: `src/alpine-singbox.sh.in`
- Modify: `tests/test-install.sh`
- Modify: `tests/test-rules.sh` or add a focused subscription test
- Generate: `alpine-singbox.sh`
- Modify: `README.md`, `docs/design.md`

- [x] Add failing regression for plan parsing, CGI quota headers, body, and bad token.
- [x] Add failing regression for `sb-admin --plan` and `--quota` snapshot behavior.
- [x] Implement private plan storage, validation, CGI response, and admin actions.
- [x] Regenerate installer and run focused Alpine regression.

### Task 2: Low internal subscription ports

**Files:**
- Modify: `src/alpine-singbox.sh.in`
- Modify: `tests/test-install.sh`
- Generate: `alpine-singbox.sh`
- Modify: `README.md`

- [x] Add failing validation and service-start regression with an internal port below 1024.
- [x] Remove only the `>=1024` restriction and request `CAP_NET_BIND_SERVICE` for `sbsub`.
- [x] Regenerate installer and run full Alpine regression with 1 CPU / 128 MiB.

### Task 3: Project records and checkpoint

**Files:**
- Modify: Obsidian project current state, progress, and issue archive.

- [ ] Record the reported FlClash failure without its tokenized URL.
- [ ] Record implementation evidence, unresolved public NAT/FlClash acceptance, and next action.
- [ ] Review scope and commit the verified task as `checkpoint: ...`.
