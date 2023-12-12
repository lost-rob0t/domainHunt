import httpclient
import asyncdispatch
import starintel_doc
import json, strutils, strformat
import resources
const CRTSH_URL = "https://crt.sh/"

type
  CrtshClient = ref object
    pool: HttpClientPool
  AsyncCrtShClient = ref object
    pool: AsyncHttpClientPool


proc newCrtShClient(poolSize: int): CrtShClient =
  var client = CrtShClient()
  client.pool = newHttpClientPool(poolSize)
  result = client
proc newAsyncCrtShClient(poolSize: int): AsyncCrtShClient =
  var client = AsyncCrtShClient()
  client.pool = newAsyncHttpClientPool(poolSize)
  result = client
proc crtsh*(client: CrtShClient or AsyncCrtShClient, domain: string): Future[seq[Domain]] {.multisync.} =
  var domains: seq[Domain]
  client.pool.withPool():
    let url = fmt"{CRTSH_URL}/?q={domain}&output=json"
    let resp = (await resource.getContent(url)).parseJson()
    when defined(debug):
      echo resp
    for resp in resp.getElems:
      let domainStr = resp["name_value"].getStr
      # TODO Make emails from this.
      if domainStr.contains("@"): continue
      var domain = newDomain(domainStr, "",  "", "crt.sh")
      domain.addSource("crt.sh")
      domains.add(domain)
  result = domains



when isMainModule:
  var client = newCrtShClient(10)
  let domains = client.crtsh("google.com")
  for domain in domains:
    echo domain.record
