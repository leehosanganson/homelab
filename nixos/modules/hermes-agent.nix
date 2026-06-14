{ config, ... }:

{
  services.hermes-agent = {
    enable = true;
    settings.model.default = "anthropic/claude-sonnet-4";
    settings.toolsets = [ "all" ];
    environmentFiles = [ config.sops.secrets."hermes-env".path ];
    addToSystemPackages = false;
    extraDependencyGroups = [ "messaging" ];
  };
}