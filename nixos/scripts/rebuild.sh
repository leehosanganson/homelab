#!/usr/bin/env bash

nixos-rebuild build-image --flake .#haproxy-1 --image-variant proxmox
