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

package.path = table.concat({ module_dir .. '/?.lua', package.path }, ';')

local util = require('util')
local schema = require('schema')
local values = require('values')
local emit = require('emit')
local report = require('report')

local RUNNER = here .. '_extensions/extension-test/run.lua'
local FIXTURES = here .. 'tests/fixtures'

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

  local orphan = run_fixture('vendored-orphan', '--layer conformance')
  local orphan_case = orphan and find_case(orphan, 'conformance/vendored/vend/example/extra.lua')
  check(orphan_case ~= nil and orphan_case.status == 'fail',
    'a file in the vendor directory that no entry declares fails')
  check(orphan_case ~= nil and orphan_case.failure.reason == 'vendored-undeclared',
    'the failure names the undeclared file', orphan_case and orphan_case.failure.reason)
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
  local results = run_fixture('expect-fail')
  local case = results and find_case(results, 'render/document/')
  check(case ~= nil and case.status == 'pass',
    'a document declaring `expect: fail` passes when the render fails')
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

io.stdout:write(string.format('\n%d checks, %d failed\n', passed + failed, failed))
io.stdout:flush()
os.exit(failed == 0 and 0 or 1, true)
