# Values for this config's variables. Terraform reads this file on every plan
# and apply, so no run can forget one; -var on the command line still overrides
# it. No secrets here: the file is committed.

# The *.hayk-lab.dedyn.io wildcard from ACM. Permanent: issued once, renewed by
# ACM, untouched by teardown. Set means TLS: everything keyed on
# var.certificate_arn switches on. Browsers reach it through the per-session
# app.hayk-lab.dedyn.io CNAME; the ALB's own DNS name won't match the cert.
certificate_arn = "arn:aws:acm:us-east-1:583534901308:certificate/74989f63-3d75-49f6-ae34-9f88617f30ac"

# Where the alarm topic sends its email. An address, not a secret.
notification_email = "hayk.hovhannisyan27.88@gmail.com"
