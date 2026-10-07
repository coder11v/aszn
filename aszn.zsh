# aszn.zsh: Alias Zone
# Per-directory zsh aliases. When you cd into a directory with a `.aszn` file,
# its aliases load. When you leave, they unload and any aliases they shadowed
# come back.
#
# https://github.com/coder11v/aszn  ·  MIT License
# Pure zsh: no external binaries on the hot path.

# ---------------------------------------------------------------------------
# Configuration (set before sourcing to override)
# ---------------------------------------------------------------------------
: ${ASZN_FILENAME:=.aszn}
: ${ASZN_INHERIT:=0}       # 1 = subdirectories inherit the nearest parent zone
: ${ASZN_SKIP_TRUST:=0}    # 1 = skip the `aszn allow` step (not recommended)
: ${ASZN_QUIET:=0}         # 1 = no load/unload messages
: ${ASZN_TRUST_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/aszn/trusted}

typeset -g ASZN_VERSION=0.1.0
typeset -g _ASZN_SOURCE=${${(%):-%x}:a}
typeset -gi _ASZN_CLI=${_ASZN_CLI:-0}

zmodload zsh/parameter 2>/dev/null
zmodload -F zsh/files b:zf_mkdir b:zf_rm 2>/dev/null

# Session state. Only initialized on first load so re-sourcing .zshrc is safe.
if (( ! ${+_aszn_keys} )); then
  typeset -g  ASZN_ACTIVE_ZONE=''   # absolute path of the loaded .aszn
  typeset -ga _aszn_keys=()         # "kind:name" entries defined by the zone
  typeset -gA _aszn_prev=()         # "kind:name" -> value the zone shadowed
fi
# kind: r = regular alias, g = global alias (-g), s = suffix alias (-s)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
_aszn_say() {  # $1 = ANSI color code or '', rest = message (stderr)
  local color=$1; shift
  if [[ -t 2 && -z $NO_COLOR && -n $color ]]; then
    print -P "%F{$color}aszn: $*%f" >&2
  else
    print -ru2 -- "aszn: $*"
  fi
}
_aszn_info() { (( ASZN_QUIET )) || _aszn_say '' "$@" }
_aszn_ok()   { (( ASZN_QUIET )) || _aszn_say 'green' "$@" }
_aszn_warn() { _aszn_say 'yellow' "$@" }
_aszn_err()  { _aszn_say 'red' "$@"; return 1 }

_aszn_colors() {  # sets c_* in the caller's scope
  if [[ -t 1 && -z $NO_COLOR ]]; then
    c_b=$'\e[1m' c_d=$'\e[2m' c_g=$'\e[32m' c_y=$'\e[33m' c_c=$'\e[36m' c_r=$'\e[0m'
  else
    c_b='' c_d='' c_g='' c_y='' c_c='' c_r=''
  fi
}

_aszn_mkdir() {
  if (( $+builtins[zf_mkdir] )); then zf_mkdir -p $1; else command mkdir -p -- $1; fi
}
_aszn_rm() {
  if (( $+builtins[zf_rm] )); then zf_rm -f $1; else command rm -f -- $1; fi
}

