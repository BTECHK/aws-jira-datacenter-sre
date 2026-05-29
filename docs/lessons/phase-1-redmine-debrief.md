# Phase 1 Debrief — Standing Up Redmine (the hard one)

*A field report from the OSS-toolchain build. Written for my own reference — and as raw material for interview stories and a LinkedIn post. Skim the bold lines; the dots underneath are the detail.*

---

## TL;DR
- **Goal:** install Redmine 5.1 (deliberately old) on its own EC2, behind nginx, on a shared RDS Postgres.
- **Reality:** ~10 failed starts before it booted. None were "big" bugs — every one was a **hidden coupling**: a non-root service account that couldn't write where a tool assumed it could, a dependency that quietly stopped loading another, a gem hiding in the wrong group, and a chain of config files that each invoke the next.
- **The actual skill** wasn't any single command. It was learning to **read the dependency graph between files** and fix at the shared root instead of patching each symptom.

---

## The one thing that was genuinely hard (my interview answer)

> The hardest part wasn't a command — it was the **implicit dependency graph**. A Rails app boots through several *entry points* — `rake`, `rails server`, and Puma (via `config.ru`) — and **each walks a different chain of `require`s** before the framework even loads. So when I patched a missing `require "logger"` into the `Rakefile`, the web server *still* crashed: it boots through `config.ru → config/environment.rb → config/application.rb`, which never touches the Rakefile. I was fixing leaves of a tree without seeing the trunk. The breakthrough was mapping those load paths and fixing at the **common ancestor** (the dependency itself), not at each entry point.

**Why one fix didn't cover everything:**
```
            three ways the app gets started
   rake task         rails server          Puma (systemd)
      |                   |                     |
   Rakefile           bin/rails             config.ru
      |                   |                     |
      +---------+---------+----------+----------+
                v                    v
         config/application.rb  <-- the common chokepoint
                |
         require "rails" -> ActiveSupport -> needs Ruby's Logger
                ^
   concurrent-ruby USED to load Logger for free... until v1.3.5 stopped.
```
- Patch a **leaf** (Rakefile) → only that one entry point works.
- Fix the **trunk** (pin the dependency, or require it once in `config/application.rb`) → all of them work.

---

## What actually went wrong, in order
*(symptom → root cause → the real fix → the lesson)*

1. **`Bundler::PermissionError` writing to `/usr/share/ruby3.2-gems/cache`**
   - Root cause: the non-root `redmine` user can't write the *system* gem cache.
   - Fix: `bundle config set --local path 'vendor/bundle'` → gems land in the app dir it owns.
   - **Lesson:** a service account only owns its app dir. Point tools at paths it owns.

2. **The setting wouldn't stick (`BUNDLE_PATH` kept missing from `.bundle/config`)**
   - Root cause: `.bundle/config` was **root-owned** from an earlier command I ran as root, so the `redmine` user couldn't rewrite it.
   - Fix: `chown -R redmine:redmine /opt/redmine-app`, then set config as `redmine`.
   - **Lesson:** running "just this one step" as root poisons later steps. Stay consistent about *who* runs each command.

3. **`uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger`**
   - Root cause: `concurrent-ruby` 1.3.5 (Jan 2025) stopped auto-loading Ruby's `Logger`, which Rails 6.1 silently depended on. A fresh `bundle install` pulled the newer concurrent-ruby into an old app.
   - Fix: pin `concurrent-ruby 1.3.4` in `Gemfile.local` (clean), or `require "logger"` early.
   - **Lesson:** old software is a contract with its *entire* dependency tree. A *newer* sub-dependency can break a *pinned* app. **This is the "hidden dependency" in one sentence.**

4. **The same error "came back" after each fix**
   - Root cause: multiple entry points (Rakefile, `bin/rails`, `config.ru`) each load the app differently.
   - Fix: fix the common ancestor (see the diagram above).
   - **Lesson:** in layered systems, find the shared chokepoint instead of whack-a-moling every leaf.

5. **`Could not find server ""` then `command not found: puma`**
   - Root cause: Redmine 5.1 lists `puma` only in its **`:test`** group, and I'd excluded test gems (`bundle config --without 'development test'`). The web server I told systemd to run wasn't installed.
   - Fix: add `gem "puma"` via `Gemfile.local`.
   - **Lesson:** "skip dev/test" can drop something production actually needs. Read the Gemfile's groups before excluding any.

6. **systemd logged `Assignment outside of section. Ignoring.`**
   - Root cause: I pasted the *entire* `sudo tee <file> <<'EOF' … EOF` **command** into the file as text. I was already root, so the heredoc wrapper became file content.
   - Fix: rewrite the file cleanly (already root → a plain editor or `cat >` is enough).
   - **Lesson:** know whether you're *piping into* a file or *typing the command that does the piping*. `sudo tee … <<EOF` is for when you're **not** already root.

