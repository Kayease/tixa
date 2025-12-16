server {
    server_name {{DOMAIN}};

    # Required for Certbot (ACME challenge)
    root /var/www/html;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Increase for large files
    client_max_body_size 500M;

    # Gzip compression
    gzip on;
    gzip_types image/svg+xml application/json text/css application/javascript application/json;

    # ---------------------------
    # Originals (static files)
    # ---------------------------
    location ^~ /originals/ {
        alias /var/www/images/{{PROJECT}}/originals/;
        expires 1y;
        add_header Cache-Control "public, immutable";
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

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

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

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # ---------------------------
    # All processing endpoints
    # ---------------------------
    location ^~ /process/ {

        location ^~ /process/pdf/ {
            proxy_pass http://127.0.0.1:{{PORT}};
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }

        location ^~ /process/video/ {
            proxy_pass http://127.0.0.1:{{PORT}};
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # ---------------------------
    # Thumbnails
    # ---------------------------
    location ^~ /thumbnail/ {
        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        expires 1y;
        add_header Cache-Control "public, immutable";
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

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
    }

    location ^~ /sections {
        if ($request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin "*";
            add_header Access-Control-Allow-Methods "GET, OPTIONS";
            add_header Access-Control-Allow-Headers "x-api-key, content-type";
            add_header Access-Control-Max-Age 86400;
            return 204;
        }

        proxy_pass http://127.0.0.1:{{PORT}};
        proxy_http_version 1.1;
    }

    # Block hidden files
    location ~ /\. {
        deny all;
        return 404;
    }
}
