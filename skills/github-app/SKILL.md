---
name: github-app
description: >
  How this avatar acts on GitHub as its own GitHub App (`<app>[bot]`): the
  `gh-app` CLI, which commands to run through it, and what its failures mean.
  Read this before any `gh` or `git` command that touches github.com.
---

# GitHub as this avatar's app

This avatar has its own **GitHub App**. Everything it does on GitHub — pushes,
commits, pull requests, issues, comments, discussions — should appear as the
app's bot user, `<app>[bot]`, not as a person. **`gh-app`** makes that happen.

```
gh-app check              # which app, which org, how many repos, permissions, expiry
gh-app exec <cmd...>      # run ONE command as the app
```

Start a session's GitHub work with `gh-app check`. It proves the four
configured values describe one real app installed on the configured org, and
shows the identity your commits will carry.

## Run every GitHub command through `gh-app exec`

```bash
gh-app exec git clone git@github.com:<org>/<repo>.git
gh-app exec git commit -m "..."          # yes, commit too -- see below
gh-app exec git push -u origin my-branch
gh-app exec gh pr create --title "..." --body-file pr.md
gh-app exec gh issue comment 12 --body "..."
gh-app exec gh api repos/<org>/<repo>/discussions
```

Each call mints a fresh token (they live one hour) and gives it to that one
command only. Inside the command:

- `gh` acts as the app, so PRs, issues, comments and discussions are the app's.
- `git` has an https credential for github.com, and `git@github.com:` remotes
  are rewritten to https so it applies. No ssh key is involved.
- **The commit author and committer are the app's bot**, with GitHub's noreply
  address. That is set for the command `exec` runs and for nothing else, so a
  plain `git commit` outside `gh-app exec` is authored by whatever identity the
  container has. Commit through `gh-app exec` in any repository that lives on
  GitHub.

For several steps at once, wrap a shell: `gh-app exec sh -c 'git commit -m x && git push'`.

## The token is never shown. Keep it that way

`gh-app` never prints the token, writes it to disk or passes it in argv. Under
`exec` it exists in the child's environment, so do not run anything there that
would echo it: no `gh auth token`, `gh auth status --show-token`, `env`,
`printenv`, `set -x`, or `echo` of credential variables. If you need to know
what the app can do, `gh-app check` answers that.

## What the app can do is set on GitHub

The app's permissions are configured by its owner on GitHub. `gh-app check`
lists them. A 403 from GitHub under `exec` means the app lacks the permission
for that action. Say so, naming the permission. Don't look for another credential
to get around it. Pushing a change under `.github/workflows/` needs the
`workflows` permission specifically.

If the avatar also has a read-only GitHub token for reading code elsewhere,
that token stays for reading. Anything that writes, or that should be recorded
as this avatar's work, goes through `gh-app exec`.

## When something fails

Every failure names the variable or the request at fault, and exits non-zero
before the command runs:

- **`$GITHUB_APP_... is not set`**: the avatar's `harness/config` lacks the
  entry. That file is the operator's. Report it.
- **not a usable PEM private key**: the key lost its newlines or is not a key.
- **GitHub rejected the JWT / no app with id**: the key and the app id belong
  to different apps, or the id is wrong.
- **`$GITHUB_APP_NAME` ... two different apps**: the configured name doesn't
  match the app the key and id identify.
- **not installed on org**: the app is not installed there, or the org name
  is wrong.
- **404 on a repository under `exec`**: the repo does not exist, or the app's
  installation does not include it. GitHub does not tell these apart.
