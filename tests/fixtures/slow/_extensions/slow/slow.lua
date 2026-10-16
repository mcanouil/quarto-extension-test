return {
  slow = function()
    -- Longer than the one-second timeout of the fixture document.
    os.execute('sleep 5')
    return pandoc.Str('late')
  end,
}
