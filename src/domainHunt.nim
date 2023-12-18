import starRouter
import starintel_doc
import domainHunt/[resources, crt, certstream_go]
import cligen
import ws
import json
import asyncdispatch
import times

proc certshFilter(doc: proto.Message[Target]): bool =
  doc.data.actor == "certsh"

proc certstreamFilter(doc: proto.Message[Target]): bool =
  doc.data.actor == "certstream" and len(doc.data.options) > 0


proc certstreamMainloop(routerClient: Client, wss: WebSocket, wssAddr: string) {.async.} =
  var
    certstream = CertStream()
    inbox = Target.newInbox(100)
    wss = wss
  inbox.registerFilter(certstreamFilter)
  proc handleTarget(doc: proto.Message[Target]) {.async.} =
    let scanInput = ScanInput(target: doc.data, scope: doc.data.options.to(Scope))
    certstream.scans.add(scanInput)
    when defined(verbose):
      echo "got target: ", doc.data.target
  inbox.registerCB(handleTarget)
  var nextPing = now().toTime().toUnix()
  Target.withInbox(routerClient, inbox):
    let timeNow = now().toTime().toUnix()
    if timeNow >= nextPing:
      await wss.ping("ping")
      nextPing = timeNow + 10
    try:
      await certStream(wss, routerClient, certstream, 10)
    except Exception:
      echo "error!"
      wss = await newWebSocket(wssAddr)

proc main(mode: string = "certstream", apiAddress: string = "tcp://127.0.0.1:6001", subAddress: string = "tcp://127.0.0.1:6000", webSocketAddr: string = "ws://127.0.0.1:8080/") =
  case mode:
    of "certstream":
      try:
        echo "Connecting..."
        var wss = waitFor newWebSocket(webSocketAddr)
        echo "Connecting..."
        var client = newClient(mode, subAddress, apiAddress, 5, @[])
        waitFor client.connect
        echo "connected...."
        waitFor certstreamMainloop(client, wss, webSocketAddr)
      except OsError:
        echo "Could not connect to websocket or message router, please check connection."
        quit(1)
    else:
      echo "Not supported mode!"
      quit(1)

dispatch(main)
