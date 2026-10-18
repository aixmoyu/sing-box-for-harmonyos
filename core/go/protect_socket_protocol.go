package main

import (
	"errors"
	"fmt"
)

var errNoEligibleUnderlay = errors.New(
	"no validated Wi-Fi or cellular underlay with INTERNET and NOT_VPN capabilities is available",
)

type underlayCandidate struct {
	netID int32

	hasInternet  bool
	hasNotVPN    bool
	hasValidated bool

	hasWiFi     bool
	hasCellular bool
	hasVPN      bool
}

type underlaySnapshotFunc func() ([]underlayCandidate, error)
type underlayBindFunc func(fd int32, netID int32) error

func validateProtectSocketFD(fd int32) error {
	if fd < 0 {
		return errors.New("cannot protect an invalid socket descriptor")
	}
	return nil
}

func isEligibleUnderlay(candidate underlayCandidate) bool {
	return candidate.netID > 0 &&
		candidate.hasInternet &&
		candidate.hasNotVPN &&
		candidate.hasValidated &&
		(candidate.hasWiFi || candidate.hasCellular) &&
		!candidate.hasVPN
}

// selectUnderlayNetwork is deliberately deterministic because GetAllNets does
// not document an ordering contract. Prefer validated Wi-Fi over cellular and
// use the lowest network ID only as a stable tie-breaker. Ethernet, Bluetooth,
// VPN and capability-incomplete networks are fail-closed.
func selectUnderlayNetwork(candidates []underlayCandidate) (int32, error) {
	var selectedID int32
	selectedScore := 0
	for _, candidate := range candidates {
		if !isEligibleUnderlay(candidate) {
			continue
		}
		score := 1
		if candidate.hasWiFi {
			score = 2
		}
		if selectedScore == 0 || score > selectedScore ||
			(score == selectedScore && candidate.netID < selectedID) {
			selectedID = candidate.netID
			selectedScore = score
		}
	}
	if selectedScore == 0 {
		return 0, errNoEligibleUnderlay
	}
	return selectedID, nil
}

// bindSocketWithFreshUnderlay performs a new network snapshot for every file
// descriptor. It intentionally holds no shared network handle: concurrent
// dials are independent, and a network-switch race fails the affected bind so
// the next descriptor re-enumerates current networks instead of reusing stale
// state.
func bindSocketWithFreshUnderlay(
	fd int32,
	snapshot underlaySnapshotFunc,
	bind underlayBindFunc,
) error {
	if err := validateProtectSocketFD(fd); err != nil {
		return err
	}
	if snapshot == nil || bind == nil {
		return errors.New("VPN socket protection has no public NetConn adapter")
	}
	candidates, err := snapshot()
	if err != nil {
		return fmt.Errorf("VPN socket protection could not enumerate underlay networks: %w", err)
	}
	netID, err := selectUnderlayNetwork(candidates)
	if err != nil {
		return fmt.Errorf("VPN socket protection refused an unsafe underlay: %w", err)
	}
	if err = bind(fd, netID); err != nil {
		return fmt.Errorf("VPN socket protection could not bind fd %d to underlay netId %d: %w", fd, netID, err)
	}
	return nil
}
