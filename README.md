# github-app

`gh-app` lets an avatar act on GitHub **as its own GitHub App** (`<app>[bot]`),
with no human step after setup and no token stored anywhere. It's a bash
script on PATH (`curl`, `jq`, `openssl`, plus `gh` and `git`). There's no daemon,
sidecar or cache.

```
gh-app check              # app, org, reach, permissions, expiry -- never the token
gh-app exec <cmd...>      # run one command (gh, git, ...) as the app
```

The skill `skills/github-app/SKILL.md` tells the agent when and how to use it.

## Why a tool

A GitHub App has no long-lived token. Its long-lived credential is a **private
key**, and an installation token derived from it lives **one hour**, fixed by
GitHub. `gh` and `git` only take a ready token, so something has to mint one.
`gh-app` does it on every call:

1. sign a JWT with the key (RS256, `iss` = app id, 10 minutes);
2. `GET /app` proves the key belongs to the app id;
3. `GET /orgs/<org>/installation` finds the installation;
4. `POST /app/installations/<id>/access_tokens` mints the token;
5. `GET /users/<slug>[bot]` gets the bot user's id for the commit address.

## What `exec` gives the child, and only the child

- the token in the environment `gh` reads, so PRs, issues, comments and
  discussions are the app's;
- a git credential helper for `https://github.com` (`!gh auth git-credential`)
  and `git@github.com:` → `https://github.com/`, via `GIT_CONFIG_COUNT` /
  `GIT_CONFIG_KEY_n` / `GIT_CONFIG_VALUE_n`, with the inherited helper list
  reset first. Nothing is written to any git config file;
- `GIT_AUTHOR_*` / `GIT_COMMITTER_*` = `<slug>[bot]` and
  `<id>+<slug>[bot]@users.noreply.github.com`, so commits are the app's too.

The private key is removed from the child's environment. The token goes to
curl on stdin, never in argv, and is never printed.

## Configuration

Four variables, all resolved from `pass` through `SANDBOX_SECRETS` in the
avatar's `harness/config`. The config describes the app completely, and
`gh-app` checks every value against what GitHub reports. A mismatch fails
closed and names the variable.

```bash
SANDBOX_SECRETS=(
    "GITHUB_APP_ID=pass:<app-entry>/app-id"
    "GITHUB_APP_PRIVATE_KEY=pass:<app-entry>/app-private-key"   # PEM, multi-line is fine
    "GITHUB_APP_NAME=pass:<app-entry>/github-app-name"          # name or slug
    "GITHUB_APP_ORG=pass:<app-entry>/org"                       # the org it is installed on
)
```

The app's permissions are set on GitHub by its owner, and `gh-app check` lists
them. The token always carries the app's full permissions on that installation.

## Install

```bash
scripts/install <avatar-dir>     # copies the tool + skill, links gh-app into each harness
```

Then commit in the avatar and **reload** it (`./launch-agent <harness> reload`):
secrets are resolved at container creation. Inside: `gh-app check`.

## Tests

```bash
tests/run-tests.sh               # §1 offline; §2 live when GITHUB_APP_* are set
tests/run-tests.sh owner/repo    # also proves git reaches that repo
```
