# zest — zsh integration.
#
# Sends the command line to Zest.app while you type, and lets the popup handle
# Tab, ↑, ↓, Enter and Esc while it is open. When the popup is closed (or the app
# is not running) every key does what it did before.
# Zed / Wu 默认由 ZLE 在命令行下方绘制文本列表，不依赖编辑器的光标坐标。
# 加载前设置 ZEST_TERMINAL_MENU=1 / 0，可强制启用或停用文本列表。
#
# Load it at the END of ~/.zshrc, after other plugins have set their key bindings:
#   source "$HOME/Library/Application Support/zest/zest.zsh"
#
# Protocol (one message per line, fields separated by \x1f, newlines in the
# command line sent as \x1e). See docs/architecture.md.

[[ -o interactive ]] || return 0
[[ -n "$ZEST_LOADED" ]] && return 0
typeset -g ZEST_LOADED=1

zmodload zsh/net/socket 2>/dev/null || return 0
zmodload zsh/datetime 2>/dev/null
autoload -Uz add-zle-hook-widget 2>/dev/null || return 0

typeset -g _zest_socket="${ZEST_SOCKET:-$HOME/Library/Application Support/zest/zest.sock}"
typeset -g _zest_fd=""
typeset -g _zest_seq=0
typeset -g _zest_last=""
typeset -g _zest_retry_at=0
typeset -g _zest_ask_position=0
[[ "$TERM_PROGRAM" == ghostty || -n "$ZEST_ASK_POSITION" ]] && _zest_ask_position=1
typeset -g _zest_terminal_menu=0
[[ "${ZEST_TERMINAL_MENU:-}" == 1 ||
   ( -z "${ZEST_TERMINAL_MENU+x}" && ( "$TERM_PROGRAM" == zed || "$__CFBundleIdentifier" == me.farshed.Wu ) ) ]] && _zest_terminal_menu=1
(( _zest_terminal_menu )) && _zest_ask_position=0
typeset -ga _zest_menu_rows=()
typeset -g _zest_menu_selected=0
typeset -gx ZEST_SESSION="$$-$RANDOM"

# Settings written by Zest.app.
typeset -g ZEST_GHOST_TEXT=1
[[ -r "$HOME/Library/Application Support/zest/settings.zsh" ]] && source "$HOME/Library/Application Support/zest/settings.zsh"

# --- Connection -----------------------------------------------------------------

