# word-aux-filter-lua-For-Rime
一个Rime词辅脚本，灵感来自Moran，独立而出的词辅lua

用法：
engine:
  translators:
    - lua_translator@*aux_word_filter
########################################
# ... schema 定义 ...
########################################
# 脚本配置
word_filter:
  enable_word_filter: true               # true: 开启功能, false: 关闭
  word_filter_match_indicator: "〔Matched!〕"  # 匹配成功时，显示在候选项后的提示符，可留空 ""

灵感来自Moran Project: https://github.com/rimeinn/rime-moran/blob/main/lua/moran_express_translator.lua

