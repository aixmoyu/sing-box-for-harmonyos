package dialer

import "github.com/sagernet/sing-box/adapter"

func shouldAttachPlatformProtect(networkManager adapter.NetworkManager, platformInterface adapter.PlatformInterface) bool {
	if networkManager == nil || platformInterface == nil {
		return false
	}
	return shouldAttachPlatformProtectForTarget(
		platformIsOpenHarmony,
		networkManager.AutoDetectInterface(),
		platformInterface.UnderNetworkExtension(),
	)
}

// Keep the platform decision pure so it can be regression-tested on the host
// toolchain even though the OpenHarmony target is cross-compiled.
func shouldAttachPlatformProtectForTarget(openHarmonyTarget bool, autoDetectInterface bool, underNetworkExtension bool) bool {
	return openHarmonyTarget && !autoDetectInterface && underNetworkExtension
}
