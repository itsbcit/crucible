# AGENTS.md

Guidance for AI coding agents working in this repo.

Crucible is the container build harness used by BCIT `container-*` repos. It
is vendored into each consumer as `lib/` plus a `Rakefile`. `lib/` is
gitignored there, so a consumer's copy can be arbitrarily old with nothing in
its git history to show it.

## Put logic in lib/, not the Rakefile

Consumers **commit** their `Rakefile`. `rake install` refreshes `lib/` and
never the `Rakefile` (only `rake update`, or `CRUCIBLE_REF=<ref> rake install`,
replaces it). Through v1.4.8 generated pipelines ran `rake install`, so CI
ran a current `lib/` with whatever `Rakefile` was last committed. Since
v1.5.0 they run `rake update`, which fetches both from the same release
(TUX-6952); every crucible `Rakefile` since v1.0.0 has that task, so it works
however old the committed copy is. That only helps once a consumer's
pipeline has been regenerated, and a local checkout still runs its committed
`Rakefile` until someone runs `rake update`.

Keep the `Rakefile` a thin loader and put behaviour in `lib/`. The
`VERSION`/`VARIANT` filter was added to the `Rakefile` in v1.4.2 and never
reached `container-qgis-server`, whose committed `Rakefile` predated it: every
per-version Woodpecker step built every version (TUX-6950). It moved to
`lib/filter_images.rb`, applied by `build_objects_array`, in v1.4.8. Callers
that need the whole matrix pass `filter: false`, as `rake woodpecker` does.

## Tests

`ruby test/all.rb` runs the minitest suite in `test/`. It needs Ruby and the
`minitest` gem only (no podman, trivy, skopeo or network), takes a few
seconds, and must pass before a release. GitHub Actions
(`.github/workflows/test.yml`) runs it on Ruby 3.3, 3.4 and 4.0 for every
push to `master` and every pull request. Each test runs in its own temp
directory, because `ContainerImage` reads and writes `.build_id` in the
working directory. `generate_pipeline` runs the real `rake woodpecker` in a
scratch consumer repo (the `Rakefile` plus `lib/`), so the pipeline tests
also exercise the Rakefile's loader.

`test/woodpecker_test.rb` pins the generated-pipeline properties listed
below. When you change one deliberately, change its test in the same commit.
When you fix a bug, add a test that fails without the fix.

minitest is a bundled gem: present in a normal Ruby install (macOS rbenv),
but missing from the woodpecker-crucible image (Ruby 4.0, no locale set) and
from AlmaLinux's ruby package. To check against CI's Ruby, run it in a
throwaway container:

```bash
podman run --rm -v "$PWD":/src:ro,Z -w /src --entrypoint sh \
  bcit.io/library/woodpecker-crucible:latest \
  -c 'gem install --no-document minitest >/dev/null && ruby test/all.rb'
```

## A fix here reaches nobody until a release is cut

Consumers do not track `master`. `rake install` / `rake update` download from:

```
https://github.com/itsbcit/crucible/releases/latest/download/crucible-lib.zip
https://github.com/itsbcit/crucible/releases/latest/download/Rakefile
```

Releases are cut **by hand**; the only workflow in `.github/` runs the tests. After
committing a fix here, say so explicitly rather than implying consumers have
it. `CRUCIBLE_REF=<ref> rake install` pulls a specific branch or tag and is
the way to test an unreleased fix in a consuming repo.

## Cutting a release

Build the zip from a clean `git archive` export, not the working tree, so no
local cruft is included. **Tag first, then archive the tag**: `git archive`
stamps the release into `lib/version.rb` and the `Rakefile` (export-subst,
see `.gitattributes`), and archiving before the tag exists stamps the
previous release's name. Name both assets correctly on disk and pass them to
`gh release create` in one command:

```bash
ruby test/all.rb
git tag vX.Y.Z && git push origin vX.Y.Z
mkdir -p /tmp/rel && git archive vX.Y.Z | tar -x -C /tmp/rel
grep -q "'vX.Y.Z'" /tmp/rel/lib/version.rb || echo 'STAMP WRONG, do not publish'
(cd /tmp/rel && zip -rq /tmp/crucible-lib.zip lib)
cp /tmp/rel/Rakefile /tmp/Rakefile
gh release create vX.Y.Z /tmp/crucible-lib.zip /tmp/Rakefile --title vX.Y.Z --notes '...'
```

`git archive` expands only one `%(describe)` per archive, so only
`lib/version.rb` uses it; the `Rakefile` carries the commit hash (`%H`), which
has no such limit. Do not add a second `%(describe)` placeholder anywhere: it
would be left unexpanded.

Do **not** use `gh release upload`'s `local#published-name` rename syntax. It
produces an asset the API reports as `state=uploaded` while every GET of its
URL 404s, and neither `--clobber` nor delete-and-reupload fixes it; the
release has to be deleted and recreated with its assets in one command.

