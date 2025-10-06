-- Word Filnter 独立脚本 (缓存版本)
--灵感来自Moran Project: https://github.com/rimeinn/rime-moran/blob/main/lua/moran_express_translator.lua
-- 支持词辅助功能，将符合条件的候选项缓存，在辅助码输入时注入
-- 格式：两字词 "nǐ;fr hǎo;nz"，三字词 "nǐ;rx hǎo;nz ya;ky"
--[[
词辅功能矩阵 (Word Auxiliary Function Matrix)
该矩阵详细说明了在输入“主编码+辅助码”时，脚本如何匹配二字词和三字词。
匹配规则为“前缀匹配”：用户输入的辅助码，只要是下面任一模式的开头部分，即可匹配。

--- 1. 二字词辅助码匹配规则 (你好 nǐ;fr hǎo;nz) ---
  - 模式一: 第一个字的全码 (缓存模式: "fr") -> 用户输入 "f" 或 "fr" 均可匹配
  - 模式二: 第二个字的全码 (缓存模式: "nz") -> 用户输入 "n" 或 "nz" 均可匹配
  - 模式三: 两个字的首码组合 (缓存模式: "fn") -> 用户输入 "f" 或 "fn" 均可匹配
  - 模式四: 两个字的尾码组合 (缓存模式: "rz") -> 用户输入 "r" 或 "rz" 均可匹配

--- 2. 三字词辅助码匹配规则 (我爱你 wǒ;rx ài;nz nǐ;ky) ---
  - 模式一: 第一个字的全码 ("rx")
  - 模式二: 第二个字的全码 ("nz")
  - 模式三: 第三个字的全码 ("ky")
  - 模式四: 首尾两个字的首码组合 ("rk")
  - 模式五: 首尾两个字的尾码组合 ("xy")
]]
--- @skowosy——“ZHT0711”
local word_filter = {}

function word_filter.init(env)
   env.enable_word_filter = env.engine.schema.config:get_bool("word_filter/enable_word_filter") or true
   env.word_filter_match_indicator = env.engine.schema.config:get_string("word_filter/word_filter_match_indicator")
   env.word_cache = {}
end

function word_filter.fini(env)
   env.word_cache = nil
   collectgarbage()
end

function word_filter.extract_aux_codes(comment)
   local aux_codes = {}
   for aux_code in comment:gmatch("[^%s]+;([^%s]+)") do
      table.insert(aux_codes, aux_code)
   end
   return aux_codes
end

function word_filter.generate_two_word_patterns(aux_codes)
   if #aux_codes < 2 then return {} end
   local patterns = {}
   local code1, code2 = aux_codes[1], aux_codes[2]
   
   table.insert(patterns, code1)
   table.insert(patterns, code2)
   if #code1 > 0 and #code2 > 0 then
      table.insert(patterns, code1:sub(1,1) .. code2:sub(1,1))
   end
   if #code1 > 0 and #code2 > 0 then
      table.insert(patterns, code1:sub(-1) .. code2:sub(-1))
   end
   return patterns
end

function word_filter.generate_three_word_patterns(aux_codes)
   if #aux_codes < 3 then return {} end
   local patterns = {}
   local code1, code2, code3 = aux_codes[1], aux_codes[2], aux_codes[3]
   
   table.insert(patterns, code1)
   table.insert(patterns, code2)
   table.insert(patterns, code3)
   if #code1 > 0 and #code3 > 0 then
      table.insert(patterns, code1:sub(1,1) .. code3:sub(1,1))
   end
   if #code1 > 0 and #code3 > 0 then
      table.insert(patterns, code1:sub(-1) .. code3:sub(-1))
   end
   return patterns
end

function word_filter.get_cache_key(input, word_len, pattern)
   return input .. "|" .. word_len .. "|" .. pattern
end

