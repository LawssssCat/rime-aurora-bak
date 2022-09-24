--[[
  
  包含 librime-lua 接口的进一步分装

  地址：https://github.com/hchunhui/librime-lua
  文档：https://github.com/hchunhui/librime-lua/wiki/Scripting
  相关：
    1. https://github.com/hchunhui/librime-lua/issues/186
  参考：
    1. https://github.com/shewer/librime-lua-script
]]

local logger = require("tools/logger")

local helper = {}

-- ============================================================ 
-- version
-- ============================================================ 

-- the version of librime (https://github.com/rime/librime): 输入法核心引擎
function helper:get_rime_version()
  return rime_api and rime_api.get_rime_version and rime_api.get_rime_version()
end

-- the version of lua (https://www.lua.org/): 脚本语言
function helper:get_lua_version()
  return _VERSION
end

-- the version of librime-lua (https://github.com/hchunhui/librime-lua): librime插件，引导lua代码的执行
function helper:get_rime_lua_version() -- 版本规则参考：https://github.com/shewer/librime-lua-script
  local ver
  if LevelDb then
    ver = 177
  elseif Opencc then
    ver = 147
  elseif KeySequence and KeySequence().repr then
    ver= 139
  elseif  ConfigMap and ConfigMap().keys then
    ver= 127
  elseif Projection then
    ver= 102
  elseif KeyEvent then
    ver = 100
  elseif Memory then
    ver = 80
  else
    ver= 79
  end
  return ver
end

function helper:get_version_info()
  return string.format("\nVer: librime %s \nlibrime-lua %s \nlua %s",
  helper.get_rime_version(), helper.get_rime_lua_version(), helper.get_lua_version())
end

-- ============================================================ 
-- config
-- ============================================================ 

--[[
  将 config_item （递归）转换为 lua 数据类型
]]
local function _get_config_item_value(config_item)
  if(not config_item or config_item.type == "kNull") then 
    local result = nil
    return result
  end
  if(config_item.type == "kScalar") then 
    local result = config_item:get_value()
    return result.value
  end
  if(config_item.type == "kList") then 
    -- issue https://github.com/hchunhui/librime-lua/issues/193
    local config_list = config_item:get_list()
    local result_list = {}
    for i = 1, config_list.size do
      local result_config_item = config_list:get_at(i-1) -- 下标 0 开始
      local result_item = _get_config_item_value(result_config_item)
      table.insert(result_list, result_item)
    end
    return result_list
  end
  if(config_item.type == "kMap") then 
    local config_map = config_item:get_map()
    local result_map = {}
    for index, key in pairs(config_map:keys()) do 
      local result_config_item = config_map:get(key)
      local result_item = _get_config_item_value(result_config_item)
      result_map[key] = result_item
    end
    return result_map
  end
end

function helper:get_config_item_value(config, path)
  -- logger.trace(logger.ERROR, config, path)
  local config_item = config:get_item(path)
  return _get_config_item_value(config_item)
end

-- ============================================================ 
-- segment
-- ============================================================ 

--[[

  Segmentation、Segment

  wiki https://github.com/hchunhui/librime-lua/wiki/Scripting#segment
]]
helper.segment_status_kVoid = "kVoid"
helper.segment_status_kGuess = "kGuess"
helper.segment_status_kSelected = "kSelected"
helper.segment_status_kConfirmed = "kConfirmed"

--[[
  候选词 当前页
  @return number 当前页, 当前候选词下标
]]
function helper:page_current(segment, page_size)
  local selected_candidate_index = segment.selected_index + 1 -- 下标1开始
  return math.ceil(selected_candidate_index / page_size), selected_candidate_index -- 下标1开始
end
--[[
  候选词 下一页
  @return number 当前页, 当前候选词下标
]]
function helper:page_next(segment, page_size)
  local menu = segment.menu
  -- page current
  local page_current, num_current = helper:page_current(segment, page_size)
  -- load candidate
  local candidate_num_requested = page_size * (page_current+1)
  local candidate_num_loaded = menu:prepare(candidate_num_requested)
  local candidate_num = candidate_num_requested
  if(candidate_num_loaded < candidate_num_requested) then
    candidate_num = candidate_num_loaded
  end
  -- calc index
  local page_new = math.ceil(candidate_num / page_size)
  local num = candidate_num -- 如果页码没变，移动到最后一个选项
  if(page_new > page_current) then -- 如果页码增加，移动到下一页第一个选项
    num = (page_new-1) * page_size + 1 
  end
  -- 更新
  local index = num - 1 -- 下标从0开始
  segment.selected_index = index
  return page_new, num -- 下标1开始
end
  --[[
    候选词 上一页
    @return number 当前页
  ]]
function helper:page_prev(segment, page_size)
  -- page current
  local page_current, num_current = helper:page_current(segment, page_size)
  -- calc index
  local page_new = (page_current>1) and (page_current-1) or page_current
  local num = (page_new-1) * page_size + 1 -- 移动到第一个选项
  -- 更新
  local index = num - 1 
  segment.selected_index = index
  return page_new, num
end

-- ============================================================ 
-- processor
-- ============================================================ 

helper.processor_return_kRejected = 0 -- 字符上屏，结束 processors 流程
helper.processor_return_kAccepted = 1 -- 字符不上屏，结束 processors 流程
helper.processor_return_kNoop = 2 -- 字符不上屏，交给下一个 processor

-- ============================================================ 
-- regex - boot.Regex from c++
-- ============================================================ 
function helper:regex_match(text, pattern)
  local result = rime_api.regex_match(text , pattern)
  return result
end

return helper
