import std/[assertions, net, os]

let unixSocketPath = getCurrentDir() / "usox"

removeFile(unixSocketPath)

let socket = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_NONE)
socket.bindUnix(unixSocketPath)
socket.listen()

var
  clientSocket: Socket
  data: string

socket.accept(clientSocket)
clientSocket.readLine(data)
doAssert data == "data sent through the socket"
clientSocket.send("Hello from server\c\l")

clientSocket.readLine(data)
doAssert data == "bye"
clientSocket.send("bye\c\l")

clientSocket.close()
socket.close()
removeFile(unixSocketPath)
