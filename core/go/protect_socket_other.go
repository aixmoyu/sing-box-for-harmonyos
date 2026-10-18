//go:build !openharmony

package main

import "errors"

func protectSocketFromVPN(fd int32) error {
	if err := validateProtectSocketFD(fd); err != nil {
		return err
	}
	return errors.New("HarmonyOS VPN socket protection is unavailable on this host")
}
