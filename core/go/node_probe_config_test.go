package main

import "testing"

func TestProbeCannotStartVPNOrPersistentServices(t *testing.T) {
	valid := `{"outbounds":[{"type":"socks","tag":"node-test"}],"route":{"auto_detect_interface":false,"final":"node-test"}}`
	if err := validateNodeProbeConfig(valid, "node-test"); err != nil {
		t.Fatal(err)
	}
	for _, text := range []string{
		`{"outbounds":[{"type":"socks","tag":"node-test"}],"route":{"auto_detect_interface":true}}`,
		`{"inbounds":[{"type":"tun"}]}`,
		`{"experimental":{"cache_file":{"enabled":true}}}`,
		`{"services":[]}`, `{"endpoints":[]}`,
		`{"outbounds":[{"type":"selector","tag":"node-test"}],"route":{}}`,
		`{"outbounds":[{"type":"socks","tag":"node-test"}],"route":{"rule_set":[]}}`,
	} {
		if validateNodeProbeConfig(text, "node-test") == nil {
			t.Fatalf("unsafe probe accepted: %s", text)
		}
	}
	if validateNodeProbeConfig(valid, "other") == nil {
		t.Fatal("unexpected outbound tag accepted")
	}
}
