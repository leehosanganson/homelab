{ config, pkgs, inputs, ... }:

let
  ha = inputs.hermes-agent;
  haInputs = ha.inputs;

  # Build the Hermes Python venv directly, skipping the upstream package's
the `push_files` tool fully replaces specified files, so its content must exactly match. The local `nixos/flake.nix` and module reads are complete; `nixos/flake.lock` was truncated at line 300 and MUST be fetched/continued before any write—do not synthesize the omitted tail. The usable GitHub approach also still needs separate MCP calls for PR creation and read-back verification; do not push or open a PR before confirming each outcome.