-- `quarto.log.warning` writes the `(W)` marker and its text in separate calls,
-- and quarto-cli logs each pipe read as its own record. The pause makes the
-- read land between the two every time, as it sometimes does by chance. A
-- second leaves room for a loaded runner, where a shorter pause can let one
-- read take both writes.
return {
  split = function()
    io.stderr:write('(W)')
    io.stderr:flush()
    os.execute('sleep 1')
    io.stderr:write(' split: on purpose', '\n')
    return pandoc.Str('split')
  end,
}
