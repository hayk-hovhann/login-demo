#!/usr/bin/env bash
# FALLBACK ONLY. Mint a TLS certificate for the ALB's raw DNS name, signed by a
# local root CA, and import it into ACM.
#
#   ./infra/make-cert.sh            # mint + import, print the ARN and next command
#   ./infra/make-cert.sh delete     # delete the imported cert (TEARDOWN — do this)
#   ./infra/make-cert.sh show       # what is imported right now, and what uses it
#
# THE NORMAL PATH DOES NOT USE THIS SCRIPT
# HTTPS normally comes from the ACM-issued *.hayk-lab.dedyn.io certificate: a
# public CA signed it, so browsers trust it with no warning. It exists before the
# stack does, so pass its ARN as CertificateArn at CREATE, then point a CNAME for
# app.hayk-lab.dedyn.io at the ALB. One phase, no minting.
#
# Reach for this script only when that path is unavailable — the domain lapsed,
# deSEC is down, the cert expired or failed renewal. No public CA will sign the
# ALB's *.elb.amazonaws.com name (it is Amazon's, not yours), so the substitute is
# to be your own CA: a root that signs a leaf for that name. The chain is real and
# verifiable (`curl --cacert`); a browser warns for exactly one reason — it has
# never heard of this root.
#
# This path IS two-phase, because the leaf must name the ALB's DNS name, which
# does not exist until the stack does:
#   1. deploy login-demo-app with CertificateArn=''   (HTTP only)
#   2. ./infra/make-cert.sh
#   3. deploy again with the ARN it prints            (443 + 301 + secure cookies)
#
# SCOPE: every mode acts only on IMPORTED certificates. The ACM-issued domain cert
# carries the same Project tag, and a tag-only match would re-import over it or
# delete it at teardown.
#
# STACK overrides the app stack name; CERT_DIR the local key/cert location.
set -euo pipefail

STACK="${STACK:-login-demo-app}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${CERT_DIR:-${REPO_ROOT}/infra/certs}"

# Tag used to find the certificate again at teardown. An imported ACM cert costs
# nothing, which is precisely why it is easy to abandon. aws-sweep.sh lists ACM
# certs in every region, but only this script's `delete` removes one.
TAG_KEY='Project'
TAG_VALUE='login-demo'

die() { echo "error: $*" >&2; exit 1; }

stack_output() {
  local stack="$1" name="$2" value
  value=$(aws cloudformation describe-stacks --stack-name "$stack" \
            --query "Stacks[0].Outputs[?OutputKey=='${name}'].OutputValue" --output text 2>/dev/null || true)
  if [ -z "$value" ] || [ "$value" = "None" ]; then
    die "output '${name}' not found on ${stack} — is it deployed?"
  fi
  echo "$value"
}

# Tagged for this project AND of type IMPORTED. The tag alone is not enough: the
# ACM-issued *.hayk-lab.dedyn.io cert shares it, and must never be re-imported
# over or deleted. Type is what ACM itself reports, so no tagging slip defeats it.
# Prints zero or more ARNs, one per line.
find_certs() {
  local imported
  imported=$(aws acm list-certificates \
               --query "CertificateSummaryList[?Type=='IMPORTED'].CertificateArn" \
               --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d')
  [ -n "$imported" ] || return 0

  aws resourcegroupstaggingapi get-resources \
    --resource-type-filters acm:certificate \
    --tag-filters "Key=${TAG_KEY},Values=${TAG_VALUE}" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null \
    | tr '\t' '\n' | sed '/^$/d' \
    | grep -Fx -f <(printf '%s\n' "$imported") || true
}

case "${1:-mint}" in
  show)
    certs=$(find_certs)
    [ -n "$certs" ] || { echo "no ${TAG_VALUE} certificate imported in this region"; exit 0; }
    while read -r arn; do
      echo "$arn"
      # InUseBy lists the ALB listener ARNs referencing it — non-empty means
      # delete-certificate will refuse, and says which resource is holding it.
      aws acm describe-certificate --certificate-arn "$arn" \
        --query 'Certificate.{Domain:DomainName,NotAfter:NotAfter,InUseBy:InUseBy}' --output table
    done <<< "$certs"
    exit 0
    ;;

  delete)
    certs=$(find_certs)
    [ -n "$certs" ] || { echo "nothing to delete — no ${TAG_VALUE} certificate in this region"; exit 0; }
    while read -r arn; do
      in_use=$(aws acm describe-certificate --certificate-arn "$arn" \
                 --query 'length(Certificate.InUseBy)' --output text)
      if [ "$in_use" != "0" ]; then
        die "certificate is still attached to a listener: ${arn}
  detach it first — update the stack with CertificateArn='' (reverts to HTTP),
  or delete ${STACK} entirely. ACM refuses to delete an in-use certificate."
      fi
      aws acm delete-certificate --certificate-arn "$arn"
      echo "deleted ${arn}"
    done <<< "$certs"
    rm -rf "$CERT_DIR"
    echo "removed ${CERT_DIR}"
    exit 0
    ;;

  mint) ;;
  *) die "unknown mode '${1}' — use: mint | show | delete" ;;
esac

