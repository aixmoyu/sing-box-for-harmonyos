package main

import (
	"context"
	"errors"
	"strings"
	"testing"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/daemon"
	"github.com/sagernet/sing-box/experimental/libbox"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	singJSON "github.com/sagernet/sing/common/json"
)

const dnsLifecycleConfigWithDirectDetour = `{
  "dns": {
    "servers": [
      {
        "type": "https",
        "tag": "bootstrap-dns",
        "server": "1.1.1.1",
        "server_port": 443,
        "path": "/dns-query",
        "detour": "direct"
      }
    ],
    "final": "bootstrap-dns"
  },
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}`

// This fixture mirrors the dependency graph produced for the first usable
// manual/global profile, but deliberately omits the TUN inbound so the host
// regression can exercise every pre-start dependency without requiring a
// privileged interface: bootstrap DNS dials directly, remote DNS detours
// through the proxy selector, and that selector resolves to one concrete node.
const manualGlobalLifecycleConfig = `{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "certificate": {
    "store": "mozilla"
  },
  "dns": {
    "servers": [
      {
        "type": "https",
        "tag": "bootstrap-dns",
        "server": "1.1.1.1",
        "server_port": 443,
        "path": "/dns-query",
        "tls": {
          "enabled": true,
          "server_name": "1.1.1.1"
        }
      },
      {
        "type": "https",
        "tag": "remote-dns",
        "server": "1.1.1.1",
        "server_port": 443,
        "path": "/dns-query",
        "tls": {
          "enabled": true,
          "server_name": "1.1.1.1"
        },
        "detour": "proxy",
        "domain_resolver": "bootstrap-dns"
      }
    ],
    "final": "remote-dns",
    "strategy": "ipv4_only"
  },
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "node-test",
      "server": "node.example.test",
      "server_port": 8388,
      "method": "aes-128-gcm",
      "password": "regression-only"
    },
    {
      "type": "shadowsocks",
      "tag": "node-test-two",
      "server": "node-two.example.test",
      "server_port": 8388,
      "method": "aes-128-gcm",
      "password": "regression-only"
    },
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": ["node-test", "node-test-two"],
      "default": "node-test",
      "interrupt_exist_connections": true
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {"action": "sniff"},
      {"protocol": "dns", "action": "hijack-dns"},
      {"ip_version": 6, "action": "reject"}
    ],
    "final": "proxy",
    "auto_detect_interface": false,
    "default_domain_resolver": "bootstrap-dns"
  }
}`

func newDNSLifecycleBox(t *testing.T, configJSON string) (*box.Box, context.CancelFunc) {
	t.Helper()
	ctx, cancel := context.WithCancel(include.Context(context.Background()))
	options, err := singJSON.UnmarshalExtendedContext[option.Options](ctx, []byte(configJSON))
	if err != nil {
		cancel()
		t.Fatalf("decode DNS lifecycle config: %v", err)
	}
	instance, err := box.New(box.Options{
		Context: ctx,
		Options: options,
	})
	if err != nil {
		cancel()
		t.Fatalf("construct DNS lifecycle box: %v", err)
	}
	return instance, cancel
}

