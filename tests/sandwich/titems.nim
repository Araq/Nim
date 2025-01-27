# issue #22984
# import sets # <<-- Uncomment this to make the error go away

import mitems

## The generic implementation
var grp: EntGroup[Fruit] = initEntGroup[Fruit]()
doAssert $get(grp) == "Fruit(20)" ## Errors here


## This works though (Non-generic)
var fruitGroup: FruitGroup = initFruitGroup()
doAssert $getNoGeneric(fruitGroup) == "Fruit(20)"
