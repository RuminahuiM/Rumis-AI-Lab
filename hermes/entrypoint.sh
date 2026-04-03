#!/bin/sh
# =============================================================================
# Hermes entrypoint — runs as root, fixes bind-mount ownership, drops to hermes
# =============================================================================
set -e

# The bind mount (hermes/data/) is created by the host as root. Fix ownership
# so hermes (uid 1001) can write config, logs, memories, and sessions.
chown -R hermes:hermes /opt/hermes-data

# Drop privileges and exec the actual command (hermes gateway run, or CLI args)
exec gosu hermes "$@"
