return {
  ['boom'] = function(args, kwargs, meta)
    -- Raising here ends the render, which is what the fixture asserts.
    error('this shortcode always fails')
  end
}
