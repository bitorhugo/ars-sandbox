# ars-sandbox

Run [Claude Code](https://docs.claude.com/en/docs/claude-code) with the
[academic-research-skills](https://github.com/Imbad0202/academic-research-skills)
(ARS) plugin inside an isolated Docker container.

The container sees one host directory (your project) and nothing else: not your
home directory, SSH keys or host `~/.claude`.

## What's in the image

- Claude Code (npm, auto-updater disabled; rebuild to upgrade)
- ARS at its newest release (or a tag you choose), cloned into `/opt/ars` and
  loaded with `--plugin-dir`
- Python venv with ARS's `requirements-dev.txt`, plus `bash`, `jq`, `curl`, `git`
  for its hooks and scripts
- Pandoc for DOCX output (on by default), tectonic for PDF output (off by default)

## Quick start

```sh
git clone <this repo> ~/github/ars-sandbox
ln -s ~/github/ars-sandbox/bin/ars ~/github/ars-sandbox/bin/ars-build ~/.local/bin/

ars-build                  # build the image
cd ~/papers/my-paper
ars                        # start Claude Code with ARS in this directory
```

On first run, log in from inside Claude Code, or set `ANTHROPIC_API_KEY` or
`CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`) on the host. The login is
kept in the `ars-sandbox-home` Docker volume and shared by every project.

```sh
ars -p "lit-review this"   # any extra arguments go to claude
ars --shell                # bash shell in the container, for debugging
```

## Isolation

`bin/ars` runs the container with:

- only the current directory mounted, at `/work/<dir-name>` (refuses `$HOME` and `/`)
- a read-only root filesystem, with a 512 MB tmpfs at `/tmp`
- all Linux capabilities dropped, `no-new-privileges`, and memory and process limits
- a non-root user with your host UID/GID, so files it writes are owned by you
- a dedicated home volume for Claude Code auth, settings, history and caches

Network access is not restricted. Claude Code needs the API, and ARS reaches out
to citation sources (OpenAlex, Crossref and others) while it works.

## Configuration

Build options (`ars-build`):

| Variable | Default | Purpose |
|---|---|---|
| `ARS_SANDBOX_ARS_REF` | `latest` | ARS tag or branch to bake in; `latest` is the newest `vX.Y.Z` release |
| `ARS_SANDBOX_IMAGE` | `ars-sandbox:latest` | image tag (also tagged `:<ARS ref>`) |

Other `docker build` options pass straight through, for example:

```sh
ars-build --build-arg INSTALL_TECTONIC=true          # PDF output (+ CJK fonts)
ars-build --build-arg INSTALL_PANDOC=false
ars-build --build-arg INSTALL_PDF_CLASSIFIER=true    # optional ARS PDF classifier
ars-build --build-arg CLAUDE_CODE_VERSION=2.1.295
ars-build --no-cache
```

Run options (`ars`):

| Variable | Default | Purpose |
|---|---|---|
| `ARS_SANDBOX_WORKSPACE` | `$PWD` | host directory to mount |
| `ARS_SANDBOX_HOME_VOLUME` | `ars-sandbox-home` | volume for the container home; set per project for separate logins |
| `ARS_SANDBOX_ENV_FILE` | `~/.config/ars-sandbox/env` | env file passed to the container, if present |
| `ARS_SANDBOX_MEMORY` | `4g` | memory limit |
| `ARS_SANDBOX_PIDS` | `512` | process limit |
| `ARS_SANDBOX_IMAGE` | `ars-sandbox:latest` | image to run |

These host variables are passed into the container when they are set:
`ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, `GEMINI_API_KEY`,
`OPENALEX_API_KEY`, `OPENALEX_POLITE_EMAIL`, `CROSSREF_POLITE_EMAIL`, and every
`ARS_*` variable (for example `ARS_CROSS_MODEL`), except `ARS_SANDBOX_*`.
Put long-lived values in the env file rather than your shell profile.

## Upgrading ARS

Because the plugin directory is read-only, ARS's own update check is turned off
(`ARS_UPDATE_CHECK=0`). Rerun `ars-build` to pick up a new ARS release: it looks
up the newest release tag before building, so Docker's cache is invalidated only
when a new release exists. The image is tagged `ars-sandbox:latest` and with the
ARS version (for example `ars-sandbox:v3.23.0`). Inside the container,
`/opt/ars/.ars-ref` records the version that was installed.

To pin a specific version instead:

```sh
ARS_SANDBOX_ARS_REF=v3.22.2 ars-build
```

A plain `docker build .` also installs the newest release, but because the
build argument stays `latest`, Docker reuses the cached layer until you pass
`--no-cache`.

## Testing

`.github/workflows/test.yml` runs on pushes to `main`, on pull requests, weekly
(to catch new ARS or Claude Code releases that break the image) and on demand.
It lints the scripts (shellcheck) and the Dockerfile (hadolint), then builds the
image on amd64 and arm64 in two variants: the default, and one with the optional
components flipped (no Pandoc; tectonic and the PDF classifier on). Each build
checks that the newest ARS release was installed and tagged, and runs
`tests/smoke.sh` through `bin/ars`, so the tests use the real isolation settings.

Run the smoke tests locally after a build:

```sh
bin/ars --shell tests/smoke.sh --pandoc
```

## Licensing note

ARS is licensed CC BY-NC 4.0. This repository does not include ARS source code;
the image downloads it at build time. If you publish a built image, you are
redistributing ARS, and its license terms apply.
