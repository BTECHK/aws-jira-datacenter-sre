---
type: source
title: "Phase 1 Debrief — Standing Up Redmine"
tags: [operations, gotcha]
authors: [project-author]
url: null
raw: docs/lessons/phase-1-redmine-debrief.md
ingested: 2026-05-26
created: 2026-05-26
updated: 2026-05-26
sources: []
---

# Source: Phase 1 Debrief — Standing Up Redmine

A field report on installing Redmine 5.1 on its own EC2 behind nginx on shared RDS Postgres. ~10 failed starts before boot; none were "big" bugs — every one was a **hidden coupling**. The real skill was reading the dependency graph between files and fixing at the shared root, not patching each symptom.

## The headline lesson

A Rails app boots through several entry points (`rake`, `rails server`, Puma via `config.ru`), each walking a different chain of `require`s. Patching a leaf (e.g. the `Rakefile`) fixes only that entry point; the web server still crashes because it boots through `config.ru → config/environment.rb → config/application.rb`. The fix that mattered was at the **common ancestor** (the dependency itself). See [[hidden-dependency-graph]].

## Failures, in order (symptom → root cause → fix)

1. `Bundler::PermissionError` on system gem cache → non-root `redmine` user can't write it → `bundle config set --local path 'vendor/bundle'`.
2. Bundle setting wouldn't stick → `.bundle/config` was root-owned from an earlier `sudo` step → `chown -R redmine:redmine`, then set as `redmine`.
3. `uninitialized constant ...Logger` → `concurrent-ruby` 1.3.5 stopped auto-loading Ruby's `Logger` that Rails 6.1 silently depended on → pin `concurrent-ruby 1.3.4` (or `require "logger"` early).
4. Error "came back" after each fix → multiple entry points → fix the common ancestor.
5. `command not found: puma` → Redmine 5.1 lists `puma` only in its `:test` group, which had been excluded via `--without` → add `gem "puma"` via `Gemfile.local`.
6. systemd `Assignment outside of section` → pasted the entire `sudo tee <<EOF` command *as file content* while already root.
7. `Address already in use ... port 3000` → Gitea already on 3000 on the same box → move Redmine to 3001 (and open 3001 in the SG — see below).
8. Crash loop `start request repeated too quickly` → `Restart=always` relaunching a unit failing on boot → `systemctl stop` first, then debug.

## The box mix-up (topology gotcha)

The lab provisions 4 EC2s (public proxy + one each for gitea/redmine/xwiki). Both the Gitea and Redmine steps were run on the **same** box, so they ended up co-located on `mds-tools-redmine` (`10.20.10.106`, Gitea :3000 + Redmine :3001) while the dedicated `mds-tools-gitea` box (`.146`) sits empty. It works, but the lesson: **always confirm which host you're on before a per-host step** (cross-check the SSM prompt IP against `terraform output app_private_ips`). Knock-on: moving Redmine's port forced a security-group change to allow 3001 — a small change with a non-local effect. See [[redmine]] and [[hidden-dependency-graph]].

## Reusable checklist

Confirm the box before per-host steps · stay one identity per sequence · install gems to a path the service user owns · read Gemfile groups before `--without` · old app + fresh deps ⇒ suspect transitive breakage, pin it · fix the common ancestor · `systemctl stop` before debugging a crash loop · one port per service per box (and update the SG).
