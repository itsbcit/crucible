# AGENTS.md

Guidance for AI coding agents working in this repo.

Crucible is the container build harness used by BCIT `container-*` repos. It
is vendored into each consumer as `lib/` plus a `Rakefile`, both of which are
**gitignored there**, so a consumer's vendored copy can be arbitrarily old
with nothing in its git history to show it.

## A fix here reaches nobody until a release is cut

Consumers do not track `master`. `rake install` / `rake update` download from:

```
https://github.com/itsbcit/crucible/releases/latest/download/crucible-lib.zip
https://github.com/itsbcit/crucible/releases/latest/download/Rakefile
```

Releases are cut **by hand**; there is no workflow in `.github/`. After
committing a fix here, say so explicitly rather than implying consumers have
it. `CRUCIBLE_REF=<ref> rake install` pulls a specific branch or tag and is
the way to test an unreleased fix in a consuming repo.

## Cutting a release

Build the zip from a clean `git archive` export, not the working tree, so no
local cruft is included. Name both assets correctly on disk and pass them to
`gh release create` in one command:

```bash
mkdir -p /tmp/rel && git archive HEAD | tar -x -C /tmp/rel
(cd /tmp/rel && zip -rq /tmp/crucible-lib.zip lib)
cp /tmp/rel/Rakefile /tmp/Rakefile
gh release create vX.Y.Z /tmp/crucible-lib.zip /tmp/Rakefile --title vX.Y.Z --notes '...'
```

Do **not** use `gh release upload`'s `local#published-name` rename syntax. It
produces an asset the API reports as `state=uploaded` while every GET of its
URL 404s, and neither `--clobber` nor delete-and-reupload fixes it; the
release has to be deleted and recreated with its assets in one command.

The zip must contain a top-level `lib/` directory, because `rake install`
unzips it into the consumer's working directory.

### Always verify with a real GET

A `gh release view` listing an asset is not evidence it downloads:

```bash
curl -sL -o /tmp/c.zip -w '%{http_code} %{size_download}\n' \
  https://github.com/itsbcit/crucible/releases/latest/download/crucible-lib.zip
unzip -p /tmp/c.zip lib/tasks/<changed-file> | grep <expected>
```

**`releases/latest/download/` can serve the PREVIOUS release's asset** from
some CDN edges for several minutes after cutting a new one. Observed on
2026-09-28 cutting v1.4.3: 4 of 5 sequential GETs returned the v1.4.2 asset
while the explicit tag URL was correct every time, and `rake update` in a
consumer pulled the stale copy twice. It resolves on its own. Until it does,
`CRUCIBLE_REF=vX.Y.Z rake install` is the reliable path, and it is worth
telling consumers that in the release notes.

## Generated pipelines: push validates, tag publishes

`rake woodpecker` renders `.woodpecker/build.yaml` from the image matrix:

| Event | Commands |
|---|---|
| push / manual on `main` | `rake build`, `rake test`, `rake scan` |
| tag | the above plus `rake tag`, `rake push` |

Tag steps derive `VERSION` from `CI_COMMIT_TAG` (stripping a leading `v`)
rather than hardcoding it. Combined with the `VERSION` filter in the
`Rakefile`, which aborts when it matches no image, this makes the git tag and
`metadata.yaml` check each other instead of relying on the operator
remembering both edits.

Repos with no `versions:` key get no tag step, since there would be nothing
for a tag to agree with.

Keep these two properties when editing `lib/tasks/woodpecker.rake`:

- Only the tag step publishes. Having push steps publish too means a tagged
  release commit builds twice and races to push identical tags, and it moves
  `:latest` on every push so consumers tracking it get unreleased commits.
- A filter matching nothing must **abort**, never exit 0. An empty `$images`
  makes every task a silent no-op: a green pipeline that published nothing.

## metadata-defaults.yaml holds vendored tool versions

`base_vars` pins `catatonit`, `tini`, `ce` (container-entrypoint) and
`dockerize`. These are baked into every consumer's image, so a stale pin is a
fleet-wide vulnerability rather than a local one.

`dockerize` is the one that matters most: it is a Go binary, so it carries
whatever Go stdlib CVEs its build toolchain had, and `rake scan` fails on it
independently of the Alpine package set. 0.13.0 carried nine HIGH CVEs and
was bumped to 0.15.1 on 2026-09-28. Check these against upstream when
touching a release.

Note that a consumer pinning one of these in its own `metadata.yaml` `vars:`
overrides the default and must be bumped separately.
