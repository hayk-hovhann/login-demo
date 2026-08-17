#!/usr/bin/env bash
# Open a local port onto the private RDS instance via SSM port-forwarding through
# the bastion — and mint short-lived IAM auth tokens so no password is handled.
#
# Why a script: the endpoint, the instance id, and the DbiResourceId are all
# regenerated every time `data` is restored from a snapshot, so anything written
# down goes stale within a session. These are resolved from stack exports at run
# time instead.
#
#   ./infra/db-tunnel.sh          # open the tunnel (blocks until Ctrl-C)
#   ./infra/db-tunnel.sh token    # print a fresh 15-minute auth token, exit
#   ./infra/db-tunnel.sh psql     # open a psql shell through an already-open tunnel
#
# LOCAL_PORT overrides the local end (default 5432). Stack names can be
# overridden by env var if you deploy under different names.
set -euo pipefail

DATA_STACK="${DATA_STACK:-login-demo-data}"
BASTION_STACK="${BASTION_STACK:-login-demo-bastion}"
LOCAL_PORT="${LOCAL_PORT:-5432}"
DB_USER="${DB_USER:-dbadmin_iam}"
REGION="${AWS_REGION:-us-east-1}"

die() { echo "error: $*" >&2; exit 1; }

# list-exports returns empty (not an error) for a missing name, so check each one.
export_value() {
  local name="$1" value
  value=$(aws cloudformation list-exports \
            --query "Exports[?Name=='${name}'].Value" --output text)
  [ -n "$value" ] && [ "$value" != "None" ] || die "export '${name}' not found — is ${DATA_STACK} deployed?"
  echo "$value"
}

stack_output() {
  local stack="$1" name="$2" value
  value=$(aws cloudformation describe-stacks --stack-name "$stack" \
            --query "Stacks[0].Outputs[?OutputKey=='${name}'].OutputValue" --output text 2>/dev/null || true)
  [ -n "$value" ] && [ "$value" != "None" ] || die "output '${name}' not found on ${stack} — is it deployed?"
  echo "$value"
}

# Signed over the RDS hostname, so it must be the real endpoint even though the
# client connects to localhost. Valid 15 minutes, and only for establishing a
# connection — sessions already open keep working after it expires.
mint_token() {
  aws rds generate-db-auth-token \
    --hostname "$DB_HOST" --port "$DB_PORT" \
    --region "$REGION" --username "$DB_USER"
}

DB_HOST=$(export_value "${DATA_STACK}-DbEndpoint")
DB_PORT=$(export_value "${DATA_STACK}-DbPort")
DB_NAME=$(export_value "${DATA_STACK}-DbName")

case "${1:-tunnel}" in
  token)
    mint_token
    exit 0
    ;;

  psql)
    # Requires the tunnel to already be open in another terminal. sslmode=require
    # encrypts without verifying: the cert names the RDS host, the client sees
    # localhost, so any verifying mode fails on the name mismatch.
    command -v docker >/dev/null || die "docker not found (used to supply psql)"
    PGPASSWORD=$(mint_token) \
    exec docker run --rm -it -e PGPASSWORD \
      postgres:16-alpine \
      psql "host=host.docker.internal port=${LOCAL_PORT} dbname=${DB_NAME} user=${DB_USER} sslmode=require"
    ;;

  tunnel) ;;
  *) die "unknown mode '${1}' — use: tunnel | token | psql" ;;
esac

BASTION_ID=$(stack_output "$BASTION_STACK" BastionInstanceId)

# A bastion whose SSM agent has not registered yet fails as an opaque
# TargetNotConnected; check first so the message says what is actually wrong.
PING=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=${BASTION_ID}" \
        --query 'InstanceInformationList[0].PingStatus' --output text)
[ "$PING" = "Online" ] || die "bastion ${BASTION_ID} is not Online in SSM (status: ${PING:-none}) — wait for the agent to register"

# "Connection refused" in the client is indistinguishable between "no tunnel" and
# "wrong port", so refuse to start on an occupied port rather than half-work.
if lsof -nP -iTCP:"${LOCAL_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  die "local port ${LOCAL_PORT} is already in use (compose postgres?) — stop it or set LOCAL_PORT=5433"
fi

cat <<EOF
bastion:  ${BASTION_ID}
db host:  ${DB_HOST}:${DB_PORT}
database: ${DB_NAME}
local:    localhost:${LOCAL_PORT}

connect as ${DB_USER} with a token as the password:
  ./infra/db-tunnel.sh token          # paste into a GUI client
  ./infra/db-tunnel.sh psql           # or get a shell (needs this tunnel open)

EOF

exec aws ssm start-session --target "$BASTION_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${DB_HOST}\"],\"portNumber\":[\"${DB_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
