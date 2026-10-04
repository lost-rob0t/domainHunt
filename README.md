# DomainHunt

DomainHunt consumes certificate observations over WebSocket and publishes matching Domain documents through StarRouter. StarLang is the sole authority for the wire schema: the complete generated 0.10.1 release is vendored, and both the Router and Nim document runtime are pinned to consumers of that same immutable release.

## Build and validate

```sh
python3 scripts/sync-starintel-schema.py
nix flake check -L
nix build
./result/bin/domainHunt --help
```

The upstream check compares every vendored artifact with its recorded StarLang commit. The build also verifies every artifact against the actual Router and Nim runtime inputs. Nix checks the whole application and its installed executable against a real plain and secure WebSocket sources and a ZeroMQ broker, including matching, exclusion precedence, stable identity, complete evidence preservation, rejected scope configuration, and rejection of malformed observations before publication.

## Configure a scan

Submit a canonical Target to the `certstream` actor. `options.scope` carries a complete canonical Scope snapshot; an optional `scope` reference must identify that snapshot. This actor option transports source-defined documents and does not define another document schema.

```json
{
  "id": "target:example",
  "dataset": "example",
  "dtype": "target",
  "schemaVersion": "0.10.1",
  "actor": "certstream",
  "target": "example.test",
  "scope": {"schema": "org.starintel/core@1/scope", "id": "scope:example"},
  "options": {
    "scope": {
      "id": "scope:example",
      "dataset": "example",
      "dtype": "scope",
      "schemaVersion": "0.10.1",
      "name": "Example domains",
      "inScope": ["\\.example\\.test$"],
      "outOfScope": ["^blocked\\."]
    }
  }
}
```

Matching retains the existing regex semantics: exclusions take precedence, and a domain must match an inclusion. Invalid snapshots, mismatched references, or invalid regexes leave existing scans intact. The existing broker polling loop remains in use; this change does not claim higher stream throughput.

Published canonical Domains use `name` and the existing MD5 domain identity, inherit the Target dataset, preserve the complete observation in `raw` and its exact original text in `rawContent`, and retain the Target ID and scope snapshot under `extensions.domainHunt`. Every domain in an observation is validated before any is published. TLS verifies peers against deployment CA environment variables; the installed wrapper supplies a closed CA bundle by default. Untrusted certificates are rejected in the live tests. WebSocket control packets are handled without treating them as malformed certificate observations.

The `crt.sh` prototype is compiled against the same canonical projection. The executable still supports only the existing `certstream` mode; the prototype is not an enabled CLI mode.
