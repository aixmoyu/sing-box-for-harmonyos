//go:build openharmony

package dialer

// The project's OpenHarmony Go port intentionally reports runtime.GOOS as
// "linux". Use the compiler target tag instead of runtime.GOOS so production
// VPN builds cannot silently skip per-socket protection.
const platformIsOpenHarmony = true
