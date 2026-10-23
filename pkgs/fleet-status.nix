# The status responder: one JSON document per connection, as a bare HTTP/1.0
# response; or a peer's announced power state, stored for the next document.
{
  lib,
  writeShellApplication,
  coreutils,
  jq,
  systemd,
}:
{
  hostName,
  peersByIp, # tailnet IP -> host name
  backupUnits,
}:
writeShellApplication {
  name = "fleet-status";
  runtimeInputs = [
    coreutils
    jq
    systemd
  ];
  text = ''
    reply() { printf 'HTTP/1.0 %s\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n' "$1"; }

    # Request line, then headers (only Content-Length matters). Reading the
    # whole request matters: closing the socket with unread input makes the
    # kernel send a reset, which discards the response before the client
    # has read it
    IFS=' ' read -r -t 2 method path _ || exit 0
    length=0
    while IFS= read -r -t 2 line && [ -n "''${line%$'\r'}" ]; do
      case "''${line,,}" in
        content-length:*) length=''${line#*: }; length=''${length%$'\r'} ;;
      esac
    done

    peers=$STATE_DIRECTORY/peers

    if [ "$method" = POST ] && [ "$path" = /state ]; then
      # A peer's last word before it suspends or shuts down. The sender is
      # whoever systemd says connected (REMOTE_ADDR), matched against the
      # fleet's tailnet IPs only, no self-declared names
      case "''${REMOTE_ADDR:-}" in
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (ip: name: "    ${ip}) peer=${lib.escapeShellArg name} ;;") peersByIp
    )}
        *) reply '403 Forbidden'; exit 0 ;;
      esac
      body=""
      [ "$length" -gt 0 ] && [ "$length" -le 1024 ] && IFS= read -r -N "$length" body
      state=$(jq -r '.state | select(. == "suspend" or . == "shutdown" or . == "resume")' <<<"$body" 2>/dev/null) || state=""
      if [ -z "$state" ]; then reply '400 Bad Request'; exit 0; fi
      mkdir -p "$peers"
      jq -cn --arg state "$state" --argjson at "$(date +%s)" '{ $state, $at }' > "$peers/$peer.json.tmp"
      mv "$peers/$peer.json.tmp" "$peers/$peer.json"
      reply '204 No Content'
      exit 0
    fi

    battery=null
    for b in /sys/class/power_supply/BAT*; do
      [ -r "$b/capacity" ] || continue
      battery=$(jq -n --argjson capacity "$(cat "$b/capacity")" --arg state "$(cat "$b/status")" \
        '{ $capacity, $state }')
      break
    done

    read -r used avail < <(df --output=pcent,avail -B1 / | tail -n 1 | tr -d '%')

    backups='[]'
    for unit in ${lib.escapeShellArgs backupUnits}; do
      at=$(systemctl show "$unit.service" --timestamp=unix -P ExecMainExitTimestamp)
      result=$(systemctl show "$unit.service" -P Result)
      backups=$(jq -c --arg unit "$unit" --arg at "''${at#@}" --arg result "$result" \
        '. + [{ $unit, at: ($at | tonumber? // null), $result }]' <<<"$backups")
    done

    # What peers last announced, by host
    peersJson='{}'
    for f in "$peers"/*.json; do
      [ -s "$f" ] || continue
      peersJson=$(jq -c --arg host "$(basename "$f" .json)" --slurpfile s "$f" '. + { ($host): $s[0] }' <<<"$peersJson")
    done

    reply '200 OK'
    jq -cn \
      --arg host ${lib.escapeShellArg hostName} \
      --argjson uptime "$(cut -d' ' -f1 /proc/uptime)" \
      --argjson battery "$battery" \
      --argjson diskUsed "$used" \
      --argjson diskFree "$avail" \
      --argjson backups "$backups" \
      --arg system "$(readlink /run/current-system)" \
      --arg booted "$(readlink /run/booted-system)" \
      --argjson rebuilt "$(stat -c %Y /nix/var/nix/profiles/system)" \
      --argjson peers "$peersJson" \
      '{ $host, $uptime, $battery, disk: { usedPercent: $diskUsed, free: $diskFree },
         $backups, $system, rebootPending: ($system != $booted), $rebuilt, $peers }'
  '';
}
