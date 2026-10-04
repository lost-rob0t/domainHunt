## Canonical StarLang-backed document projection and actor scope configuration.
import std/[json, jsonutils, md5, options, re]
import starintel_doc except Message

type
  ScanInput* = object
    target*: Target
    scope*: Scope
    included: seq[Regex]
    excluded: seq[Regex]

proc checked*(document: JsonNode): JsonNode =
  let check = validateDocument(document)
  if not check.ok: raise newException(ValueError, check.category & ": " & check.message)
  document

proc configureScan*(target: Target): ScanInput =
  let options = target.options.get(newJObject())
  if not options.hasKey("scope"):
    raise newException(ValueError, "options.scope must contain a canonical Scope document")
  let scopeDocument = checked(options["scope"])
  if scopeDocument["dtype"].getStr() != "scope":
    raise newException(ValueError, "options.scope must be a Scope document")
  result.target = target
  result.scope = jsonTo(scopeDocument, Scope, Joptions(allowMissingKeys:true))
  if target.scope.isSome:
    let reference = target.scope.get()
    if reference.schema != "org.starintel/core@1/scope" or reference.id != scopeDocument["id"].getStr():
      raise newException(ValueError, "target scope reference differs from options.scope")
  for pattern in result.scope.inScope.get(@[]): result.included.add(re(pattern))
  for pattern in result.scope.outOfScope.get(@[]): result.excluded.add(re(pattern))

proc matches*(scan: ScanInput, name: string): bool =
  for pattern in scan.excluded:
    if name.contains(pattern): return false
  for pattern in scan.included:
    if name.contains(pattern): return true

proc domainDocument*(name, dataset, rawContent: string, raw: JsonNode): JsonNode =
  checked(%*{"id": $toMD5(name), "dataset": dataset, "dtype": "domain", "schemaVersion": "0.10.1",
             "name": name, "raw": raw.copy(), "rawContent": rawContent})
