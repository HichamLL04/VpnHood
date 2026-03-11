# ============================================================
#  VpnHood Server — Multi-stage Dockerfile
#  Target: net10.0 / Linux (amd64 + arm64)
#  Storage: /app/storage  (mount a volume here)
# ============================================================

# ── Stage 1: Build ───────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

# TARGETARCH is injected by Buildx: "amd64" or "arm64"
ARG TARGETARCH
ARG BUILD_VERSION=0.0.0

WORKDIR /src

# Copy .csproj files first — this layer is cached until any
# .csproj changes, so NuGet restore is not re-run every build.
COPY Src/Apps/Server.Net/VpnHood.App.Server.Net.csproj \
     Src/Apps/Server.Net/
COPY Src/Core/VpnHood.Core.Common/VpnHood.Core.Common.csproj \
     Src/Core/VpnHood.Core.Common/
COPY Src/Core/VpnHood.Core.IpLocations/VpnHood.Core.IpLocations.csproj \
     Src/Core/VpnHood.Core.IpLocations/
COPY Src/Core/VpnHood.Core.PacketTransports/VpnHood.Core.PacketTransports.csproj \
     Src/Core/VpnHood.Core.PacketTransports/
COPY Src/Core/VpnHood.Core.Packets/VpnHood.Core.Packets.csproj \
     Src/Core/VpnHood.Core.Packets/
COPY Src/Core/VpnHood.Core.Server.Access.FileAccessManager/VpnHood.Core.Server.Access.FileAccessManager.csproj \
     Src/Core/VpnHood.Core.Server.Access.FileAccessManager/
COPY Src/Core/VpnHood.Core.Server.Access/VpnHood.Core.Server.Access.csproj \
     Src/Core/VpnHood.Core.Server.Access/
COPY Src/Core/VpnHood.Core.Server/VpnHood.Core.Server.csproj \
     Src/Core/VpnHood.Core.Server/
COPY Src/Core/VpnHood.Core.Toolkit/VpnHood.Core.Toolkit.csproj \
     Src/Core/VpnHood.Core.Toolkit/
COPY Src/Core/VpnHood.Core.Tunneling/VpnHood.Core.Tunneling.csproj \
     Src/Core/VpnHood.Core.Tunneling/
COPY Src/Core/VpnHood.Core.VpnAdapters.Abstractions/VpnHood.Core.VpnAdapters.Abstractions.csproj \
     Src/Core/VpnHood.Core.VpnAdapters.Abstractions/
COPY Src/Core/VpnHood.Core.VpnAdapters.LinuxTun/VpnHood.Core.VpnAdapters.LinuxTun.csproj \
     Src/Core/VpnHood.Core.VpnAdapters.LinuxTun/

# Restore — pass the correct RID so project.assets.json is valid
# for the subsequent publish step.
RUN DOTNET_RID=$([ "$TARGETARCH" = "arm64" ] && echo "linux-arm64" || echo "linux-x64") && \
    echo "Restoring for RID: $DOTNET_RID" && \
    dotnet restore Src/Apps/Server.Net/VpnHood.App.Server.Net.csproj \
        -r "$DOTNET_RID" \
        --verbosity minimal

# Copy full source (separate layer keeps restore cached on src changes)
COPY Src/ Src/

# Publish — SolutionDir is set explicitly to fix CS8101 (PathMap in csproj)
RUN DOTNET_RID=$([ "$TARGETARCH" = "arm64" ] && echo "linux-arm64" || echo "linux-x64") && \
    echo "Publishing for RID: $DOTNET_RID  version: $BUILD_VERSION" && \
    dotnet publish Src/Apps/Server.Net/VpnHood.App.Server.Net.csproj \
        --no-restore \
        -c Release \
        -r "$DOTNET_RID" \
        --self-contained false \
        -p:Version="$BUILD_VERSION" \
        -p:SolutionDir=/src/ \
        -o /app/publish

# ── Stage 2: Runtime ─────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/runtime:10.0 AS runtime

# Install runtime deps + clean cache in one layer
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        iproute2 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Create non-root user for running the server
RUN groupadd --gid 1001 vpnhood \
 && useradd --uid 1001 --gid vpnhood --no-create-home --shell /sbin/nologin vpnhood

WORKDIR /app
COPY --from=build /app/publish .
COPY docker-entrypoint.sh /docker-entrypoint.sh

# Set up storage directory with correct ownership and make entrypoint executable
RUN mkdir -p /app/storage \
 && chown -R vpnhood:vpnhood /app \
 && chmod +x /docker-entrypoint.sh

VOLUME ["/app/storage"]

# ── Ports ─────────────────────────────────────────────────────
EXPOSE 443/tcp
EXPOSE 443/udp

# ── Environment variables ─────────────────────────────────────
ENV VH_LOG_LEVEL="Information"
ENV VH_TCP_ENDPOINTS="0.0.0.0:443,[::]:443"
ENV VH_UDP_ENDPOINTS="0.0.0.0:0,[::]:0"
ENV VH_PUBLIC_ENDPOINTS=""
ENV VH_HOST_NAME=""
ENV VH_IS_VALID_HOSTNAME="false"
ENV VH_INCLUDE_LOCAL_NETWORK="false"
ENV VH_ADD_LISTENER_IPS_TO_NETWORK="*"

# Health check — server creates a lock file when running
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD test -f /app/storage/internal/server.lock || exit 1

USER vpnhood

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["start"]