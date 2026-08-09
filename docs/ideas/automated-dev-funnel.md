# Automated dev funnel on GitHub — options, costs, decision

> **Status: evaluated 2026-08-09. Decided NOT to build.** Nothing here is implemented.
> Captured so the research doesn't have to be redone. The two things that *are* worth doing
> are at the bottom under [What we do instead](#what-we-do-instead).

## The brief

> "what's the claude way of dealing with github issues? i would like to have the process of
> take issue → write tests → implement → review with browser → review code. but each stage is
> it's own agent. and automatic. and the issue agent will first do the analysis and planning
> and ask questions. so basically i can run everything in GH without opening claude on my pc
> at all."

## Requirements (as they ended up)

Stated up front:

1. **Stages are separate agents** — analyse → tests → implement → browser check → code review.
2. **Issue-driven**, with the first stage doing analysis/planning and *asking questions* before
   any code is written.
3. **Automatic** — label/event driven, not hand-run.
4. **No PC required** — drive it all from GitHub.

Added during the discussion:

5. **Claude must actually run things** — boot the server, run `mix test`, drive the UI. A
   read-only "comment on the diff" agent is not enough.
6. **One environment, one framework.** Not three places to configure.
7. **Control** over each stage's prompt and model.
8. **Live server URL on the PR** so the UI can be eyeballed without checking anything out.
9. **An orchestrator, not a dumb chain.** If the implementer discovers the tests are wrong, the
   run must not stop dead — something has to *reason* about whether the tests should change,
   rather than the implementer quietly rewriting them into a comfy bed.
10. **Cheap.**

Relaxed or dropped as we went:

- **~10s replies to issue comments** — dropped. Only reachable with a resident process on a warm
  box; 30–60s accepted, then moot once the whole thing was dropped.
- **"No PC"** — this dissolved. See [Decision](#decision).

## Options surveyed

| # | Option | Where it runs | Verdict |
|---|---|---|---|
| A | Claude Code GitHub Actions | ephemeral GH runners | viable, cold |
| B | Claude Code Routines | Anthropic cloud | no issue trigger |
| C | Copilot coding agent / Agent HQ | GitHub cloud | can't express stages |
| D | GitHub Agentic Workflows (`gh-aw`) | GH Actions | closest declarative fit |
| E | OpenAI Codex | OpenAI cloud | loses our skills |
| F | OpenHands / SWE-agent | self-hosted | turnkey-ish, own format |
| G | Sprite + webhook listener | Fly Sprite | fits Sprites, DIY plumbing |
| H | Always-on VPS + self-hosted runner | Hetzner ~€5/mo | **best of the lot** |

### A — Claude Code GitHub Actions (`anthropics/claude-code-action@v1`)

Two modes: *interactive* (no `prompt` input → waits for `@claude`, replies as a comment) and
*automation* (`prompt` input → headless on any event).

- **+** Reuses `CLAUDE.md`, `.claude/skills/`, `docs/design.md` unchanged — the single biggest
  asset we have. Checkout gives every stage our house rules for free.
- **+** `/install-github-app` does the whole setup in one command.
- **+** Free logs, re-run, concurrency groups, secrets, timeouts.
- **−** Ephemeral. **Nothing stays resident**; every stage pays a cold Elixir compile.
- **−** You pay wall-clock *including the time Claude spends thinking*.

### B — Claude Code Routines

Saved prompt + repos + cloud environment + triggers, on Anthropic infra. Research preview.

- **+** Zero YAML, zero machine, cached setup script.
- **−** **GitHub triggers are `pull_request.*` and `release.*` only. There is no issue trigger.**
  Requirement 2 is unreachable natively; you'd need an Actions workflow curling the `/fire`
  endpoint, i.e. two systems.
- **−** Per-account (not team), hourly webhook caps, daily run cap, pushes only to `claude/*`.

### C — Copilot coding agent / Agent HQ

Assign an issue to an agent, get a PR. Agent HQ (public preview Feb 2026) fans one issue out to
Claude/Codex/Copilot in parallel for comparison.

- **+** Lowest setup of anything. $10/mo Copilot Pro; $39/mo Pro+ for third-party agents.
- **−** One agent, one task. The staged tests-first funnel isn't expressible.

### D — GitHub Agentic Workflows (`gh-aw`)

Workflows written in Markdown, compiled to Actions lockfiles. Agent-agnostic (Copilot / Claude /
Codex / Gemini per workflow). Read-only by default, writes via sanitized "safe outputs". Public
preview June 2026.

- **+** Multi-stage chaining is first-class rather than hand-rolled with labels.
- **+** Cheap model for triage, Opus for implementation, no rewiring.
- **−** Another abstraction layer on top of Actions; preview-stage churn.

### E — OpenAI Codex

`@codex` on an issue/PR, cloud tasks, Code reviews tab, `AGENTS.md`.

- Functionally parallel to A/B. No advantage for staging, and we'd re-encode everything that
  currently lives in `CLAUDE.md` + skills.

### F — OpenHands / SWE-agent

- **OpenHands Resolver**: label an issue → sandboxed Docker runtime → PR. MIT, BYOK. The real
  open-source answer to issue→PR.
- **SWE-agent**: Princeton, minimal, a building block rather than a product.
- **−** Own memory/config format; we'd lose the skills.

### G — Sprite + webhook listener

Fly Sprite (persistent Firecracker VM, checkpoint/restore) with a small HTTP listener that
shells out to `claude -p` per webhook.

- **+** Inbound webhook is *exactly* how Sprites wake. Fits the platform.
- **+** Fastest possible (~5–20s, all model time). ~$1–3/mo idle.
- **−** You write and maintain the listener, the worktree lifecycle, and all the monitoring.
- **−** Inbound endpoint that triggers agent runs on a box holding the repo and secrets.
- **−** No logs, no re-run, no concurrency control, no timeouts unless you build them.

### H — Always-on VPS + self-hosted Actions runner ← would have been the pick

Hetzner CX22 (~€5/mo) running the GitHub Actions runner daemon, with warm `deps/` + `_build/`,
postgres and the chromium sidecar in docker.

- **+** Same warm box as G, but the dispatcher is `apt install` + a systemd unit instead of code.
- **+** **Outbound HTTPS only** — no inbound port, no HMAC, no security surface.
- **+** All the Actions plumbing for free; state machine visible in the PR UI.
- **+** Self-hosted runners are free (see findings).
- **−** ~30–60s per stage vs ~5–20s. Accepted.

## Key findings

The expensive, non-obvious, perishable bits. These are the reason this doc exists.

1. **Nothing runs "at all times" in GitHub Actions.** Every job allocates a fresh VM, clones,
   installs, runs, and is destroyed. For Colt (postgres + full Elixir compile + assets +
   chromium) that's **3–8 minutes before Claude says a word**, per stage.

2. **`actions/checkout` defaults to `clean: true`**, which runs `git clean -ffdx` and therefore
   **deletes `deps/` and `_build/`** — they're gitignored. On a self-hosted runner you must set
   `clean: false` or your warm box is cold on every job. This one line is the entire performance
   premise of option H.

3. **One runner instance runs one job at a time.** Jobs serialize automatically, so an MVP needs
   *no* worktrees and *no* `MIX_TEST_PARTITION`. Add a second runner for parallelism and *then*
   you need both (see the known shared-`colt_test` collision).

4. **Fly Sprites sleep after 30s of inactivity and cannot wake themselves.** They wake on inbound
   HTTP to port 8080. An Actions runner polls *outbound* — so **Sprite + self-hosted runner is
   broken**: the box sleeps, the daemon stops polling, jobs queue forever, nothing wakes it.
   Waking it from a hosted "wake job" that curls the Sprite half-works but adds unpredictable
   runner-reconnect delay, risks sleeping mid-job, and rebuilds the listener you were avoiding.
   **Sprites ⇒ webhook listener. Runner daemon ⇒ always-on VPS.** The choice is coupled.

5. **Claude Code has no inbound event socket.** It's an interactive REPL blocked on its own turn
   loop; you cannot poke a webhook into a running session. The only real shapes are `claude -p`
   (headless, one-shot), `--resume`, and `/loop` (self-polling). "Keep Claude running at all
   times" is not a thing — keep the *box* warm, spawn a process per event.

6. **Subagents of one session are not independent stages.** They share the parent's framing, so
   a reviewer spawned by the session that just implemented will rubber-stamp, and a test-writer
   spawned by a parent already planning the implementation writes tests to fit it. Real
   independence needs **separate processes reading state from GitHub** (issue body, PR diff).
   This fails silently — you just get reviews that always approve.

7. **A Fly preview URL decouples browser review from the runner entirely.** Once
   `colt-pr-123.fly.dev` exists, Claude can run on a throwaway hosted runner and point Playwright
   at it. This removes the *only* capability that required a warm box.

8. **Fly Managed Postgres starts at $38/mo** — more than everything else combined. For previews
   use a plain postgres machine (~$5.70/mo, one `colt_pr_<n>` db per PR), or better, put postgres
   *inside* the preview machine so it scales to zero as a unit (fresh seeded data per preview is
   a feature, not a bug).

9. **Actions gotchas that silently break chains:**
   - The action rejects bot actors by default. Stage N's output won't trigger stage N+1 unless
     the bot is listed in `allowed_bots`. #1 cause of chains that don't fire.
   - Don't pass `github_token: ${{ secrets.GITHUB_TOKEN }}` — pushes made with it don't retrigger
     workflows, so CI never runs on Claude's commits. Let it auth as the Claude GitHub App.

10. **Preview apps run the prod release**, so `System.fetch_env!` in `runtime.exs` crashes the
    boot on any credential you don't set. And the agent needs `/dev/mailbox` exposed to do the
    magic-link login — gate that on an env var, not `Mix.env()`.

## Costs

Rates verified 2026-08-09.

| Item | Rate |
|---|---|
| Actions, Linux 2-core | **$0.006/min** (cut from $0.008 Jan 2026); 2,000 free min/mo private repo |
| Actions, self-hosted runner | **$0** — a $0.002/min fee was announced Dec 2025 and withdrawn in 48h |
| Fly preview app running | ~$0.008/hr (shared-cpu-1x 1GB, scale-to-zero) |
| Fly preview app idle | $0.15/GB/30d rootfs → ~$0.15/mo per open PR |
| Fly plain postgres machine | ~$5.70/mo |
| Fly Managed Postgres | $38/mo — avoid |
| Hetzner CX22 | ~€5/mo |
| Claude tokens | $0 marginal on subscription (`CLAUDE_CODE_OAUTH_TOKEN`) |

Runner minutes per issue, all five stages: **~26–52 min** (implement dominates at 10–25). At ~35
min average that's **$0.21/issue**; the free tier covers ~55 issues/month.

| Issues/mo | Actions | Fly | Total |
|---|---|---|---|
| 10 | $0 | ~$7 | ~$7 |
| 30 | $0 | ~$7 | ~$7 |
| 100 | $9 | ~$8 | ~$17 |

With postgres inside the preview machine, the 10–30/mo rows drop to **~$1/mo**.

**The real cost is not money.** Tokens come off the subscription, so the constraint is usage
limits — and **five stages means five cold contexts**, each re-reading `CLAUDE.md` and re-grepping
the codebase. That's 30–50% more tokens than doing the same work in one warm local session.

## Paid alternatives

| Product | Price | Shape |
|---|---|---|
| GitHub Agent HQ | $10/mo Pro; $39/mo Pro+ for third-party agents | assign issue → PR, inside GitHub |
| Devin (Cognition) | from $20/mo ACU-based; Teams $80 + $40/seat | own VM, browser, terminal — closest single product |
| OpenHands Cloud | free tier upward | hosted OSS, label issue → PR |

None run Colt's environment. Our conventions live in `CLAUDE.md` / `.claude/skills/` /
`docs/design.md`; each platform wants them re-encoded in its own format. Browser review needs the
chromium sidecar and `/dev/mailbox`. And all of them bill compute on top of the Claude
subscription we already pay for.

## Decision

**Not building any of it.**

Two reasons, the second being the deeper one:

1. **Every option buys asynchrony — work happening while away from the machine.** The original
   premise was "run everything in GH without opening claude on my pc." In practice I'm at the pc
   anyway, and I review the output either way. Once that premise goes, the funnel is strictly
   worse than a local session: slower, more tokens (finding 6 above), and a box to maintain.

2. **The whole shape presumes a PR-based flow we don't have.** Colt is a solo repo committed
   straight to master. issue → PR → review → merge is a *collaboration protocol*. That's not a
   tooling gap to close; it's just not the situation.

Had we built it, the pick was **H — Hetzner box + self-hosted Actions runner**, with the build
stage as a single orchestrator job (satisfying requirement 9) and review as a separate job for
independence (finding 6).

## What we do instead

1. **Three local prompts for stage separation.** The one thing a single session genuinely can't
   give you is a reviewer who doesn't share the implementer's framing. Write tests → implement →
   review as three explicit prompts. Worth folding into a skill so it's one command rather than a
   remembered sequence. ~20 minutes, not an architecture.

2. **A `mix test` CI workflow.** Orthogonal to all of the above and currently missing —
   `.github/workflows/` contains only `fly.yml` (deploy on push to `production`). Postgres service
   container, `erlef/setup-beam` pinned to `.tool-versions` (erlang 27.2 / elixir 1.18.1-otp-27),
   `actions/cache` on `deps` + `_build`. ~30 lines, useful whether or not an agent touches the repo.

## Revisit when

- Work needs kicking off from a phone / away from the desk.
- Someone else joins the repo, and a PR flow appears for real reasons.
- Three or more issues run in parallel often enough that serialized local sessions are the
  bottleneck (at which point: finding 3 — multiple runners, worktrees, `MIX_TEST_PARTITION`).

## Sources

- [Claude Code GitHub Actions](https://code.claude.com/docs/en/github-actions) ·
  [claude-code-action](https://github.com/anthropics/claude-code-action)
- [Claude Code Routines](https://code.claude.com/docs/en/routines)
- [GitHub Agentic Workflows](https://github.com/github/gh-aw) ·
  [technical preview changelog](https://github.blog/changelog/2026-02-13-github-agentic-workflows-are-now-in-technical-preview/)
- [GitHub Actions 2026 pricing changes](https://github.com/resources/insights/2026-pricing-changes-for-github-actions)
- [Fly resource pricing](https://fly.io/docs/about/pricing/) · [Managed Postgres](https://fly.io/docs/mpg/) ·
  [Sprites](https://fly.io/sprites/)
