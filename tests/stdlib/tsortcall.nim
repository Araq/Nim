discard """
  matrix: "--mm:refc; --mm:orc"
"""

import algorithm
import unittest


suite "test sort, sorted, and isSorted procs":
  proc foosort(ships: var seq[int]) = sort(ships, system.cmp[int])

  type
    User = object
      name: string
      age: int

  func newUser(name: string, age: int): User =
    result = default(User)
    result.name = name
    result.age = age

  proc compareUsers(x, y: User): int =
    if x.age == y.age: return 0
    if x.age < y.age: return -1
    return 1

  setup:
    var
      unSortedIntSeq = @[1, 4, 3, 5, -1]
      unSortedUserSeq = @[newUser("Andreas", 34), newUser("Alice", 12), newUser("Bob", 23)]

    let
      sortedIntSeq = @[-1, 1, 3, 4, 5]
      sortedUserSeq = @[newUser("Alice", 12), newUser("Bob", 23), newUser("Andreas", 34)]

  test "test the shortcut versions of sort, sorted, and isSorted":
    check(not unSortedIntSeq.isSorted)
    check sorted(unSortedIntSeq) == sortedIntSeq
    check sorted(unSortedIntSeq).isSorted

    unSortedIntSeq.sort()
    check unSortedIntSeq == sortedIntSeq
    check unSortedIntSeq.isSorted

  test "test the shortcut versions with descending sort order":
    check(not unSortedIntSeq.isSorted(SortOrder.Descending))
    check sorted(unSortedIntSeq, SortOrder.Descending) == reversed sortedIntSeq
    check sorted(unSortedIntSeq).isSorted(SortOrder.Ascending)

    unSortedIntSeq.sort(SortOrder.Descending)
    check unSortedIntSeq == reversed sortedIntSeq
    check unSortedIntSeq.isSorted(SortOrder.Descending)

  test "test the versions that accept a custom compareUsers function":
    check(not unSortedUserSeq.isSorted(compareUsers))
    check sorted(unSortedUserSeq, compareUsers) == sortedUserSeq
    check sorted(unSortedUserSeq, compareUsers).isSorted(compareUsers)

    unSortedUserSeq.sort(compareUsers)
    check unSortedUserSeq == sortedUserSeq
    check unSortedUserSeq.isSorted(compareUsers)

  test "test the long versions with descending sort order":
    check(not unSortedUserSeq.isSorted(compareUsers, SortOrder.Descending))
    check sorted(unSortedUserSeq, compareUsers, SortOrder.Descending) == reversed sortedUserSeq
    check sorted(unSortedUserSeq, compareUsers,
                  SortOrder.Descending).isSorted(compareUsers, SortOrder.Descending)
    unSortedUserSeq.sort(compareUsers, SortOrder.Descending)
    check unSortedUserSeq == reversed sortedUserSeq
    check unSortedUserSeq.isSorted(compareUsers, SortOrder.Descending)
