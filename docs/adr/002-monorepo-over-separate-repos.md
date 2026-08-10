# ADR-002: Monorepo Over Separate Repos

**Date:** 2026-08-01  
**Status:** Accepted

## Context

The VitaCare project consists of multiple applications (caregiver mobile app, admin web dashboard, API server) and shared packages (constants, DTOs, utilities). The development team is 1-2 developers using AI-assisted development tools heavily.

We needed to decide between:
1. Separate repositories for each app/package
2. A single monorepo containing everything

## Decision

We will use a single monorepo managed with Melos (for Flutter/Dart packages) and npm workspaces (for TypeScript/Node packages).

Repository structure:
- `apps/` — contains all deployable applications
- `packages/` — contains shared code (Dart and TS)
- Top-level `melos.yaml` and `package.json` for workspace orchestration

## Consequences

**Positive:**
- AI coding assistants have full project context in a single repository, improving code generation quality
- Shared constants, types, and DTOs are defined once and imported everywhere
- Refactoring across app boundaries is a single atomic commit
- Easier to maintain consistency (linting, formatting, conventions) across the project
- Simpler dependency management — no versioning/publishing of internal packages

**Negative:**
- CI/CD pipelines are slightly more complex (must detect which apps changed)
- Repository size grows over time (mitigated by being a small team)
- All developers need tooling for both Flutter and Node.js installed locally
