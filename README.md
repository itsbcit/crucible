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

Update `.gitignore` to exclude the Rakefile library and `.build_id` marker file.

`.gitignore` contents:

```text
.build_id
lib
```

### Install Rakefile support files

`Rakefile` can be updated to the latest release version with [`rake update`](#update).

The majority of the Rakefile support code is contained in the `lib` directory, which should be excluded from individual Git repositories using this system. This way, the latest release code is always used.

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
    org_name: myorg
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

### update

`Rakefile` self-update. Download and overwrite the `Rakefile` and `libs` directory with the [latest release](https://github.com/itsbcit/crucible/releases/latest)

`rake update`

Side-effect: also calls [install](#install)

### template

Create or overwrite Containerfile(s) from ERB templates and render any templated files listed for the versions and variants into their build directories. `Dockerfile.erb` is also accepted as a fallback for backwards compatibility.

`rake template`

### build

Build the container image(s) using `podman build` (buildah internally).

`rake build`

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

Requires `trivy` to be installed. See [aquasecurity/trivy](https://github.com/aquasecurity/trivy) for installation.

### push

Push all images and tags to the registries configured in `metadata.yaml`. Authentication must be set up before calling this task, either via `podman login` or by setting `REGISTRY_AUTH_FILE` to a valid auth config.

`rake push`

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
        org_name: myorg
  '':
    registries:
      - url: registry.example.com
        org_name: myorg
  'oci':
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

## Snippets

Reusable Containerfile fragments in `lib/snippets/`. Include them in `Containerfile.erb` with:

```erb
<%= snippet('name', binding) -%>
```

Any snippet can be overridden by placing a file with the same name in `local/snippets/`.

### container-entrypoint

Downloads and installs the entrypoint script framework from [itsbcit/container-entrypoint](https://github.com/itsbcit/container-entrypoint).

Variable: `ce_version` (default: `1.0`)

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

Variable: `dockerize_version` (default: `0.11.1`)

### labels

Renders `LABEL` instructions from the image's labels hash.

## Obsoleted config options

### `de_version`

The `de_version` variable (used by the old `docker-entrypoint` snippet to download from [itsbcit/docker-entrypoint](https://github.com/itsbcit/docker-entrypoint)) is obsolete. Use `ce_version` instead, which downloads from [itsbcit/container-entrypoint](https://github.com/itsbcit/container-entrypoint).

Setting `de_version` in `base_vars` or `vars` at any level will raise an error during config parsing.

## Releasing

Every GitHub release must include two assets that `rake install` and `rake update` download:

1. **`crucible-lib.zip`** — a zip of the `lib/` directory contents (flat `.rb`/`.yaml` files at root, `tasks/` and `snippets/` subdirectories preserved)
2. **`Rakefile`** — the current `Rakefile` from the repo root

To create a release:

```bash
# build the lib zip (must contain lib/ as top-level directory)
zip -r /tmp/crucible-lib.zip lib/

# create the release with assets
gh release create vX.Y.Z --title "vX.Y.Z" --notes "..." /tmp/crucible-lib.zip Rakefile
```
