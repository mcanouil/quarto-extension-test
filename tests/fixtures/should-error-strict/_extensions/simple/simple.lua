return {
  ['complain'] = function(args, kwargs, meta)
    -- The error is logged and the render goes on, so Quarto exits 0.
    quarto.log.error('logged, and the render goes on')
    return pandoc.Str('written anyway')
  end,
  ['halt'] = function(args, kwargs, meta)
    -- Stopping the process ends the render before any output is written.
    io.stderr:write('ERROR: halted on purpose\n')
    os.exit(1)
  end,
}
