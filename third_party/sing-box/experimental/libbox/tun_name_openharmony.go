//go:build openharmony

package libbox

// HarmonyOS VpnConnection returns an already configured TUN descriptor. The
// public API does not expose a Linux TUNGETIFF ioctl contract, and sing-box only
// needs a stable logical name when the platform owns interface configuration.
func getTunnelName(fd int32) (string, error) {
	return "vpn-tun", nil
}
