# HarmonyOS outbound socket binding

The embedded sing-box core binds every newly created outbound file descriptor
to a physical underlay with public HarmonyOS NetworkKit NDK APIs. It does not
call any private internal socket-marking protocol.

## SDK ABI pinned by the build

The API 26 SDK bundled with DevEco Studio declares these interfaces in
`network/netmanager/net_connection.h` and links them from
`libnet_connection.so`:

- `OH_NetConn_GetAllNets(NetConn_NetHandleList *)`, introduced in API 11.
- `OH_NetConn_GetNetCapabilities(NetConn_NetHandle *, NetConn_NetCapabilities *)`, introduced in API 11.
- `OH_NetConn_BindSocket(int32_t, NetConn_NetHandle *)`, introduced in API 12.

The C shim contains compile-time checks for those function signatures and for
the capability and bearer enum values it consumes. These APIs are below the
application's API 22 compatibility floor.

## Fail-closed selection

For each descriptor, the core takes a new `GetAllNets` snapshot and queries the
capabilities of every returned network. A candidate is eligible only when all
of these statements are true:

- its network ID is positive;
- it contains `INTERNET`, `NOT_VPN`, and `VALIDATED` capabilities;
- it has a Wi-Fi or cellular bearer;
- it does not contain a VPN bearer.

Validated Wi-Fi is preferred over cellular, with the lowest network ID used as
the deterministic tie-breaker. Ethernet, Bluetooth, VPN, unvalidated, portal,
capability-incomplete, and malformed candidates are rejected. An enumeration,
capability, or bind error fails that connection; there is no fallback to the
default route or a private service.

No network handle is cached. Concurrent connection attempts use independent
stack-local snapshots. If a network changes between enumeration and
`BindSocket`, that bind is allowed to fail; the next file descriptor performs a
fresh enumeration and can select the new underlay.

## Verification boundary

Host unit tests cover eligibility, deterministic preference, fail-closed error
propagation, concurrent calls, and re-enumeration after a simulated Wi-Fi to
cellular switch. The ARM64 cross-build proves the NDK headers and dynamic link
contract. Only real-device testing can prove runtime permissions, service
behavior, traffic bypass, Wi-Fi/cellular handover, and absence of VPN routing
loops on a shipping HarmonyOS build.
