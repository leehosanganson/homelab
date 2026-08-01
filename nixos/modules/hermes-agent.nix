{ config, pkgs, ... }:

{
  services.hermes-agent = {
    enable = true;

    # Make the `hermes` CLI available on the system PATH and share HERMES_HOME
    # with the gateway service, so SSH logins can inspect the agent.
    addToSystemPackages = true;

    # Declarative base config (secret-free). Discord credentials and API keys
    # come from the sops-managed `hermes-env` secret.
    # Default model: cheapest reasonable option for experimenting with Hermes.
    # Switch anytime with `/model` in Discord/SSH or by changing this file.
    settings = {
      model.provider = "opencode-go";
      model.default = "deepseek-v4-flash";
      toolsets = [ "all" ];
    };

    environmentFiles = [ config.sops.secrets."hermes-env".path ];

    # Pull in the Discord/Telegram/Slack messaging dependencies.
    extraDependencyGroups = [ "messaging" ];

    # Common tools available to the agent's terminal backend.
    extraPackages = with pkgs; [ git jq ripgrep ffmpeg nodejs kubectl kubernetes-helm ];
  };
}
