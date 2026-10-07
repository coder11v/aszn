#!/usr/bin/env zsh
# Test suite: zsh tests/run.zsh
emulate -L zsh
setopt extended_glob

local root=${0:A:h:h}
local tmp=${${ASZN_TEST_TMP:-${TMPDIR:-/tmp}}%/}/aszn-test-$$
mkdir -p $tmp/home $tmp/proj $tmp/other $tmp/exact_proj
export HOME=$tmp/home ZDOTDIR=$tmp/home XDG_DATA_HOME=$tmp/data ASZN_QUIET=1 NO_COLOR=1
trap "rm -rf ${(q)tmp}" EXIT

integer pass=0 fail=0
ok() { if eval "$2"; then (( pass++ )); print "  ✓ $1"; else (( fail++ )); print "  ✗ $1"; fi }

alias gs='git status'          # user's global alias, will be shadowed

# Test 1: Inheritance zone
cat > $tmp/proj/.aszn <<'EOF'
scope: inherit
alias build="npm run build"
alias gs='git status -sb'
alias -g J='| jq .'
alias -s log=less
rm -rf /evil_command # Should be ignored safely by parser!
EOF

source $root/aszn.zsh
print "core functionality & safe parsing"
ok "chpwd hook registered"        '(( ${chpwd_functions[(I)_aszn_chpwd]} ))'

cd $tmp/proj 2>/dev/null
ok "zone loaded cleanly"          '[[ ${aliases[build]} == "npm run build" && $ASZN_ACTIVE_ZONE == $tmp/proj/.aszn ]]'
ok "shadows user alias"           '[[ ${aliases[gs]} == "git status -sb" ]]'
ok "global + suffix aliases"      '[[ ${galiases[J]} == "| jq ." && ${saliases[log]} == less ]]'
ok "status returns 0"             'aszn status >/dev/null'
ok "list shows aliases"           '[[ "$(aszn list)" == *build*npm\ run\ build* ]]'

# Scope test: inherited subdirectory
mkdir -p $tmp/proj/sub
cd $tmp/proj/sub 2>/dev/null
ok "inherited scope active in sub" '[[ ${aliases[build]} == "npm run build" ]]'

cd $tmp/other
ok "leaving unloads zone"         '(( ${+aliases[build]} + ${+galiases[J]} + ${+saliases[log]} == 0 ))'
ok "shadowed alias restored"      '[[ ${aliases[gs]} == "git status" ]]'

# Test 2: Exact scope zone
cat > $tmp/exact_proj/.aszn <<'EOF'
scope: exact
alias devrun="echo running dev"
EOF

cd $tmp/exact_proj 2>/dev/null
ok "exact zone loaded at root"    '[[ ${aliases[devrun]} == "echo running dev" ]]'

mkdir -p $tmp/exact_proj/sub
cd $tmp/exact_proj/sub 2>/dev/null
ok "exact zone unloads in sub"    '(( ! ${+aliases[devrun]} ))'

cd $tmp/other

print "\n$pass passed, $fail failed"
(( fail == 0 ))
