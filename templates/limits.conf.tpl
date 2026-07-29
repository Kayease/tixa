# Shared rate-limit state for every Tixa media service.
#
# limit_req_zone and limit_conn_zone are only valid in the http context, so they
# live here in conf.d rather than in the per-service server block. Installed by
# `tixa create` and refreshed by `tixa update`; safe to edit if a service needs
# a different ceiling, but `tixa update` will restore these defaults.

# Read/transform endpoints: bursty by nature (a gallery page fans out into many
# thumbnail requests), so the burst allowance is generous.
limit_req_zone $binary_remote_addr zone=tixa_process:10m rate=30r/s;

# Writes are rare and expensive.
limit_req_zone $binary_remote_addr zone=tixa_write:10m rate=2r/s;

limit_conn_zone $binary_remote_addr zone=tixa_conn:10m;

# 429 is the honest status for a throttled client; the nginx default is 503.
limit_req_status 429;
limit_conn_status 429;
