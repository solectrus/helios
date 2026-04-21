# ADR-0010: Authentication Model

## Context

HELIOS manages a SOLECTRUS installation and has full access to the Docker socket. Only the operator of the host should be able to reach it. Options considered:

1. Full user system (Devise, multiple users, roles)
2. HTTP Basic Auth at the reverse-proxy layer
3. Single shared admin password, managed by HELIOS itself
4. No authentication (rely on LAN-only access)

HELIOS is a single-user admin tool — there are no roles, no per-user state, no audit trail requirements beyond what Docker itself logs.

## Decision

Use a **single admin password**, stored as plain text in `config.yaml` under `system.admin_password`, verified via `ActiveSupport::SecurityUtils.secure_compare`, with a boolean `session[:authenticated]` flag in the Rails session cookie.

- If `system.admin_password` is blank, authentication is skipped entirely (useful for local development and first-run setup).
- The password is also exported as `ADMIN_PASSWORD` in `.env` and reused by the Dashboard and Ingest services, so the whole stack shares a single admin credential.
- No user model, no database table, no password reset flow — the user edits `config.yaml` or uses the Settings UI.

See [authentication.rb](../../app/controllers/concerns/authentication.rb) and [sessions_controller.rb](../../app/controllers/sessions_controller.rb).

## Consequences

**Positive:**

- Minimal surface area — no Devise, no migrations, no email flows
- One credential for the whole SOLECTRUS stack
- Works offline, no external identity provider
- First-run setup is trivial (no password = no login wall)

**Negative:**

- Plain-text password at rest in `config.yaml` — acceptable because `config.yaml` already holds other secrets (DB password, InfluxDB token, `SECRET_KEY_BASE`) and is only readable by the host operator
- No per-user audit trail
- No multi-user support — out of scope for a home-lab admin tool
- Password change requires editing config or using the Settings UI; no "forgot password" flow
