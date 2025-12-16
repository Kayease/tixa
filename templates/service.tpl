[Unit]
Description={{PROJECT}} Media Processor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/{{PROJECT}}-processor
ExecStart=/opt/{{PROJECT}}-processor/venv/bin/uvicorn main:app --host 0.0.0.0 --port {{PORT}}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
