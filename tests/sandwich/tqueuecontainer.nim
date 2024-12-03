# issue #4773

import mqueuecontainer

# works if this is uncommented (or if the `queuecontainer` exports `queues`):
# import queues

var c: QueueContainer[int]
c.init()
c.addToQ(1)
