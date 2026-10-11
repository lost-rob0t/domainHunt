## Verified WebSocket upgrade using ws framing and an explicit TLS context.
## The pinned ws constructor cannot accept the deployment CA configuration.
import ws
import std/[asyncdispatch, base64, httpclient, httpcore, net, sha1, strutils, sysrand, uri]

proc openWebSocket*(address: string): Future[WebSocket] {.async.} =
  var endpoint = parseUri(address)
  let secure = endpoint.scheme == "wss"
  case endpoint.scheme
  of "wss": endpoint.scheme = "https"
  of "ws": endpoint.scheme = "http"
  else: raise newException(ValueError, "Expected ws or wss endpoint")
  when defined(ssl):
    let client = if secure:
      newAsyncHttpClient(sslContext = newContext(verifyMode = CVerifyPeerUseEnvVars))
    else:
      newAsyncHttpClient(sslContext = nil)
  else:
    if secure: raise newException(ValueError, "Secure WebSocket requires -d:ssl")
    let client = newAsyncHttpClient()
  let key = base64.encode(urandom(16))
  client.headers = newHttpHeaders({"Connection": "Upgrade", "Upgrade": "websocket",
                                 "Sec-WebSocket-Version": "13", "Sec-WebSocket-Key": key})
  let response = await client.get($endpoint)
  let expected = base64.encode(Sha1Digest(secureHash(key & "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")))
  if response.code != Http101 or
      response.headers.getOrDefault("Upgrade").toLowerAscii() != "websocket" or
      response.headers.getOrDefault("Sec-WebSocket-Accept") != expected:
    client.close()
    raise newException(WebSocketFailedUpgradeError, "Invalid WebSocket upgrade")
  return WebSocket(tcpSocket: client.getSocket(), masked: true, readyState: Open)
