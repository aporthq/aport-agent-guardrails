# Changesets

We use a **single version** for the whole suite (core + all framework adapters + the root CLI package).

## Adding a changeset

After making code or doc changes:

```bash
npx changeset
```

- Choose the type of change: **patch**. The current public package line is released as `1.0.x`; `npm run version` normalizes accidental `minor` bumps to `patch` and rejects `major` bumps unless `APORT_ALLOW_NON_PATCH_RELEASE=1` is set intentionally.
- Write a short summary for the changelog.
- Commit the new file under `.changeset/`.
- Target one of the **workspace packages** in the fixed release group, typically `@aporthq/aport-agent-guardrails-core`.

When the release is cut, `changeset version` bumps the fixed workspace group and updates workspace changelogs. Then `npm run sync-version` propagates that same version to the root CLI package, Python packages, manifests, lockfiles, and release docs.

See [docs/RELEASE.md](../docs/RELEASE.md) for the full release flow.
