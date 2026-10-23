# `fleet-announce suspend|shutdown|resume`: tell the relay before going.
{ writeShellApplication, curl }:
{
  relay,
  relayAddress,
  port,
}:
writeShellApplication {
  name = "fleet-announce";
  runtimeInputs = [ curl ];
  text = ''
    case "''${1:-}" in
      suspend | shutdown | resume) ;;
      *) echo "usage: fleet-announce suspend|shutdown|resume" >&2; exit 64 ;;
    esac
    curl -sS -m 3 -o /dev/null -X POST --data "{\"state\":\"$1\"}" \
      "http://${relayAddress}:${toString port}/state" \
      || echo "fleet-announce: ${relay} didn't take '$1'" >&2
  '';
}