func TestRuntimeStatusUsesSingBoxTrackerTotals(t *testing.T) {
	status, err := runtimeStatusFromDaemon(true, &daemon.Status{
		TrafficAvailable: true,
		UplinkTotal:      1234,
		DownlinkTotal:    5678,
		ConnectionsIn:    9,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !status.running || status.uploadBytes != 1234 || status.downloadBytes != 5678 || status.activeConnections != 9 {
		t.Fatalf("unexpected runtime status: %+v", status)
	}
}

func TestRuntimeStatusRejectsMissingTrackerWhileRunning(t *testing.T) {
	_, err := runtimeStatusFromDaemon(true, &daemon.Status{})
	if err == nil {
		t.Fatal("expected unavailable tracker error")
	}
}

func TestRuntimeStatusIsZeroWhenStopped(t *testing.T) {
	status, err := runtimeStatusFromDaemon(false, nil)
	if err != nil {
		t.Fatal(err)
	}
	if status.running || status.uploadBytes != 0 || status.downloadBytes != 0 || status.activeConnections != 0 {
		t.Fatalf("unexpected stopped status: %+v", status)
	}
}

func TestCleanupFailureRemainsLatchedAcrossIdempotentStop(t *testing.T) {
	coreMu.Lock()
	previousServer := coreServer
	previousRunning := coreRunning
	previousCleanupErr := coreCleanupErr
	previousLastErr := coreLastErr
	coreServer = nil
	coreRunning = false
	coreCleanupErr = errors.New("simulated close failure")
	coreLastErr = ""
	coreMu.Unlock()

	result := int32(HnaCoreStop())

	coreMu.Lock()
	latchedErr := coreCleanupErr
	lastErr := coreLastErr
	coreServer = previousServer
	coreRunning = previousRunning
	coreCleanupErr = previousCleanupErr
	coreLastErr = previousLastErr
	coreMu.Unlock()

	if result != coreInternalError {
		t.Fatalf("cleanup failure was downgraded to idempotent stop: %d", result)
	}
	if latchedErr == nil || !strings.Contains(lastErr, "cleanup remains unconfirmed") {
		t.Fatalf("cleanup failure latch was lost: latch=%v lastError=%q", latchedErr, lastErr)
	}
}

func TestDNSDirectDetourFailsOnlyWhenTransportsPreStart(t *testing.T) {
	// No inbound is present in either fixture, so PreStart exercises outbound
	// and DNS lifecycle initialization without opening a TUN interface.
	broken, cancelBroken := newDNSLifecycleBox(t, dnsLifecycleConfigWithDirectDetour)
	brokenErr := broken.PreStart()
	cancelBroken()
	if brokenErr == nil {
		_ = broken.Close()
		t.Fatal("expected explicit DNS detour to an empty direct outbound to fail")
	}
	if !strings.Contains(brokenErr.Error(), "detour to an empty direct outbound makes no sense") {
		t.Fatalf("unexpected DNS pre-start error: %v", brokenErr)
	}

	fixedConfig := strings.Replace(dnsLifecycleConfigWithDirectDetour, `,
        "detour": "direct"`, "", 1)
	fixed, cancelFixed := newDNSLifecycleBox(t, fixedConfig)
	fixedErr := fixed.PreStart()
	if fixedErr != nil {
		cancelFixed()
		t.Fatalf("DNS pre-start without a direct detour failed: %v", fixedErr)
	}
	if err := fixed.Close(); err != nil {
		cancelFixed()
		t.Fatalf("close pre-started DNS lifecycle box: %v", err)
	}
	cancelFixed()
}

func TestManualGlobalSelectorAndDNSDependencyGraphPreStarts(t *testing.T) {
	instance, cancel := newDNSLifecycleBox(t, manualGlobalLifecycleConfig)
	defer cancel()
	if err := instance.PreStart(); err != nil {
		t.Fatalf("manual/global DNS and selector graph failed pre-start: %v", err)
	}
	if err := instance.Close(); err != nil {
		t.Fatalf("close pre-started manual/global lifecycle box: %v", err)
	}
}

func TestLibboxManualGlobalLifecycleStartsWithEmbeddedTracker(t *testing.T) {
	workingDirectory := t.TempDir()
	if err := libbox.Setup(&libbox.SetupOptions{
		BasePath:    workingDirectory,
		WorkingPath: workingDirectory,
		TempPath:    workingDirectory,
		LogMaxLines: 200,
	}); err != nil {
		t.Fatalf("setup libbox lifecycle regression: %v", err)
	}
	server, err := libbox.NewCommandServer(&harmonyHandler{}, &harmonyPlatform{})
	if err != nil {
		t.Fatalf("create command server: %v", err)
	}
	defer server.Close()
	if err = server.StartOrReloadService(manualGlobalLifecycleConfig, &libbox.OverrideOptions{}); err != nil {
		if strings.Contains(err.Error(), "clash api is not included in this build") {
			t.Skip("embedded tracker regression requires the production with_clash_api build tag")
		}
		t.Fatalf("start libbox manual/global lifecycle without TUN: %v", err)
	}
	status := server.StatusSnapshot()
	if status == nil || !status.TrafficAvailable {
		t.Fatalf("embedded traffic tracker did not enter an available state: %+v", status)
	}
	instance := server.Instance()
	if instance == nil || adapter.RootPoolFromContext(instance.Context()) == nil {
		t.Fatal("running instance context does not expose its configured certificate store")
	}
	if err = server.CloseService(); err != nil {
		t.Fatalf("close libbox manual/global lifecycle: %v", err)
	}
}

func TestRunningProxySelectorSwitchesWithoutReloadingService(t *testing.T) {
	workingDirectory := t.TempDir()
	if err := libbox.Setup(&libbox.SetupOptions{
		BasePath:    workingDirectory,
		WorkingPath: workingDirectory,
		TempPath:    workingDirectory,
		LogMaxLines: 200,
	}); err != nil {
		t.Fatalf("setup selector switch regression: %v", err)
	}
	server, err := libbox.NewCommandServer(&harmonyHandler{}, &harmonyPlatform{})
	if err != nil {
		t.Fatalf("create command server: %v", err)
	}
	defer server.Close()
	if err = server.StartOrReloadService(manualGlobalLifecycleConfig, &libbox.OverrideOptions{}); err != nil {
		if strings.Contains(err.Error(), "clash api is not included in this build") {
			t.Skip("selector switch regression requires the production with_clash_api build tag")
		}
		t.Fatalf("start selector switch service: %v", err)
	}

	coreMu.Lock()
	previousServer, previousRunning := coreServer, coreRunning
	coreServer, coreRunning = server, true
	instanceBefore := server.Instance()
	err = selectProxyOutboundLocked("node-test-two")
	instanceAfter := server.Instance()
	coreServer, coreRunning = previousServer, previousRunning
	coreMu.Unlock()
	if err != nil {
		t.Fatalf("select running outbound: %v", err)
	}
	if instanceBefore == nil || instanceAfter != instanceBefore {
		t.Fatal("selector switch replaced the running service instance")
	}
	proxyOutbound, loaded := instanceAfter.Box().Outbound().Outbound("proxy")
	if !loaded {
		t.Fatal("proxy selector disappeared after switch")
	}
	if selected := proxyOutbound.(adapter.OutboundGroup).Selected("tcp").Tag(); selected != "node-test-two" {
		t.Fatalf("unexpected selected outbound: %q", selected)
	}

	coreMu.Lock()
	coreServer, coreRunning = server, true
	err = selectProxyOutboundLocked("not-a-member")
	coreServer, coreRunning = previousServer, previousRunning
	coreMu.Unlock()
	if err == nil || !strings.Contains(err.Error(), "not a member") {
		t.Fatalf("expected selector membership rejection, got %v", err)
	}
	if selected := proxyOutbound.(adapter.OutboundGroup).Selected("tcp").Tag(); selected != "node-test-two" {
		t.Fatalf("failed switch changed selected outbound to %q", selected)
	}

	if err = server.CloseService(); err != nil {
		t.Fatalf("close selector switch service: %v", err)
	}

	// The live switch above is persisted by sing-box's cache. A subsequent
	// profile launch still has to honor the explicit default generated from the
	// app's saved node selection instead of resurrecting the previous session.
	if err = server.StartOrReloadService(manualGlobalLifecycleConfig, &libbox.OverrideOptions{}); err != nil {
		t.Fatalf("restart selector service: %v", err)
	}
	restarted := server.Instance()
	if restarted == nil {
		t.Fatal("selector service did not restart")
	}
	restartedProxy, loaded := restarted.Box().Outbound().Outbound("proxy")
	if !loaded {
		t.Fatal("proxy selector missing after restart")
	}
	if selected := restartedProxy.(adapter.OutboundGroup).Selected("tcp").Tag(); selected != "node-test" {
		t.Fatalf("explicit selector default lost to stale cache: %q", selected)
	}
	if err = server.CloseService(); err != nil {
		t.Fatalf("close restarted selector service: %v", err)
	}
}
