# ============================================================
#  VpnHood Server — Multi-stage Dockerfile
#  Target: net10.0 / Linux x64
#  Storage: /app/storage  (mount a volume here)
# ============================================================

# ── Stage 1: Build ───────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy only the project files first to maximise layer-cache hits
COPY Src/Apps/Server.Net/VpnHood.App.Server.Net.csproj                                          Src/Apps/Server.Net/
COPY Src/Core/VpnHood.Core.Common/VpnHood.Core.Common.csproj                                    Src/Core/VpnHood.Core.Common/
COPY Src/Core/VpnHood.Core.Toolkit/VpnHood.Core.Toolkit.csproj                                  Src/Core/VpnHood.Core.Toolkit/
COPY Src/Core/VpnHood.Core.Tunneling/VpnHood.Core.Tunneling.csproj                              Src/Core/VpnHood.Core.Tunneling/
COPY Src/Core/VpnHood.Core.Server/VpnHood.Core.Server.csproj                                    Src/Core/VpnHood.Core.Server/
COPY Src/Core/VpnHood.Core.Server.Access/VpnHood.Core.Server.Access.csproj                      Src/Core/VpnHood.Core.Server.Access/
COPY Src/Core/VpnHood.Core.Server.Access.FileAccessManager/VpnHood.Core.Server.Access.FileAccessManager.csproj \
                                                                                                  Src/Core/VpnHood.Core.Server.Access.FileAccessManager/
COPY Src/Core/VpnHood.Core.VpnAdapters.Abstractions/VpnHood.Core.VpnAdapters.Abstractions.csproj \
                                                                                                  Src/Core/VpnHood.Core.VpnAdapters.Abstractions/
COPY Src/Core/VpnHood.Core.VpnAdapters.LinuxTun/VpnHood.Core.VpnAdapters.LinuxTun.csproj       Src/Core/VpnHood.Core.VpnAdapters.LinuxTun/

# Restore (cached separately from the full source copy)
RUN dotnet restore Src/Apps/Server.Net/VpnHood.App.Server.Net.csproj

# Copy everything else and publish
COPY . .
RUN dotnet publish Src/Apps/Server.Net/VpnHood.App.Server.Net.csproj \
        --no-restore \
        -c Release \
        -r linux-x64 \
        --self-contained false \
        -o /app/publish

# ── Stage 2: Runtime ─────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/runtime:10.0 AS runtime

# iproute2  → ip / route manipulation required by the TUN adapter
# ca-certificates → needed for outbound TLS / token URL lookups
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        iproute2 \
        ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/publish .

# ── Persistent storage ────────────────────────────────────────
# The server looks for appsettings.json + access tokens here.
# Mount a host directory or named volume to /app/storage so that
# access tokens survive container restarts.
RUN mkdir -p /app/storage
VOLUME ["/app/storage"]

# ── Network ports ─────────────────────────────────────────────
# 443/tcp  — VPN tunnel (TLS)
# 443/udp  — UDP datagram channel  (same port, random if unset)
EXPOSE 443/tcp
EXPOSE 443/udp

# ── Environment variables (all optional) ──────────────────────
# Override any appsettings.json value without rebuilding the image.
# These are read by the entrypoint script and written to
# /app/storage/appsettings.json only when no file is present yet.
ENV VH_LOG_LEVEL="Information"
ENV VH_TCP_ENDPOINTS="0.0.0.0:443,[::]:443"
ENV VH_UDP_ENDPOINTS="0.0.0.0:0,[::]:0"
# Set to your server's public IP:port, e.g. "203.0.113.5:443"
ENV VH_PUBLIC_ENDPOINTS=""
# Set to your domain if you have a valid hostname
ENV VH_HOST_NAME=""
ENV VH_IS_VALID_HOSTNAME="false"
# Set to "true" to include the LAN in the VPN route
ENV VH_INCLUDE_LOCAL_NETWORK="false"
# Password for default.pfx (leave empty if none)
ENV VH_SSL_PASSWORD=""
# Network interface for auto-configuration ("*" = auto-detect)
ENV VH_ADD_LISTENER_IPS_TO_NETWORK="*"

# ── Entrypoint ────────────────────────────────────────────────
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["start"]