# ---------------------------------------------------------------------------
# Zone discovery & trust
# ---------------------------------------------------------------------------
_aszn_find() {  # REPLY = zone file for $PWD (or ''), returns 1 if none
  local dir=$PWD
  REPLY=''
  while :; do
    local candidate=${dir%/}/$ASZN_FILENAME
    if [[ -f $candidate ]]; then
      if [[ ${dir:a} == ${PWD:a} ]]; then
        REPLY=$candidate
        return 0
      else
        # Inspect scope setting if in a subdirectory
        local scope="inherit" line
        while IFS= read -r line || [[ -n $line ]]; do
          line="${${line##[[:space:]]##}%%[[:space:]]##}"
          if [[ $line == scope:* ]]; then
            scope=${line#scope:}
            scope=${scope//[[:space:]]/}
            break
          fi
        done < "$candidate"
        
        if [[ $scope == "exact" ]]; then
          # Don't use parent zone with exact scope, keep looking up
          :
        else
          REPLY=$candidate
          return 0
        fi
      fi
    fi
    [[ $dir != / ]] || return 1
    dir=${dir:h}
  done
  return 1
}

_aszn_here() {  # REPLY = zone file to act on: active zone, nearest zone, or ./.aszn
  if [[ -n $ASZN_ACTIVE_ZONE ]]; then REPLY=$ASZN_ACTIVE_ZONE
  elif _aszn_find; then REPLY=${REPLY:a}
  else REPLY=$PWD/$ASZN_FILENAME
  fi
}

# ---------------------------------------------------------------------------
# Load / unload
# ---------------------------------------------------------------------------
# Record every alias whose value or existence changed between the snapshot
# ($2, name of an assoc) and the live table ($3, e.g. `aliases`).
_aszn_diff() {
  local tag=$1 k
  local -A old new
  old=("${(@Pkv)2}")
  new=("${(@Pkv)3}")
  for k in "${(@k)old}" "${(@k)new}"; do
    (( ${+old[$k]} == ${+new[$k]} )) && [[ ${old[$k]} == "${new[$k]}" ]] && continue
    (( ${+new[$k]} )) && _aszn_keys+=("$tag:$k")
    (( ${+old[$k]} )) && _aszn_prev[$tag:$k]=${old[$k]}
  done
  _aszn_keys=("${(@u)_aszn_keys}")
}

_aszn_load() {
  emulate -L zsh
  local __aszn_file=${1:a}
  [[ -r $__aszn_file ]] || return 1

  local line scope="inherit" alias_def
  local -A __aszn_r __aszn_g __aszn_s
  __aszn_r=("${(@kv)aliases}")
  __aszn_g=("${(@kv)galiases}")
  __aszn_s=("${(@kv)saliases}")

  _aszn_keys=() _aszn_prev=()
  ASZN_ACTIVE_ZONE=$__aszn_file

  # Read file safely without sourcing executable code
  while IFS= read -r line || [[ -n $line ]]; do
    line="${${line##[[:space:]]##}%%[[:space:]]##}"
    [[ -z $line || $line == \#* ]] && continue

    if [[ $line == scope:* ]]; then
      scope=${line#scope:}
      scope=${scope//[[:space:]]/}
      continue
    fi

    if [[ $line == alias\ * ]]; then
      builtin eval "$line" 2>/dev/null
    fi
  done < "$__aszn_file"

  _aszn_diff r __aszn_r aliases
  _aszn_diff g __aszn_g galiases
  _aszn_diff s __aszn_s saliases

  if (( ${#_aszn_keys} )); then
    _aszn_ok "▸ ${(D)__aszn_file} [$scope]: ${(j:, :)${(@o)_aszn_keys#?:}}"
  else
    _aszn_info "▸ ${(D)__aszn_file} (no aliases loaded)"
  fi
}

_aszn_unload() {
  emulate -L zsh
  [[ -n $ASZN_ACTIVE_ZONE ]] || return 0
  local entry name n=${#_aszn_keys}

  # 1. Remove everything the zone defined (it may already be gone: ignore).
  for entry in "${_aszn_keys[@]}"; do
    name=${entry#?:}
    if [[ $entry == s:* ]]; then
      builtin unalias -s $name 2>/dev/null
    else
      builtin unalias $name 2>/dev/null
    fi
  done

  # 2. Restore anything the zone shadowed.
  for entry in "${(@k)_aszn_prev}"; do
    name=${entry#?:}
    case $entry in
      r:*) builtin alias    "$name=${_aszn_prev[$entry]}" ;;
      g:*) builtin alias -g "$name=${_aszn_prev[$entry]}" ;;
      s:*) builtin alias -s "$name=${_aszn_prev[$entry]}" ;;
    esac
  done

  (( n )) && _aszn_info "◂ unloaded ${(D)ASZN_ACTIVE_ZONE} ($n)"
  _aszn_keys=() _aszn_prev=()
  ASZN_ACTIVE_ZONE=''
}

# Reconcile loaded state with $PWD. Pass "force" to reload the same zone.
_aszn_sync() {
  emulate -L zsh
  local REPLY target=''
  _aszn_find && target=${REPLY:a}
  [[ $1 != force && $target == "$ASZN_ACTIVE_ZONE" ]] && return 0
  _aszn_unload
  [[ -n $target ]] && _aszn_load $target
  return 0
}

_aszn_chpwd() { _aszn_sync }

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------
typeset -g _ASZN_TEMPLATE='# .aszn: Alias Zone for this directory
#
# Scope config:
#   scope: inherit   (default: applies in this directory and all subdirectories)
#   scope: exact     (applies ONLY when standing directly in this directory)
scope: inherit

# Aliases to register:
# alias build="npm run build"
# alias dev="npm run dev"
# alias t="npm test --"
# alias -g J="| jq ."            # global alias
# alias -s log=less              # suffix alias: `app.log` opens in less
'

_aszn_init() {
  local file=$PWD/$ASZN_FILENAME
  if [[ -e $file ]]; then
    _aszn_warn "$ASZN_FILENAME already exists: $file"
    return 1
  fi
  print -rn -- $_ASZN_TEMPLATE >| $file || return 1
  print -r -- "Created $file"
  print -r -- "Add aliases with: aszn edit"
  (( _ASZN_CLI )) || _aszn_sync force
}

_aszn_list() {
  local c_b c_d c_g c_y c_c c_r; _aszn_colors
  if [[ -z $ASZN_ACTIVE_ZONE ]]; then
    print -r -- "${c_d}No active zone${c_r}"
    return 1
  fi
  print -r -- "${c_b}Alias Zone${c_r} ${c_d}·${c_r} ${(D)ASZN_ACTIVE_ZONE}"
  if (( ! ${#_aszn_keys} )); then
    print -r -- "  ${c_d}(no aliases yet, add some with: aszn edit)${c_r}"
    return 0
  fi

  local entry name value note
  local -i w=0
  for entry in "${_aszn_keys[@]}"; do
    (( ${#${entry#?:}} > w )) && w=${#${entry#?:}}
  done
  for entry in "${(@o)_aszn_keys}"; do
    name=${entry#?:} note=''
    case $entry in
      r:*) value=${aliases[$name]-} ;;
      g:*) value=${galiases[$name]-}; note=" ${c_d}(global)${c_r}" ;;
      s:*) value=${saliases[$name]-}; note=" ${c_d}(suffix)${c_r}" ;;
    esac
    print -r -- "  ${c_c}${(r:w:)name}${c_r}  ${value}${note}"
  done
}

_aszn_status() {
  local c_b c_d c_g c_y c_c c_r REPLY; _aszn_colors
  if [[ -n $ASZN_ACTIVE_ZONE ]]; then
    print -r -- "${c_g}●${c_r} ${c_b}Alias Zone active${c_r}"
    print -r -- "  file     $ASZN_ACTIVE_ZONE"
    print -r -- "  aliases  ${#_aszn_keys}"
    return 0
  fi
  print -r -- "${c_d}○${c_r} Not in an Alias Zone"
  return 1
}

_aszn_edit() {
  local REPLY; _aszn_here
  local file=$REPLY
  [[ -f $file ]] || { _aszn_err "no $ASZN_FILENAME here (create one with: aszn init)"; return 1 }
  local -a editor=(${=${VISUAL:-${EDITOR:-vi}}})
  "${editor[@]}" $file || { _aszn_err "editor exited with an error"; return 1 }
  (( _ASZN_CLI )) || _aszn_sync force
}

typeset -g _ASZN_RC_BEGIN='# >>> aszn >>>' _ASZN_RC_END='# <<< aszn <<<'

_aszn_install() {
  local rc=${ZDOTDIR:-$HOME}/.zshrc src=$_ASZN_SOURCE
  if [[ -f $rc && "$(<$rc)" == *"$_ASZN_RC_BEGIN"* ]]; then
    print -r -- "aszn is already installed in ${(D)rc}"
    return 0
  fi
  {
    print
    print -r -- $_ASZN_RC_BEGIN
    print -r -- "# Alias Zone: per-directory aliases. Managed by 'aszn install' / 'aszn uninstall'."
    print -r -- "[[ -r ${(qq)src} ]] && source ${(qq)src}"
    print -r -- $_ASZN_RC_END
  } >> $rc || { _aszn_err "could not write to $rc"; return 1 }
  print -r -- "✓ Added aszn to ${(D)rc}"
  (( _ASZN_CLI )) && print -r -- "  Restart your terminal or run: exec zsh"
  return 0
}

_aszn_uninstall() {
  local rc=${ZDOTDIR:-$HOME}/.zshrc line
  local -i skip=0
  if [[ ! -f $rc || "$(<$rc)" != *"$_ASZN_RC_BEGIN"* ]]; then
    print -r -- "aszn is not installed in ${(D)rc}"
    return 0
  fi
  local -a out
  for line in "${(@f)$(<$rc)}"; do
    if [[ $line == "$_ASZN_RC_BEGIN" ]]; then
      skip=1
      [[ ${#out} -gt 0 && -z ${out[-1]} ]] && out[-1]=()   # drop our blank spacer
      continue
    fi
    if (( skip )); then
      [[ $line == "$_ASZN_RC_END" ]] && skip=0
      continue
    fi
    out+=("$line")
  done
  print -r -- "$(<$rc)" >| $rc.aszn-backup || return 1
  print -rl -- "${out[@]}" >| $rc || return 1
  print -r -- "✓ Removed aszn from ${(D)rc} (backup: ${(D)rc}.aszn-backup)"
  print -r -- "  Trusted zones are kept in ${(D)ASZN_TRUST_DIR}; delete it to forget them."
}

_aszn_help() {
  print -r -- "aszn $ASZN_VERSION: Alias Zone, per-directory zsh aliases

Usage: aszn <command>

  init       Create a $ASZN_FILENAME template in the current directory
  list       List aliases from the active zone
  status     Show whether you're in an active zone
  edit       Open the zone in \$EDITOR, then allow + reload it
  allow      Trust the zone file here (required after manual edits)
  deny       Revoke trust and unload the zone file here
  reload     Re-source the active zone
  install    Add aszn to ${ZDOTDIR:-~}/.zshrc
  uninstall  Remove aszn from ${ZDOTDIR:-~}/.zshrc
  version    Print version

Config (set before aszn loads):
  ASZN_INHERIT=1     subdirectories inherit the nearest parent zone
  ASZN_QUIET=1       silence load/unload messages
  ASZN_FILENAME      zone filename (default: .aszn)"
}

_aszn_needs_shell() {
  (( _ASZN_CLI )) || return 0
  _aszn_err "'aszn $1' needs the shell hook, which isn't loaded in this shell."
  print -ru2 -- "      Run 'aszn install', then restart your terminal (or: exec zsh)."
  return 1
}

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------
aszn() {
  emulate -L zsh
  local cmd=${1:-help}
  (( $# )) && shift
  case $cmd in
    init)               _aszn_init ;;
    list|ls)            _aszn_needs_shell list   && _aszn_list ;;
    status|st)          _aszn_needs_shell status && _aszn_status ;;
    edit)               _aszn_edit ;;
    reload)             _aszn_needs_shell reload && _aszn_sync force ;;
    install)            _aszn_install ;;
    uninstall)          _aszn_uninstall ;;
    version|-v|--version) print -r -- "aszn $ASZN_VERSION" ;;
    help|-h|--help)     _aszn_help ;;
    *) _aszn_err "unknown command: $cmd (see: aszn help)"; return 2 ;;
  esac
}

_aszn_complete() {
  local -a cmds=(
    'init:create a .aszn template here'
    'list:list aliases from the active zone'
    'status:show whether a zone is active'
    'edit:edit and reload the zone'
    'reload:re-source the active zone'
    'install:add aszn to .zshrc'
    'uninstall:remove aszn from .zshrc'
    'version:print version'
    'help:show help'
  )
  (( CURRENT == 2 )) && _describe -t commands 'aszn command' cmds
}

# ---------------------------------------------------------------------------
# Activate (skipped when sourced by the standalone CLI)
# ---------------------------------------------------------------------------
if (( ! _ASZN_CLI )); then
  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd _aszn_chpwd
  (( $+functions[compdef] )) && compdef _aszn_complete aszn
  _aszn_sync   # handle shells that start inside a zone
fi
