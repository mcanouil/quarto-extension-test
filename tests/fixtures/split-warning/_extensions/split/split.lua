-- `quarto.log.warning` writes the `(W)` marker and its text in separate calls,
-- and quarto-cli logs each pipe read as its own record. The pause makes the
-- read land between the two every time, as it sometimes does by chance.
return {
  split = function()
    io.stderr:write('(W)')
    io.stderr:flush()
    os.execute('sleep 0.3')
    io.stderr:write(' split: on purpose', '\n')
    return pandoc.Str('split')
  end,
}
