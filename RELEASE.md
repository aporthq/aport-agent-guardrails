# How to release

Use the canonical process in [docs/RELEASE.md](docs/RELEASE.md).

## Summary

1. Add changesets in feature PRs.
2. Run `npm run version` on the release branch.
3. Commit the generated version and changelog updates.
4. Merge to `main`.
5. The `release-on-version.yml` dispatcher runs from `main`, creates the matching `vX.Y.Z` tag
   when needed, and starts the publish workflow.

`npm run version` is the only supported bump flow. It runs Changesets for the fixed workspace group and then syncs the root CLI package, Python packages, lockfiles, manifests, and release docs to the same version.

Manual tag pushes remain a fallback only when the tag matches `package.json`. See
[docs/RELEASE.md](docs/RELEASE.md) for recovery details.
