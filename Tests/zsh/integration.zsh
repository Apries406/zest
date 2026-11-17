#!/bin/zsh -f
# End-to-end test of shell/zest.zsh: drives an interactive zsh in a pseudo-terminal
# (zsh/zpty) against `zest serve`, types, presses keys and checks the command line.
# Run with: scripts/test-zsh.sh
emulate -L zsh
zmodload zsh/zpty

zest=$1 socket=$2 root=$3
failures=0

dump=${socket:h}/buffer
menu_dump=${socket:h}/menu

drain() {
  local chunk
  REPLY=""
  while zpty -r -t z chunk 2>/dev/null; do REPLY+=$chunk; done
}

start_shell() {
  zpty -d z 2>/dev/null
  zpty z "$1 ZEST_SOCKET='$socket' ZEST_GHOST_TEXT=0 HISTFILE=/dev/null PS1='%% ' TERM=xterm zsh -f -i"
  # Ctrl-X Ctrl-D writes the command line to a file, so the test can read it exactly.
  zpty -w z "source '$root/shell/zest.zsh'; _dump() { print -rn -- \"\$BUFFER\" > '$dump'; print -r -- \"\${(F)_zest_menu_rows}\" > '$menu_dump' }; zle -N _dump; bindkey '^X^D' _dump; print READY"
  zpty -r z _ '*READY*READY*'
}

# check <name> <keys> <expected command line>
check() {
  local name=$1 keys=$2 expected=$3
  start_shell "$4"
  : > "$dump"
  # One key at a time, like a person types: zle skips redraws while input is pending.
  local key
  for key in "${(@s:|:)keys}"; do
    [[ $key == SLEEP ]] && { sleep 0.6; continue; }
    zpty -w -n z "$key"
    sleep 0.08
    drain
  done
  sleep 0.4
  drain
  zpty -w -n z $'\x18\x04'
  sleep 0.3
  drain
  local got=$(<"$dump")
  if [[ "$got" == "$expected" ]]; then
    print "ok   $name"
  else
    print "FAIL $name: expected [$expected], got [$got]"
    (( failures++ ))
  fi
}

# Keys are separated by |.
check "tab inserts subcommand" "g|i|t| |c|h|e|c|"$'\t' "git checkout "
check "arrow down then tab" "g|i|t| |c|h|e|c|"$'\e[B'"|"$'\t' "git cherry-pick "
check "enter runs the line when the popup is closed" "p|r|i|n|t| |h|i|"$'\r' ""
check "enter after a space runs the command" "g|i|t| |s|t|a|t|u|s| |"$'\r' ""
# Wait out KEYTIMEOUT after Esc, or zle reads Esc+Tab as Meta-Tab.
check "escape closes the popup, so Tab does not insert" "g|i|t| |c|h|e|c|"$'\e'"|SLEEP|"$'\t' "git chec"
check "folders" "c|d| |S|o|u|r|"$'\t' "cd Sources/"
check "option" "l|s| |-|-|c|o|l|"$'\t' "ls --color="

# Terminals like Ghostty are asked where the cursor is (CSI 6n). Keys typed before
# the terminal answers must not get lost.
check_position() {
  start_shell ZEST_ASK_POSITION=1
  : > "$dump"
  local out="" chunk i
  zpty -w -n z g
  for i in {1..40}; do
    drain
    out+=$REPLY
    [[ $out == *$'\e[6n'* ]] && break
    sleep 0.05
  done
  if [[ $out != *$'\e[6n'* ]]; then
    print "FAIL position: the shell did not ask for the cursor position"
    (( failures++ ))
    return
  fi
  zpty -w -n z i
  zpty -w -n z t
  zpty -w -n z $'\e[5;3R'
  for key in " " c h; do
    sleep 0.08
    zpty -r -t z _ 2>/dev/null
    zpty -w -n z "$key"
  done
  sleep 0.4
  zpty -w -n z $'\x18\x04'
  sleep 0.3
  local got=$(<"$dump")
  if [[ "$got" != "git ch" ]]; then
    print "FAIL position: keys typed while waiting got lost: [$got]"
    (( failures++ ))
  elif ! grep -q "^position 5;3 at 0 of " "${socket:h}/server.log"; then
    print "FAIL position: the app did not get the position"
    (( failures++ ))
  else
    print "ok   position query keeps typed-ahead keys"
  fi
}
check_position

# 使用真实 socket 与 ZLE 显示消息，确保列表不再依赖屏幕坐标。
check_terminal_menu() {
  start_shell 'TERM_PROGRAM=zed'
  local key out="" chunk
  for key in g i t ' ' c h; do
    zpty -w -n z "$key"
    sleep 0.08
    drain
    out+=$REPLY
  done
  sleep 0.3
  drain
  out+=$REPLY
  zpty -w -n z $'\x18\x04'
  sleep 0.2
  drain
  if [[ $(<"$dump") == 'git ch' && $(<"$menu_dump") == *checkout* && $out == *checkout* ]]; then
    print 'ok   文本列表出现在命令行下方，且不改变命令内容'
  else
    print "FAIL 终端列表：命令=[$(<"$dump")] 列表=[$(<"$menu_dump")] 输出=[$out]"
    (( failures++ ))
  fi
}
check_terminal_menu
check '终端列表方向键后 Tab 接受候选' "g|i|t| |c|h|e|c|"$'\e[B'"|"$'\t' 'git cherry-pick ' 'ZEST_TERMINAL_MENU=1'
check '终端列表 Esc 关闭后恢复原 Tab 行为' "g|i|t| |c|h|e|c|"$'\e'"|SLEEP|"$'\t' 'git chec' 'ZEST_TERMINAL_MENU=1'

check_async_terminal_menu() {
  start_shell 'ZEST_TERMINAL_MENU=1'
  zpty -w -n z 'zest-delayed '
  local i
  for i in {1..12}; do sleep 0.05; drain; done
  zpty -w -n z $'\x18\x04'
  sleep 0.2
  drain
  if [[ $(<"$dump") == 'zest-delayed ' && $(<"$menu_dump") == *late-result* ]]; then
    print 'ok   停止输入后仍能收到异步候选更新'
  else
    print "FAIL 异步终端列表：[$(<"$menu_dump")]"
    (( failures++ ))
  fi
}
check_async_terminal_menu

zpty -d z 2>/dev/null
(( failures == 0 )) && print "all zsh tests passed" || print "$failures zsh test(s) failed"
exit $failures
