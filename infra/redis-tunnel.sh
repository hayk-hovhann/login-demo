#!/usr/bin/env bash
# Open a local port onto the private ElastiCache Redis node via SSM port-forwarding
# through the bastion, so a GUI client (Redis.redis-for-vscode) can inspect the
# live session store.
#
# Sibling of db-tunnel.sh and deliberately much shorter: Redis here has no
# password and no TLS, because in-VPC reachability IS the security boundary.
# There is no token to mint — being admitted to 6379 is the whole authorization
# story, which is exactly why the bastion needs the app's Redis client group:
# apply it with -var redis_client_security_group_id=... (see its variables.tf).
#
#   ./infra/redis-tunnel.sh          # open the tunnel (blocks until Ctrl-C)
#   ./infra/redis-tunnel.sh cli      # redis-cli through an already-open tunnel
#
# LOCAL_PORT overrides the local end (default 6379). The app's and the
# bastion's Terraform directories can be overridden by env var.
set -euo pipefail

APP_TF_DIR="${APP_TF_DIR:-$(dirname "$0")/terraform/app}"
BASTION_TF_DIR="${BASTION_TF_DIR:-$(dirname "$0")/terraform/bastion}"
LOCAL_PORT="${LOCAL_PORT:-6379}"

die() { echo "error: $*" >&2; exit 1; }

# A missing output is an error: terraform exits non-zero and prints its own
# message, so no empty-string check is needed.
tf_output() {
  local dir="$1" name="$2" value
  value=$(terraform -chdir="$dir" output -raw "$name") \
    || die "output '${name}' not found in ${dir} — has it been applied?"
  echo "$value"
}

# redis_endpoint is a single host:port output, unlike the DB's separate
# host and port parameters.
REDIS_ENDPOINT=$(tf_output "$APP_TF_DIR" redis_endpoint)
REDIS_HOST="${REDIS_ENDPOINT%:*}"
REDIS_PORT="${REDIS_ENDPOINT##*:}"
[ -n "$REDIS_HOST" ] && [ "$REDIS_HOST" != "$REDIS_ENDPOINT" ] \
  || die "could not split host:port out of redis_endpoint='${REDIS_ENDPOINT}'"

case "${1:-tunnel}" in
  cli)
    # Requires the tunnel to already be open in another terminal. Sessions are
    # stored by connect-redis under the "login-demo:sess:" prefix set in main.ts.
    command -v docker >/dev/null || die "docker not found (used to supply redis-cli)"
    exec docker run --rm -it redis:7-alpine \
      redis-cli -h host.docker.internal -p "${LOCAL_PORT}"
    ;;

  tunnel) ;;
  *) die "unknown mode '${1}' — use: tunnel | cli" ;;
esac

BASTION_ID=$(tf_output "$BASTION_TF_DIR" instance_id)

# A bastion whose SSM agent has not registered yet fails as an opaque
# TargetNotConnected; check first so the message says what is actually wrong.
PING=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=${BASTION_ID}" \
        --query 'InstanceInformationList[0].PingStatus' --output text)
[ "$PING" = "Online" ] || die "bastion ${BASTION_ID} is not Online in SSM (status: ${PING:-none}) — wait for the agent to register"

# "Connection refused" in the client is indistinguishable between "no tunnel" and
# "wrong port", so refuse to start on an occupied port rather than half-work.
if lsof -nP -iTCP:"${LOCAL_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  die "local port ${LOCAL_PORT} is already in use (compose redis?) — stop it or set LOCAL_PORT=6380"
fi

cat <<EOF
bastion:  ${BASTION_ID}
redis:    ${REDIS_HOST}:${REDIS_PORT}
local:    localhost:${LOCAL_PORT}

no password, no TLS — connect straight to localhost:${LOCAL_PORT}:
  Redis.redis-for-vscode  -> add connection, host localhost, port ${LOCAL_PORT}
  ./infra/redis-tunnel.sh cli   # or a shell (needs this tunnel open)

live sessions:  KEYS login-demo:sess:*
EOF

exec aws ssm start-session --target "$BASTION_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${REDIS_HOST}\"],\"portNumber\":[\"${REDIS_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
