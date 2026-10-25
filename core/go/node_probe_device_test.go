package main

import (
	"runtime"
	"testing"
)

func TestProbeOnDeviceDiagnostic(t *testing.T) {
	if runtime.GOOS != "openharmony" {
		t.Skip("device diagnostic")
	}
	config := `{"log":{"disabled":true},"dns":{"servers":[{"type":"udp","tag":"probe-dns","server":"1.1.1.1"}]},"outbounds":[{"type":"socks","tag":"node-test","server":"127.0.0.1","server_port":9}],"route":{"auto_detect_interface":false,"default_domain_resolver":"probe-dns","final":"node-test"}}`
	result := testNodeProbe(config, "node-test")
	t.Logf("synthetic probe result=%d error=%s", result, coreLastErr)
}
