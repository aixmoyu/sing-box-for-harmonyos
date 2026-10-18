//go:build !openharmony

package main

import "testing"

func TestHarmonyPlatformControlIsNotANoopOnHost(t *testing.T) {
	if err := (&harmonyPlatform{}).AutoDetectInterfaceControl(0); err == nil {
		t.Fatal("non-HarmonyOS platform control unexpectedly succeeded")
	}
}