7. **`Address already in use … port 3000`**
   - Root cause: Gitea was already on 3000 **on the same box** (I'd installed both tools on one EC2 — see topology below).
   - Fix: move Redmine to **3001**.
   - **Lesson:** one port per service per box. If you colocate services, they need distinct ports *and* the firewall must allow each.

8. **Crash loop — `start request repeated too quickly`**
   - Root cause: `Restart=always` kept relaunching a unit that failed on boot, so the logs scrolled with repeats.
   - Fix: `systemctl stop` **first**, fix the real cause, *then* start.
   - **Lesson:** stop the loop before you debug, or you're reading stale failures.

---

## The box mix-up (topology — a lesson on its own)

- The lab provisions **4 separate EC2s**: a public proxy + one box each for gitea / redmine / xwiki, each with its own private IP.
- I connected over SSM and ran **both** the Gitea (Step 4) and Redmine (Step 5) steps on the **same** box. So Gitea + Redmine ended up co-located on `mds-tools-redmine` (`10.20.10.106`), and the dedicated `mds-tools-gitea` box (`.146`) sits empty.
- It still works (Gitea `:3000`, Redmine `:3001`, nginx points both at `.106`), but the takeaway is real:

> **Always confirm which host you're on before a per-host step.** The SSM shell prompt shows the box's private IP (`ip-10-20-10-106`). Cross-check it against `terraform output app_private_ips` *before* running anything.

```
Internet --> proxy (10.20.1.112, public)   nginx + TLS
                |  git.lab.local     --> 10.20.10.106:3000  (gitea)
                |  redmine.lab.local --> 10.20.10.106:3001  (redmine)
                |  wiki.lab.local    --> 10.20.10.244:8080  (xwiki, own box)
    mds-tools-gitea (10.20.10.146)  <-- provisioned but empty
```
- Knock-on: moving Redmine to `3001` means the **app security group** (was: allow only `3000`/`8080` from the proxy) must also allow `3001`, or nginx can't reach it. One port change rippled into the firewall — that's the kind of downstream coupling that's invisible until it bites.

---

## Concept primers (the stuff I was pasting without fully understanding)

### systemd / systemctl / journalctl
- **systemd** is PID 1 — it starts and supervises long-running services. A **unit file** (`/etc/systemd/system/X.service`) declares *how* to run X.
- `systemctl daemon-reload` — re-read unit files after editing one.
- `enable` (start on every boot) vs `start` (start right now). `--now` does both. `disable`/`stop` are the inverses.
- `journalctl -u X -f` — follow live logs; `-n 50` shows the last 50 lines.
- Unit anatomy:
```
[Unit]    After=network.target      # ordering: don't start until network is up
[Service] User=redmine              # run as this unprivileged account
          WorkingDirectory=/opt/... # the process's cwd
          ExecStart=...             # the actual command to run
          Restart=always            # relaunch on crash (this is what crash-loops)
[Install] WantedBy=multi-user.target # hook into normal multi-user boot
```

### Bundler & gem groups (Ruby's dependency manager)
- `bundle install` reads the `Gemfile` and installs the gems.
- `--without 'development test'` skips those **groups** (don't do it if a group holds something prod needs — e.g. puma).
- `--local path 'vendor/bundle'` installs *inside* the app dir (so a non-root user can write).
- `Gemfile.local` (a Redmine convenience) lets you add/pin gems **without editing Redmine's own Gemfile**.
- `bundle exec X` runs `X` with exactly the app's locked gem versions.

### sed (the one-liners I ran blind)
- `sed -i 's/foo/bar/' file` — in-place, replace first `foo` with `bar` per line. `-i` = edit the file in place.
- `sed -i '1a TEXT' file` — append `TEXT` **after** line 1.
- `sed -i '/pattern/d' file` — delete every line matching `pattern`.
- The gotcha I hit: `sed '1s/^/X\n/'` inserts `X` *before* line 1 — which shoved the `#!/usr/bin/env ruby` shebang to line 2 and broke the script. **The shebang must be line 1.**

### File ownership & permissions
- `chown user:group file` — sets owner / group. `chmod 640` = owner read+write, group read, others nothing (use for secrets like `database.yml`). `644` = world-readable (fine for systemd units, which root reads).
- Rule of thumb: **files the app reads → owned by the app user; files systemd reads → owned by root.**

---

## Checklist so I don't repeat this
- [ ] Confirm the box (prompt IP vs `terraform output app_private_ips`) before a per-host step.
- [ ] Stay one identity per sequence (don't `sudo` one step and `sudo -u` the next).
- [ ] For a service user: install gems to a path it owns (`--local path vendor/bundle`).
- [ ] Read the Gemfile's groups before `--without`.
- [ ] Old app + freshly-resolved deps → suspect transitive breakage; pin it.
- [ ] One fix at the common ancestor beats N fixes at the leaves.
- [ ] `systemctl stop` before debugging a crash-looping unit.
- [ ] One port per service per box — and remember the firewall/SG when you change one.

---

## LinkedIn / interview soundbites (lift these)
- *"Most of my time went to invisible problems — a dependency that stopped loading another, a gem in the wrong group, a service account that couldn't write where a tool assumed it could. The visible commands were the easy 10%."*
- *"The fix that mattered was conceptual: map the load path, fix the shared root, stop patching symptoms. Once I saw that `rake`, `rails server`, and Puma each booted through a different chain, the recurring error finally made sense."*
- *"Running old software on a modern OS taught me that a version pin is a contract with the whole dependency tree — including the transitive parts you didn't pin. A point release of `concurrent-ruby` is what actually broke a five-year-old Rails app."*
- *"Small infra changes have non-local effects: moving one service's port also meant opening it in the security group. I learned to trace a change all the way to the edge."*
