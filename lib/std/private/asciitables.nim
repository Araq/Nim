#[
move to std/asciitables.nim once stable, or to a fusion package
once compiler can depend on fusion
]#

type Cell* = object
  text*: string
  width*, row*, col*, ncols*, nrows*: int

iterator parseTableCells*(s: string, delim = '\t'): Cell =
  ## Iterates over all cells in a `delim`-delimited `s`, after a 1st
  ## pass that computes number of rows, columns, and width of each column.
  var widths: seq[int] = @[]
  var cell: Cell = Cell()
  template update() =
    if widths.len<=cell.col:
      widths.setLen cell.col+1
      widths[cell.col] = cell.width
    else:
      widths[cell.col] = max(widths[cell.col], cell.width)
    cell.width = 0

  for a in s:
    case a
    of '\n':
      update()
      cell.col = 0
      cell.row.inc
    elif a == delim:
      update()
      cell.col.inc
    else:
      # todo: consider multi-width chars when porting to non-ascii implementation
      cell.width.inc
  if s.len > 0 and s[^1] != '\n':
    update()

  cell.ncols = widths.len
  cell.nrows = cell.row + 1
  cell.row = 0
  cell.col = 0
  cell.width = 0

  template update2() =
    cell.width = widths[cell.col]
    yield cell
    cell.text = ""
    cell.width = 0
    cell.col.inc

  template finishRow() =
    for col in cell.col..<cell.ncols:
      cell.col = col
      update2()
    cell.col = 0

  for a in s:
    case a
    of '\n':
      finishRow()
      cell.row.inc
    elif a == delim:
      update2()
    else:
      cell.width.inc
      cell.text.add a

  if s.len > 0 and s[^1] != '\n':
    finishRow()

proc alignTable*(s: string, delim = '\t', fill = ' ', sep = " "): string =
  ## Formats a `delim`-delimited `s` representing a table; each cell is aligned
  ## to a width that's computed for each column; consecutive columns are
  ## delimited by `sep`, and alignment space is filled using `fill`.
  ## More customized formatting can be done by calling `parseTableCells` directly.
  result = ""
  for cell in parseTableCells(s, delim):
    result.add cell.text
    for i in cell.text.len..<cell.width:
      result.add fill
    if cell.col < cell.ncols-1:
      result.add sep
    if cell.col == cell.ncols-1 and cell.row < cell.nrows - 1:
      result.add '\n'
