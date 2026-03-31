# ADR-0007: Technology Stack

## Status

Accepted

## Context

Helios needs a technology stack for building a web-based Docker management interface. Key requirements:

- Lightweight (runs on Raspberry Pi)
- Modern UI without heavy JavaScript frameworks
- Good Docker ecosystem support
- Maintainability by a small team

## Decision

| Component     | Choice                     | Rationale                                         |
| ------------- | -------------------------- | ------------------------------------------------- |
| Language      | Ruby 4                     | Mature, expressive, good for rapid development    |
| Framework     | Ruby on Rails 8.1          | Convention over configuration, batteries included |
| Frontend      | Hotwire (Turbo + Stimulus) | SPA-like UX without heavy JS, Rails-native        |
| CSS Framework | TailwindCSS 4              | Utility-first, small bundle, rapid prototyping    |
| UI Components | DaisyUI                    | Pre-built components on top of Tailwind           |
| Asset Bundler | Vite (via rails_vite)      | Fast builds, modern tooling                       |
| Database      | SQLite                     | No extra container, single file, easy backup      |
| Testing       | RSpec                      | Expressive, widely used in Ruby community         |

## Consequences

**Positive:**

- Full-stack Ruby means single language for backend and views
- Hotwire eliminates need for separate frontend build/deploy
- SQLite keeps resource usage minimal
- Rails generators speed up development
- Large ecosystem of gems available

**Negative:**

- Ruby is slower than Go/Rust (acceptable for this use case)
- Team must know Ruby (but that's given for SOLECTRUS)
