# Changesets

We use a **single version** for the whole suite (core + all framework adapters). When you add a changeset, it will drive a single bump for every package.

## Adding a changeset

After making code or doc changes:

```bash
npx changeset
```

- Choose the type of change: **patch** (bugfix), **minor** (feature), **major** (breaking).
- Write a short summary for the changelog.
- Commit the new file under `.changeset/`.

When the release is cut, `changeset version` will bump **all** packages to the same new version and update changelogs. Python packages are then synced to that version via `npm run sync-version`.

See [docs/RELEASE.md](../docs/RELEASE.md) for the full release flow.
