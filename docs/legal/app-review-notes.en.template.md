<!-- HNA_LEGAL_TEMPLATE_DO_NOT_SUBMIT -->

# AppGallery Review Notes (English Template — Do Not Submit)

> ⚠️ **Reviewer-note draft only.** [TODO: Copy into AGC only after every item
> matches the final release `.app`, public policies, and real-device behavior.
> Provide live credentials only through Huawei-controlled review fields.]

## App identity

- App name: [TODO: final name]
- Bundle name: `com.harmonynet.assistant` [TODO: match final AGC record]
- Version: [TODO: versionName/versionCode]
- Legal operator: [TODO: full entity]
- Countries/regions and devices: [TODO: mainland-China phone or other scope
  confirmed by Huawei in writing]
- Huawei VPN/proxy classification ticket: [TODO: ticket ID]

## Primary review flow

1. Open Subscriptions and add the review-only subscription name and URL.
2. Return Home and select manual, URL-test, or preferred-node recovery strategy.
3. Select Rules, Global Proxy, or Direct routing, then tap Connect.
4. Approve the operating-system VPN dialog; the app does not bypass it.
5. Use Diagnostics for node latency, site availability, and IP/DNS checks.
6. While connected, change the node, DNS, or IPv6 setting and verify runtime
   readback.
7. Tap Disconnect and confirm the VPN indicator, TUN, and native core stop.

[TODO: attach steps/screenshots from the minimum API 22 device, the API 26 target device, and the exact final build]

## Review configuration

- Review subscription: [TODO: provide in secure AGC field, never in Git/public docs]
- Expiration/traffic quota: [TODO: cover expected review period]
- Region, IP, or time restrictions: [TODO: none or exact limitations]
- Support responder and time zone: [TODO: name/email/time zone]

## Permissions, data, and destinations

- INTERNET: subscription fetches, DNS, proxy connections, and user-triggered tests.
- GET_NETWORK_INFO: confirms that the system VPN bearer has disappeared before reporting a completed disconnect.
- GET_BUNDLE_INFO: reads launchable app names and bundle IDs only when the user opens VPN allowlist management; processing stays on device.
- VPN Extension: creates TUN only after the user connects and grants system consent.
- Sensitive local configuration: [TODO: link final HUKS/secure asset evidence]
- Built-in DNS/test destinations: [TODO: list every final hostname and purpose]
- Third-party SDK/telemetry: [TODO: attach final SBOM and network-capture conclusion]

## Native core and open source

- sing-box version: [TODO: copy from release-manifest.json]
- Updates: signed app releases only; no hot replacement of executable `.so` files.
- GPL corresponding source: [TODO: exact public HTTPS commit/patch URL]
- Open-source notices: [TODO: public HTTPS URL]

## Evidence and unresolved items

- Release App Pack SHA-256: [TODO: copy from SHA256SUMS]
- Device connection/speed/switch/disconnect evidence: [TODO: report link]
- Privacy policy, agreement, and support pages: [TODO: public HTTPS URLs]
- Mainland telecom/VPN opinion or overseas phone eligibility: [TODO: evidence/ticket]
- Known limitations: [TODO: accurate list matching the submitted build]
