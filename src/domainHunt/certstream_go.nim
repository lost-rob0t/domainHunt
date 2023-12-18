import ws
import starintel_doc, starRouter
import jsony
import resources
import httpclient, asyncdispatch
import regex
import times
import strutils

type
  Certstream* = ref object
    scans*: seq[ScanInput]
  Subject = ref object
    C: string
    CN: string
    L: string
    O: string
    OU: string
    ST: string
    aggregated: string
    email_address: string

  Issuer = ref object
    C: string
    CN: string
    L: string
    O: string
    OU: string
    ST: string
    aggregated: string
    email_address: string

  Extensions = ref object
    authorityInfoAccess: string
    authorityKeyIdentifier: string
    basicConstraints: string
    keyUsage: string
    subjectAltName: string
    subjectKeyIdentifier: string

  LeafCert = ref object
    all_domains: seq[string]
    extensions: Extensions
    fingerprint: string
    sha1: string
    sha256: string
    not_after: int
    not_before: int
    serial_number: string
    signature_algorithm: string
    subject: Subject
    issuer: Issuer
    is_ca: bool

  CertData = ref object
    cert_index: int
    cert_link: string
    leaf_cert: LeafCert
    seen: float
    source: Source
    update_type: string

  Source = ref object
    name: string
    url: string

  X509LogEntry = ref object
    data: CertData
    message_type: string




proc parseDomains*(data: string): seq[Domain] =
  let certData = data.fromJson(X509LogEntry)
  for entry in certData.data.leaf_cert.all_domains:
    var domain = newDomain(entry, "", "", "cert-stream")
    domain.addSource("cert-stream")
    result.add(domain)

proc certStream*(wss: WebSocket, routerClient: Client, certstream: Certstream, pingTime: int = 30) {.async.} =

  let data = await wss.receiveStrPacket()
  if data.startsWith("{"):
    let domains = data.parseDomains()
    for data in domains:
      # TODO Logging
      for scan in certstream.scans:
        if scan.scope.contains(data):
          when defined(verbose):
            echo "Found Domain: ", data.record
          data.dataset = scan.target.dataset
          data.timestamp
          let message =  proto.newMessage(data, proto.newDocument, routerClient.id, data.dtype)
          await routerClient.emit(message)


when isMainModule:
  proc testLoop() {.async.} =
    var wss = await newWebSocket("ws://10.50.50.221:8080/")
    var router = newClient("certstream", "tcp://127.0.0.1:6000", "tcp://127.0.0.1:6001", 5,@[])
    var scope = newScope("test aws", "This is a test for aws")
    scope.inScopeAdd(".*")
    echo scope.toJson
    await router.connect()
    await certStream(wss, router, CertStream(scans: @[newScan("test", "amazonaws.com", "certstream", scope)]))

  import jsony
  var hs = newHttpClient()
  while true:
    waitFor testLoop()
