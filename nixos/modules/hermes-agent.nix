{ config, pkgs, inputs, ... }:

let
  ha = inputs.hermes-agent;
  haInputs = ha.inputs;

  # Build the Hermes Python venv directly, skipping the upstream package's
  # TUI/Web npm builds (those currently fail because of a private/stale
  # @nous-research/ui dependency).
  hermesVenv = (pkgs.callPackage "${ha}/nix/python.nix" {
    inherit (haInputs) uv2nix pyproject-nix pyproject-build-systems;
    pythonSrc = ha;
    dependency-groups = [ "all" "messaging" ];
  }).venv;

  hermesAgent = pkgs.stdenv.mkDerivation {
    pname = "hermes-agent-minimal";
    version = "0.19.1";
    dontUnpack = true;
    dontBuild = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/share/hermes-agent
      ln -s ${ha}/skills $out/share/hermes-agent/skills
      ln -s ${ha}/optional-skills $out/share/hermes-agent/optional-skills
      ln -s ${ha}/plugins $out/share/hermes-agent/plugins
      ln -s ${ha}/locales $out/share/hermes-agent/locales
      ln -s ${ha}/optional-mcps $out/share/hermes-agent/optional-mcps
      mkdir -p $out/share/hermes-agent/web_dist $out/share/hermes-agent/ui-tui

      for bin in hermes hermes-agent hermes-acp; do
        makeWrapper ${hermesVenv}/bin/$bin $out/bin/$bin \
          --suffix PATH : "${pkgs.lib.makeBinPath [ pkgs.nodejs pkgs.ripgrep pkgs.git pkgs.openssh pkgs.ffmpeg pkgs.tirith ]}" \
          --set HERMES_BUNDLED_SKILLS $out/share/hermes-agent/skills \
          --set HERMES_OPTIONAL_SKILLS $out/share/hermes-agent/optional-skills \
          --set HERMES_BUNDLED_PLUGINS $out/share/hermes-agent/plugins \
          --set HERMES_BUNDLED_LOCALES $out/share/hermes-agent/locales \
          --set HERMES_OPTIONAL_MCPS $out/share/hermes-agent/optional-mcps \
          --set HERMES_WEB_DIST $out/share/hermes-agent/web_dist \
          --set HERMES_TUI_DIR $out/share/hermes-agent/ui-tui \
          --set HERMES_PYTHON ${hermesVenv}/bin/python3 \
          --set HERMES_NODE ${pkgs.lib.getExe pkgs.nodejs}
      done
      runHook postInstall
    '';
  };
in
{
  services.hermes-agent = {
    enable = true;
    package = hermesAgent;

    # Make the `hermes` CLI available on the system PATH and share HERMES_HOME
    # with the gateway service, so SSH logins can inspect the agent.
    addToSystemPackages = true;

    # Declarative base config (secret-free). Discord credentials and API keys
    # come from the sops-managed `hermes-env` secret.
    # Default model: unsloth/qwen-3.6 via LiteLLM for cost-effective experimentation.
    # Switch anytime with `/model` in Discord/SSH or by changing this file.
    settings = {
      model = {
        default = "unsloth/qwen-3.6";
        provider = "litellm";
      };
      toolsets = [ "all" ];
      providers = {
        litellm = {
          name = "litellm";
          api = "https://litellm.homelab.leehosanganson.dev/v1";
          key_env = "OPENAI_API_KEY";
          default_model = "unsloth/qwen-3.6";
        };
      };
      model_aliases = {
        qwen = {
          model = "unsloth/qwen-3.6";
          provider = "litellm";
        };
        kimi = {
          model = "kimi-k2.7-code";
          provider = "opencode-go";
        };
      };
    };

    environmentFiles = [ config.sops.secrets."hermes-env".path ];

    # GitHub MCP server — token is loaded from the sops-managed hermes-env.
    mcpServers = {
      github = {
        command = "npx";
        args = [ "-y" "@modelcontextprotocol/server-github" ];
        env = {
          GITHUB_PERSONAL_ACCESS_TOKEN = "\${GITHUB_PERSONAL_ACCESS_TOKEN}";
        };
      };
    };

    # Common tools available to the agent's terminal backend.
    extraPackages = with pkgs; [ git jq ripgrep ffmpeg nodejs kubectl kubernetes-helm ];
  };
}
