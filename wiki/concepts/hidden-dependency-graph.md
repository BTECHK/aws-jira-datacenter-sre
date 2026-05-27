---
type: concept
title: "Hidden Dependency Graph (fix the trunk, not the leaves)"
tags: [operations, gotcha]
created: 2026-05-26
updated: 2026-05-26
sources: [phase-1-redmine-debrief]
---

# Hidden Dependency Graph

The headline operational lesson from Phase 1: most of the hard problems standing up legacy software are not single bugs but **hidden couplings** — implicit dependencies between files, services, and versions. The skill is reading that graph and fixing at the **shared root** instead of patching each symptom.

## The canonical example

A Rails app boots through several entry points — `rake` (via `Rakefile`), `rails server` (via `bin/rails`), and Puma (via `config.ru`). Each walks a *different* chain of `require`s before the framework loads, but they converge on a common chokepoint (`config/application.rb → require "rails" → ActiveSupport → Ruby's Logger`).

- Patch a **leaf** (e.g. add `require "logger"` to the `Rakefile`) → only that one entry point works; the web server still crashes because it never touches the Rakefile.
- Fix the **trunk** (pin the dependency, or require it once at the common ancestor) → all entry points work.

The specific break: `concurrent-ruby` 1.3.5 stopped auto-loading Ruby's `Logger` that Rails 6.1 silently depended on — so a fresh `bundle install` pulled a *newer* sub-dependency that broke a *pinned* old app.

## Generalizable principles

- **A version pin is a contract with the entire dependency tree** — including the transitive parts you didn't pin. A point release of a sub-dependency can break a five-year-old app.
- **Find the shared chokepoint.** In layered systems, fix the common ancestor rather than whack-a-moling every leaf.
- **Small infra changes have non-local effects.** Moving Redmine's port from 3000→3001 forced a security-group change to allow 3001 — trace a change all the way to the edge.
- **Identity consistency.** Running "just this one step" as root poisons later steps (root-owned config a service user then can't rewrite). Stay consistent about *who* runs each command.
- **Stop the loop before debugging.** `Restart=always` relaunches a unit that fails on boot; `systemctl stop` first or you read stale failures.

## Source

Drawn from [[phase-1-redmine-debrief]]; manifested concretely on [[redmine]].
