package main

import (
	"encoding/json"
	"errors"
)

func validateNodeProbeConfig(text, tag string) error {
	var config map[string]json.RawMessage
	if len(text) > 65536 || tag != "node-test" {
		return errors.New("invalid probe request")
	}
	if err := json.Unmarshal([]byte(text), &config); err != nil {
		return err
	}
	for key := range config {
		if key != "log" && key != "dns" && key != "route" && key != "outbounds" {
			return errors.New("probe cannot create listeners, TUN or persistent services")
		}
	}
	var outbounds []struct {
		Type string `json:"type"`
		Tag  string `json:"tag"`
	}
	if err := json.Unmarshal(config["outbounds"], &outbounds); err != nil {
		return err
	}
	if len(outbounds) != 1 || outbounds[0].Tag != tag {
		return errors.New("probe requires one node")
	}
	switch outbounds[0].Type {
	case "selector", "urltest", "direct", "block", "dns", "":
		return errors.New("probe requires a proxy outbound")
	}
	var route map[string]json.RawMessage
	if err := json.Unmarshal(config["route"], &route); err != nil {
		return err
	}
	var auto bool
	if err := json.Unmarshal(route["auto_detect_interface"], &auto); err != nil || auto {
		return errors.New("probe requires explicit public socket binding, not interface auto-detection")
	}
	for key := range route {
		if key != "auto_detect_interface" && key != "default_domain_resolver" && key != "final" {
			return errors.New("probe cannot load routing rules or rule sets")
		}
	}
	return nil
}
