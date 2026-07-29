server {
    server_name {{DOMAIN}};

    # Required for Certbot (ACME challenge)
    root /var/www/html;

    # ^~ so the "block hidden files" regex below cannot shadow this.
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Increase for large files. Keep in step with MAX_UPLOAD_SIZE in main.py.
    client_max_body_size 500M;

    # Media processing can be slow; fail before a client waits forever.
    proxy_connect_timeout 5s;
    proxy_send_timeout 120s;
    proxy_read_timeout 120s;

    # Gzip compression
    gzip on;
    gzip_types image/svg+xml text/css application/javascript application/json;

    add_header X-Content-Type-Options "nosniff" always;

    # ---------------------------
    # Originals (static files)
    # ---------------------------
    location ^~ /originals/ {
        alias /var/www/images/{{PROJECT}}/originals/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options "nosniff" always;
        limit_conn tixa_conn 40;
        client_max_body_size 500M;
    }

    # ---------------------------
    # Health check
    # ---------------------------
    location /health {
        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # ---------------------------
    # File info endpoint
    # ---------------------------
    location ^~ /info/ {
        limit_req zone=tixa_process burst=60 nodelay;
        limit_conn tixa_conn 20;

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # ---------------------------
    # Upload endpoint
    # ---------------------------
    location ^~ /upload/ {
        if ($request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin "*";
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
            add_header Access-Control-Allow-Headers "x-api-key, content-type";
            add_header Access-Control-Max-Age 86400;
            return 204;
        }

        limit_req zone=tixa_write burst=10 nodelay;
        limit_conn tixa_conn 10;

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_request_buffering off;
        client_max_body_size 500M;
    }

    # ---------------------------
    # Delete endpoint
    # ---------------------------
    location ^~ /delete/ {
        if ($request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin "*";
            add_header Access-Control-Allow-Methods "DELETE, OPTIONS";
            add_header Access-Control-Allow-Headers "x-api-key, content-type";
            add_header Access-Control-Max-Age 86400;
            return 204;
        }

        limit_req zone=tixa_write burst=10 nodelay;
        limit_conn tixa_conn 10;

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # ---------------------------
    # All processing endpoints
    # (images, video thumbnails, PDF thumbnails/previews, audio waveforms
    #  and audio conversion all live under /process/)
    # ---------------------------
    location ^~ /process/ {
        limit_req zone=tixa_process burst=60 nodelay;
        limit_conn tixa_conn 20;

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options "nosniff" always;
    }

    # ---------------------------
    # Thumbnails
    # ---------------------------
    location ^~ /thumbnail/ {
        limit_req zone=tixa_process burst=60 nodelay;
        limit_conn tixa_conn 20;

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options "nosniff" always;
    }

    # ---------------------------
    # Audio streaming
    # ---------------------------
    location ^~ /stream/ {
        limit_conn tixa_conn 20;

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header Range $http_range;
        proxy_set_header If-Range $http_if_range;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
    }

    # ---------------------------
    # List endpoints
    # ---------------------------
    location ^~ /list/ {
        if ($request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin "*";
            add_header Access-Control-Allow-Methods "GET, OPTIONS";
            add_header Access-Control-Allow-Headers "x-api-key, content-type";
            add_header Access-Control-Max-Age 86400;
            return 204;
        }

        limit_req zone=tixa_process burst=30 nodelay;
        limit_conn tixa_conn 10;

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location ^~ /sections {
        if ($request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin "*";
            add_header Access-Control-Allow-Methods "GET, OPTIONS";
            add_header Access-Control-Allow-Headers "x-api-key, content-type";
            add_header Access-Control-Max-Age 86400;
            return 204;
        }

        limit_req zone=tixa_process burst=30 nodelay;
        limit_conn tixa_conn 10;

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Block hidden files
    location ~ /\. {
        deny all;
        return 404;
    }

    # ---------------------------
    # Everything else the application serves: /docs, /redoc, /openapi.json and
    # any route added by a future Tixa release. Without this, endpoints the
    # service implements return an Nginx 404.
    # ---------------------------
    location / {
        limit_req zone=tixa_process burst=30 nodelay;
        limit_conn tixa_conn 10;

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
