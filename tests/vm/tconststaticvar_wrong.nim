proc test =
  const TEST = block:
    let i = 1
    const j = i + 1 #[tt.Error
              ^ cannot evaluate at compile time: i]#
    j