_zest_connect() {
  [[ -n "$_zest_fd" ]] && return 0
  (( EPOCHREALTIME < _zest_retry_at )) && return 1
  if [[ ! -S "$_zest_socket" ]] || ! zsocket "$_zest_socket" 2>/dev/null; then
    # The app is not running. Try again in a few seconds, not on every key.
    _zest_retry_at=$(( EPOCHREALTIME + 3 ))
    return 1
  fi
  _zest_fd=$REPLY
  local app=${__CFBundleIdentifier:-$TERM_PROGRAM}
  _zest_write "hello"$'\x1f'"$ZEST_SESSION"$'\x1f'"$$"$'\x1f'"$app"$'\x1f'"${HISTFILE:-$HOME/.zsh_history}" || return 1
  if (( _zest_terminal_menu )); then
    _zest_write "terminal"$'\x1f'"$ZEST_SESSION" || return 1
    zle -F -w "$_zest_fd" _zest_receive
  fi
  local name list=()
  for name in ${(k)aliases}; do list+=("$name=${aliases[$name]//$'\n'/ }"); done
  (( ${#list} )) && _zest_write "aliases"$'\x1f'"$ZEST_SESSION"$'\x1f'"${(pj:\x1f:)list}"
  return 0
}

_zest_disconnect() {
  (( _zest_terminal_menu )) && [[ -n "$_zest_fd" ]] && zle -F "$_zest_fd" 2>/dev/null
  [[ -n "$_zest_fd" ]] && exec {_zest_fd}>&- 2>/dev/null
  _zest_fd=""
  _zest_retry_at=$(( EPOCHREALTIME + 3 ))
  _zest_menu_rows=()
  (( _zest_terminal_menu )) && zle -M '' 2>/dev/null
}

# Writes one message. A closed socket must not kill the shell with SIGPIPE.
_zest_write() {
  [[ -n "$_zest_fd" ]] || return 1
  setopt localoptions localtraps
  trap '' PIPE
  if ! print -rn -- "$1"$'\n' >&$_zest_fd 2>/dev/null; then
    _zest_disconnect
    return 1
  fi
}

# --- Messages -------------------------------------------------------------------

# Sets REPLY to the session, folder, cursor and command line (no subshell: this
# runs on every key press).
_zest_line() {
  REPLY="$ZEST_SESSION"$'\x1f'"$PWD"$'\x1f'"$CURSOR"$'\x1f'"${BUFFER//$'\n'/$'\x1e'}"
}

# 只显示与当前输入完全匹配的快照，丢弃异步生成器迟到的旧结果。
_zest_read_menu() {
  local parts=("${(@ps:\x1f:)1}") count buffer
  [[ ${parts[1]} == menu && ${parts[2]} == "$ZEST_SESSION" &&
     ${parts[3]} == <-> && ${parts[4]} == [0-4] && ${parts[5]} == [0-5] ]] || return
  count=${parts[5]}
  (( ${#parts} >= count + 6 && (count == 0 || parts[4] < count) )) || return
  buffer="${(pj:\x1f:)parts[$((count + 6)),-1]}"
  buffer=${buffer//$'\x1e'/$'\n'}
  [[ ${parts[3]} == "$CURSOR" && $buffer == "$BUFFER" ]] || return
  _zest_menu_selected=${parts[4]}
  _zest_menu_rows=()
  (( count )) && _zest_menu_rows=("${(@)parts[6,$((count + 5))]}")
  _zest_paint_menu
}

_zest_paint_menu() {
  setopt localoptions
  unsetopt promptsubst
  local rows=() row clipped i=0 width=$(( COLUMNS > 2 ? COLUMNS - 1 : 1 ))
  for row in "${_zest_menu_rows[@]}"; do
    if (( i == _zest_menu_selected )); then row="› $row"; else row="  $row"; fi
    # Prompt 截断按显示宽度处理中文；先转义 %，且禁止执行候选内容中的命令替换。
    clipped="%${width}>…>${row//\%/%%}%>>"
    rows+=("${(%)clipped}")
    (( i++ ))
  done
  zle -M "${(F)rows}"
}

# ZLE 在 socket 可读时调用，不轮询、不占用额外后台进程。
_zest_receive() {
  [[ -n "$2" ]] && { _zest_disconnect; return; }
  local line
  if IFS= read -r -t 0.25 -u "$1" line; then
    _zest_read_menu "$line"
    zle -R
  else
    _zest_disconnect
  fi
}

# Asks the app what a key should do. Prints "pass", "ok" or "set".
# For "set", the new cursor and buffer are in $_zest_cursor and $_zest_buffer.
_zest_ask() {
  _zest_connect || { REPLY=pass; return; }
  (( _zest_seq++ ))
  _zest_line
  _zest_write "key"$'\x1f'"$_zest_seq"$'\x1f'"$1"$'\x1f'"$REPLY" || { REPLY=pass; return; }
  local line parts
  # Skip replies to earlier questions that came too late.
  while IFS= read -r -t 0.25 -u $_zest_fd line; do
    parts=("${(@ps:\x1f:)line}")
    if [[ "${parts[1]}" == menu ]]; then _zest_read_menu "$line"; continue; fi
    [[ "${parts[1]}" == r && "${parts[2]}" == "$_zest_seq" ]] || continue
    REPLY=${parts[3]}
    if [[ $REPLY == set ]]; then
      _zest_cursor=${parts[4]}
      _zest_buffer=${parts[5]//$'\x1e'/$'\n'}
    fi
    return
  done
  REPLY=pass
}

# Called before every redraw: tell the app when the line changed.
_zest_redraw() {
  local now="$CURSOR:$BUFFER"
  [[ "$now" == "$_zest_last" ]] && return
  local before=$_zest_last
  _zest_last=$now
  if (( _zest_terminal_menu && ${#_zest_menu_rows} )); then
    _zest_menu_rows=()
    zle -M ''
  fi
  _zest_ghost
  _zest_connect || return
  # This runs before the screen is redrawn, so the terminal's cursor is still where
  # the previous state put it.
  if (( _zest_ask_position )) && [[ -n "$BUFFER" ]] &&
     [[ -z "${before#*:}" || "$_zest_where_size" != "$LINES:$COLUMNS" ]]; then
    _zest_where "${${before%%:*}:-0}"
  fi
  _zest_line && _zest_write "line"$'\x1f'"$REPLY"
}

# Terminals that don't tell macOS where their text cursor is (Ghostty) get asked
# directly with CSI 6n: when you start typing a line, and when the window size
# changes. Keys typed while we wait for the answer are put back.
typeset -g _zest_where_size=""
_zest_where() {
  # $1: the buffer index the terminal's cursor is at right now.
  setopt localoptions extendedglob
  local reply="" c
  _zest_where_size="$LINES:$COLUMNS"
  print -n $'\e[6n' >/dev/tty
  while read -s -k 1 -t 0.3 c; do
    reply+=$c
    [[ $c == R ]] && break
  done
  if [[ $reply == (#b)(*)$'\e['([0-9]##)';'([0-9]##)R ]]; then
    [[ -n "${match[1]}" ]] && zle -U "${match[1]}"
    _zest_write "pos"$'\x1f'"$ZEST_SESSION"$'\x1f'"${match[2]}"$'\x1f'"${match[3]}"$'\x1f'"$LINES"$'\x1f'"$COLUMNS"$'\x1f'"$1"
  elif [[ -n "$reply" ]]; then
    zle -U "$reply"
  fi
}

_zest_finish() {
  _zest_last=""
  POSTDISPLAY=""
  _zest_menu_rows=()
  (( _zest_terminal_menu )) && zle -M ''
  [[ -n "$_zest_fd" ]] && _zest_write "end"$'\x1f'"$ZEST_SESSION"
}

_zest_preexec() {
  [[ -n "$_zest_fd" ]] && _zest_write "exec"$'\x1f'"$ZEST_SESSION"$'\x1f'"${1//$'\n'/$'\x1e'}"
}

# --- Ghost text: the rest of the last matching command, shown in grey ---------------

_zest_ghost() {
  POSTDISPLAY=""
  region_highlight=("${(@)region_highlight:#*zest-ghost*}")
  (( ZEST_GHOST_TEXT )) || return
  [[ -n "$BUFFER" && $CURSOR -eq ${#BUFFER} && "$BUFFER" != *$'\n'* ]] || return
  local match=${history[(r)${(b)BUFFER}?*]}
  [[ -n "$match" && "$match" != *$'\n'* ]] || return
  POSTDISPLAY=${match#$BUFFER}
  region_highlight+=("P0 ${#POSTDISPLAY} fg=8 memo=zest-ghost")
}

# --- Keys -----------------------------------------------------------------------

typeset -gA _zest_original

# Runs the widget the key had before zest took it over.
_zest_fallback() {
  local widget=${_zest_original[$1]}
  [[ -n "$widget" && "$widget" != undefined-key ]] && zle "$widget"
}

_zest_apply() {
  _zest_menu_rows=()
  (( _zest_terminal_menu )) && zle -M ''
  BUFFER=$_zest_buffer
  CURSOR=$_zest_cursor
  _zest_last="$CURSOR:$BUFFER"
  _zest_ghost
  _zest_connect && _zest_line && _zest_write "line"$'\x1f'"$REPLY"
}

_zest_key() {
  _zest_ask "$1"
  case $REPLY in
    set) _zest_apply ;;
    ok) ;;
    *) _zest_fallback "$KEYS" ;;
  esac
}

_zest_tab()    { _zest_key tab }
_zest_up()     { _zest_key up }
_zest_down()   { _zest_key down }
_zest_enter()  { _zest_key enter }
_zest_escape() { _zest_key escape }

_zest_right() {
  # → at the end of the line accepts the ghost text.
  if [[ -n "$POSTDISPLAY" && $CURSOR -eq ${#BUFFER} ]]; then
    BUFFER+=$POSTDISPLAY
    CURSOR=${#BUFFER}
    POSTDISPLAY=""
    return
  fi
  _zest_fallback "$KEYS"
}

_zest_bind() {
  local key=$1 widget=$2 current
  current=$(bindkey -M emacs "$key" 2>/dev/null)
  current=${current##* }
  [[ $current == _zest_* ]] && return
  _zest_original[$key]=$current
  bindkey -M emacs "$key" "$widget"
  # In vi mode Esc switches to command mode; leave it alone.
  [[ $key == $'\e' ]] || bindkey -M viins "$key" "$widget"
}

zle -N _zest_tab
zle -N _zest_up
zle -N _zest_down
zle -N _zest_enter
zle -N _zest_escape
zle -N _zest_right
zle -N _zest_redraw
zle -N _zest_finish
zle -N _zest_receive

# Raw key sequences, so they match $KEYS in _zest_fallback.
_zest_bind $'\t' _zest_tab
_zest_bind $'\e[A' _zest_up
_zest_bind $'\eOA' _zest_up
_zest_bind $'\e[B' _zest_down
_zest_bind $'\eOB' _zest_down
_zest_bind $'\r' _zest_enter
_zest_bind $'\e' _zest_escape
_zest_bind $'\e[C' _zest_right
_zest_bind $'\eOC' _zest_right

add-zle-hook-widget line-pre-redraw _zest_redraw
add-zle-hook-widget line-finish _zest_finish
autoload -Uz add-zsh-hook
add-zsh-hook preexec _zest_preexec
