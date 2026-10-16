--- Extension Test - Reading a json-stream render log.
---
--- quarto-cli writes the output of Lua filters as INFO records, several lines
--- to a record, so a warning from `quarto.log.warning` is only visible by the
--- `(W)` marker at the start of its line. Each line therefore gets its own
--- level. Neither q2 nor quarto-cli smoke-all sees these lines as warnings,
--- which makes the raised levels a rule of this runner alone.

local util = require('util')

local M = {}

local LEVELS = { DEBUG = 'DEBUG', INFO = 'INFO', WARN = 'WARN', WARNING = 'WARN', ERROR = 'ERROR' }

--- A level name in the form this runner uses.
--- @param name any
--- @return string|nil `DEBUG`, `INFO`, `WARN`, or `ERROR`
function M.normalise_level(name)
  if type(name) ~= 'string' then
    return nil
  end
  return LEVELS[name:upper()]
end

--- Remove ANSI colour codes, so a marker at the start of a line is visible.
--- @param text string
--- @return string
local function strip_ansi(text)
  return (text:gsub('\27%[[%d;]*[A-Za-z]', ''))
end

--- The level of one line, raised by the markers quarto-cli passes on.
--- @param line string
--- @param record_level string
--- @return string
local function line_level(line, record_level)
  if line:match('^%(W%) ') or line:match('^WARNING') then
    return 'WARN'
  end
  if line:match('^%(E%) ') or line:match('^ERROR') or line:match('^FATAL') then
    return 'ERROR'
  end
  return record_level
end

--- Turn the text of a json-stream log into log lines.
--- @param text string
--- @return table[] lines {level, message}
--- @return boolean incomplete true when a record could not be read
function M.parse(text)
  local lines, incomplete = {}, false
  for _, raw in ipairs(util.lines(text or '')) do
    if util.trim(raw) ~= '' then
      local ok, record = pcall(pandoc.json.decode, raw, false)
      if ok and type(record) == 'table' and type(record.msg) == 'string' then
        local level = M.normalise_level(record.levelName) or 'INFO'
        for _, line in ipairs(util.lines(strip_ansi(record.msg))) do
          if util.trim(line) ~= '' then
            lines[#lines + 1] = {
              level = line_level(line, level),
              message = (line:gsub('^%([WE]%) ', '')),
            }
          end
        end
      else
        incomplete = true
      end
    end
  end
  return lines, incomplete
end

--- Read a json-stream log file.
---
--- A render that stops before Quarto writes the file leaves nothing to read,
--- and that is no log line rather than an error.
--- @param path string
--- @return table[] lines, boolean incomplete
function M.read(path)
  local text = util.read_file(path)
  if not text then
    return {}, false
  end
  return M.parse(text)
end

--- The messages of the log lines at one level, in log order.
--- @param lines table[]
--- @param level string
--- @return string[]
function M.messages_at(lines, level)
  local out = {}
  for _, line in ipairs(lines) do
    if line.level == level then
      out[#out + 1] = line.message
    end
  end
  return out
end

return M
