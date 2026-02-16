# How to release

Same process every time. **Merges to main are not releases** — only pushing a tag triggers a release. **Do not commit directly to main;** use the usual branch flow (e.g. dev → staging → main).

## Steps

1. **Bump version** in a branch (e.g. `dev`), then merge via PRs to `main`:
   - `package.json`: set `"version": "X.Y.Z"` (e.g. `1.0.1`).
   - `CHANGELOG.md`: add/update the section for that version and release date.
   - Open PR dev → staging, merge; then PR staging → main, merge.

2. **Tag and push** (after the version bump is on `main`):
   ```bash
   git checkout main && git pull origin main
   git tag v1.0.1   # must match package.json "version"
   git push origin v1.0.1
   ```

3. **CI does the rest:** The Release workflow runs on tag push. It publishes to npm and creates the GitHub Release (with generated notes).

## After v1.0.0

For the next release (e.g. v1.0.1): bump to `1.0.1` in `package.json` and CHANGELOG, merge to main, then:

```bash
git pull origin main
git tag v1.0.1
git push origin v1.0.1
```

See [PUBLISHING.md](PUBLISHING.md) for what gets published and prerequisites (`NPM_TOKEN`).
