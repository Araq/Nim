discard """
  matrix: "--mm:refc; --mm:orc"
  output: '''Can't access 6
10
11
2
Can't access 6
10
11
2
Can't access 6
10
11
2
Can't access 6
10
11
2
0
10
11
0
10
11
Can't access 6
5
Can't access 6
10
11
Can't access 6
10
11'''
"""

import tables

block:
  var x = initTable[int, int]()
  x[5] = 10
  try:
    echo x[6]
  except KeyError:
    echo "Can't access 6"
  echo x[5]
  x[5] += 1
  var c = x[5]
  echo c
  x.mgetOrPut(7).inc
  x.mgetOrPut(7).inc
  echo x[7]

block:
  var x = newTable[int, int]()
  x[5] = 10
  try:
    echo x[6]
  except KeyError:
    echo "Can't access 6"
  echo x[5]
  x[5] += 1
  var c = x[5]
  echo c
  x.mgetOrPut(7).inc
  x.mgetOrPut(7).inc
  echo x[7]

block:
  var x = initOrderedTable[int, int]()
  x[5] = 10
  try:
    echo x[6]
  except KeyError:
    echo "Can't access 6"
  echo x[5]
  x[5] += 1
  var c = x[5]
  echo c
  x.mgetOrPut(7).inc
  x.mgetOrPut(7).inc
  echo x[7]

block:
  var x = newOrderedTable[int, int]()
  x[5] = 10
  try:
    echo x[6]
  except KeyError:
    echo "Can't access 6"
  echo x[5]
  x[5] += 1
  var c = x[5]
  echo c
  x.mgetOrPut(7).inc
  x.mgetOrPut(7).inc
  echo x[7]

block:
  var x = initCountTable[int]()
  x[5] = 10
  try:
    echo x[6]
  except KeyError:
    echo "Can't access 6"
  echo x[5]
  x.inc 5, 1
  var c = x[5]
  echo c

block:
  var x = newCountTable[int]()
  x[5] = 10
  try:
    echo x[6]
  except KeyError:
    echo "Can't access 6"
  echo x[5]
  x.inc 5, 1
  var c = x[5]
  echo c

import sets

block:
  var x = initHashSet[int]()
  x.incl 5
  try:
    echo x[6]
  except KeyError:
    echo "Can't access 6"
  echo x[5]

import critbits

block:
  var x: CritBitTree[int]
  x["5"] = 10
  try:
    echo x["6"]
  except KeyError:
    echo "Can't access 6"
  echo x["5"]
  x["5"] += 1
  var c = x["5"]
  echo c

import strtabs

block:
  var x = newStringTable()
  x["5"] = "10"
  try:
    echo x["6"]
  except KeyError:
    echo "Can't access 6"
  echo x["5"]
  x["5"][1] = '1'
  var c = x["5"]
  echo c
