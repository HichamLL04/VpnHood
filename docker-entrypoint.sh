#!/bin/sh
# =============================================================
#  VpnHood Server — Docker Entrypoint
#  Generates /app/storage/appsettings.json from environment
#  variables the first time the container runs (i.e. when the
#  storage volume is empty).  If the file already exists it is
#  left untouched so you can manage it manually.
# =============================================================
set -e

STORAGE_DIR="/app/storage"
SETTINGS_FILE="$STORAGE_DIR/appsettings.json"

mkdir -p "$STORAGE_DIR"

# ── Generate appsettings.json only when missing ───────────────
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "[entrypoint] No appsettings.json found — generating from environment variables..."

  # Build PublicEndPoints JSON array (comma-separated input)
  if [ -n "$VH_PUBLIC_ENDPOINTS" ]; then
    PUBLIC_EPS=$(echo "$VH_PUBLIC_ENDPOINTS" | \
      awk -F',' '{ for(i=1;i<=NF;i++) printf "    \"%s\"%s\n", $i, (i<NF)?",":"" }')
    PUBLIC_EPS_JSON="[\n$PUBLIC_EPS\n  ]"
  else
    PUBLIC_EPS_JSON="null"
  fi

  # Build TcpEndPoints JSON array
  TCP_EPS=$(echo "$VH_TCP_ENDPOINTS" | \
    awk -F',' '{ for(i=1;i<=NF;i++) printf "    \"%s\"%s\n", $i, (i<NF)?",":"" }')

  # Build UdpEndPoints JSON array
  UDP_EPS=$(echo "$VH_UDP_ENDPOINTS" | \
    awk -F',' '{ for(i=1;i<=NF;i++) printf "    \"%s\"%s\n", $i, (i<NF)?",":"" }')

  # HostName block (only relevant when IS_VALID_HOSTNAME=true)
  if [ -n "$VH_HOST_NAME" ]; then
    HOST_NAME_LINE="\"HostName\": \"$VH_HOST_NAME\","
  else
    HOST_NAME_LINE=""
  fi

  # SSL password (null when empty)
  if [ -n "$VH_SSL_PASSWORD" ]; then
    SSL_PASS="\"$VH_SSL_PASSWORD\""
  else
    SSL_PASS="null"
  fi

  cat > "$SETTINGS_FILE" <<EOF
{
  "LogLevel": "$VH_LOG_LEVEL",
  "HttpAccessManager": null,
  "FileAccessManager": {
    $HOST_NAME_LINE
    "IsValidHostName": $VH_IS_VALID_HOSTNAME,
    "PublicEndPoints": $PUBLIC_EPS_JSON,
    "TcpEndPoints": [
$TCP_EPS
    ],
    "UdpEndPoints": [
$UDP_EPS
    ],
    "AddListenerIpsToNetwork": "$VH_ADD_LISTENER_IPS_TO_NETWORK",
    "SslCertificatesPassword": $SSL_PASS,
    "ReplyAccessKey": true,
    "LogAnonymizer": true,
    "NetFilter": {
      "IncludeLocalNetwork": $VH_INCLUDE_LOCAL_NETWORK
    }
  }
}
EOF

  echo "[entrypoint] appsettings.json written to $SETTINGS_FILE"
else
  echo "[entrypoint] appsettings.json already exists — using existing file."
fi

# ── Hand off to VpnHoodServer ─────────────────────────────────
# Change into storage so the server finds its files correctly.
cd "$STORAGE_DIR"
exec dotnet /app/VpnHoodServer.dll "$@"
