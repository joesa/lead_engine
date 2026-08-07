# Completion and deployment

For every task that changes code, configuration, or database schema, do not consider the work complete until all of the following are done:

1. Run the relevant tests and validation.
2. Commit only the task-related changes in each affected repository. Preserve unrelated user changes.
3. Push every affected repository branch to its configured remote.
4. If a submodule changed, commit and push the updated submodule pointer in this parent repository.
5. From `closet-dashboard`, run `./scripts/db-migrate.sh` to apply every pending SQL migration and bring the Graphile Worker schema up to date.
6. Confirm the pushes and migrations succeeded before reporting completion. If permissions, credentials, the network, or deployment policy prevents either action, report that explicitly instead of claiming the task is complete.

In short: always push finished work and apply pending migrations.
