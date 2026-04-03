#!/bin/sh
# =============================================================================
# Hermes entrypoint — runs as root, fixes bind-mount ownership, drops to hermes
# =============================================================================
set -e

# Fix bind-mount ownership (host creates hermes/data/ as root, container uid 1001
# can't write to it without this). hermes.env is mounted separately at /hermes.env
# (read-only, outside the data dir) so it is not touched by this chown.
chown -R hermes:hermes /opt/hermes-data

# Copy runtime env into HERMES_HOME so hermes picks up GATEWAY_ALLOW_ALL_USERS etc.
# Hermes reads $HERMES_HOME/.env, not Docker env vars.
if [ -f /hermes.env ]; then
    cp /hermes.env /opt/hermes-data/.env
    chown hermes:hermes /opt/hermes-data/.env
fi

# Drop privileges and exec the actual command (hermes gateway run, or CLI args)
exec gosu hermes "$@"
