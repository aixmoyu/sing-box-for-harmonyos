package main

import (
	"encoding/json"
	"github.com/sagernet/sing-box/daemon"
	"strings"
	"testing"
)

func TestRuntimeWireContract(t *testing.T) {
	value := harmonySnapshot{SampledAt: 123456, Status: &daemon.Status{UplinkTotal: 1234, DownlinkTotal: 5678, Memory: 1024, Goroutines: 12},
		Groups: &daemon.Groups{Group: []*daemon.Group{{Tag: "proxy", Selectable: true, Selected: "node", Items: []*daemon.GroupItem{{Tag: "node", Type: "vless", UrlTestDelay: 650}}}}}}
	encoded := encodeHarmonySnapshot(value)
	var wire map[string]interface{}
	if err := json.Unmarshal([]byte(encoded), &wire); err != nil {
		t.Fatal(err)
	}
	metrics := wire["status"].(map[string]interface{})
	if metrics["uplinkTotal"] != float64(1234) || metrics["downlinkTotal"] != float64(5678) || wire["sampledAt"] != float64(123456) {
		t.Fatal("traffic sample fields differ from ArkTS contract")
	}
	if !strings.Contains(encoded, `"urlTestDelay":650`) || strings.Contains(encoded, `url_test_delay`) {
		t.Fatal("node latency field differs from ArkTS contract")
	}
}

func TestLargeLogsPreserveTrafficAndNodeDelays(t *testing.T) {
	value := harmonySnapshot{SampledAt: 1, Status: &daemon.Status{UplinkTotal: 99},
		Groups: &daemon.Groups{Group: []*daemon.Group{{Tag: "proxy"}}}}
	for i := 0; i < 200; i++ {
		value.Logs = append(value.Logs, strings.Repeat("x", 2048))
	}
	encoded := encodeHarmonySnapshot(value)
	if len(encoded) > 200000 || !strings.Contains(encoded, `"uplinkTotal":99`) || !strings.Contains(encoded, `"tag":"proxy"`) {
		t.Fatal("oversized logs erased runtime telemetry")
	}
}

func TestConnectionWireContractAndBudget(t *testing.T) {
	value := harmonySnapshot{SampledAt: 2, Status: &daemon.Status{UplinkTotal: 33},
		Connections: []*daemon.Connection{{Id: "test-id", Network: "tcp", Destination: "example.com:443", UplinkTotal: 321, DownlinkTotal: 654}}}
	encoded := encodeHarmonySnapshot(value)
	if !strings.Contains(encoded, `"connections":[`) || !strings.Contains(encoded, `"uplinkTotal":321`) {
		t.Fatal("connection totals are not present in native wire format")
	}
	value.Connections[0].Rule = strings.Repeat("x", 210000)
	encoded = encodeHarmonySnapshot(value)
	if len(encoded) > 200000 || !strings.Contains(encoded, `"uplinkTotal":33`) {
		t.Fatal("oversized connection data erased runtime telemetry")
	}
}
