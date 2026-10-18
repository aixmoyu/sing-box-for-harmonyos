//go:build !openharmony

package dialer

import "testing"

func TestHostBuildDoesNotClaimOpenHarmony(t *testing.T) {
	if platformIsOpenHarmony {
		t.Fatal("host build selected the OpenHarmony platform target")
	}
}
