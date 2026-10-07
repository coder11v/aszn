# aszn: Alias Zone

Per-directory zsh aliases. `cd` into a folder with a `.aszn` file and its aliases load. `cd` out and they unload, and any global alias they shadowed comes back. It's pure zsh, so there's no runtime dependency.

```console
$ cd ~/code/webapp
aszn: ▸ ~/code/webapp/.aszn: build, dev, t
$ build          # → npm run build
$ cd ..
aszn: ◂ unloaded ~/code/webapp/.aszn (3)
```

## Install

```sh
brew install coder11v/tap/aszn
aszn install        # adds one guarded line to ~/.zshrc
exec zsh
```

<details><summary>Manual / plugin managers</summary>

```sh
git clone https://github.com/coder11v/aszn ~/.aszn
~/.aszn/bin/aszn install
```
For oh-my-zsh, antidote, or zinit, load the repo as a plugin (`aszn.plugin.zsh`).
</details>

## Usage

| Command | |
|---|---|
| `aszn init` | Create a `.aszn` template here (already allowed) |
| `aszn edit` | Open it in `$EDITOR`, then allow + reload |
| `aszn list` | Show the active zone's aliases |
| `aszn status` | Is a zone active? Prints its absolute path |
| `aszn allow` / `deny` | Trust / revoke the zone file here |
| `aszn reload` | Re-source the active zone |
| `aszn uninstall` | Remove the `.zshrc` block (do this before `brew uninstall`) |

`.aszn` is plain zsh:

```zsh
alias build="npm run build"
alias -g J="| jq ."     # global
alias -s log=less       # suffix
```

## Security

Entering a directory must not run code you haven't reviewed (think `git clone` of a hostile repo). So a zone only loads after you `aszn allow` it. Allowing stores a snapshot of the file's exact contents, and any later edit requires allowing it again. `aszn init` and `aszn edit` do this for you.

## Config

Set these in `.zshrc` *before* the aszn line:

| Var | Default | |
|---|---|---|
| `ASZN_INHERIT` | `0` | `1` = subdirectories use the nearest parent zone |
| `ASZN_QUIET` | `0` | `1` = no load/unload messages |
| `ASZN_FILENAME` | `.aszn` | |
| `ASZN_TRUST_DIR` | `$XDG_DATA_HOME/aszn/trusted` | |

`$ASZN_ACTIVE_ZONE` holds the loaded file's path, which is handy in prompts.

## Releasing (maintainers)

```sh
scripts/release.zsh 0.2.0     # bumps version, tags, updates Formula/aszn.rb sha256
# copy Formula/aszn.rb → github.com/coder11v/homebrew-tap/Formula/aszn.rb
zsh tests/run.zsh
```
