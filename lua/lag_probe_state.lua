-- 卡顿探针的共用状态与写日志（由 lag_probe_processor / lag_probe_filter 使用）
local THRESHOLD = 0.08
local MAX_BYTES = 200 * 1024
local M = { t0 = nil, fired = true, path = nil, threshold = THRESHOLD }

local function log_path()
  if not M.path then
    local ok, d = pcall(function() return rime_api.get_user_data_dir() end)
    M.path = (ok and d or ".") .. "/lag_probe.log"
    local f = io.open(M.path, "r")
    if f then
      local size = f:seek("end")
      f:close()
      if size and size > MAX_BYTES then os.remove(M.path) end
    end
  end
  return M.path
end

function M.write(line)
  local f = io.open(log_path(), "a")
  if f then f:write(line, "\n"); f:close() end
end

return M
