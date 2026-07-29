[Unit]
Description={{PROJECT}} Media Processor
After=network.target

[Service]
Type=simple
User={{SERVICE_USER}}
Group={{SERVICE_USER}}

WorkingDirectory=/opt/{{PROJECT}}-processor
Environment=PATH=/opt/{{PROJECT}}-processor/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
# The application directory is read-only under ProtectSystem=strict, so do not
# let Python retry bytecode writes on every import.
Environment=PYTHONDONTWRITEBYTECODE=1
Environment=PYTHONUNBUFFERED=1
# ProtectHome makes the account's home unreachable, so point the libraries that
# insist on a cache directory somewhere this service is allowed to write.
# Without this, Matplotlib rebuilds its font cache on every start.
Environment=MPLCONFIGDIR=/var/www/images/{{PROJECT}}/.cache/matplotlib
Environment=XDG_CACHE_HOME=/var/www/images/{{PROJECT}}/.cache

# Bind to loopback only: every public request must pass through Nginx, which
# holds the TLS certificate, the body-size cap and the rate limits.
ExecStart=/opt/{{PROJECT}}-processor/venv/bin/uvicorn main:app --host 127.0.0.1 --port {{PORT}}

Restart=always
RestartSec=5

# ---------------------------------------------------------------
# Sandboxing. The service handles untrusted uploads, so it gets no
# more of the host than its own media directory.
# ---------------------------------------------------------------
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
ProtectProc=invisible
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictNamespaces=true
LockPersonality=true
# AF_NETLINK is included because glibc's resolver uses it to enumerate local
# interfaces; without it the listener can fail to start on some kernels.
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
SystemCallArchitectures=native
ReadWritePaths=/var/www/images/{{PROJECT}}

# ---------------------------------------------------------------
# Resource ceilings. Media transcoding is the expensive path; these
# stop one service from starving its neighbours on a shared VPS.
# ---------------------------------------------------------------
MemoryHigh=1G
MemoryMax=2G
CPUQuota=200%
TasksMax=256
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
