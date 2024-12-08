# issue #14860

type
  Dummie = object

iterator `[]`(d: Dummie, a, b: int): int = discard

let d = Dummie()

for s in d[0, 1]: discard # error here
