# Changesets

We use a **single version** for the whole suite (core + all framework adapters + the root CLI package).

## Adding a changeset

After making code or doc changes:

```bash
npx changeset
```

- Choose the type of change: **patch** (bugfix), **minor** (feature), **major** (breaking).
- Write a short summary for the changelog.
- Commit the new file under `.changeset/`.
- Target one of the **workspace packages** in the fixed release group, typically `@aporthq/aport-agent-guardrails-core`.

When the release is cut, `changeset version` bumps the fixed workspace group and updates workspace changelogs. Then `npm run sync-version` propagates that same version to the root CLI package, Python packages, manifests, lockfiles, and release docs.

See [docs/RELEASE.md](../docs/RELEASE.md) for the full release flow.
