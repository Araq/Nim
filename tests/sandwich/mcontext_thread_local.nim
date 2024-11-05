# context_thread_local
import ./mtasks, ./mlistdeques

export mlistdeques            # Exporting the type with destructor doesn't help
# export tasks               # solution 1. Exporting the inner type

type MagicCompile = object
  dq: ListDeque[Task]

# var x: MagicCompile        # solution 2. Instantiating the type with destructors
echo "Success"

type
  TLContext* = object
    deque*: ListDeque[Task]
