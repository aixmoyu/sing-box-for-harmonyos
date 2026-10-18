package dialer

import "testing"

func TestShouldAttachPlatformProtectForTarget(t *testing.T) {
	tests := []struct {
		name        string
		openharmony bool
		auto        bool
		extension   bool
		want        bool
	}{
		{name: "HarmonyOS extension without auto detect", openharmony: true, extension: true, want: true},
		{name: "existing auto detect path", openharmony: true, auto: true, extension: true, want: false},
		{name: "HarmonyOS regular process", openharmony: true, extension: false, want: false},
		{name: "non-HarmonyOS extension remains unchanged", extension: true, want: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := shouldAttachPlatformProtectForTarget(test.openharmony, test.auto, test.extension); got != test.want {
				t.Fatalf("decision = %v, want %v", got, test.want)
			}
		})
	}
}
