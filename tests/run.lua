--- Extension Test - the framework's own tests.
---
--- Run with the Pandoc that Quarto ships, from the repository root:
---
---     quarto pandoc lua tests/run.lua
---
--- Two kinds of check. The unit tests call a module directly. The fixture
--- tests run the whole runner against a small extension built to produce one
--- outcome, and assert on the result JSON, because the JSON is the contract
--- the catalogue reads and a change to it is a change to that contract.

local here = (arg and arg[0] or 'tests/run.lua'):match('(.*)tests/run%.lua$') or './'
local module_dir = here .. '_extensions/extension-test/_modules'
local vendor_dir = here .. '_extensions/extension-test/_vendor/quarto-wizard'

package.path = table.concat({
  module_dir .. '/?.lua', vendor_dir .. '/?.lua', package.path }, ';')

local util = require('util')
local schema = require('schema')
local values = require('values')
local emit = require('emit')
local report = require('report')
local conformance = require('conformance')
local vocabulary = require('vocabulary')
local log = require('log')
local cli = require('cli')
local frontmatter = require('frontmatter')
local assertions = require('assert')

local RUNNER = here .. '_extensions/extension-test/run.lua'
local FIXTURES = here .. 'tests/fixtures'

--- Where the degraded runs copy the framework to, and clean up after.
local DEGRADED = here .. 'tests/_results/degraded'

local passed, failed = 0, 0

--- Record one assertion.
local function check(ok, description, detail)
  if ok then
    passed = passed + 1
    io.stdout:write('ok   ', description, '\n')
  else
    failed = failed + 1
    io.stdout:write('FAIL ', description, '\n')
    if detail then
      io.stdout:write('     ', tostring(detail), '\n')
    end
  end
end

local function equal(actual, expected, description)
  check(actual == expected, description,
    string.format('expected %s, got %s', tostring(expected), tostring(actual)))
end

--- Run the runner against this repository, which vendors one file itself.
local function run_self()
  local json = here .. 'tests/_results/self.json'
  local command = string.format(
    'quarto pandoc lua %s --root %s --tests %s --json %s --tap /dev/null --quiet --layer conformance',
    util.shell_quote(RUNNER), util.shell_quote(here), util.shell_quote(here .. 'tests'),
    util.shell_quote(json))
  util.capture(command)
  local text = util.read_file(json)
  if not text then
    return nil
  end
  local ok, parsed = pcall(pandoc.json.decode, text, false)
  return ok and parsed or nil
end

--- Run the runner against a fixture and return the parsed result.
--- @param name string fixture directory name
--- @param extra string|nil extra arguments
--- @return table|nil results, string output
local function run_fixture(name, extra)
  local root = util.join(FIXTURES, name)
  local tests = util.join(root, '_t')
  local json = util.join(tests, 'results.json')
  util.remove_tree(util.join(tests, '_results'))
  util.remove_tree(util.join(tests, 'generated'))
  util.remove_tree(util.join(tests, '_output'))

  local command = string.format(
    'quarto pandoc lua %s --root %s --tests %s --json %s --tap /dev/null --quiet',
    util.shell_quote(RUNNER), util.shell_quote(root),
    util.shell_quote(tests), util.shell_quote(json))
  if extra then
    command = command .. ' ' .. extra
  end
  local _, output = util.capture(command)

  local text = util.read_file(json)
  if not text then
    return nil, output
  end
  local ok, parsed = pcall(pandoc.json.decode, text, false)
  if not ok then
    return nil, output
  end
  return parsed, output
end

--- Run a copy of the framework whose own descriptors are missing.
---
--- `M.run` continues with empty descriptors when it cannot read them, so this
--- is the path where nothing validates a manifest before it is walked. It
--- cannot be reached from a fixture, because the descriptors belong to the
--- framework rather than to the repository under test.
--- @param name string fixture directory name
--- @param removed string descriptor file to remove from the copy
--- @return table|nil results, string output
local function run_without_descriptors(name, removed)
  local copy = DEGRADED
  util.remove_tree(copy)
  local ok, copy_err = util.copy_tree(here .. '_extensions/extension-test',
    util.join(copy, 'extension-test'))
  if not ok then
    util.remove_tree(copy)
    return nil, tostring(copy_err)
  end
  os.remove(util.join(copy, 'extension-test', removed))

  local root = util.join(FIXTURES, name)
  local json = util.join(copy, 'results.json')
  local command = string.format(
    'quarto pandoc lua %s --root %s --tests %s --json %s --tap /dev/null --quiet --layer conformance',
    util.shell_quote(util.join(copy, 'extension-test', 'run.lua')),
    util.shell_quote(root), util.shell_quote(util.join(root, '_t')),
    util.shell_quote(json))
  local _, output = util.capture(command)

  -- The copy is the whole framework, vendored validator included. Read the
  -- result out of it, then take it away again, the way `run_fixture` cleans up
  -- after itself. Leaving it behind puts a second copy of the extension in the
  -- working tree after every run.
  local text = util.read_file(json)
  util.remove_tree(copy)
  if not text then
    return nil, output
  end
  local decoded, parsed = pcall(pandoc.json.decode, text, false)
  if not decoded then
    return nil, output
  end
  return parsed, output
end

--- Run a copy of the framework whose manifest declares a version nothing
--- else would produce by coincidence.
---
--- The real manifest and the runner's old hard-coded fallback both happened
--- to read `0.0.0` before the first release, so asserting `--version`
--- against the real manifest alone cannot fail: reverting the runner to a
--- constant would still agree with it. Diverging a copy, the way
--- `run_without_descriptors` diverges a copy to reach a path a fixture
--- cannot reach, is what makes the check able to fail.
--- @param version string a value nothing else would produce
--- @return string|nil reported, string|nil error
local function run_with_manifest_version(version)
  local copy = DEGRADED
  util.remove_tree(copy)
  local ok, copy_err = util.copy_tree(here .. '_extensions/extension-test',
    util.join(copy, 'extension-test'))
  if not ok then
    util.remove_tree(copy)
    return nil, tostring(copy_err)
  end

  local manifest = util.join(copy, 'extension-test', '_extension.yml')
  local text = util.read_file(manifest)
  local rewritten = text and text:gsub('version:%s*[^\r\n]+', 'version: ' .. version, 1)
  if not rewritten then
    util.remove_tree(copy)
    return nil, 'could not read ' .. manifest
  end
  util.write_file(manifest, rewritten)

  local command = string.format('quarto pandoc lua %s --version',
    util.shell_quote(util.join(copy, 'extension-test', 'run.lua')))
  local _, output = util.capture(command)
  util.remove_tree(copy)
  return util.trim(output), nil
end

--- Find the first case id a result document writes twice.
---
--- The result JSON is the contract the catalogue reads, and two cases sharing
--- one id in it is a defect: a reader keying on the id sees one of the two and
--- never learns which.
--- @param results table|nil
--- @return string|nil the duplicated id
local function duplicate_id(results)
  local seen = {}
  for _, entry in ipairs((results or {}).cases or {}) do
    if seen[entry.id] then
      return entry.id
    end
    seen[entry.id] = true
  end
  return nil
end

