--- Extension Test - The keys of a `_quarto.tests` format entry.
---
--- The tables match q2 `crates/quarto-test/src/spec.rs` at `origin/main`
--- `e7d4eab` and the quarto-cli smoke-all verify map of the same date. When
--- q2 adds an assertion, add it here, and say whether this runner executes it.

local util = require('util')

local M = {}

--- The keys that choose the log rule. A key applies when it is present,
--- whatever its value, as in q2.
M.POLICY = { 'noErrors', 'noErrorsOrWarnings', 'shouldError' }

--- Keys this runner executes, mapped to whether `q2 call test` rejects them.
local EXECUTED = {
  noErrors = false,
  noErrorsOrWarnings = false,
  shouldError = false,
  ensureFileRegexMatches = false,
  ensureTypstFileRegexMatches = false,
  printsMessage = false,
  fileExists = false,
  ensureDocxRegexMatches = true,
}

--- Keys this runner knows and does not execute, mapped the same way.
local KNOWN = {
  ensureHtmlElements = false,
  ensureCssRegexMatches = false,
  ensurePdfRegexMatches = false,
  ensurePdfTextPositions = false,
  ensurePdfMetadata = false,
  folderExists = false,
  pathDoesNotExist = false,
  pathDoNotExists = false,
  ['dom-parity'] = false,
  postRenderCleanup = true,
  fileNotExists = true,
  ensureHtmlElementContents = true,
  ensureHtmlElementCount = true,
  ensureLatexFileRegexMatches = true,
  ensureEpubFileRegexMatches = true,
  ensureIpynbCellMatches = true,
  ensureDocxXpath = true,
  ensureOdtXpath = true,
  ensureJatsXpath = true,
  ensurePptxRegexMatches = true,
  ensurePptxXpath = true,
  ensurePptxLayout = true,
  ensurePptxMaxSlides = true,
  ensureSnapshotMatches = true,
  ensureLlmsMdRegexMatches = true,
  ensureLlmsMdExists = true,
  ensureLlmsMdDoesNotExist = true,
  ensureLlmsTxtRegexMatches = true,
  ensureLlmsTxtExists = true,
  ensureLlmsTxtDoesNotExist = true,
}

--- Classify one key of a format entry.
--- @param key string
--- @return table {class = 'executed'|'known'|'unknown', q2_rejects = boolean}
function M.classify(key)
  if EXECUTED[key] ~= nil then
    return { class = 'executed', q2_rejects = EXECUTED[key] }
  end
  if KNOWN[key] ~= nil then
    return { class = 'known', q2_rejects = KNOWN[key] }
  end
  return { class = 'unknown', q2_rejects = true }
end

--- Whether a key chooses the log rule.
--- @param key string
--- @return boolean
function M.is_policy(key)
  return util.contains(M.POLICY, key)
end

--- Every key the tables know, sorted, for the message of an unknown key.
--- @return string[]
function M.known_keys()
  local keys = util.sorted_keys(EXECUTED)
  for _, key in ipairs(util.sorted_keys(KNOWN)) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

return M
