#!/usr/bin/env bash
# compgen -X + extglob: what actually happens, and when.
# Run:  bash test/compgen_x_extglob.sh        (tested with bash 5.2.37, Git Bash)

echo "bash: $BASH_VERSION"
sec() { printf '\n--- %s\n' "$*"; }
pm()  { sed 's/^/  | /'; }

sec '1. baseline: ordinary glob is filtered with extglob OFF'
shopt -u extglob
echo "  compgen -W 'foo bar foobar barfoo' -X 'foo*'"
compgen -W 'foo bar foobar barfoo' -X 'foo*' | pm

sec '2. quoted extglob pattern, extglob OFF  -> nothing filtered (literal match)'
echo "  compgen -W 'foo bar foobar barfoo' -X '@(foo|bar)'"
compgen -W 'foo bar foobar barfoo' -X '@(foo|bar)' | pm

sec '3. quoted extglob pattern, extglob ON   -> really filtered'
shopt -s extglob
echo "  compgen -W 'foo bar foobar barfoo' -X '@(foo|bar)'"
compgen -W 'foo bar foobar barfoo' -X '@(foo|bar)' | pm

sec '4. UNQUOTED extglob, extglob OFF -> syntax error (isolated bash -c)'
bash -c 'shopt -u extglob; compgen -W "foo bar" -X @(foo|bar)' 2>&1 | pm
echo "  rc=${PIPESTATUS[0]}"

sec '4b. same line "shopt -s extglob; compgen ... @(...)" -> still a syntax error'
bash -c 'shopt -u extglob; shopt -s extglob; compgen -W "foo bar" -X @(foo|bar)' 2>&1 | pm
echo "  rc=${PIPESTATUS[0]}"

sec '5. UNQUOTED extglob, extglob ON on an earlier line -> works'
shopt -s extglob
echo "  compgen -W 'foo bar foobar barfoo' -X @(foo|bar)"
compgen -W 'foo bar foobar barfoo' -X @(foo|bar) | pm

sec '6. one-shot: bash -O extglob -c ...'
bash -O extglob -c 'compgen -W "foo bar foobar barfoo" -X @(foo|bar)' | pm

sec '7. with extglob OFF the pattern is pure literal text'
shopt -u extglob
echo "  candidates: '@foo' '@(foo|bar)' '@(foo)' 'x'"
echo "  compgen -W '@foo @(foo|bar) @(foo) x' -X '@(foo|bar)'"
compgen -W '@foo @(foo|bar) @(foo) x' -X '@(foo|bar)' | pm

sec '8. leading ! means different things with the option off/on'
echo "  shopt -u extglob; compgen -W 'foo bar baz' -X '!(foo)'"
compgen -W 'foo bar baz' -X '!(foo)' | pm
shopt -s extglob
echo "  shopt -s extglob; compgen -W 'foo bar baz' -X '!(foo)'"
compgen -W 'foo bar baz' -X '!(foo)' | pm

sec '9. the same global switch governs other pattern contexts'
shopt -u extglob; p='@(bar)'; v=foobar
echo "  OFF: \${v%\$p} -> '${v%$p}'"
shopt -s extglob
echo "  ON : \${v%\$p} -> '${v%$p}'"

sec '10. function body parsed while extglob was OFF -> syntax error at definition'
bash -c '
f() { compgen -W "foo bar" -X @(foo|bar); }
shopt -s extglob
f
' 2>&1 | pm
echo "  rc=${PIPESTATUS[0]}"

sec '11. quoted pattern: turning extglob on later is enough'
shopt -u extglob
p='@(foo|bar)'
shopt -s extglob
echo "  compgen -W 'foo bar baz' -X \"\$p\""
compgen -W 'foo bar baz' -X "$p" | pm
echo
