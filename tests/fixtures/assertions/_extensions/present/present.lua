return {
  present = function()
    if quarto.doc.is_format('html') then
      quarto.doc.add_html_dependency({ name = 'present', version = '1.0.0', scripts = { 'present.js' } })
    end
    return pandoc.Str('here')
  end,
}
