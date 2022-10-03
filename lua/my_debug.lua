
local logger = require("tools/logger")
local rime_api_helper = require("tools/rime_api_helper")
local string_helper = require("tools/string_helper")

local debug_option = false

-- ============================================================= processor

-- ----------------
-- methods
-- ----------------

local function get_segment(env)
  local context = env.engine.context
  local composition =  context.composition
  if(not composition:empty()) then
    -- 获得 Segment 对象
    local segment = composition:back()
    return segment
  end
  return nil
end

-- 标签 信息
local function get_msg_tags(env)
  local segment = get_segment(env)
  if(segment) then
    local tags = segment.tags
    if(tags) then
      local tag_arr = {}
      for tag, _ in pairs(tags) do
        table.insert(tag_arr, tag)
      end
      local msg = string.format("🏷:(%s)", string_helper.join(tag_arr, ","))
      return true, msg
    end
  end
  return false
end

-- 页码 信息
local function get_msg_page(env)
  local schema = env.engine.schema
  local segment = get_segment(env)
  if(segment) then
    local page_size = schema.page_size
    -- 获得选中的候选词下标
    local count_select = segment.selected_index or 0
    local page_select = count_select/page_size
    -- 获取 Menu 对象
    local menu = segment.menu
    -- 获得（已加载）候选词数量
    local count_loaded = menu and menu:candidate_count() or 0
    local page_loaded = count_loaded/page_size
    local msg = string.format("📖:[%s/%s]📚:[%0.0f/%0.0f]", 
      count_select, count_loaded,
      page_select, page_loaded)
    return true, msg
  end
  return false
end

-- ----------------
-- processor
-- ----------------

local processor = {}

local prompt_map_notifier_id = 0

function processor.init(env)
  local context = env.engine.context
  env.notifiers = {
    context.option_update_notifier:connect(function(ctx)
      debug_option = ctx:get_option("option_debug_comment_filter") or false -- 开关
    end),
  }
  prompt_map_notifier_id = prompt_map_notifier_id + 1
  env.prompt_map_notifier_id = prompt_map_notifier_id
  rime_api_helper:add_prompt_map_notifier(context, env.prompt_map_notifier_id, function(ctx)
    -- 展示
    local prompt_map = rime_api_helper:get_prompt_map()
    -- 修改 prompt
    local prompt_arr = {}
    for key, msg in pairs(prompt_map) do
      table.insert(prompt_arr, msg)
    end
    local segment = get_segment(env)
    if(segment) then
      segment.prompt = table.concat(prompt_arr, " ")
    else
      logger.warn("can't find segment.")
    end
  end)
end

function processor.fini(env)
  for i, n in pairs(env.notifiers) do
    n:disconnect()
  end
  local context = env.engine.context
  rime_api_helper:remove_prompt_map_notifier(context, env.prompt_map_notifier_id)
end

local function add_prompts(prompts, msg_error, flag, msg)
  if(flag) then
    table.insert(prompts, msg)
  else
    logger.warn(msg_error)
  end
end

function processor.func(key, env)
  local context = env.engine.context
  if(not debug_option) then
    rime_api_helper:clear_prompt_map(context, "debug")
    return rime_api_helper.processor_return_kNoop
  end
  if(context:is_composing()) then
    local prompts = {}
    -- 标签
    add_prompts(prompts, "fail to get \"tags\" info.", get_msg_tags(env))
    -- 页码
    add_prompts(prompts, "fail to get \"page\" info.", get_msg_page(env))
    -- 添加
    rime_api_helper:add_prompt_map(context, "debug", string_helper.join(prompts, " "))
  end
  return rime_api_helper.processor_return_kNoop
end

-- ============================================================= filter

local filter = {}

function filter.init(env)
  env.debug_comment_pattern = "『{dynamic_type}:{type}|🏆{quality}』" -- 当 weasel 为前端时，内容过长（或者换行）可能导致闪退（同时关闭父应用...）。 issue https://github.com/rime/home/issues/1129
end

local function show_candidate_info(input, env)
  for cand in input:iter() do
    -- 整理 info
    local info = {
      dynamic_type = cand:get_dynamic_type(),
      type = cand.type,
      _start = cand._start,
      _end = cand._end,
      preedit = cand.preedit,
      quality = string.format("%6.4f", cand.quality),
    }
    local comment = cand.comment .. string_helper.format(env.debug_comment_pattern, info)
    yield(ShadowCandidate(cand, cand.type, cand.text, comment))
  end
end

function filter.func(input, env)
  if debug_option then
    show_candidate_info(input, env)
  else
    for cand in input:iter() do
      yield(cand)
    end
  end
end

return {
  filter=filter,
  processor=processor,
}