command -v openssl >/dev/null || die "openssl not found"

DNS_NAME=$(stack_output "$STACK" LoadBalancerDnsName)

mkdir -p "$CERT_DIR"
# Private keys land here. .gitignore covers infra/certs/, but keep the directory
# unreadable to anyone else on the machine regardless.
chmod u=rwx,go= "$CERT_DIR"

# --- root CA -----------------------------------------------------------------
# Reused across mints if it already exists, so a browser exception you granted
# once survives the next spin-up. Deleted only by `make-cert.sh delete`.
if [ ! -f "${CERT_DIR}/ca.pem" ]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "${CERT_DIR}/ca.key" -out "${CERT_DIR}/ca.pem" \
    -subj '/O=login-demo/CN=login-demo local root CA' 2>/dev/null
  echo "created local root CA: ${CERT_DIR}/ca.pem"
else
  echo "reusing existing local root CA: ${CERT_DIR}/ca.pem"
fi

# --- leaf certificate for this ALB -------------------------------------------
# ACM requires RSA-2048 (or a supported EC curve), PEM, and an UNENCRYPTED key —
# hence -nodes. The SAN is what browsers and curl actually match on; CN alone has
# been ignored for years, so a cert with only a CN fails verification.
openssl req -newkey rsa:2048 -nodes \
  -keyout "${CERT_DIR}/server.key" -out "${CERT_DIR}/server.csr" \
  -subj "/O=login-demo/CN=${DNS_NAME}" 2>/dev/null

cat > "${CERT_DIR}/leaf.ext" <<EOF
subjectAltName = DNS:${DNS_NAME}
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

# 397 days = the CA/Browser Forum maximum for public certs. Nothing enforces it
# on a private CA; matching it keeps the habit honest.
openssl x509 -req -in "${CERT_DIR}/server.csr" \
  -CA "${CERT_DIR}/ca.pem" -CAkey "${CERT_DIR}/ca.key" -CAcreateserial \
  -out "${CERT_DIR}/server.pem" -days 397 -sha256 \
  -extfile "${CERT_DIR}/leaf.ext" 2>/dev/null

chmod u=rw,go= "${CERT_DIR}"/*.key

# --- import into ACM ----------------------------------------------------------
# Re-import into an EXISTING ARN when one is already tagged for this project.
# That is the real certificate-rotation path: the listener keeps pointing at the
# same ARN and picks up the new material with no stack update — and it stops a
# fresh ARN accumulating on every spin-up.
EXISTING=$(find_certs | head -n1)

if [ -n "$EXISTING" ]; then
  CERT_ARN=$(aws acm import-certificate \
    --certificate-arn "$EXISTING" \
    --certificate "fileb://${CERT_DIR}/server.pem" \
    --private-key "fileb://${CERT_DIR}/server.key" \
    --certificate-chain "fileb://${CERT_DIR}/ca.pem" \
    --query CertificateArn --output text)
  echo "re-imported into the existing certificate (rotation, same ARN)"
else
  # Tags can only be set on the FIRST import — the re-import path above rejects
  # --tags, which is why this is not one shared command.
  CERT_ARN=$(aws acm import-certificate \
    --certificate "fileb://${CERT_DIR}/server.pem" \
    --private-key "fileb://${CERT_DIR}/server.key" \
    --certificate-chain "fileb://${CERT_DIR}/ca.pem" \
    --tags "Key=${TAG_KEY},Value=${TAG_VALUE}" "Key=Name,Value=${STACK}-alb" \
    --query CertificateArn --output text)
fi

cat <<EOF

certificate covers:  ${DNS_NAME}
arn:                 ${CERT_ARN}

attach it (the stack flips to 443 + a 301 from 80, and COOKIE_SECURE to true):

  aws cloudformation deploy --stack-name ${STACK} \\
    --template-file infra/app-ecs.yaml \\
    --capabilities CAPABILITY_IAM \\
    --parameter-overrides CertificateArn=${CERT_ARN}

\`deploy\`, not \`update-stack\`: it reuses the previous value of every parameter you
do not name, so this cannot silently reset NotificationEmail (deleting the SNS
subscription) or the image tags. update-stack reverts omissions to the TEMPLATE
DEFAULT and would need four explicit UsePreviousValue entries to be equivalent.

No --disable-rollback: this update replaces the backend task definition, and
CloudFormation refuses replacements on a stack with rollback disabled.

Image tags are worth a thought either way. Whatever this update reuses is what
the STACK recorded, which is not necessarily what is RUNNING — CD deploys by
mutating the ECS service behind CloudFormation's back. This update re-registers
the backend task definition (COOKIE_SECURE changes), so a stale recorded tag
rolls the service backwards. If CD has shipped since the stack was created, add
BackendImageTag=<sha> FrontendImageTag=<sha> to the overrides.

then verify the chain for real (no -k) — want 200:

  curl -sSI --cacert ${CERT_DIR}/ca.pem https://${DNS_NAME}/ | head -1

and that port 80 now redirects — want 301 and a Location on https:

  curl -sSI http://${DNS_NAME}/ | head -3

DO NOT FORGET AT TEARDOWN:  ./infra/make-cert.sh delete
EOF
