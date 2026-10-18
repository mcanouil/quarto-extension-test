-- Quarto reports a filter that exits or raises, so the render here is killed
-- from outside instead, as the out-of-memory killer would: the shell's parent
-- is pandoc, and pandoc's parent is the Quarto process.
return {
  silent = function()
    os.execute('kill -KILL "$(ps -o ppid= -p "$PPID" | tr -d " ")"')
    return pandoc.Str('unreachable')
  end,
}
