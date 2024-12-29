discard """
  matrix: "--mm:refc; --mm:arc"
  joinable: false
"""

import std/[unittest, asyncdispatch]

# bug #18616
type
  ClientResponse = object
    status*: int
    data*: string

template asyncTest*(name: string, body: untyped): untyped =
  test name:
    waitFor((
      proc() {.async, gcsafe.} =
        body
    )())

suite "Test suite":
  asyncTest "test1":
    const PostVectors = [
      (
        ("/test/post", "somebody0908", "text/html",
        "app/type1;q=0.9,app/type2;q=0.8"),
        ClientResponse(status: 200, data: "type1[text/html,somebody0908]")
      ),
      (
        ("/test/post", "somebody0908", "text/html",
        "app/type2;q=0.8,app/type1;q=0.9"),
        ClientResponse(status: 200, data: "type1[text/html,somebody0908]")
      ),
      (
        ("/test/post", "somebody09", "text/html",
         "app/type2,app/type1;q=0.9"),
        ClientResponse(status: 200, data: "type2[text/html,somebody09]")
      ),
      (
        ("/test/post", "somebody09", "text/html", "app/type1;q=0.9,app/type2"),
        ClientResponse(status: 200, data: "type2[text/html,somebody09]")
      ),
      (
        ("/test/post", "somebody", "text/html", "*/*"),
        ClientResponse(status: 200, data: "type1[text/html,somebody]")
      ),
      (
        ("/test/post", "somebody", "text/html", ""),
        ClientResponse(status: 200, data: "type1[text/html,somebody]")
      ),
      (
        ("/test/post", "somebody", "text/html", "app/type2"),
        ClientResponse(status: 200, data: "type2[text/html,somebody]")
      ),
      (
        ("/test/post", "somebody", "text/html", "app/type3"),
        ClientResponse(status: 406, data: "")
      )
    ]

    for item in PostVectors:
      discard item

  asyncTest "test2":
    const PostVectors = [
      (
        "/test/post", "somebody0908", "text/html",
        "app/type1;q=0.9,app/type2;q=0.8",
        ClientResponse(status: 200, data: "type1[text/html,somebody0908]")
      ),
      (
        "/test/post", "somebody0908", "text/html",
        "app/type2;q=0.8,app/type1;q=0.9",
        ClientResponse(status: 200, data: "type1[text/html,somebody0908]")
      ),
      (
        "/test/post", "somebody09", "text/html",
        "app/type2,app/type1;q=0.9",
        ClientResponse(status: 200, data: "type2[text/html,somebody09]")
      ),
      (
        "/test/post", "somebody09", "text/html", "app/type1;q=0.9,app/type2",
        ClientResponse(status: 200, data: "type2[text/html,somebody09]")
      ),
      (
        "/test/post", "somebody", "text/html", "*/*",
        ClientResponse(status: 200, data: "type1[text/html,somebody]")
      ),
      (
        "/test/post", "somebody", "text/html", "",
        ClientResponse(status: 200, data: "type1[text/html,somebody]")
      ),
      (
        "/test/post", "somebody", "text/html", "app/type2",
        ClientResponse(status: 200, data: "type2[text/html,somebody]")
      ),
      (
        "/test/post", "somebody", "text/html", "app/type3",
        ClientResponse(status: 406, data: "")
      )
    ]

    for item in PostVectors:
      discard item