discard """
  output: '''success'''
  cmd: "nim c --gc:orc -d:release $file"
"""

# bug #17170

when true:
  import asyncdispatch

  type
    Flags = ref object
      returnedEof, reading: bool

  proc dummy(): Future[string] {.async.} =
    result = "foobar"

  proc hello(s: Flags) {.async.} =
    let buf =
      try:
        await dummy()
      except CatchableError as exc:
        # When an exception happens here, the Bufferstream is effectively
        # broken and no more reads will be valid - for now, return EOF if it's
        # called again, though this is not completely true - EOF represents an
        # "orderly" shutdown and that's not what happened here..
        s.returnedEof = true
        raise exc
      finally:
        s.reading = false

  waitFor hello(Flags())
  echo "success"

# bug #18240
import tables

type
  TopicHandler* = proc(topic: string,
                       data: seq[byte]): Future[void] {.gcsafe, raises: [Defect].}

  PeerID* = object
    data*: seq[byte]

  PeerInfo* = ref object of RootObj
    peerId*: PeerID

  Connection* = ref object of RootObj
    peerInfo*: PeerInfo

  PubSubPeer* = ref object of RootObj
    codec*: string

  PubSub* = ref object of RootObj
    topics*: Table[string, seq[TopicHandler]]
    peers*: Table[PeerID, PubSubPeer]

proc getOrCreatePeer*(myParam: PubSub, peerId: PeerID, protos: seq[string]): PubSubPeer =
  result = nil
  myParam.peers.withValue(peerId, peer):
    return peer[]

method handleConn*(myParam: PubSub,
                  conn: Connection,
                  proto: string) {.base, async.} =
  myParam.peers.withValue(conn.peerInfo.peerId, peer):
    let peerB = peer[]
