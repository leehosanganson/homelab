let
  loadHost = path: (import path) {
    sops-secrets = throw "IP inventory does not evaluate sops-secrets";
  };
  hostDir = <inventory/hosts>;
  hostPaths = builtins.filter builtins.pathExists (
    map (name: hostDir + "/${name}/default.nix") (builtins.attrNames (builtins.readDir hostDir))
  );
  hostEntries = path:
    let
      networking = (loadHost path).networking or { };
      interfaces = networking.interfaces or { };
    in
    builtins.concatMap (interface:
      builtins.concatMap (family:
        map (entry: {
          inherit interface family;
          inherit (entry) address;
          hostname = networking.hostName;
          position = builtins.unsafeGetAttrPos "address" entry;
          file = toString path;
        }) (interfaces.${interface}.${family}.addresses or [ ])
      ) [ "ipv4" "ipv6" ]
    ) (builtins.attrNames interfaces);

  proxyPath = <inventory/modules/haproxy.nix>;
  proxy = (import proxyPath) {
    config.networking = (loadHost (hostDir + "/haproxy-1/default.nix")).networking;
  };
  projectOption = service: option:
    let settings = proxy.services.${service} or { }; in
    {
      text = settings.${option} or "";
      position = builtins.unsafeGetAttrPos option settings;
      file = toString proxyPath;
    };
in
{
  hosts = if hostPaths == [ ] then throw "no NixOS host files found" else builtins.concatMap hostEntries hostPaths;
  keepalived = projectOption "keepalived" "extraConfig";
  haproxy = projectOption "haproxy" "config";
}
