import ws
import starRouter
import std/[json, asyncdispatch, options]
import ./documents
export documents

type Certstream* = ref object
  scans*: seq[ScanInput]

proc parseDomains*(data: string, dataset = ""): seq[JsonNode] =
  let observation = parseJson(data)
  if observation.kind != JObject: raise newException(ValueError, "certificate observation must be an object")
  if observation.hasKey("message_type") and observation["message_type"].getStr() == "heartbeat": return
  let names = observation["data"]["leaf_cert"]["all_domains"]
  if names.kind != JArray: raise newException(ValueError, "all_domains must be an array")
  for entry in names:
    if entry.kind != JString: raise newException(ValueError, "certificate domain must be a string")
    result.add(domainDocument(entry.getStr(), dataset, data, observation))

proc certStream*(wss: WebSocket, routerClient: Client, certstream: Certstream, pingTime = 30) {.async.} =
  let data = await wss.receiveStrPacket()
  # WebSocket Ping/Pong control packets yield an empty text result.
  if data.len == 0: return
  let domains = parseDomains(data)
  var outgoing: seq[JsonNode]
  for domain in domains:
    for scan in certstream.scans:
      if scan.matches(domain["name"].getStr()):
        var document = domain.copy()
        document["dataset"] = %scan.target.dataset
        document["extensions"] = %*{"domainHunt": {"targetId": string(scan.target.id), "scope": scan.target.options.get()["scope"]}}
        outgoing.add(checked(document))
  # Complete observation/configuration validation precedes every publication.
  for document in outgoing:
    await routerClient.emit(proto.newMessage(document, proto.newDocument, routerClient.id, "domain"))
