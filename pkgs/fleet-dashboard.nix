# The fleet dashboard: one row per host, then the actions for the chosen one.
{
  lib,
  writeShellApplication,
  writeText,
  coreutils,
  curl,
  jq,
  openssh,
  wl-clipboard,
  libnotify,
  git,
}:
{
  hosts,
  self,
  port,
  flake,
  dmenu, # prompt -> command
  terminal,
  tailscale,
  nix,
}:
let
  hostList = lib.mapAttrsToList (name: h: {
    inherit name;
    inherit (h)
      address
      tailnetName
      ssh
      wake
      power
      ;
    isSelf = name == self;
    # Where the host announces suspend/shutdown; its status carries `peers.<name>`
    relayAddress = if h.relay == null then null else hosts.${h.relay}.address;
  }) hosts;
  hostsJson = writeText "fleet-hosts.json" (builtins.toJSON hostList);
in
writeShellApplication {
  name = "fleet-dashboard";
  runtimeInputs = [
    coreutils
    curl
    jq
    openssh
    wl-clipboard
    libnotify
    git
    tailscale
    nix
  ];
  text = ''
    hosts=${hostsJson}
    dir=$(mktemp -d)
    trap 'rm -rf "$dir"' EXIT
    notify() { notify-send -a Fleet -i network-server "$1" "$2"; }

    # The status of every host tailscale sees online, in parallel. Asleep or
    # absent ones would only hit the timeout, so they aren't asked (all are
    # when tailscale itself can't answer, as are hosts without a tailnet name).
    tailscale status --json > "$dir/tailscale.json" 2>/dev/null || echo '{}' > "$dir/tailscale.json"
    for address in $(jq -r --slurpfile ts "$dir/tailscale.json" '
      ($ts[0] | [(.Self // empty), ((.Peer // {}) | .[])] | map(select(.Online) | .HostName)) as $online
      | .[] | select(($online | length) == 0 or .tailnetName == null or (.tailnetName | IN($online[]))) | .address
    ' "$hosts"); do
      curl -sf -m 2 "http://$address:${toString port}/" > "$dir/$address.json" &
    done
    # And the power state of hosts switched through a plug: a powered-off
    # host still shows its plug, which is the moment that matters
    for name in $(jq -r '.[] | select(.power != null) | .name' "$hosts"); do
      eval "$(jq -r --arg n "$name" '.[] | select(.name == $n) | .power.status' "$hosts")" > "$dir/power-$name" 2>/dev/null &
    done
    wait

    ago() {
      local s=$(( $(date +%s) - $1 ))
      if [ "$s" -lt 3600 ]; then echo "$((s / 60))m"
      elif [ "$s" -lt 86400 ]; then echo "$((s / 3600))h"
      else echo "$((s / 86400))d"; fi
    }

    # One line per host. Live status when it answers; otherwise the plug
    # (no power is no power), then what the host told its relay before
    # going (asleep / shut down), then tailscale's view.
    line() {
      local name=$1 address=$2 tsname=$3 self=$4 hasPower=$5 relayAddress=$6 file="$dir/$2.json"
      local power="" plugOn="" watts="" word="" at=""
      if [ "$hasPower" = true ] && [ -s "$dir/power-$name" ]; then
        plugOn=$(sed -n 1p "$dir/power-$name")
        watts=$(sed -n 2p "$dir/power-$name")
        [ -n "$watts" ] && power="$watts W"
      fi
      if [ -n "$relayAddress" ] && [ -s "$dir/$relayAddress.json" ]; then
        read -r word at < <(jq -r --arg h "$name" '.peers[$h] // empty | "\(.state) \(.at)"' "$dir/$relayAddress.json")
      fi
      if [ -s "$file" ]; then
        jq -r --arg name "$name" --arg self "$self" --arg power "$power" '
          def ago: (now - .) as $s
            | if $s < 3600 then "\($s / 60 | floor)m"
              elif $s < 86400 then "\($s / 3600 | floor)h" else "\($s / 86400 | floor)d" end;
          def dur: if . < 3600 then "\(. / 60 | floor)m"
                   elif . < 86400 then "\(. / 3600 | floor)h" else "\(. / 86400 | floor)d" end;
          [ "● \($name)" + (if $self == "true" then " (this)" else "" end),
            (.battery | select(. != null) | "battery \(.capacity)%" + (if .state == "Charging" then "+" else "" end)),
            "disk \(.disk.usedPercent)%",
            "up \(.uptime | dur)",
            "rebuilt \(.rebuilt | ago) ago",
            (.backups | map(select(.at != null)) | max_by(.at) | select(. != null)
              | "backup \(.at | ago) ago" + (if .result != "success" then " (FAILED)" else "" end)),
            (select(.rebootPending) | "reboot pending"),
            ($power | select(. != "") | "power \(.)")
          ] | join(" · ")' "$file"
      elif [ "$plugOn" = off ]; then
        echo "⏻ $name · no power"
      elif [ "$word" = suspend ]; then
        echo "○ $name · asleep since $(ago "$at")''${power:+ · $power}"
      elif [ "$word" = shutdown ]; then
        echo "⏼ $name · shut down since $(ago "$at")''${power:+ · $power}"
      elif [ -z "$tsname" ]; then
        echo "○ $name · unreachable''${power:+ · $power}"
      else
        local state seen
        read -r state seen < <(jq -r --arg ts "$tsname" '
          ([(.Self // empty), ((.Peer // {}) | .[])] | map(select(.HostName == $ts)) | first)
          | if . == null then "absent -" elif .Online then "online -" else "offline \(.LastSeen)" end
        ' "$dir/tailscale.json")
        case "$state" in
          absent) echo "✗ $name · not on the tailnet''${power:+ · $power}" ;;
          online) echo "◐ $name · online, no status''${power:+ · $power}" ;;
          *)
            local s
            s=$(ago "$(date -d "$seen" +%s 2>/dev/null || date +%s)")
            if [ "$plugOn" = on ]; then
              # Powered and never said goodbye: crashed, or lost power while on
              echo "? $name · unreachable · seen $s ago · $power"
            else
              echo "○ $name · offline · seen $s ago"
            fi
            ;;
        esac
      fi
    }

    names=() ; labels=()
    while IFS=$'\t' read -r name address tsname self hasPower relayAddress; do
      names+=("$name")
      labels+=("$(line "$name" "$address" "$tsname" "$self" "$hasPower" "$relayAddress")")
    done < <(jq -r '.[] | [.name, .address, (.tailnetName // ""), (.isSelf | tostring), (.power != null | tostring), (.relayAddress // "")] | @tsv' "$hosts")

    choice=$(printf '%s\n' "''${labels[@]}" | ${dmenu "Fleet"}) || exit 0
    host=""
    for i in "''${!labels[@]}"; do
      if [ "''${labels[$i]}" = "$choice" ]; then host=''${names[$i]}; fi
    done
    [ -n "$host" ] || exit 0

    entry=$(jq -c --arg h "$host" '.[] | select(.name == $h)' "$hosts")
    address=$(jq -r .address <<<"$entry")
    hasPower=$(jq -r '.power != null' <<<"$entry")

    actions=()
    if [ "$(jq -r '.ssh != null' <<<"$entry")" = true ]; then actions+=("SSH"); fi
    if [ "$(jq -r '.wake != null' <<<"$entry")" = true ]; then actions+=("Wake"); fi
    if [ "$hasPower" = true ]; then actions+=("Power on" "Power off"); fi
    ${lib.optionalString (flake != null) ''
      if [ -d ${lib.escapeShellArg flake} ]; then actions+=("Check if a rebuild is needed"); fi
    ''}
    if [ -s "$dir/$address.json" ]; then actions+=("Details"); fi
    actions+=("Copy address")

    action=$(printf '%s\n' "''${actions[@]}" | ${dmenu "Action"}) || exit 0
    case "$action" in
      SSH)
        eval "exec ${terminal} $(jq -r .ssh.command <<<"$entry")"
        ;;
      Wake)
        if [ "$hasPower" = true ] && [ "$(sed -n 1p "$dir/power-$host" 2>/dev/null)" = off ]; then
          notify "$host has no power" "Its plug is off: use Power on"
          exit 0
        fi
        if eval "$(jq -r .wake <<<"$entry")"; then
          notify "Waking $host" "Magic packet sent"
        else
          notify "Could not wake $host" "The wake command failed"
        fi
        ;;
      "Power on")
        if eval "$(jq -r .power.on <<<"$entry")" > /dev/null; then
          notify "Powering on $host" "Wake it if the BIOS doesn't start it"
        else
          notify "Could not power on $host" "The plug didn't answer"
        fi
        ;;
      "Power off")
        if [ "$(jq -r .isSelf <<<"$entry")" = true ]; then
          notify "Refused" "That plug powers this host"
          exit 0
        fi
        [ "$(printf 'No\nYes\n' | ${dmenu "Cut the power?"})" = Yes ] || exit 0
        if eval "$(jq -r .power.off <<<"$entry")" > /dev/null; then
          notify "Powered off $host" "Its plug is off"
        else
          notify "Could not power off $host" "The plug didn't answer"
        fi
        ;;
      ${lib.optionalString (flake != null) ''
        "Check if a rebuild is needed")
          if [ ! -s "$dir/$address.json" ]; then
            notify "$host" "It isn't answering, so its running system is unknown"
            exit 0
          fi
          running=$(jq -r .system "$dir/$address.json")
          notify "Checking $host" "Evaluating ${flake} ($(git -C ${lib.escapeShellArg flake} rev-parse --short HEAD 2>/dev/null || echo "not a git checkout"))..."
          wanted=$(nix eval --raw ${lib.escapeShellArg flake}"#nixosConfigurations.$host.config.system.build.toplevel.outPath" 2>/dev/null) || {
            notify "$host" "Evaluating ${flake} failed"
            exit 0
          }
          if [ "$running" = "$wanted" ]; then
            notify "$host is up to date" "It runs what ${flake} builds"
          else
            notify "$host needs a rebuild" "It runs a different system than ${flake} builds"
          fi
          ;;
      ''}
      Details)
        relayAddress=$(jq -r '.relayAddress // empty' <<<"$entry")
        if [ -n "$relayAddress" ] && [ -s "$dir/$relayAddress.json" ]; then
          jq -r --arg h "$host" '.peers[$h] // empty | "last word: \(.state) \(.at | todate)"' "$dir/$relayAddress.json"
        fi > "$dir/lastword"
        { cat "$dir/lastword"; jq -r '
          [ "host: \(.host)", "system: \(.system)", "rebuilt: \(.rebuilt | todate)",
            "disk: \(.disk.usedPercent)% used, \(.disk.free / 1e9 | floor) GB free",
            (.battery | select(. != null) | "battery: \(.capacity)% \(.state)"),
            (.backups[] | "\(.unit): \(if .at then (.at | todate) else "never" end) \(.result)") ]
          | .[]' "$dir/$address.json"; } | ${dmenu "Details"} > /dev/null || true
        ;;
      "Copy address")
        printf '%s' "$address" | wl-copy
        notify "Copied" "$address"
        ;;
    esac
  '';
}
