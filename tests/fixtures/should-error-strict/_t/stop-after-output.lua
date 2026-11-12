-- The render of `output-written.qmd` has written its output by now, and this
-- script makes it exit 1 anyway.
local files = os.getenv('QUARTO_PROJECT_OUTPUT_FILES') or ''
if files:find('output-written', 1, true) then
  io.stderr:write('post-render stops after the output is written\n')
  os.exit(1)
end
