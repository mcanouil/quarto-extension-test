return {
  warns = function()
    quarto.log.warning('warns: on purpose')
    return pandoc.Str('here')
  end,
}
