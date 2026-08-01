# Copilot instructions — lead_engine workspace

## Always build before deploy

Before running `vercel deploy --prod` (or any production deploy) for **any**
project in this workspace, run a full local production build first and confirm
it succeeds. Do not skip this step even for "small" CSS / copy / one-line
changes — Next.js catches issues like missing Suspense boundaries, RSC export
errors, and type regressions only at build time.

Workflow:

1. `cd <project>` (e.g. `closet-dashboard`, `closet-widget`, `basic-closet-demo`)
2. `npm run build` — must exit 0 with no errors.
3. Only then: `vercel deploy --prod --yes --no-wait`

If the build fails, fix the errors and re-build. Never deploy a broken build
and rely on Vercel's remote builder to surface the same error — that wastes
build minutes and clutters the deployment history with failed/queued entries.

When invoking deploys via a subagent, the subagent must run `npm run build`
first and only proceed to `vercel deploy` if the build succeeded.

## Deploy command discipline

- Use `vercel deploy --prod --yes --no-wait` so the CLI returns immediately
  after upload. Vercel will continue building remotely.
- Run the deploy command **exactly once**. Do not retry on apparent hangs or
  SIGINT — Ctrl-C only kills the local watcher, not the remote build. Multiple
  invocations create cascading queued deployments that all eventually build
  and waste build minutes.
- After deploy, optionally poll status with `vercel list <project-name>`
  (non-streaming) rather than re-running deploy.

## Always migrate, commit, and push completed work

For every completed coding task, finish the repository workflow instead of
leaving changes only in the local worktree:

1. If an affected project has a database migration mechanism, check for pending
  migrations and apply them to the configured target. Any migration added or
  changed by the task must be applied successfully before committing. Never
  mark a migration as applied without executing it.
2. Run the focused tests, typecheck, lint, or production build appropriate to
  the changed surface. Fix task-related failures before proceeding.
3. Review `git status` and the final diff. Do not stage local secrets such as
  `.env*`, generated build artifacts, or unrelated user changes unless the user
  explicitly asks for them.
4. Commit all task-related changes in every affected repository with a concise,
  descriptive commit message, then push each current branch to its configured
  upstream remote.
5. This workspace uses Git submodules. After pushing changed child repositories,
  commit and push their updated pointers in the parent `lead_engine` repository.
6. Verify that every affected repository is clean and synchronized with its
  upstream branch. Report commit hashes and any migration applied.

Do not deploy merely because changes were pushed. Production deployment still
requires an explicit user request and the build-first workflow above.
