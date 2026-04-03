#!/bin/sh
# =============================================================================
# Hermes entrypoint — runs as root, fixes bind-mount ownership, drops to hermes
# =============================================================================
set -e

# Fix bind-mount ownership (host creates hermes/data/ as root, container uid 1001
# can't write to it without this).
chown -R hermes:hermes /opt/hermes-data

# Copy runtime env file into HERMES_HOME so hermes picks up GATEWAY_ALLOW_ALL_USERS
# and any other settings. Hermes reads $HERMES_HOME/.env, not Docker env vars.
if [ -f /opt/hermes-data/hermes.env ]; then
    cp /opt/hermes-data/hermes.env /opt/hermes-data/.env
fi

# Drop privileges and exec the actual command (hermes gateway run, or CLI args)
exec gosu hermes "$@"