--- Find one case by the tail of its id.
local function find_case(results, suffix)
  for _, case in ipairs((results or {}).cases or {}) do
    if case.id:sub(-#suffix) == suffix or case.id:find(suffix, 1, true) then
      return case
    end
  end
  return nil
end

io.stdout:write('# values\n')

do
  -- The invariant the smoke layer rests on: a derived value always satisfies
  -- the descriptor it came from, or the descriptor is reported undecidable.
  -- Anything else means the generator can emit input an extension's own
  -- contract rejects, and a smoke failure would no longer be the extension's
  -- fault.
  local types = { 'string', 'number', 'integer', 'boolean', 'array', 'object', 'content' }
  local extras = {
    {}, { minLength = 6 }, { maxLength = 2 }, { minimum = 5 }, { maximum = -3 },
    { multipleOf = 4 }, { minItems = 3 }, { enum = { 'a', 'b' } }, { const = 'fixed' },
    { default = 'given' }, { pattern = '^[a-z]+$' }, { pattern = '^\\d+$' },
    { format = 'uri' }, { examples = { 'sample' } },
  }
  local violations, undecidable, total = 0, 0, 0
  for _, kind in ipairs(types) do
    for _, extra in ipairs(extras) do
      local descriptor = { type = kind }
      for key, value in pairs(extra) do
        descriptor[key] = value
      end
      total = total + 1
      local value, ok = values.derive(descriptor)
      if ok then
        if not values.validates(value, descriptor) then
          violations = violations + 1
        end
      else
        undecidable = undecidable + 1
      end
    end
  end
  equal(violations, 0, string.format(
    'every derived value satisfies its descriptor (%d combinations, %d undecidable)',
    total, undecidable))
end

equal(select(2, values.derive({ type = 'string', const = 'fixed' })), true,
  'a const value is derivable')
equal(values.derive({ type = 'string', const = 'fixed' }), 'fixed',
  'a const value wins over every other candidate')
equal(values.derive({ type = 'string', default = 'given', enum = { 'given', 'other' } }), 'given',
  'a default wins over an enum')
equal(select(2, values.derive({ type = 'string', pattern = '^zzz%-only%-this$' })), false,
  'a pattern no candidate satisfies is undecidable rather than guessed')

io.stdout:write('# emit\n')

equal(emit.scalar('plain'), 'plain', 'a plain string needs no quoting')
equal(emit.scalar('has: colon'), '"has: colon"', 'a colon forces quoting')
equal(emit.scalar('true'), '"true"', 'a string that reads as a boolean is quoted')
equal(emit.scalar('12'), '"12"', 'a string that reads as a number is quoted')
equal(emit.scalar(true), 'true', 'a real boolean is not quoted')
equal(emit.scalar(3), '3', 'an integer keeps its integer form')
check(emit.shortcode('name', { 'a b' }, {}):find('"a b"', 1, true) ~= nil,
  'a shortcode argument containing a space is quoted')
check(emit.shortcode('name', {}, { key = true }):find('key="true"', 1, true) ~= nil,
  'a boolean attribute is written as text, because Pandoc attributes are text')

io.stdout:write('# report\n')

equal(report.yaml_scalar('ERROR: broke'), '"ERROR: broke"',
  'a TAP diagnostic containing a colon stays a quoted scalar')
equal(report.yaml_scalar('say "hi"'), '"say \\"hi\\""',
  'a quote inside a TAP diagnostic is escaped')

io.stdout:write('# vocabulary\n')

do
  local cases = {
    { 'noErrors', 'executed', false },
    { 'shouldError', 'executed', false },
    { 'ensureFileRegexMatches', 'executed', false },
    { 'ensureTypstFileRegexMatches', 'executed', false },
    { 'printsMessage', 'executed', false },
    { 'fileExists', 'executed', false },
    { 'ensureDocxRegexMatches', 'executed', true },
    { 'ensureHtmlElements', 'known', false },
    { 'dom-parity', 'known', false },
    { 'postRenderCleanup', 'known', true },
    { 'ensurePptxLayout', 'known', true },
    { 'ensureLlmsTxtExists', 'known', true },
    { 'ensureFileRegexMatch', 'unknown', true },
  }
  for _, case in ipairs(cases) do
    local kind = vocabulary.classify(case[1])
    check(kind.class == case[2] and kind.q2_rejects == case[3],
      string.format('`%s` is %s, and q2 %s it', case[1], case[2], case[3] and 'rejects' or 'accepts'),
      kind.class .. ' ' .. tostring(kind.q2_rejects))
  end
  check(vocabulary.is_policy('noErrors') and not vocabulary.is_policy('printsMessage'),
    'only the three log rule keys are policy keys')
  local keys = vocabulary.known_keys()
  check(util.contains(keys, 'ensureHtmlElements') and util.contains(keys, 'noErrors')
    and not util.contains(keys, 'run'),
    'the list of valid keys holds executed and known keys, and not `run`')
end

io.stdout:write('# log\n')

do
  -- The records below are the shapes measured from quarto-cli with
  -- `--log-format json-stream`: Lua filter output in one INFO record, and a
  -- missing shortcode wrapped in ANSI colour codes with a trailing reset.
  local text = table.concat({
    '{"msg":"(W) veil: undeclared group x\\nsecond line\\n(E) veil: boom\\nplain output\\n","level":20,"levelName":"INFO","loggerName":"default"}',
    '',
    '{"msg":"\\u001b[33mWARNING (/q/shortcodes.lua:461) Shortcode \'x\' not found\\n\\u001b[39m","level":20,"levelName":"INFO","loggerName":"default"}',
    '',
    '{"msg":"FATAL (/q/includes.lua:3) stop","level":20,"levelName":"INFO","loggerName":"default"}',
    '',
    '{"msg":"pandoc failed\\n  at step","level":40,"levelName":"ERROR","loggerName":"default"}',
    '',
    '{"msg":"cut off',
  }, '\n')
  local lines, incomplete = log.parse(text)
  local function at(index)
    return lines[index] and (lines[index].level .. ' ' .. lines[index].message) or 'nil'
  end
  equal(at(1), 'WARN veil: undeclared group x', 'a `(W)` line is a warning, without its marker')
  equal(at(2), 'INFO second line', 'a continuation line keeps the level of its record')
  equal(at(3), 'ERROR veil: boom', 'an `(E)` line is an error, without its marker')
  equal(at(4), 'INFO plain output', 'plain filter output stays at INFO')
  equal(at(5), "WARN WARNING (/q/shortcodes.lua:461) Shortcode 'x' not found",
    'a WARNING line inside colour codes is a warning, and the reset code is dropped')
  equal(at(6), 'ERROR FATAL (/q/includes.lua:3) stop', 'a FATAL line is an error')
  equal(at(7), 'ERROR pandoc failed', 'a record at ERROR gives error lines')
  equal(at(8), 'ERROR   at step', 'every line of an ERROR record is an error line')
  equal(#lines, 8, 'empty lines between records and inside messages give no log line')
  check(incomplete, 'an incomplete last record is reported')

  local none, none_incomplete = log.read(util.join(here, 'tests/_results/no-such.log'))
  check(#none == 0 and none_incomplete == false, 'a missing log file gives no log line and no error')

  equal(log.normalise_level('warning'), 'WARN', '`warning` in any case is WARN')
  equal(log.normalise_level('Error'), 'ERROR', 'a level in mixed case is accepted')
  equal(log.normalise_level('LOUD'), nil, 'an unknown level is refused')
  equal(table.concat(log.messages_at(lines, 'WARN'), '|'),
    "veil: undeclared group x|WARNING (/q/shortcodes.lua:461) Shortcode 'x' not found",
    'the messages at one level keep their order')
end

io.stdout:write('# cli\n')

do
  local text = pandoc.json.encode({
    formats = {
      typst = { pandoc = { ['output-file'] = 'doc.typ' }, metadata = {} },
      html = {
        pandoc = { ['output-file'] = 'doc.html' },
        metadata = { _quarto = { tests = { run = { ['extension-test'] = { timeout = 5 } } } } },
      },
    },
    project = { config = { project = { ['output-dir'] = 'out' } } },
  })
  local info, err = cli.parse_inspect(text)
  check(info ~= nil, 'an inspect result with formats is read', err)
  equal(table.concat(info.formats, ','), 'html,typst', 'the formats come back sorted')
  equal(info.output_files.html, 'doc.html', 'the output file of each format is kept')
  equal(info.output_dir, 'out', 'the project output directory is kept')
  equal(info.tests.run['extension-test'].timeout, 5,
    '`_quarto.tests` is read from the first sorted format')

  local bad, bad_err = cli.parse_inspect('not json')
  check(bad == nil and bad_err ~= nil, 'an inspect result that is not JSON is an error')
  local no_meta, no_meta_err = cli.parse_inspect(pandoc.json.encode({ formats = { html = { pandoc = {} } } }))
  check(no_meta == nil and no_meta_err ~= nil,
    'a format without metadata is an error, not a document without a block')

  local command = cli.render_command('/t', '/t/doc.qmd', 'html', '/t/log.json', 30)
  check(command:find("quarto render '/t/doc.qmd' --to 'html'", 1, true) ~= nil
    and command:find("--log '/t/log.json' --log-level info --log-format json-stream", 1, true) ~= nil
    and command:find("cd '/t' && ", 1, true) == 1,
    'the render command writes a json-stream log at level info', command)
end

io.stdout:write('# frontmatter\n')

do
  local null = pandoc.json.null
  local spec, problem = frontmatter.spec({
    run = { skip = false, ['extension-test'] = { timeout = 5 } },
    html = { noErrors = true, ensureFileRegexMatches = { { 'a' } }, ensureHtmlElements = { { 'p' } } },
    revealjs = null,
    typst = { noErrors = true, shouldError = true },
    docx = { ensureFileRegexMatch = { { 'a' } } },
  })
  check(problem == nil and spec.has_format_keys, 'a valid block with format keys is read', problem)
  local names = {}
  for _, entry in ipairs(spec.formats) do
    names[#names + 1] = entry.name
  end
  equal(table.concat(names, ','), 'docx,html,revealjs,typst', 'format entries come in sorted order')
  local docx, html, revealjs, typst = spec.formats[1], spec.formats[2], spec.formats[3], spec.formats[4]
  equal(html.policy, 'noErrors', 'a policy key chooses the log rule')
  equal(#html.assertions, 2, 'executed and known keys become assertions, policy keys do not')
  equal(html.assertions[2].class, 'known', 'a known key keeps its class')
  equal(revealjs.policy, 'noErrorsOrWarnings', 'an empty format value renders under the default rule')
  check(revealjs.problem == nil, 'an empty format value is valid')
  equal(typst.problem and typst.problem.reason, 'policy-conflict', 'two policy keys conflict')
  equal(docx.problem and docx.problem.reason, 'unknown-assertion', 'an unknown key is reported')
  check(docx.problem and docx.problem.message:find('ensureFileRegexMatches', 1, true) ~= nil,
    'the unknown key message lists the valid keys')
  check(docx.problem and docx.problem.message:find('e7d4eab', 1, true) ~= nil,
    'the unknown key message names the q2 commit the key table tracks')

  local empty = frontmatter.spec(nil)
  check(not empty.has_format_keys and #empty.formats == 0, 'no block gives no format keys')
  local _, list_problem = frontmatter.spec({ 'html' })
  check(list_problem ~= nil, 'a block that is a list is invalid')
  local _, scalar_problem = frontmatter.spec('html')
  check(scalar_problem ~= nil, 'a block that is a scalar is invalid')
  local _, format_problem = frontmatter.spec({ html = { 'noErrors' } })
  check(format_problem ~= nil, 'a format value that is a list is invalid')

  local descriptors = schema.load_schema(here .. '_extensions/extension-test/test-schema.yml').options
  local settings, options_problem = frontmatter.options({ ['extension-test'] = { timeout = 5 } }, descriptors, 'doc')
  check(options_problem == nil and settings.timeout == 5 and settings.name == 'doc',
    'valid options are read, and the name defaults to the stem', options_problem)
  local defaults = frontmatter.options({}, descriptors, 'doc')
  equal(defaults.timeout, 300, 'the timeout defaults to 300 seconds')
  local _, bad_value = frontmatter.options({ ['extension-test'] = { timeout = 0 } }, descriptors, 'doc')
  check(bad_value ~= nil and bad_value:find('timeout', 1, true) ~= nil, 'a timeout below 1 is invalid', bad_value)
  local _, bad_key = frontmatter.options({ ['extension-test'] = { strict = true } }, descriptors, 'doc')
  check(bad_key ~= nil and bad_key:find('strict', 1, true) ~= nil, 'a removed option is invalid', bad_key)
  local unread, unread_problem = frontmatter.options({ ['extension-test'] = { timeout = 7 } }, {}, 'doc')
  check(unread_problem == nil and unread.timeout == 7,
    'without readable descriptors the options are kept, not all reported as unknown', unread_problem)

  local probe = { ci = true, os = 'linux', has_command = function(name) return name == 'Rscript' end }
  equal(frontmatter.skip_reason({ skip = 'later' }, probe), 'later', 'a skip string is the reason')
  equal(frontmatter.skip_reason({ skip = true }, probe), 'skip: true', 'a skip flag gives a reason')
  equal(frontmatter.skip_reason({ ci = false }, probe), 'tests.run.ci is false', '`ci: false` skips on CI')
  equal(frontmatter.skip_reason({ os = { 'darwin' } }, probe), 'tests.run.os does not include linux',
    '`os` skips another system')
  equal(frontmatter.skip_reason({ not_os = 'linux' }, probe), 'tests.run.not_os includes linux',
    '`not_os` skips the named system')
  check(frontmatter.skip_reason({ requires_js = true }, probe) ~= nil, '`requires_js` skips the document')
  equal(frontmatter.skip_reason({ requires = { 'knitr' } }, probe), nil, 'an available engine does not skip')
  check(frontmatter.skip_reason({ requires = 'jupyter' }, probe) ~= nil, 'a missing engine skips')
  local unknown_engine = frontmatter.skip_reason({ requires = 'julia' }, probe)
  check(unknown_engine ~= nil and unknown_engine:find('does not know', 1, true) ~= nil,
    'an engine the runner does not know is named as such, not as a missing runtime', unknown_engine)
  equal(frontmatter.skip_reason({}, probe), nil, 'an empty `run` does not skip')

  local message = frontmatter.project_problem({
    run = { skip = true, ['extension-test'] = { timeout = 9 } },
    html = null,
  })
  check(message ~= nil and message:find('_quarto.tests.html', 1, true) ~= nil
    and message:find('_quarto.tests.run.skip', 1, true) ~= nil,
    'a project block that sets more than `run.extension-test` is reported, empty keys included', message)
  equal(frontmatter.project_problem({ run = { ['extension-test'] = { timeout = 9 } } }), nil,
    'a project block with only `run.extension-test` is valid')
  equal(frontmatter.project_problem(nil), nil, 'no project block is valid')
end

io.stdout:write('# assert\n')

do
  local compiled = schema._compile_pattern('^here$')
  check(assertions.matches('a\nhere\nb', compiled, true), 'an anchored pattern matches one line of a file')
  check(not assertions.matches('a\nhere\nb', compiled, false), 'without the line rule, the anchor is the whole text')
  local dot = schema._compile_pattern('Backup.*enabled')
  check(not assertions.matches('Backup\nlater enabled', dot, true)
    and not assertions.matches('Backup\nlater enabled', dot, false),
    'a dot does not cross a line break, as in q2 and quarto-cli')
  check(assertions.matches('Backup is enabled', dot, true), 'a dot still matches within a line')
  check(assertions.matches('a.x', schema._compile_pattern('[.]x'), false), 'a dot inside a class stays literal')
  check(assertions.matches('100%\nmore', schema._compile_pattern('100%$'), true),
    'a literal percent before the end anchor keeps the anchor')

  local entries = assertions.pattern_pair('ensureFileRegexMatches', { { 'here', '^b$' }, { 'gone' } },
    'a\nhere\nb', true, 'doc.html')
  equal(#entries, 3, 'each pattern gives one entry')
  equal(entries[1].id, 'ensureFileRegexMatches/match/1', 'a match entry has its list and index')
  equal(entries[3].id, 'ensureFileRegexMatches/noMatch/1', 'a no-match entry has its list and index')
  check(entries[1].status == 'pass' and entries[2].status == 'pass' and entries[3].status == 'pass',
    'patterns that match and patterns that do not match pass')

  local failing = assertions.pattern_pair('ensureFileRegexMatches', { { 'absent' }, { 'here' } },
    'here', true, 'doc.html')
  equal(failing[1].message, 'not found in doc.html', 'a missing pattern says so')
  equal(failing[2].message, 'found in doc.html', 'a forbidden pattern says so')

  local no_patterns = assertions.pattern_pair('ensureFileRegexMatches', { {}, {} }, 'here', true, 'f')
  check(#no_patterns == 1 and no_patterns[1].status == 'fail'
    and no_patterns[1].message:find('assertion-invalid', 1, true) == 1,
    'an assertion with no pattern at all is invalid, not a silent pass')
  local empty_lists = assertions.pattern_pair('ensureFileRegexMatches', { {}, { 'x' } }, 'here', true, 'f')
  check(#empty_lists == 1 and empty_lists[1].status == 'pass', 'an empty match list is valid')
  local no_second = assertions.pattern_pair('ensureFileRegexMatches', { { 'here' } }, 'here', true, 'f')
  check(#no_second == 1 and no_second[1].status == 'pass', 'the no-match list is optional')
  local flat = assertions.pattern_pair('ensureFileRegexMatches', { 'here' }, 'here', true, 'f')
  check(#flat == 1 and flat[1].status == 'fail' and flat[1].message:find('assertion-invalid', 1, true) == 1,
    'a flat list of patterns is invalid')
  local refused = assertions.pattern_pair('ensureFileRegexMatches', { { 'x{2}' } }, 'xx', true, 'f')
  check(refused[1].status == 'skip' and refused[1].message:find('pattern-unsupported', 1, true) == 1,
    'a pattern the compiler refuses is a skip')

  local lines = {
    { level = 'WARN', message = 'veil: undeclared group x' },
    { level = 'INFO', message = 'veil: undeclared group y' },
  }
  local printed = assertions.evaluate({
    { key = 'printsMessage', class = 'executed', value = { level = 'warning', regex = 'undeclared group' } },
    { key = 'printsMessage', class = 'executed', value = { { level = 'ERROR', regex = 'boom', negate = true },
      { level = 'DEBUG', regex = 'x' } } },
  }, { lines = lines }, true)
  equal(printed[1].status, 'pass', 'a WARN line matches `warning`')
  equal(printed[2].status, 'pass', 'a negated message that is absent passes')
  equal(printed[3].status, 'skip', 'a DEBUG entry is a skip, because the log is at info')

  local skipped, notes = assertions.evaluate({
    { key = 'ensureFileRegexMatches', class = 'executed', value = { { 'x' } } },
    { key = 'postRenderCleanup', class = 'known', q2_rejects = true, value = {} },
  }, { lines = {} }, true)
  equal(#skipped, 1, 'under shouldError, file assertions give no entry')
  check(#notes == 1 and notes[1]:find('shouldError', 1, true) ~= nil, 'under shouldError, a note says why')
  check(skipped[1].status == 'skip' and skipped[1].warnings and skipped[1].warnings[1]:find('q2', 1, true) ~= nil,
    'a known key that q2 rejects is a skip with a q2 warning')

  local scratch = util.join(here, 'tests/_results/assert')
  pcall(pandoc.system.make_directory, util.join(scratch, 'doc_files'), true)
  util.write_file(util.join(scratch, 'doc.html'), 'x')
  util.write_file(util.join(scratch, 'doc_files', 'style.css'), 'x')
  local files = assertions.evaluate({
    { key = 'fileExists', class = 'executed', value = { outputPath = 'doc.html', supportPath = 'style.css' } },
    { key = 'fileExists', class = 'executed', value = { supportPath = 'gone.css' } },
  }, { lines = {}, output_dir = scratch, support_dir = util.join(scratch, 'doc_files') }, false)
  check(files[1].status == 'pass' and files[2].status == 'pass', 'files that exist pass')
  check(files[3].status == 'fail' and files[3].id == 'fileExists/supportPath', 'a missing file fails')
  local no_paths = assertions.evaluate({ { key = 'fileExists', class = 'executed', value = {} } },
    { lines = {}, output_dir = scratch, support_dir = scratch }, false)
  check(#no_paths == 1 and no_paths[1].status == 'fail'
    and no_paths[1].message:find('assertion-invalid', 1, true) == 1,
    'fileExists with no path is invalid, not a silent pass')

  util.write_file(util.join(scratch, 'doc.typ'), 'line\nhere\n')
  local typst = assertions.evaluate({
    { key = 'ensureTypstFileRegexMatches', class = 'executed', value = { { '^here$' }, { 'Backup' } } },
  }, { lines = {}, typ_path = util.join(scratch, 'doc.typ'), typ_label = 'doc.typ', output_is_typ = false }, false)
  check(typst[1].status == 'pass' and typst[2].status == 'pass', 'the kept Typst file is read')
  check(util.exists(util.join(scratch, 'doc.typ')),
    'the assertion leaves the kept Typst file in place; the render layer removes it')
  local preexisting = assertions.evaluate({
    { key = 'ensureTypstFileRegexMatches', class = 'executed', value = { { 'here' } } },
  }, { lines = {}, typ_path = util.join(scratch, 'doc.typ'), typ_label = 'doc.typ', typ_preexisting = true }, false)
  check(preexisting[1].status == 'fail' and preexisting[1].message:find('already existed', 1, true) ~= nil,
    'a Typst file that existed before the render is not read')
  os.remove(util.join(scratch, 'doc.typ'))
  local no_typ = assertions.evaluate({
    { key = 'ensureTypstFileRegexMatches', class = 'executed', value = { { 'here' } } },
  }, { lines = {}, typ_path = util.join(scratch, 'doc.typ'), typ_label = 'doc.typ' }, false)
  equal(no_typ[1].message, 'set keep-typ: true', 'a missing Typst file asks for keep-typ')

  local md = util.join(scratch, 'doc.md')
  util.write_file(md, 'Always here\n')
  local docx = util.join(scratch, 'doc.docx')
  util.capture(string.format('quarto pandoc %s -o %s', util.shell_quote(md), util.shell_quote(docx)))
  local word = assertions.evaluate({
    { key = 'ensureDocxRegexMatches', class = 'executed', q2_rejects = true, value = { {}, { 'Backup' } } },
  }, { lines = {}, output_path = docx, output_label = 'doc.docx' }, false)
  check(word[1].status == 'pass', 'a word that is not in the DOCX passes the no-match list')
  check(word[1].warnings and word[1].warnings[1]:find('q2', 1, true) ~= nil, 'a DOCX entry carries the q2 warning')
  local word_match = assertions.evaluate({
    { key = 'ensureDocxRegexMatches', class = 'executed', value = { { 'Always here' } } },
  }, { lines = {}, output_path = docx, output_label = 'doc.docx' }, false)
  check(word_match[1].status == 'pass', 'a word that is in the DOCX passes the match list')
  util.write_file(util.join(scratch, 'broken.docx'), 'not a zip')
  local broken = assertions.evaluate({
    { key = 'ensureDocxRegexMatches', class = 'executed', value = { { 'x' } } },
  }, { lines = {}, output_path = util.join(scratch, 'broken.docx'), output_label = 'broken.docx' }, false)
  equal(broken[1].status, 'fail', 'a DOCX that is not a ZIP file fails rather than crashing')

  equal(assertions.failure({ { status = 'pass' } }), nil, 'no failed entry gives no failure')
  equal(assertions.failure(failing), 'ensureFileRegexMatches/match/1 "absent" not found in doc.html (2 of 2 assertions failed)',
    'the failure names the first failed entry and the count')
  util.remove_tree(scratch)
end

io.stdout:write('# conformance\n')

-- The licence rule is a rule about names, and the fixtures below can only ask
-- the filesystem they run on. A case-insensitive one answers for `LICENSE`
-- when the directory holds `license`, so it hides the half of the rule that
-- the Linux runner sees. These read the name alone.
check(conformance._is_licence_file('LICENSE'),
  'the licence rule accepts the name upstreams ship most often')
check(conformance._is_licence_file('license'),
  'the licence rule accepts a licence spelled in lower case')
check(conformance._is_licence_file('licence.md'),
  'the licence rule accepts the British spelling in lower case')
check(conformance._is_licence_file('Copying'),
  'the licence rule accepts a name spelled in mixed case')
check(not conformance._is_licence_file('licensed.lua'),
  'the licence rule refuses a name that merely starts like a licence')
check(not conformance._is_licence_file('sample.lua'),
  'the licence rule refuses a vendored module')

io.stdout:write('# fixtures\n')

do
  local results = run_fixture('clean')
  check(results ~= nil, 'the clean fixture produces a result document')
  if results then
    equal(results.status, 'pass', 'the clean fixture passes every layer')
    check((results.summary.fail or 0) == 0, 'the clean fixture reports no failure',
      results.summary and results.summary.fail)
    local smoke = find_case(results, 'smoke/generated/')
    check(smoke ~= nil and smoke.status == 'pass',
      'the clean fixture generates and renders a smoke document')
  end
end

do
  local results = run_fixture('bad-default')
  local case = results and find_case(results, 'conformance/defaults/')
  check(case ~= nil and case.status == 'fail',
    'a default that its own descriptor rejects fails conformance')
  check(case ~= nil and case.failure.reason == 'defaults-invalid',
    'the failure names the defaults', case and case.failure.reason)
end

do
  local results = run_fixture('missing-file')
  local case = results and find_case(results, 'conformance/path/')
  check(case ~= nil and case.status == 'fail',
    'a contributed file that does not exist fails conformance')
  check(case ~= nil and case.failure.reason == 'missing-contributed-file',
    'the failure names the missing file', case and case.failure.reason)
end

do
  local results = run_fixture('v1-schema')
  local case = results and find_case(results, 'conformance/schema/')
  check(case ~= nil and case.status == 'skip',
    'a v1 schema is skipped rather than failed')
  check(case ~= nil and case.failure.reason == 'schema-v1-not-supported',
    'the skip names the v1 vocabulary', case and case.failure.reason)
end

do
  local results = run_fixture('no-schema')
  local case = results and find_case(results, 'conformance/schema/')
  check(case ~= nil and case.status == 'skip',
    'an extension with no schema is skipped rather than failed')
end

do
  -- Every catalogued extension belongs to somebody else, so a repository that
  -- declares nothing is not a repository doing something wrong.
  local results = run_fixture('clean', '--layer conformance')
  local case = results and find_case(results, 'conformance/vendored/')
  check(case ~= nil and case.status == 'skip',
    'an extension with no dependency manifest is skipped rather than failed')
  check(case ~= nil and case.failure.reason == 'no-dependency-manifest',
    'the skip names the missing manifest', case and case.failure.reason)
end

do
  local clean = run_fixture('vendored-clean', '--layer conformance')
  local declared = clean and find_case(clean, 'conformance/vendored/vend/example/sample.lua')
  check(declared ~= nil and declared.status == 'pass',
    'a vendored file that is present and matches its checksum passes')
  -- The whole result, not one case. A check that can never pass, or an
  -- exclusion that goes missing, adds a failure that no single-case assertion
  -- above would see.
  check(clean ~= nil and (clean.summary.fail or 0) == 0,
    'a conforming vendored extension reports no vendored failure',
    clean and clean.summary and clean.summary.fail)

  local missing = run_fixture('vendored-missing-file', '--layer conformance')
  local missing_case = missing and find_case(missing, 'conformance/vendored/vend/example/sample.lua')
  check(missing_case ~= nil and missing_case.status == 'fail',
    'a declared file the vendor directory does not hold fails')
  check(missing_case ~= nil and missing_case.failure.reason == 'vendored-file-missing',
    'the failure names the missing file', missing_case and missing_case.failure.reason)

  local edited = run_fixture('vendored-checksum', '--layer conformance')
  local edited_case = edited and find_case(edited, 'conformance/vendored/vend/example/sample.lua')
  check(edited_case ~= nil and edited_case.status == 'fail',
    'a vendored file edited after it was written fails its checksum')
  check(edited_case ~= nil and edited_case.failure.reason == 'vendored-checksum-mismatch',
    'the failure names the checksum', edited_case and edited_case.failure.reason)

  -- A declared entry that exists but cannot be hashed. "No tool is available"
  -- is a statement about the machine, and saying it about a file the machine
  -- can plainly see is both false and a pass where a failure belongs.
  local unreadable = run_fixture('vendored-checksum-unreadable', '--layer conformance')
  local unreadable_case = unreadable and find_case(unreadable, 'conformance/vendored/vend/example/sample.lua')
  check(unreadable_case ~= nil and unreadable_case.status == 'fail',
    'a declared entry that exists but cannot be hashed fails',
    unreadable_case and unreadable_case.status)
  check(unreadable_case ~= nil and unreadable_case.failure
    and unreadable_case.failure.reason == 'vendored-checksum-unreadable',
    'the failure names the unreadable entry rather than a missing tool',
    unreadable_case and unreadable_case.failure and unreadable_case.failure.reason)

  local orphan = run_fixture('vendored-orphan', '--layer conformance')
  local orphan_case = orphan and find_case(orphan, 'conformance/vendored/vend/example/extra.lua')
  check(orphan_case ~= nil and orphan_case.status == 'fail',
    'a file in the vendor directory that no entry declares fails')
  check(orphan_case ~= nil and orphan_case.failure.reason == 'vendored-undeclared',
    'the failure names the undeclared file', orphan_case and orphan_case.failure.reason)

  -- The per-source loop only ever lists the directories the manifest names,
  -- so a source copied in by hand is invisible to it. These two are the
  -- commonest shape of the habit the check exists to catch.
  local undeclared = run_fixture('vendored-undeclared-source', '--layer conformance')
  local source_case = undeclared and find_case(undeclared, 'conformance/vendored/vend/other')
  check(source_case ~= nil and source_case.status == 'fail',
    'a source directory the manifest does not declare fails')
  check(source_case ~= nil and source_case.failure.reason == 'vendored-undeclared',
    'the failure names the undeclared source', source_case and source_case.failure.reason)

  local loose_case = undeclared and find_case(undeclared, 'conformance/vendored/vend/stray.lua')
  check(loose_case ~= nil and loose_case.status == 'fail',
    'a loose file at the root of the vendor directory fails')
  check(loose_case ~= nil and loose_case.failure.reason == 'vendored-undeclared',
    'the failure names the loose file', loose_case and loose_case.failure.reason)
end

do
  -- A name the manifest does declare, written at `_vendor/<name>` as a file
  -- rather than a directory. The verdict is a failure either way, and telling
  -- the author it is "not a source the manifest declares" contradicts the
  -- manifest they are reading.
  local results = run_fixture('vendored-source-not-a-directory', '--layer conformance')
  local root_case = nil
  for _, entry in ipairs((results or {}).cases or {}) do
    if entry.id == 'conformance/vendored/vend/example' then
      root_case = entry
    end
  end
  check(root_case ~= nil and root_case.status == 'fail',
    'a declared source written as a file fails', root_case and root_case.status)
  check(root_case ~= nil and root_case.failure
    and root_case.failure.reason == 'vendored-source-not-a-directory',
    'the failure names the source that is not a directory',
    root_case and root_case.failure and root_case.failure.reason)
  check(root_case ~= nil and root_case.failure and root_case.failure.message
    and root_case.failure.message:find('is not a source the manifest declares', 1, true) == nil,
    'the failure does not deny that the manifest declares the source',
    root_case and root_case.failure and root_case.failure.message)
end

do
  -- The sweep runs over other people's repositories. A manifest written to a
  -- later version of the format is not their defect, and every copy of this
  -- framework already released would call it one.
  local results = run_fixture('vendored-future-version', '--layer conformance')
  local case = results and find_case(results, 'conformance/vendored/vend')
  check(case ~= nil and case.status == 'skip',
    'a manifest declaring a later format version is skipped rather than failed',
    case and case.status)
  check(case ~= nil and case.failure
    and case.failure.reason == 'dependency-schema-version-unknown',
    'the skip names the unknown format version',
    case and case.failure and case.failure.reason)
end

do
  -- `schema` is required, so a manifest that never declares it is malformed
  -- rather than written to a version this runner has not heard of. Skipping it
  -- takes every checksum, licence and orphan check for that extension with it.
  local missing = run_fixture('vendored-missing-version', '--layer conformance')
  local missing_case = missing and find_case(missing, 'conformance/vendored/vend')
  check(missing_case ~= nil and missing_case.status == 'fail',
    'a manifest that declares no format version fails rather than skipping',
    missing_case and missing_case.status)
  check(missing_case ~= nil and missing_case.failure
    and missing_case.failure.reason == 'dependencies-invalid',
    'the failure names the manifest rather than an unknown format version',
    missing_case and missing_case.failure and missing_case.failure.reason)

  -- `schema: "1"` beside the quoted `version: "1.0.0"` on the next line is an
  -- easy mistake. The validator coerces a quoted scalar toward its declared
  -- type, so this manifest does declare version 1, and every vendored check
  -- for it must still run. It used to be read as a version from the future.
  local quoted = run_fixture('vendored-quoted-version', '--layer conformance')
  local quoted_case = quoted and find_case(quoted, 'conformance/vendored/vend')
  check(quoted_case ~= nil and quoted_case.status == 'pass',
    'a format version written as a string is not read as a version from the future',
    quoted_case and quoted_case.status)
  local quoted_file = quoted and find_case(quoted, 'conformance/vendored/vend/example/sample.lua')
  check(quoted_file ~= nil and quoted_file.status == 'pass',
    'a format version written as a string still has its vendored files checked',
    quoted_file and quoted_file.status)
end

do
  -- `tonumber` reads `1e999` as `inf`. `inf` is not 1, so the future-version
  -- test used to take it as a version from the future and skip every
  -- checksum, licence and orphan check for the extension silently, instead of
  -- reporting the typo it is.
  local overflow = run_fixture('vendored-overflow-version', '--layer conformance')
  local overflow_case = overflow and find_case(overflow, 'conformance/vendored/vend')
  check(overflow_case ~= nil and overflow_case.status == 'fail',
    'a format version that overflows to infinity fails rather than skips',
    overflow_case and overflow_case.status)
  check(overflow_case ~= nil and overflow_case.failure
    and overflow_case.failure.reason == 'dependencies-invalid',
    'the failure names the manifest rather than an unknown format version',
    overflow_case and overflow_case.failure and overflow_case.failure.reason)
end

do
  local results = run_fixture('vendored-no-licence', '--layer conformance')
  local case = results and find_case(results, 'conformance/vendored/vend/example/source-licence')
  check(case ~= nil and case.status == 'fail',
    'a source whose licence is not shipped beside its files fails')
  check(case ~= nil and case.failure.reason == 'vendored-licence-missing',
    'the failure names the licence', case and case.failure.reason)

  -- Upstreams spell the file several ways and the format offers no way to say
  -- which. Every spelling used to cost two failures: the licence check and the
  -- orphan check.
  local spelling = run_fixture('vendored-licence-spelling', '--layer conformance')
  local spelling_case = spelling and find_case(spelling, 'conformance/vendored/vend/example/source-licence')
  check(spelling_case ~= nil and spelling_case.status == 'pass',
    'a licence shipped as `LICENSE.md` satisfies the licence check',
    spelling_case and spelling_case.status)
  check(spelling ~= nil and (spelling.summary.fail or 0) == 0,
    'a licence shipped as `LICENSE.md` is not reported as an undeclared file',
    spelling and spelling.summary and spelling.summary.fail)

  -- Upstreams also spell the file in lower case. The names used to be compared
  -- exactly, so `license` failed the licence check on a case-sensitive
  -- filesystem and passed on a case-insensitive one, and was reported as an
  -- undeclared file on both. The verdict belongs to the repository, not to the
  -- machine that reads it.
  local lower = run_fixture('vendored-licence-case', '--layer conformance')
  local lower_case = lower and find_case(lower, 'conformance/vendored/vend/example/source-licence')
  check(lower_case ~= nil and lower_case.status == 'pass',
    'a licence shipped as `license` satisfies the licence check',
    lower_case and lower_case.status)
  check(lower ~= nil and (lower.summary.fail or 0) == 0,
    'a licence shipped as `license` is not reported as an undeclared file',
    lower and lower.summary and lower.summary.fail)

  local runtime = run_fixture('vendored-pandoc-runtime', '--layer conformance')
  local runtime_case = runtime and find_case(runtime, '/runtime')
  check(runtime_case ~= nil and runtime_case.status == 'pass',
    'a runtime the vocabulary allows is an advisory rather than a failure')
  check(runtime_case ~= nil and #(runtime_case.diagnostics.warnings or {}) > 0,
    'the advisory carries the warning rather than losing it')
end

do
  -- `fetch` is a template for one file. Without `{file}` in it every file of
  -- the source resolves to the same URL, which is not a template at all.
  local results = run_fixture('vendored-fetch-template', '--layer conformance')
  local case = results and find_case(results, 'conformance/vendored/vend')
  check(case ~= nil and case.status == 'fail',
    'a fetch template that does not carry `{file}` is invalid', case and case.status)
  check(case ~= nil and case.failure and case.failure.reason == 'dependencies-invalid',
    'the failure names the manifest', case and case.failure and case.failure.reason)
end

do
  -- A digest pasted in upper case used to make the whole manifest invalid,
  -- which skips every per-file check for that extension.
  local results = run_fixture('vendored-checksum-case', '--layer conformance')
  local case = results and find_case(results, 'conformance/vendored/vend/example/sample.lua')
  check(case ~= nil and case.status == 'pass',
    'a checksum recorded in upper case matches the file', case and case.status)
  check(results ~= nil and (results.summary.fail or 0) == 0,
    'a checksum recorded in upper case leaves the manifest valid',
    results and results.summary and results.summary.fail)
end

do
  -- The result JSON is the contract the catalogue reads, and two cases sharing
  -- one id in it is a defect. A source's own licence case and a declared file
  -- named `licence` used to write the same id.
  local results = run_fixture('vendored-licence-collision', '--layer conformance')
  local duplicate = duplicate_id(results)
  check(results ~= nil and duplicate == nil,
    'no two cases share one id when a declared file is named `licence`', duplicate)

  local licence_case = results and find_case(results, 'conformance/vendored/vend/example/source-licence')
  check(licence_case ~= nil and licence_case.status == 'pass',
    'the source licence keeps its own case id', licence_case and licence_case.status)
end

do
  -- The validator warns about an unknown key in the top-level map only. The
  -- format is public and written by hand, so `runtimes:` for `runtime:` used
  -- to disable the runtime tripwire and say nothing at all.
  local results = run_fixture('vendored-unknown-key', '--layer conformance')
  local source_key = results and find_case(results, 'conformance/vendored/vend/example/unknown-key/homepage')
  check(source_key ~= nil and source_key.status == 'pass'
    and #((source_key.diagnostics or {}).warnings or {}) > 0,
    'an unrecognised key in a source is reported as an advisory',
    source_key and source_key.status)

  local file_key = results
    and find_case(results, 'conformance/vendored/vend/example/sample.lua/unknown-key/runtimes')
  check(file_key ~= nil and file_key.status == 'pass'
    and #((file_key.diagnostics or {}).warnings or {}) > 0,
    'an unrecognised key in a file entry is reported as an advisory',
    file_key and file_key.status)

  check(results ~= nil and (results.summary.fail or 0) == 0,
    'an unrecognised key is an advisory rather than a failure',
    results and results.summary and results.summary.fail)
end

do
  -- The runner keeps going when it cannot read its own descriptors, so the
  -- per-source loop is reached with nothing having validated the manifest. A
  -- Lua error there takes the JSON, the TAP and every other layer with it.
  local results, output = run_without_descriptors('vendored-invalid-source', 'dependencies-schema.yml')
  check(results ~= nil,
    'a manifest walked without descriptors still produces a result document', output)
  local case = results and find_case(results, 'conformance/vendored/vend/example/declaration')
  check(case ~= nil and case.status == 'fail',
    'a source that is not a source declaration fails rather than crashing the run',
    case and case.status)
  check(case ~= nil and case.failure and case.failure.reason == 'dependencies-invalid',
    'the failure names the source that is not a declaration',
    case and case.failure and case.failure.reason)
end

do
  -- `sources` that is not a map is reported after the manifest has already
  -- passed, so the guard needs an id of its own. Writing the manifest's own id
  -- puts one id on two cases in the document the catalogue reads.
  local results, output = run_without_descriptors('vendored-invalid-sources', 'dependencies-schema.yml')
  check(results ~= nil,
    'a manifest whose `sources` is not a map still produces a result document', output)
  local duplicate = duplicate_id(results)
  check(results ~= nil and duplicate == nil,
    'no two cases share one id when `sources` is not a map', duplicate)

  local case = results and find_case(results, 'conformance/vendored/vend/sources')
  check(case ~= nil and case.status == 'fail',
    '`sources` that is not a map fails under an id of its own',
    case and case.status)
  check(case ~= nil and case.failure and case.failure.reason == 'dependencies-invalid',
    'the failure names the manifest', case and case.failure and case.failure.reason)
end

do
  -- A file entry that is not a map used to reach `entry.sha256` and raise. A
  -- Lua error there takes the JSON, the TAP and every other layer with it.
  local results, output = run_without_descriptors('vendored-invalid-file-entry', 'dependencies-schema.yml')
  check(results ~= nil,
    'a file entry that is not a map still produces a result document', output)
  local case = results and find_case(results, 'conformance/vendored/vend/example/sample.lua')
  check(case ~= nil and case.status == 'fail',
    'a file entry that is not a map fails rather than crashing the run',
    case and case.status)
  check(case ~= nil and case.failure and case.failure.reason == 'dependencies-invalid',
    'the failure names the manifest rather than the checksum',
    case and case.failure and case.failure.reason)
  check(case ~= nil and case.failure and case.failure.message
    and case.failure.message:find('sample.lua', 1, true) ~= nil
    and case.failure.message:find('example', 1, true) ~= nil,
    'the failure names both the source and the file',
    case and case.failure and case.failure.message)

  -- The copy is the framework itself. A degraded run that does not take it
  -- away leaves a second copy of the extension in the working tree.
  check(not util.is_dir(DEGRADED),
    'a degraded run leaves no copy of the framework behind', DEGRADED)
end

do
  -- The framework is the format's first consumer. If its own manifest does not
  -- pass its own checks, the format is not usable by anyone.
  local results = run_self()
  local declared = results and find_case(results, 'conformance/vendored/extension-test/quarto-wizard/schema.lua')
  check(declared ~= nil and declared.status == 'pass',
    'the framework passes the dependency checks it ships')
  check(results ~= nil and (results.summary.fail or 0) == 0,
    'the framework itself reports no conformance failure',
    results and results.summary and results.summary.fail)
end

do
  local results = run_fixture('bad-pattern')
  local strict = results and find_case(results, 'conformance/pattern/')
  check(strict ~= nil and strict.status == 'fail',
    'a pattern the validator cannot compile fails under strict severity')

  local lenient = run_fixture('bad-pattern', '--severity lenient')
  local case = lenient and find_case(lenient, 'conformance/pattern/')
  check(case ~= nil and case.status == 'pass',
    'the same pattern is an advisory under lenient severity')
  check(case ~= nil and #(case.diagnostics.warnings or {}) > 0,
    'the advisory carries the warning rather than losing it')
end

do
  -- Pins the vendored validator to the published one. Each of these three
  -- passes against the copy this repository carried before, which accepted an
  -- escape with no Lua equivalent as the bare letter, anchored every branch of
  -- a top-level alternation, and read an empty string as no value at all. A
  -- stale copy passes every other check in this suite, so without these the
  -- vendored file could go backwards unnoticed.
  local escape = run_fixture('unsupported-escape', '--layer conformance')
  local escape_case = escape and find_case(escape, 'conformance/pattern/')
  check(escape_case ~= nil and escape_case.status == 'fail',
    'an escape the compiler cannot express fails rather than matching the bare letter')
  check(escape_case ~= nil and escape_case.failure.reason == 'pattern-uncompilable',
    'the escape failure reports an uncompilable pattern', escape_case and escape_case.failure.reason)
  -- The escape itself, not the wording around it. The reason is shared with
  -- every other pattern that does not compile, and the prose belongs to the
  -- vendored validator, which is free to reword it.
  check(escape_case ~= nil and escape_case.failure.message:find('\\b', 1, true) ~= nil,
    'the escape failure names the escape', escape_case and escape_case.failure.message)

  local alternation = run_fixture('anchored-alternation', '--layer conformance')
  local alternation_case = alternation and find_case(alternation, 'conformance/pattern/')
  check(alternation_case ~= nil and alternation_case.status == 'fail',
    'an anchor across a top-level alternation fails rather than anchoring every branch')
  check(alternation_case ~= nil and alternation_case.failure.reason == 'pattern-uncompilable',
    'the alternation failure reports an uncompilable pattern',
    alternation_case and alternation_case.failure.reason)

  local empty = run_fixture('empty-default', '--layer conformance')
  local empty_case = empty and find_case(empty, 'conformance/defaults/')
  check(empty_case ~= nil and empty_case.status == 'fail',
    'an empty string is a value, so a default of it is tested against `minLength`')
  check(empty_case ~= nil and empty_case.failure.reason == 'defaults-invalid',
    'the empty default failure names the defaults', empty_case and empty_case.failure.reason)
end

do
  -- The reason the render layer exists: Quarto reports an unresolved
  -- shortcode as a warning and still exits 0.
  local results = run_fixture('unresolved-shortcode')
  local case = results and find_case(results, 'render/document/')
  check(case ~= nil and case.status == 'fail',
    'an unresolved shortcode fails even though the render exits 0')
  check(case ~= nil and case.failure.reason == 'shortcode-not-found',
    'the failure names the unresolved shortcode', case and case.failure.reason)
end

do
  -- A document that sets `output-file` writes somewhere other than a file
  -- named after itself. Looking only for the latter finds nothing, and the
  -- layer that exists to read the output then asserts nothing while the run
  -- still reports a pass.
  local results = run_fixture('output-file')
  local case = results and find_case(results, 'render/document/')
  check(case ~= nil and case.status == 'pass',
    'a document that renames its output is rendered and checked',
    case and (case.status .. ' ' .. tostring(case.failure and case.failure.reason)))
end

do
  -- A project can name any output directory. Assuming `_output` reads a
  -- working render as having written nothing, which is now a failure rather
  -- than a skip, so the assumption would fail every such repository.
  local results = run_fixture('output-dir')
  local case = results and find_case(results, 'render/document/')
  check(case ~= nil and case.status == 'pass',
    'a project writing outside _output is rendered and checked',
    case and (case.status .. ' ' .. tostring(case.failure and case.failure.reason)))
end

do
  -- An extension documents itself by showing its own syntax, and that reaches
  -- the output looking exactly like a shortcode that failed to expand. The
  -- scan has to tell the two apart, or every self-documenting extension fails.
  local render = require('render')
  local scratch = util.join(here, 'tests/_results/unexpanded')
  pcall(pandoc.system.make_directory, scratch, true)

  local quoted = util.join(scratch, 'quoted.html')
  util.write_file(quoted,
    '<p>Write it like this:</p><pre class="sourceCode"><code>{{&lt; demo icon &gt;}}</code></pre>')
  check(render.has_unexpanded(quoted) == false,
    'shortcode syntax quoted in a code block is not read as unexpanded')

  local inline = util.join(scratch, 'inline.md')
  util.write_file(inline, 'Write it as `{{< demo icon >}}` in your document.\n')
  check(render.has_unexpanded(inline) == false,
    'shortcode syntax in an inline code span is not read as unexpanded')

  local leaked = util.join(scratch, 'leaked.html')
  util.write_file(leaked, '<p>Here is the icon: {{&lt; demo icon &gt;}}</p>')
  check(render.has_unexpanded(leaked) == true,
    'a shortcode left in the body is still read as unexpanded')

  util.remove_tree(scratch)
end

do
  -- The two ways `output_path` comes back empty mean different things, and the
  -- render layer grades them differently: nowhere to look is this harness's
  -- gap, nothing written is the extension's failure.
  local render = require('render')
  local document = { relative = 'absent.qmd', absolute = FIXTURES .. '/absent.qmd' }

  local path, reason = render.output_path(FIXTURES, document, 'html')
  check(path == nil and reason == 'output-not-found',
    'a known format with no output reports output-not-found', tostring(reason))

  path, reason = render.output_path(FIXTURES, document, 'some-unknown-format')
  check(path == nil and reason == 'unknown-suffix',
    'a format this harness cannot place reports unknown-suffix', tostring(reason))

  -- The reasons above only matter for the status they produce. Reporting a
  -- missing output as a skip is the defect this layer exists to remove, and
  -- nothing else in the suite would notice the mapping being flipped or
  -- dropped. The messages are asserted with the statuses, because a status
  -- alone would only restate the line it checks.
  local status, failure = render.grade_missing('unknown-suffix', 'some-unknown-format', nil)
  check(status == 'skip',
    'a format this harness cannot place is a skip', tostring(status))
  check(failure.message:find('does not know what file', 1, true) ~= nil,
    'the unplaceable message says the harness cannot look', tostring(failure.message))

  status, failure = render.grade_missing('output-not-found', 'html', '/tmp/render.log')
  check(status == 'fail',
    'a render that wrote no output is a failure, not a skip', tostring(status))
  check(failure.message:find('wrote no', 1, true) ~= nil,
    'the missing-output message says the render produced nothing', tostring(failure.message))
  check(failure.reason == 'output-not-found' and failure.log == '/tmp/render.log',
    'the failure carries the reason and the log it was given', tostring(failure.reason))

  -- The default branch, which no reason in the code reaches today. Only an
  -- unplaceable format may downgrade a case to a skip; a reason this harness
  -- has never seen must not.
  check(render.grade_missing('a-reason-nobody-has-written-yet', 'html', nil) == 'fail',
    'an unrecognised reason is a failure rather than a skip')

  -- The name and the directory come from Quarto, so they are pinned here
  -- rather than left to how the installed version happens to report them.
  local scratch = util.join(here, 'tests/_results/paths')
  pcall(pandoc.system.make_directory, util.join(scratch, 'elsewhere'), true)
  local placed = { relative = 'doc.qmd', absolute = util.join(scratch, 'doc.qmd') }

  util.write_file(util.join(scratch, 'renamed.html'), 'x')
  path = render.output_path(scratch, placed, 'html', 'renamed')
  check(path == util.join(scratch, 'renamed.html'),
    'a reported name without its suffix has one added', tostring(path))

  path = render.output_path(scratch, placed, 'html', 'renamed.html')
  check(path == util.join(scratch, 'renamed.html'),
    'a reported name carrying its suffix is used as it stands', tostring(path))

  path = render.output_path(scratch, placed, 'some-unknown-format', 'renamed.html')
  check(path == util.join(scratch, 'renamed.html'),
    'a format with no mapped suffix is placed by the name Quarto reports',
    tostring(path))

  util.write_file(util.join(scratch, 'elsewhere', 'doc.html'), 'x')
  os.remove(util.join(scratch, 'renamed.html'))
  path = render.output_path(scratch, placed, 'html', nil, 'elsewhere')
  check(path == util.join(scratch, 'elsewhere', 'doc.html'),
    'the output directory Quarto names is searched', tostring(path))

  -- A stale copy in any candidate would let a render that wrote nothing read
  -- as a pass, so the render clears every candidate rather than the first one
  -- that happens to exist.
  local candidates = render.output_candidates(scratch, placed, 'html', nil, 'elsewhere')
  check(candidates ~= nil and #candidates == 4,
    'every place a render could have written is offered for removal',
    candidates and tostring(#candidates))
  check(candidates ~= nil and util.contains(candidates, util.join(scratch, 'elsewhere', 'doc.html')),
    'the candidates include the directory Quarto names')
  check(candidates ~= nil and util.contains(candidates, util.join(scratch, '_site', 'doc.html')),
    'the candidates keep the defaults as a fallback')

  util.remove_tree(scratch)
end

do
  -- The same fault one layer over. A digest that cannot be computed used to
  -- emit an advisory, which passes, so on a machine carrying neither hashing
  -- tool every digest case reported success without having looked, over the
  -- manifest contract the whole fleet run depends on.
  --
  -- `conformance` reads `util` through the loader this file already set up, so
  -- replacing the function here is the same instance the layer calls.
  local real_sha256 = util.sha256
  util.sha256 = function()
    return nil, 'no-tool'
  end
  local cases = {}
  local ok = pcall(conformance.run, {
    root = here,
    extension_dir = here .. '_extensions/extension-test',
    severity = 'strict',
  }, function(entry)
    cases[#cases + 1] = entry
  end)
  util.sha256 = real_sha256

  local unverifiable
  for _, entry in ipairs(cases) do
    if entry.failure and entry.failure.reason == 'vendored-checksum-unverifiable' then
      unverifiable = entry
    end
  end
  check(ok, 'the conformance layer runs with no hashing tool available')
  check(unverifiable ~= nil,
    'a digest that cannot be computed is reported, not passed over')
  check(unverifiable ~= nil and unverifiable.status == 'skip',
    'a digest that cannot be computed is a skip, never a pass',
    unverifiable and unverifiable.status)
end

do
  -- Without a project file the staged extension is not resolved, and every
  -- document then reports a shortcode that is not found. The harness knows it
  -- staged the extension itself, so it says what is missing instead.
  local results = run_fixture('no-project-file')
  local render_case = results and find_case(results, 'render/stage')
  check(render_case ~= nil and render_case.status == 'fail',
    'a tests directory with no project file fails the render layer')
  check(render_case ~= nil and render_case.failure.reason == 'no-project-file',
    'the failure names the missing project file',
    render_case and render_case.failure.reason)

  local smoke_case = results and find_case(results, 'smoke/stage')
  check(smoke_case ~= nil and smoke_case.failure
    and smoke_case.failure.reason == 'no-project-file',
    'the smoke layer reports the same missing project file',
    smoke_case and smoke_case.failure and smoke_case.failure.reason)

  local blamed = false
  for _, case in ipairs((results or {}).cases or {}) do
    if case.failure and case.failure.reason == 'shortcode-not-found' then
      blamed = true
    end
  end
  check(not blamed,
    'no case blames the extension for a shortcode the harness never resolved')
end

do
  -- quarto-cli exits 0 when the Lua code of an extension fails, so
  -- `shouldError` passes on an ERROR log line as well as on an exit code.
  local results = run_fixture('should-error', '--layer render')
  local lua_error = results and find_case(results, 'render/lua-error/html')
  check(lua_error ~= nil and lua_error.status == 'pass',
    'a shortcode that raises error() satisfies shouldError', lua_error and lua_error.status)
  check(lua_error ~= nil and #lua_error.assertions == 1 and lua_error.assertions[1].status == 'pass',
    'printsMessage runs under shouldError and finds the error')
  local missing = results and find_case(results, 'render/missing-bibliography/html')
  check(missing ~= nil and missing.status == 'pass',
    'a render that exits with an error code satisfies shouldError', missing and missing.status)
end

do
  -- The log rule reads log lines, and the promoted warning still comes first,
  -- so the reason of an unresolved shortcode does not change.
  local results = run_fixture('unresolved-shortcode', '--layer render')
  local case = results and find_case(results, 'render/document/html')
  check(case ~= nil and case.failure and case.failure.stage == 'assert',
    'the promoted warning keeps its stage', case and case.failure and case.failure.stage)
  check(case ~= nil and #((case.diagnostics or {}).warnings or {}) > 0,
    'the warning line is recorded in the diagnostics')
end

do
  local results = run_fixture('vocabulary', '--layer render')
  local function reason(suffix)
    local case = find_case(results, suffix)
    return case and (case.status .. ' ' .. tostring(case.failure and case.failure.reason)) or 'missing'
  end
  equal(reason('render/unknown-assertion/html'), 'fail unknown-assertion', 'an unknown key fails its format')
  equal(reason('render/policy-conflict/html'), 'fail policy-conflict', 'two policy keys fail their format')
  local known = find_case(results, 'render/known-not-executed/html')
  check(known ~= nil and known.status == 'pass' and known.assertions[1].status == 'skip',
    'a known key the runner does not execute is a skip entry, and the case passes')
  check(known ~= nil and table.concat((known.diagnostics or {}).warnings or {}, '|')
    :find('ensureHtmlElements', 1, true) ~= nil,
    'an assertion that did not run is named in the case warnings')
  local rejected = find_case(results, 'render/q2-rejected-key/html')
  check(rejected ~= nil and rejected.assertions[1].warnings ~= nil,
    'a key q2 rejects carries a warning')
  equal(reason('render/run-skip-os'), 'skip skipped', '`not_os` skips the document')
  local unknown_run = find_case(results, 'render/run-unknown-key/html')
  check(unknown_run ~= nil and unknown_run.status == 'pass'
    and table.concat((unknown_run.diagnostics or {}).warnings or {}, '|'):find('not-os', 1, true) ~= nil,
    'an unknown key under run is named in the case warnings, as q2 ignores it',
    unknown_run and unknown_run.status)
  equal(reason('render/options-invalid'), 'fail options-invalid', 'an invalid timeout fails the document')
  equal(reason('render/no-format-keys/html'), 'pass nil', 'a document with no format keys renders every format')
  equal(reason('render/empty-format-value/html'), 'pass nil', 'an empty format value renders under the default rule')
  equal(reason('render/format-not-in-front-matter/docx'), 'pass nil',
    'a format key that the format key does not name renders with --to, and its output is found')
  equal(reason('render/prints-warn-without-noerrors/html'), 'fail shortcode-not-found',
    'an expected warning without noErrors still fails, here on the promoted warning first')
  check(duplicate_id(results) == nil, 'no two cases of the vocabulary fixture share an id')

  local project = run_fixture('project-tests-keys', '--layer render')
  local config = find_case(project, 'render/_config')
  equal(config and (config.status .. ' ' .. tostring(config.failure and config.failure.reason)) or 'missing',
    'fail project-tests-keys', 'a project file that sets `run.skip` fails `render/_config`')

  -- A key with no value is merged into every document by Quarto, but the
  -- vendored YAML reader drops it, so the guard reads what Quarto resolved.
  local null_key = run_fixture('project-null-key', '--layer render')
  local null_config = find_case(null_key, 'render/_config')
  equal(null_config and (null_config.status .. ' ' .. tostring(null_config.failure and null_config.failure.reason))
    or 'missing', 'fail project-tests-keys', 'a project file with an empty format key fails `render/_config`')

  -- `run.extension-test` in the project file reaches each document only
  -- through the merge that `quarto inspect` does, so the merge is checked.
  local defaults_dir = util.join(FIXTURES, 'project-defaults', '_t')
  local merged = cli.inspect(util.join(defaults_dir, 'document.qmd'), defaults_dir)
  local merged_spec = merged and frontmatter.spec(merged.tests)
  local merged_settings = merged_spec and frontmatter.options(merged_spec.run,
    schema.load_schema(here .. '_extensions/extension-test/test-schema.yml').options, 'document')
  equal(merged_settings and merged_settings.timeout, 120,
    'a project-level run.extension-test option reaches the document')

  if util.timeout_command() then
    local slow = run_fixture('slow', '--layer render')
    local stalled = find_case(slow, 'render/document/html')
    check(stalled ~= nil and stalled.failure and stalled.failure.reason == 'timeout'
      and stalled.failure.stage == 'render',
      'a render that exceeds its timeout fails with `timeout`',
      stalled and stalled.failure and stalled.failure.reason)
  else
    io.stdout:write('skip a render that exceeds its timeout: neither timeout nor gtimeout is available\n')
  end
end

do
  -- A `.typ` file already beside a document is not what the render kept.
  -- Quarto itself writes and removes `<stem>.typ` during a Typst render, so
  -- the file is created here, before the run, rather than committed.
  util.write_file(util.join(FIXTURES, 'assertions', '_t', 'handwritten.typ'), 'here\n')
  local results = run_fixture('assertions', '--layer render')
  os.remove(util.join(FIXTURES, 'assertions', '_t', 'handwritten.typ'))
  for _, format in ipairs({ 'html', 'typst', 'docx' }) do
    local pass = find_case(results, 'render/assert-pass/' .. format)
    check(pass ~= nil and pass.status == 'pass',
      'the passing assertions pass in ' .. format,
      pass and (pass.status .. ' ' .. tostring(pass.failure and pass.failure.message)))
    local fail = find_case(results, 'render/assert-fail/' .. format)
    check(fail ~= nil and fail.status == 'fail' and fail.failure.reason == 'assertion-failed'
      and fail.failure.stage == 'assert',
      'the failing assertions fail in ' .. format,
      fail and (fail.status .. ' ' .. tostring(fail.failure and fail.failure.reason)))
  end
  local typst_pass = find_case(results, 'render/assert-pass/typst')
  check(typst_pass ~= nil and typst_pass.assertions[1].id == 'ensureTypstFileRegexMatches/match/1',
    'the Typst entries carry their ids')
  check(not util.exists(util.join(FIXTURES, 'assertions', '_t', 'assert-pass.typ')),
    'no kept Typst file stays behind')
  check(not util.exists(util.join(FIXTURES, 'assertions', '_t', 'keep-typ-only.typ')),
    'a kept Typst file is removed even when no assertion reads it')
  local html_fail = find_case(results, 'render/assert-fail/html')
  check(html_fail ~= nil and html_fail.failure.message:find('2 of 2 assertions failed', 1, true) ~= nil,
    'every assertion is evaluated, and the message gives the count',
    html_fail and html_fail.failure.message)
  local printed = find_case(results, 'render/prints-message/html')
  check(printed ~= nil and printed.status == 'pass' and #printed.assertions == 2,
    'printsMessage finds an INFO line and the absence of an ERROR line',
    printed and (printed.status .. ' ' .. tostring(printed.failure and printed.failure.message)))
  local handwritten = find_case(results, 'render/handwritten/typst')
  check(handwritten ~= nil and handwritten.status == 'fail'
    and handwritten.assertions[1].message:find('already existed', 1, true) ~= nil,
    'a .typ file that existed before the render is not read as the kept file',
    handwritten and (handwritten.status .. ' ' .. tostring(handwritten.failure and handwritten.failure.message)))
  local known_case = find_case(results, 'render/assert-pass/docx')
  check(known_case ~= nil and table.concat((known_case.diagnostics or {}).warnings or {}, '|')
    :find('q2 call test fails a document with ensureDocxRegexMatches', 1, true) ~= nil,
    'the q2 warning of an assertion entry reaches the case diagnostics')
  local files = find_case(results, 'render/file-exists/html')
  check(files ~= nil and files.status == 'pass',
    'fileExists finds the output and its support directory',
    files and (files.status .. ' ' .. tostring(files.failure and files.failure.message)))
end

do
  -- A format that `quarto inspect` does not report is written under the
  -- document's `output-file` only when every reported format agrees on it.
  -- A name set inside one format block says nothing about the others.
  local render = require('render')
  equal(render.fallback_output_file({ html = 'elsewhere.html', typst = 'elsewhere.pdf' }, 'doc'), 'elsewhere',
    'a stem that every reported format shares is the fallback')
  equal(render.fallback_output_file({ html = 'custom.html', typst = 'doc.pdf' }, 'doc'), 'doc',
    'formats that disagree fall back to the document stem')
  equal(render.fallback_output_file({}, 'doc'), 'doc', 'no reported format falls back to the document stem')

  -- A project inspect that fails cannot check the project keys, and says so.
  local config_case = render.project_check(util.join(here, 'tests/_results/no-such-project'))
  check(config_case ~= nil and config_case.id == 'render/_config' and config_case.status == 'skip'
    and config_case.failure.reason == 'project-inspect-failed',
    'a failed project inspect is reported as a skip, not passed over',
    config_case and (config_case.status .. ' ' .. tostring(config_case.failure and config_case.failure.reason)))
end

do
  -- The log rule judges what Quarto logged, never a note the runner adds,
  -- such as the one for an incomplete log record.
  local render = require('render')
  equal(render.log_failure('noErrorsOrWarnings', {}, {}), nil, 'a clean log passes the default rule')
  equal(select(1, render.log_failure('noErrorsOrWarnings', {}, { 'w' })), 'warning-logged',
    'a logged warning fails the default rule')
  equal(render.log_failure('noErrors', {}, { 'w' }), nil, 'noErrors allows a logged warning')
  equal(select(1, render.log_failure('noErrors', { 'e' }, {})), 'error-logged', 'noErrors fails on a logged error')
end

do
  -- The default rule fails on a warning from `quarto.log.warning`, which
  -- quarto-cli writes as an INFO record with a `(W)` marker. `noErrors`
  -- allows it, and `printsMessage` finds it without the marker.
  local results = run_fixture('warnings', '--layer render')
  local default = find_case(results, 'render/default-rule/html')
  check(default ~= nil and default.status == 'fail' and default.failure.reason == 'warning-logged'
    and default.failure.stage == 'log',
    'the default rule fails on a warning from quarto.log.warning',
    default and (default.status .. ' ' .. tostring(default.failure and default.failure.reason)))
  local allowed = find_case(results, 'render/warning-allowed/html')
  check(allowed ~= nil and allowed.status == 'pass' and allowed.assertions[1].status == 'pass',
    'noErrors allows the warning, and printsMessage finds it',
    allowed and (allowed.status .. ' ' .. tostring(allowed.failure and allowed.failure.message)))

  -- Generated documents carry no policy, and the generator makes inputs a
  -- careful extension warns about, so the smoke layer renders under
  -- `noErrors` and keeps the warning in the diagnostics.
  local smoke = run_fixture('warnings', '--layer smoke')
  local generated = find_case(smoke, 'smoke/generated/')
  check(generated ~= nil and generated.status == 'pass'
    and #((generated.diagnostics or {}).warnings or {}) > 0,
    'a generated document that logs a warning passes, and the warning is recorded',
    generated and (generated.status .. ' ' .. tostring(generated.failure and generated.failure.reason)))
end

do
  -- A generated document names its formats in `format`, which is all the
  -- render layer needs. A leftover `test:` key would be ordinary metadata
  -- now, and a sign that the generator still writes the old block.
  local results = run_fixture('clean', '--layer smoke --keep-generated')
  local generated = util.join(FIXTURES, 'clean', '_t', 'generated')
  local names = util.list_dir(generated)
  local found_test_key = false
  for _, name in ipairs(names) do
    local text = util.read_file(util.join(generated, name)) or ''
    if text:find('\ntest:', 1, true) then
      found_test_key = true
    end
  end
  check(results ~= nil and #names > 0 and not found_test_key, 'generated documents carry no `test:` key',
    tostring(#names) .. ' generated')
  util.remove_tree(generated)
end

io.stdout:write('# determinism\n')

do
  --- The findings of the vendored validator arrive in hash order, which
  --- differs per process, so this compares the parts a reader would diff.
  local function fingerprint(results)
    local lines = {}
    for _, case in ipairs((results or {}).cases or {}) do
      lines[#lines + 1] = table.concat({
        case.id, case.status,
        (case.failure and case.failure.reason) or '',
        (case.failure and case.failure.message) or '',
        table.concat((case.diagnostics or {}).warnings or {}, '~'),
      }, '|')
    end
    return table.concat(lines, '\n')
  end

  local first = fingerprint(run_fixture('clean'))
  local second = fingerprint(run_fixture('clean'))
  local third = fingerprint(run_fixture('bad-default'))
  local fourth = fingerprint(run_fixture('bad-default'))
  check(first == second and first ~= '',
    'two runs of the passing fixture produce identical cases')
  check(third == fourth and third ~= '',
    'two runs of the failing fixture produce identical cases and messages')
end

io.stdout:write('# version\n')

do
  local text = util.read_file(here .. '_extensions/extension-test/_extension.yml')
  local parsed = schema._parse_yaml_text(text)
  local pipe = io.popen('quarto pandoc lua ' .. RUNNER .. ' --version')
  local reported = pipe:read('*l')
  pipe:close()
  equal(reported, tostring(parsed.version),
    'the runner reports the version its manifest declares')
end

do
  -- The check above documents the happy path, but it cannot fail on its
  -- own: the real manifest and a hard-coded fallback constant could agree
  -- by coincidence, as they did before this task. Diverging a copy's
  -- manifest from anything real is what makes the check able to fail
  -- whenever the runner stops reading it.
  local marker = 'not-a-real-version-8f2c1e'
  local reported, err = run_with_manifest_version(marker)
  check(reported == marker,
    'the runner reports a manifest version nothing else could produce by coincidence',
    err or reported)
end

io.stdout:write(string.format('\n%d checks, %d failed\n', passed + failed, failed))
io.stdout:flush()
os.exit(failed == 0 and 0 or 1, true)