function word_filter.is_word_filter_input(input)
   local input_len = utf8.len(input)
   
   if input_len > 6 then
      return true, input:sub(1, 6), input:sub(7), 3
   elseif input_len > 4 then
      return true, input:sub(1, 4), input:sub(5), 2
   end
   
   return false, input, "", 0
end

function word_filter.is_base_input(input)
   local input_len = utf8.len(input)
   return input_len == 4 or input_len == 6
end

--[[
  FINAL FIX: 将 new_cand 的类型硬编码为 "fit"，确保所有注入的候选项类型正确。
]]
function word_filter.clone_candidate(cand)
   local new_cand = Candidate("fit", cand._start, cand._end, cand.text, cand.comment)
   new_cand.preedit = cand.preedit
   new_cand.quality = cand.quality
   return new_cand
end

function word_filter.func(input, env)
   if not env.enable_word_filter then
      for cand in input:iter() do yield(cand) end
      return
   end

   local current_input = env.engine.context.input
   local is_filter_mode, base_input, user_aux_code, expected_word_len = word_filter.is_word_filter_input(current_input)
   
   if is_filter_mode then
      -- 词辅助过滤模式
      local injected_candidates = {}
      local original_candidates = {}
      
      for cand in input:iter() do
         table.insert(original_candidates, cand)
      end
      
      for cache_key, cached_cands in pairs(env.word_cache) do
         local key_parts = {}
         for part in cache_key:gmatch("[^|]+") do
            table.insert(key_parts, part)
         end
         
         if #key_parts == 3 and key_parts[1] == base_input and tonumber(key_parts[2]) == expected_word_len then
            local pattern_from_cache = key_parts[3]
            
            -- 使用前缀匹配，统一处理单位和多位辅助码
            if pattern_from_cache:find('^' .. user_aux_code) then
               for _, cached_cand in ipairs(cached_cands) do
                  table.insert(injected_candidates, word_filter.clone_candidate(cached_cand))
               end
            end
         end
      end
      
      -- 为所有注入的候选项更新属性
      for _, new_cand in ipairs(injected_candidates) do
         new_cand._end = new_cand._start + utf8.len(current_input)
         new_cand.preedit = current_input
         
         if env.word_filter_match_indicator then
            new_cand.comment = env.word_filter_match_indicator
         end
      end

      -- 输出候选项
      if #original_candidates > 0 then
         yield(original_candidates[1])
      end
      
      for _, cand in ipairs(injected_candidates) do
         yield(cand)
      end
      
      for i = 2, #original_candidates do
         yield(original_candidates[i])
      end
      
   elseif word_filter.is_base_input(current_input) then
      -- 基础编码模式：缓存候选项
      for cand in input:iter() do
         local cand_len = utf8.len(cand.text)
         
         if (cand_len == 2 or cand_len == 3) and cand.comment and cand.comment ~= "" then
            local aux_codes = word_filter.extract_aux_codes(cand.comment)
            local patterns = {}
            
            if cand_len == 2 and #aux_codes >= 2 then
               patterns = word_filter.generate_two_word_patterns(aux_codes)
            elseif cand_len == 3 and #aux_codes >= 3 then
               patterns = word_filter.generate_three_word_patterns(aux_codes)
            end
            
            for _, pattern in ipairs(patterns) do
               local cache_key = word_filter.get_cache_key(current_input, cand_len, pattern)
               if not env.word_cache[cache_key] then
                  env.word_cache[cache_key] = {}
               end
               
               local exists = false
               for _, existing_cand in ipairs(env.word_cache[cache_key]) do
                  if existing_cand.text == cand.text then
                     exists = true
                     break
                  end
               end
               
               if not exists then
                  table.insert(env.word_cache[cache_key], word_filter.clone_candidate(cand))
               end
            end
         end
         
         yield(cand)
      end
      
   else
      -- 其他情况，直接透传并清空缓存
      if next(env.word_cache) ~= nil then
        env.word_cache = {}
      end
      for cand in input:iter() do
         yield(cand)
      end
   end
end

return word_filter
