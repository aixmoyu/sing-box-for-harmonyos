<!-- HNA_LEGAL_TEMPLATE_DO_NOT_SUBMIT -->

# Privacy Policy (English Template — Do Not Submit)

> ⚠️ **Drafting template only. Do not publish or submit for review.** The actual
> operator and qualified counsel must verify every statement and replace every
> `[TODO: ...]` placeholder in a separate final document.

Effective date: [TODO: YYYY-MM-DD]
Data controller/operator: [TODO: full legal entity name]
Registered address: [TODO: full address]
Privacy contact: [TODO: monitored public email]
Published policy URL: [TODO: HTTPS URL matching the store listing]

## 1. Product and scope

“[TODO: final product name]” is a VPN/TUN networking utility configured with
subscriptions, proxy nodes, DNS services, and routing rules supplied or selected
by the user. When VPN is enabled, the operating system directs device network
traffic to the app. The app then connects directly or through the user-selected
proxy configuration.

Do not claim that the operator cannot access or process network data unless a
complete audit of source code, dependencies, remote services, and logs proves
that statement. [TODO: disclose any first-party server, telemetry, crash,
update, or customer-support processing]

## 2. Data processed

| Data category | Purpose | Processing location/recipient | Retention |
| --- | --- | --- | --- |
| Subscription URL and local name | Fetch and manage user configuration | Device; subscription provider selected by the user | [TODO: verify encryption and deletion] |
| Proxy host, port, and credentials | Establish the selected connection | Device; proxy operator selected by the user | [TODO: verify HUKS/secure asset implementation] |
| DNS queries and destination domains/IPs | Name resolution and routing | Selected DNS provider, direct network, or proxy | Session; [TODO: verify disk persistence] |
| Latency and availability results | Show node/site reachability | Device; test destination receives the request | [TODO: retention] |
| Traffic rate, byte totals, active connection count | Display runtime status | Device | [TODO: verify memory-only behavior] |
| Diagnostics and crash data | Troubleshooting | [TODO: state whether collected and identify recipient] | [TODO: retention] |

The final policy must not claim “we collect no data” unless the shipped build,
all SDKs, network calls, and logs support that exact statement.

## 3. System permissions

- Network access: fetch subscriptions, connect to user-configured servers, run
  DNS queries, and perform user-requested availability tests.
- VPN service: create a virtual network interface only after the user initiates
  a connection and grants the system VPN authorization. The TUN and native core
  should stop when disconnected.
- [TODO: list every permission from the final module.json5 and its exact purpose]

## 4. Sharing, processors, and international transfers

Requests may be sent to subscription providers, DNS providers, proxy nodes, and
test destinations chosen or configured by the user. Those third parties control
their own processing. [TODO: list every destination preconfigured by the app and
link to the corresponding privacy notice]

[TODO: document the lawful transfer mechanism, user controls, and relevant
regions for each target market. Do not publish an unsupported transfer claim.]

## 5. Local security and deletion

[TODO: after source and device verification, describe credential encryption,
key management, log redaction, atomic writes, uninstall behavior, backups, and
in-app deletion. An app-private directory alone is not encryption.]

Users can delete individual subscriptions or clear configuration in the app,
and can remove sandboxed app data by uninstalling. [TODO: verify that caches,
logs, backups, and system VPN state follow the stated deletion behavior]

## 6. Rights, children, and policy changes

[TODO: list access, correction, deletion, withdrawal, objection, complaint, and
response-time rights for every applicable jurisdiction]

The intended audience is [TODO: age range]. Set the appropriate store age rating
and document the process for handling data identified as belonging to a child.

Material changes will be communicated through [TODO: in-app notice/site/other].
Archived policies: [TODO: HTTPS URL].

## 7. Contact

Privacy requests: [TODO: email]
Postal address: [TODO: legal address]
Response period: [TODO: applicable statutory period]
