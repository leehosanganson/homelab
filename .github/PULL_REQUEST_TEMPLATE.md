## What

Comprehensive documentation overhaul for the homelab repository. This PR includes:

- **README updates**: Rewritten and reformatted with updated Services section covering all cluster services, added server rack photo, and improved overall structure.
- **Architecture diagrams**: Introduced a Graphviz-based `.dot` source file (`docs/homelab-architecture/homelab-diagram.dot`) that renders to an SVG architecture diagram. The previous Mermaid and hand-crafted SVG diagrams have been consolidated into this single authoritative source.
- **Docs directory restructuring**: Moved architecture diagrams from `docs/` root into `docs/homelab-architecture/` for better organization. Renamed `iac-nixos-installation.md` to `iac-nixos-configurations.md`. Reorganized runbooks structure.
- **Diagram-as-code workflow**: Added a pre-commit hook that renders `.dot` files to SVG automatically, ensuring diagrams stay in sync with their source. Integrated Graphviz CLI into the flake.nix devShell.
- **AGENTS.md & docs/README.md**: Updated links and references throughout to reflect the new directory structure.

## How to Test

1. Verify `docs/homelab-architecture/homelab-diagram.dot` renders correctly: run `dot -Tsvg docs/homelab-architecture/homelab-diagram.dot -o /tmp/test.svg` and open the output.
2. Check that `README.md` displays all cluster services accurately — cross-reference against the Services section.
3. Confirm all links in `README.md` and `docs/README.md` resolve correctly (no broken internal links).
4. Ensure the pre-commit hook triggers `.dot` → SVG rendering when committing changes to architecture files.
5. Verify runbook paths in `AGENTS.md` still point to valid files after the restructuring.

## Impact

- **Risk**: Large number of file renames/moves could affect external links or linters. Verify that no CI jobs depend on old paths (`docs/network-diagram.*`, `docs/app-diagram.*` removed).
- **Trade-off**: Switched from Mermaid diagrams to Graphviz (.dot) for architecture diagrams — requires Graphviz CLI in the dev environment, but provides more flexibility and cleaner output.
- **New files**: Large binary file added (`docs/homelab-architecture/server-rack.jpg`, ~3 MB). Consider whether this should be gitignored or stored externally if repo size is a concern.
