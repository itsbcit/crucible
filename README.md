# crucible

Rakefile and libraries for managing container image builds with Podman.

Forked from [docker-rakefile](https://github.com/itsbcit/docker-rakefile). If you need Docker support, use the original project.

## Requirements

- **Ruby** with `rake`
- **Podman** (builds use `podman build`, which runs buildah internally)

### macOS setup

```bash
brew install podman
podman machine init
podman machine start
```

### Linux

Install Podman via your package manager. See [podman.io/docs/installation](https://podman.io/docs/installation).

## How to use

### New container image repositories

Clone [container-template](https://github.com/itsbcit/container-template) as the starting point for a new container image repository:

```bash
git clone https://github.com/itsbcit/container-template ~/Devel/my-new-image
```

### Existing container image repositories

Update the Rakefile and support library in the existing code with [rake update](#update).

### Exclude support files

Update `.gitignore` to exclude the Rakefile library, the `.build_id` marker file, and the `.iid-*` files that `rake build` writes with `podman build --iidfile`. Each holds the local image ID that `rake clean` and `rake patch` use to find the image in the local podman store, so it means nothing on any other machine.

`.gitignore` contents:

```text
.build_id
.iid-*
lib
```

Repos that already committed `.iid-*` files keep tracking them until they are removed with `git rm --cached .iid-*`.

### Install Rakefile support files

`Rakefile` can be updated to the latest release version with [`rake update`](#update).

The majority of the Rakefile support code is contained in the `lib` directory, which should be excluded from individual Git repositories using this system. This way, the latest release code is always used.

The `Rakefile` itself is committed, and `rake install` does not replace it. Generated pipelines run `rake update`, so CI always uses a `Rakefile` and `lib/` from the same release, but a local checkout runs its committed `Rakefile` until you run `rake update` and commit the result.

See [`rake install`](#install)

This will pull the latest release of the `lib` support files from GitHub.

### Create metadata.yaml

`metadata.yaml` defines the layout and handling of the container image(s) in this repository.

A simple example for an image without versions or variants:

```yaml
---
image_name: template_test
registries:
  - url: registry.example.com
    project: myorg
vars:
  foo_version: '1.2.3'
```

Inside ERB templated files, these parameters are available as eg. `image.vars['foo_version']`. Eg in a Containerfile.erb:

```erb
RUN yum install \
      foo-<%= image.vars['foo_version'] %>
```

Labels, vars, and tags can all be ERB-templated with inline values, but note that the context is the image, so no `image.` prefix. This example will add a label `foo_version = 1.2.3` using the value of `foo_version` from the image vars:

```yaml
labels:
  foo_version: '<%= vars['foo_version'] %>'
```

Important: parameters are rendered in the order: vars -> labels -> tags.

* vars can only include replacements from the image top-level, and other non-templatable image properties
* labels can include vars
* tags can include vars and labels

### Build platform

By default, all builds target `linux/amd64`. Override per-image in `metadata.yaml`:

```yaml
build_platform: 'linux/arm64'
```

Or via environment variable: `BUILD_PLATFORM=linux/arm64 rake build`

### Optional build ID tagging

By default, images are tagged with a build ID suffix (e.g. `image:1.0-b1567100182`). To disable:

```yaml
tag_build_id: false
```

This can be set at the top level, per-version, or per-variant.

### Optional commit SHA tagging

`git_sha` returns the 7-character commit SHA and can be used in ERB tags. It reads Woodpecker's `CI_COMMIT_SHA` and falls back to the local checkout; if neither is available the tag is dropped.

```yaml
tags:
  - 'latest'                                         # tags: replaces the default list, so restate latest
  - '<%= tag_join(version, variant, git_sha) %>'     # e.g. 1.2.3-abc1234, or abc1234 when unversioned
```

Locally the SHA names `HEAD` even when the working tree has uncommitted changes, so treat it as meaningful only for CI-built images. A scheduled rebuild (see [Scheduled rebuilds](#scheduled-rebuilds)) re-points the SHA tag at the rebuilt image, so it means "latest build of this commit"; use the `b<id>` tag for an immutable reference.

### Building a single version or variant

Set `VERSION` and/or `VARIANT` environment variables to restrict any rake task to a subset of the matrix. This works for all tasks: `build`, `tag`, `push`, `template`, `scan`, etc. A filter that matches no image aborts with the list of available versions and variants. `rake woodpecker` ignores the filter and always renders the whole matrix.

```bash
VERSION=17 rake build               # build all variants of version 17
VARIANT=pgvector rake build         # build pgvector across all versions
VERSION=17 VARIANT=pgvector rake build  # build exactly one image
```

### Custom image handling

Any file in `lib` can be overridden by the same file name in `local/`. For example, if you need a custom [test](#test) task, copy `lib/tasks/test.rake` to `local/tasks/test.rake` and modify it. Test helpers from `lib/test_helpers.rb` are available for composing multi-container test setups.

### Normal usage workflow

1. Make `Containerfile` changes in `Containerfile.erb`
1. `rake update` to pull down Rakefile and library updates
1. `rake` (runs [template](#template), [build](#build), [test](#test), and [tag](#tag))
1. `rake push` to push to registries defined in [`metadata.yaml`](#create-metadatayaml)

## Rake tasks

### install

Install the Rakefile support files from the [latest release](https://github.com/itsbcit/crucible/releases/latest).

`rake install`

To install from a specific branch or tag instead of the latest release:

`CRUCIBLE_REF=main rake install`

When `CRUCIBLE_REF` is set, both `lib/` and the `Rakefile` are fetched from that ref's archive. This is useful for testing unreleased crucible changes in a consumer repo before cutting a release.

### version

Show the crucible release that the `Rakefile` and `lib/` came from, and whether they match.

`rake version`

Every other task prints a warning when they differ. `rake install` refreshes `lib/` but not the committed `Rakefile`, so the warning means the `Rakefile` needs `rake update` and a commit.

### update

`Rakefile` self-update. Download and overwrite the `Rakefile` and `lib/` directory with the [latest release](https://github.com/itsbcit/crucible/releases/latest).

`rake update`

`CRUCIBLE_REF=main rake update` — update from a specific branch or tag (delegates to `rake install`, which already fetches both `lib/` and the `Rakefile` from the archive).

Side-effect: also calls [install](#install)

### template

Create or overwrite Containerfile(s) from ERB templates and render any templated files listed for the versions and variants into their build directories. `Dockerfile.erb` is also accepted as a fallback for backwards compatibility.

`rake template`

### build

Build the container image(s) using `podman build` (buildah internally).

`rake build`

#### Pre-build commands

`pre_build` lists shell commands that `rake build` runs from the repo root before building an image, for things a `podman build` step cannot do itself, such as building apk packages with melange (which needs a privileged container). Set it at the top level, per version or per variant; the levels are concatenated in that order. Commands are rendered with ERB like tags, so they can use `version`, `variant` and `vars`. A command that fails stops the build.

```yaml
versions:
  '17':
    pre_build:
      - './melange/build.sh <%= version %> <%= variant %>'
```

The commands run on every `rake build` of that image, locally and in CI, so make them safe to repeat. `rake debug` shows them under the build task.

### tag

Add standard and `metadata.yaml` configured tags to the image(s).

`rake tag`

Standard tags:

* image_name:b(`build id`) eg. `mybusybox:b1567100182` (unless `tag_build_id: false`)
* image_name:latest

### test

Run automated tests against the image(s). Uses composable helpers from `lib/test_helpers.rb`.

### patch

Apply security updates to an existing image without a full rebuild.

`rake patch` — patches all images using `apk upgrade --no-cache`

`PATCH_CMD='yum update -y' rake patch` — custom patch command

`PATCH_BASE='myimage:b1567100182' rake patch` — patch a specific build

Produces images tagged with a `-pN` suffix (e.g. `image:b1567100182-p1`).

### scan

Scan built container images for vulnerabilities using [Trivy](https://trivy.dev/).

`rake scan` — fails if any HIGH or CRITICAL vulnerabilities are found

`SEVERITY=CRITICAL rake scan` — only fail on CRITICAL vulnerabilities

`SCAN_REPORT_ONLY=1 rake scan`: print the findings but never fail

To make an image's scan report-only in every run, including the generated Woodpecker pipeline, set `scan_report_only: true` in `metadata.yaml`. Like `test`, it can be set at the top level, per version or per variant:

```yaml
scan_report_only: true      # every image
versions:
  'prod':
    scan_report_only: false # except prod, which still fails on findings
```

A report-only scan still prints trivy's full table in the build log.

`scan_ignore_unfixed` controls whether vulnerabilities with no fix available count. It is set the same way (top level, per version or per variant):

| `metadata.yaml` | `rake scan` passes | Effect |
|---|---|---|
| unset (default) | nothing | trivy decides: `TRIVY_IGNORE_UNFIXED`, then `trivy.yaml` in the repo, then trivy's default (unfixed findings count) |
| `scan_ignore_unfixed: true` | `--ignore-unfixed` | only fixable findings are reported or fail the scan |
| `scan_ignore_unfixed: false` | `--ignore-unfixed=false` | unfixed findings count, whatever `trivy.yaml` or the environment says |

trivy's precedence is command-line flag, then `TRIVY_*` environment variable, then `trivy.yaml`, so a value set here always wins. Leave it unset to keep control in `trivy.yaml`.

Requires `trivy` to be installed. See [aquasecurity/trivy](https://github.com/aquasecurity/trivy) for installation.

### push

Push all images and tags to the registries configured in `metadata.yaml`. Authentication must be set up before calling this task, either via `podman login` or by setting `REGISTRY_AUTH_FILE` to a valid auth config.

`rake push`

### woodpecker

Render `.woodpecker/build.yaml` from the image matrix in `metadata.yaml`. Each version×variant combination becomes a parallel Woodpecker CI step with `VERSION` and `VARIANT` set. A `render` step runs first to stamp a shared build ID and re-render all Containerfiles.

`rake woodpecker`

The generated file should be committed to the repository. Re-run `rake woodpecker` whenever `metadata.yaml` changes and commit the result.

See [Woodpecker CI integration](#woodpecker-ci-integration) for the full parallel build workflow, and [Extra steps](#extra-steps) for adding your own steps before or after the generated ones.

### clean

Removes all tags, images, "FROM images" and runs `podman system prune`.

### debug

Shows rendered tags, vars, labels, platform, and predicted commands. Use to preview what your metadata will produce.

## metadata.yaml

Sample metadata.yaml with most options used:

```yaml
---
image_name: php-fpm
maintainer: 'jesse@weisner.ca, chriswood.ca@gmail.com'
build_platform: 'linux/amd64'
tag_build_id: true
labels:
  php_version: '<%= vars["php_version"] %>'
vars:
  pecl_oci8_version: '2.2.0'
  pecl_xdebug_version: '3.1.0'
  pecl_igbinary_version: '3.2.6'
  oracle_version: '18.3.0.0.0'
  oracle_major: '18.3'
variants:
  'builder':
    registries:
      - url: registry.example.com
        project: myorg
  '':
    registries:
      - url: registry.example.com
        project: myorg
  'oci':
    depends_on: ''    # must be built after the base ('') variant
    registries:
      - url: registry.example.com:5000
    labels:
      oracle_version: '<%= vars["oracle_major"] %>'
versions:
  '7.3':
    vars:
      php_version: '7.3.30'
  '7.4':
    vars:
      php_version: '7.4.24'
```

### Registry project key

The registry project/namespace can be specified as `project`, `org`, or `org_name` — all three are equivalent. `project` is preferred. If more than one is set, `org_name` takes priority, then `project`, then `org`.

## Snippets

Reusable Containerfile fragments in `lib/snippets/`. Include them in `Containerfile.erb` with:

```erb
<%= snippet('name', binding) -%>
```

Any snippet can be overridden by placing a file with the same name in `local/snippets/`.

### container-entrypoint

Downloads and installs the entrypoint script framework from [itsbcit/container-entrypoint](https://github.com/itsbcit/container-entrypoint).

Variable: `ce_version` (default: `1.0.0`)

### docker-entrypoint

Backward-compatible stub that delegates to [container-entrypoint](#container-entrypoint).

### catatonit

Downloads and installs [catatonit](https://github.com/openSUSE/catatonit), a minimal container init process. Drop-in replacement for tini, and the same init used internally by Podman.

Variable: `catatonit_version` (default: `0.2.1`)

```erb
<%= snippet('catatonit', binding) -%>
```

```dockerfile
ENTRYPOINT ["/catatonit", "--", "/container-entrypoint.sh"]
```

### tini

Downloads and installs [tini](https://github.com/krallin/tini), a lightweight init process.

Variable: `tini_version` (default: `0.19.0`)

### dockerize

Downloads and installs [dockerize](https://github.com/jwilder/dockerize) for template rendering and service readiness checks.

Variable: `dockerize_version` (default: `0.13.0`)

### labels

Renders `LABEL` instructions from the image's labels hash.

## Obsoleted config options

### `de_version`

The `de_version` variable (used by the old `docker-entrypoint` snippet to download from [itsbcit/docker-entrypoint](https://github.com/itsbcit/docker-entrypoint)) is obsolete. Use `ce_version` instead, which downloads from [itsbcit/container-entrypoint](https://github.com/itsbcit/container-entrypoint).

Setting `de_version` in `base_vars` or `vars` at any level will raise an error during config parsing.

## Woodpecker CI integration

Crucible supports parallel builds in [Woodpecker CI](https://woodpecker-ci.org/) via `rake woodpecker`. Each version×variant combination builds in its own parallel step. Steps that depend on another variant (e.g. a `pgvector` image that `FROM`s the base image) are sequenced automatically via Woodpecker's `depends_on`.

### Workflow

Two pipelines are used:

**Render pipeline** (triggered by upstream automation or manually when `metadata.yaml` changes):

```bash
rake update && rake template && rake woodpecker
git add .woodpecker/build.yaml Containerfile* && git commit -m "..." && git push
```

This stamps a new build ID, re-renders all Containerfiles, and regenerates `.woodpecker/build.yaml`. The commit triggers the build pipeline.

**Build pipeline** (`.woodpecker/build.yaml`, generated by `rake woodpecker`):

- `render` step: runs `rake update && rake template && rake woodpecker` to stamp a fresh build ID
- One parallel step per version×variant, on push/manual to `main`: runs `rake update && rake template && rake build && rake test && rake scan` with `VERSION`, `VARIANT`, and `KEEP_BUILD=1` set, so each step builds exactly one image (base-variant steps export an empty `VARIANT`, which selects only the base image). These validate only and publish nothing.
- One tag step per version×variant, on a git tag: the same commands plus `rake tag && rake push`. This is the only place images are published. A versioned image's tag step runs only on a tag naming its version (`<version>` or `v<version>`), and a `check-tag` step fails the pipeline when the tag names no version in `metadata.yaml`. Images with no `versions:` key publish on any tag.

- One rebuild step per version×variant, on a Woodpecker cron named `rebuild`: the same commands as the tag step, but with `VERSION` taken from `metadata.yaml`, after a fresh `render`. This republishes the current version with the latest base image and packages, without a commit or a new tag.

To publish:

```bash
git tag -a v1.2.3 -m "..."    # versioned: bump metadata.yaml first; unversioned: any tag name
git push origin v1.2.3
```

### Scheduled rebuilds

Rebuild steps only run when a cron **named `rebuild`** exists for the repo; a cron with any other name triggers none of them. Schedules use standard 5-field cron syntax in UTC:

```bash
woodpecker-cli repo cron add --repo ORG/REPO --name rebuild --branch main --schedule '0 11 * * *'
```

A scheduled rebuild publishes only when the image's content changed. `rake build` labels each image with `crucible.fingerprint`, a SHA-256 of the rendered Containerfile (without the `build_id` line) and the installed package list (apk, rpm or dpkg). Rebuild steps set `CRUCIBLE_SKIP_UNCHANGED=1`, and `rake push` then reads the label on each published non-build tag with `skopeo inspect` (no pull) and skips the image when every one matches. Without this, every run moved every tag to a new digest even when nothing changed, because each build stamps a new `build_id`.

When a rebuild does push, it gets a new build ID, so its `b<id>` tag is new, and the floating tags (`latest`, the version tag, and a `git_sha` tag) move to the rebuilt image. Tag-triggered publishes always push. Anything that cannot be compared counts as changed and is pushed: an image with no shell or package manager (no fingerprint), no `skopeo` in the CI image, or a tag not yet published or published without the label.

Not covered by the fingerprint: content that no package manager tracks, such as a binary compiled in a builder stage from a pinned source version, changes only when its Containerfile line does.

### depends_on

If a variant's Containerfile `FROM`s another variant's published image, declare the dependency in `metadata.yaml`:

```yaml
variants:
  '': {}
  'pgvector':
    depends_on: ''    # wait for base variant to be built and pushed first
```

`rake woodpecker` uses this to add `depends_on` to the generated Woodpecker step, so `build-17-pgvector` waits for `build-17-base` to complete before starting. Variants without `depends_on` run fully in parallel.

### Extra steps

Steps the generator does not know about, such as fetching source from another repository before the build or updating a deployment repository after a release, are declared under `woodpecker:` in `metadata.yaml`. Each entry is a raw Woodpecker step, copied into `.woodpecker/build.yaml` as written:

```yaml
woodpecker:
  pre_steps:
    - name: fetch-source
      image: alpine/git:latest
      environment:
        GIT_USER:
          from_secret: git_user
        GIT_PASS:
          from_secret: git_pass
      commands:
        - git clone "https://$GIT_USER:$GIT_PASS@git.example.com/app.git" src
  post_steps:
    - name: update-manifest
      image: alpine/git:latest
      commands:
        - ./update-manifest.sh
  post_steps_on_rebuild: false   # default
```

Only `when:` and `depends_on` are filled in, and only when the entry leaves them out:

| | `pre_steps` | `post_steps` |
|---|---|---|
| Position in the file | before the generated steps | after them |
| Default `when:` | every event a build, rebuild or tag step runs on | every event a tag step runs on, plus the `rebuild` cron with `post_steps_on_rebuild: true` |
| Default `depends_on` | none (runs alongside `render` / `setup`) | every tag step, plus every rebuild step with `post_steps_on_rebuild: true` |
| Wiring into generated steps | added to `depends_on` of every `build-*`, `rebuild-*` and `tag-*` step | none |

A `when:` you write is kept as given, so a pre step can be narrower than the steps it feeds (e.g. push only).

Every dependency the generator adds is marked `optional: true` (Woodpecker 3.15 or later). Woodpecker removes steps whose `when:` does not match before resolving `depends_on`, and fails the pipeline on a missing dependency that is not optional. A `v18` tag pipeline has no `tag-17-*` steps, and a narrowed pre step is absent from some events.

Things to know:

- **Secrets:** give the step its own `environment` with `from_secret`, as above. Generated steps only receive `harbor_config`.
- **Shared workspace:** all steps share one workspace, and pre steps run in parallel with `render` / `setup`, which delete and re-extract `lib/`. A pre step must not use `lib/` or the `Rakefile`, and must write to its own paths.
- **Post steps on rebuild:** a scheduled rebuild skips pushing unchanged images (see [Scheduled rebuilds](#scheduled-rebuilds)), so its `b<id>` tag may not exist in the registry. A post step that points a deployment at the new `b<id>` tag should not run on rebuilds, or must check that the tag exists first.
- **Validation:** `rake woodpecker` fails on an entry that is not a mapping, a missing or duplicated `name`, a name that clashes with a generated one (`render`, `setup`, `check-tag`, `build-*`, `rebuild-*`, `tag-*`), and any other key under `woodpecker:`.

### Authentication

Each step requires a `harbor_config` Woodpecker secret containing a Docker-format `config.json`:

```json
{"auths":{"registry.example.com":{"auth":"<base64-encoded-user:password>"}}}
```

Add it via: `woodpecker-cli repo secret add <ORG/REPO> --name harbor_config --value "$(cat ~/.docker/config.json)"`

## Releasing

Every GitHub release must include two assets that `rake install` and `rake update` download:

1. **`crucible-lib.zip`** — a zip of the `lib/` directory contents (flat `.rb`/`.yaml` files at root, `tasks/` and `snippets/` subdirectories preserved)
2. **`Rakefile`** — the current `Rakefile` from the repo root

Run the tests first. They need Ruby and the `minitest` gem only (no podman, trivy, skopeo or network), and nothing under `test/` ships to consumers:

```bash
ruby test/all.rb
```

To create a release:

```bash
# build the lib zip (must contain lib/ as top-level directory)
zip -r /tmp/crucible-lib.zip lib/

# create the release with assets
gh release create vX.Y.Z --title "vX.Y.Z" --notes "..." /tmp/crucible-lib.zip Rakefile
```