The zip must contain a top-level `lib/` directory, because `rake install`
unzips it into the consumer's working directory.

## Release stamps

`rake version` shows which release a consumer's `Rakefile` and `lib/` came
from, and every other task warns when the two differ (skipped for `install`
and `update`, which are how it gets fixed). `Rakefile`s from before v1.5.0
carry no stamp and are reported as older than v1.5.0. In crucible's own
checkout the placeholders stay unexpanded and nothing is compared. GitHub's
`/archive/<ref>.zip` applies export-subst too, so a `CRUCIBLE_REF` install is
stamped with `git describe` output such as `v1.4.8-4-g0c4b5b9`.

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
| cron named `rebuild` | `render`, then the above plus `rake tag`, `rake push`, with `VERSION` from `metadata.yaml` |

The cron steps filter on the cron **name**, so they are inert until someone
creates a `rebuild` cron for the repo. They exist so base-image and package
fixes ship without a commit or a tag. They run after `render` so each run
gets a fresh build ID; without it the committed `.build_id` would be reused
and every scheduled run would overwrite the same `b<id>` tag.

Each versioned tag step runs only on a tag naming its own version
(`when: ref` matching `refs/tags/<version>` or `refs/tags/v<version>`), with
`VERSION` set statically like the build steps. A `check-tag` step runs on
every tag and fails unless `${CI_COMMIT_TAG#v}` is a version in
`metadata.yaml`. Without it, a tag matching no version would skip every tag
step and go green with nothing published. Together they keep the git tag and
`metadata.yaml` checking each other instead of relying on the operator
remembering both edits.

Through v1.4.8 every tag step instead exported `VERSION` from the tag, so in
a multi-version repo all of them built the tagged version and raced to push
the same images (TUX-6951).

Repos with no `versions:` key still get a tag step, without the `VERSION`
export: there is nothing for the tag to agree with, so any tag publishes
them. Do not skip them. Through v1.4.5 they got no tag step at all, which left
an unversioned repo (e.g. `container-wolfi-base`, published only as
`:latest`) with no publish step anywhere: green pipelines, nothing pushed.

Keep these properties when editing `lib/tasks/woodpecker.rake`:

- `rake update` runs **once per pipeline**: in `render` (push, cron) or
  `setup` (tag), with every other step depending on it. Steps share the
  workspace, and `update` deletes `lib/` before unpacking it again. Through
  v1.6.0 every build and tag step ran it, so parallel steps could delete
  `lib/` under one another (`LoadError: cannot load such file --
  lib/tasks/default.rake`; container-wolfi-postgresql pipeline 21).

- Only tag and cron-rebuild steps publish; push steps never do. Having push steps publish too means a tagged
  release commit builds twice and races to push identical tags, and it moves
  `:latest` on every push so consumers tracking it get unreleased commits.
- A filter matching nothing must **abort**, never exit 0. An empty `$images`
  makes every task a silent no-op: a green pipeline that published nothing.
- Every step selects **exactly one image**. An unset `VARIANT` matches all
  variants, so in a repo with variants the base-variant steps run
  `export VARIANT=''` (an empty `VARIANT` selects only the base image).
  Without it they built and pushed every variant of their version, racing
  the variant steps (TUX-6951).
- Every `depends_on` entry that can name a step absent from the event must
  be `optional: true`. Woodpecker drops steps whose `when:` does not match
  before resolving dependencies and fails the pipeline on a missing one
  (3.20.1 `convertDAGToStages`, `ErrStepMissingDependency`). This bites the
  extra-step wiring (`lib/woodpecker_extra_steps.rb`): a post step depends on
  every `tag-*` step, but a `v18` tag has no `tag-17-*`. Optional
  dependencies need Woodpecker 3.15+.
- Only **rebuild** steps set `CRUCIBLE_SKIP_UNCHANGED`. Tag steps must always
  push: a tag is an explicit release, and skipping it would leave the git tag
  pointing at nothing new with a green pipeline.

## Unchanged rebuilds are not republished

`lib/fingerprint.rb`: `rake build` labels each image `crucible.fingerprint`
(rendered Containerfile minus `build_id`, plus the package list), and `rake
push` with `CRUCIBLE_SKIP_UNCHANGED` skips an image whose label matches every
published non-build tag (read with `skopeo inspect`, which woodpecker-crucible
ships). Keep every failure mode on the push side: no fingerprint, no skopeo, a
missing tag or a missing label must all push, never skip.

Before v1.7.0 every daily rebuild republished, moving all tags to a new digest
with nothing changed. That broke downstream "did the image change?" checks
(pgsql-bby's quadlet playbook compares image IDs, so it would restart nodes
daily) and cycled `b<id>` tags out of Harbor's keep-the-last-30 retention in
about a week. Labelling repeats the build with `--label`; every layer is
cached, so it costs seconds.

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
