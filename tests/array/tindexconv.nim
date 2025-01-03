block: # issue #17958
  var mem: array[uint8, uint8]
  let val = 0xffff'u16
  discard mem[uint8 val]   # Error: unhandled exception: index 65535 not in 0 .. 255 [IndexDefect]
