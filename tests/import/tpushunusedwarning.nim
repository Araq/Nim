# issue #24552

{.warningAsError[UnusedImport]: on.}
{.push warning[UnusedImport]: off.}
import tables
{.pop.}

proc test*(a: float): float =
  a
