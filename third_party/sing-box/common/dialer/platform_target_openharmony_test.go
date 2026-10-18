//go:build openharmony

package dialer

import "testing"

func TestOpenHarmonyBuildTagSelected(t *testing.T) {
	if !platformIsOpenHarmony {
		t.Fatal("OpenHarmony build did not select its platform target")
	}
}
