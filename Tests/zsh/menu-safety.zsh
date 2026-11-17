#!/bin/zsh -fi
# 直接调用实际渲染函数，验证候选不会被当成 Prompt 代码执行。
source "$1/shell/zest.zsh"
marker=$2
rendered=''
zle() { [[ $1 == -M ]] && rendered=$2; return 0; }
setopt promptsubst
COLUMNS=1000
_zest_menu_selected=0
_zest_menu_rows=('checkout %n $(touch '"$marker"') 中文说明')
_zest_paint_menu
if [[ -e "$marker" || $rendered != *'%n'* || $rendered != *'$(touch '* ]]; then
  print 'FAIL 候选被解释为 Prompt 或命令替换'
  exit 1
fi
COLUMNS=20
_zest_paint_menu
if [[ $rendered != '› checkout'* || $rendered != *… || ${#rendered} -gt 19 ]]; then
  print "FAIL 窄终端未保留候选名称：[$rendered]"
  exit 1
fi
BUFFER='git ch'
CURSOR=6
before="${(F)_zest_menu_rows}"
_zest_read_menu "menu"$'\x1f'"$ZEST_SESSION"$'\x1f0\x1f0\x1f1\x1fstale\x1fother'
if [[ "${(F)_zest_menu_rows}" != "$before" ]]; then
  print 'FAIL 迟到快照覆盖了当前列表'
  exit 1
fi
print 'ok   候选不执行代码，窄终端保留名称，迟到快照不覆盖当前列表'
