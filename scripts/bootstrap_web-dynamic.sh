#!/bin/bash
set -e

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting RHEL Web and DB initialization... (Trigger EC2 Recreation)"

# 1. Update OS and install Python and PostgreSQL client
dnf install -y postgresql python3 python3-pip

# 1.5 Setup Vault OS Users and SSH Password Authentication
useradd -m -s /bin/bash linuxadmin
echo '${linuxadmin_initial}' | passwd --stdin linuxadmin
usermod -aG wheel linuxadmin
echo "linuxadmin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/linuxadmin

useradd -m -s /bin/bash appuser
echo '${appuser_initial}' | passwd --stdin appuser

# Enable Password Authentication for SSH so Vault can connect
# We must insert our override as 00-force-password-auth.conf so it evaluates before AWS cloud-init
cat << 'EOF_SSH' > /etc/ssh/sshd_config.d/00-force-password-auth.conf
# Aggressively force Password and Keyboard-Interactive auth globally
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication yes
UsePAM yes
Match Address *
    PasswordAuthentication yes
EOF_SSH

# Also forcefully purge negations from existing files
sed -i 's/^[#]*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sed -i 's/^[#]*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config.d/*.conf || true

systemctl restart sshd

# 2. Install Flask and psycopg2 for the python web app
dnf install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
dnf install -y vault

pip3 install Flask psycopg2-binary pyOpenSSL cryptography

# 3. Wait for the database to be reachable & Seed the Database!
export PGPASSWORD='${db_password}'
echo "Seeding the remote AWS RDS Database..."

# Create a table and insert a row if it doesn't exist
psql -h ${db_host} -p ${db_port} -U ${db_user} -d ${db_name} -c "
CREATE TABLE IF NOT EXISTS demo_content (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255),
    message TEXT
);
INSERT INTO demo_content (title, message)
SELECT 'Vault Dynamic Secrets Demo', 'This information was successfully retrieved from an AWS RDS PostgreSQL Database!'
WHERE NOT EXISTS (SELECT 1 FROM demo_content);
"

# 4. Create the Web Application
mkdir -p /opt/app

# Configure Vault Agent for Continuous Internal Cert Auto-Rotation
mkdir -p /opt/vault

cat << 'EOF_VAULT' > /etc/vault.d/agent.hcl
pid_file = "/var/run/vault-agent.pid"

vault {
  address = "${vault_address}"
}

auto_auth {
  method "aws" {
    mount_path = "auth/${aws_auth_path}"
    namespace  = "${pki_namespace}"
    config = {
      type = "iam"
      role = "web-agent-role"
    }
  }
}

template {
  destination = "/opt/app/bundle.pem"
  contents = <<EOT
{{- with secret "pki-internal/issue/internal-web-role" (printf "common_name=web-dynamic.%s" "${private_zone}") "ttl=5m" -}}
{{ .Data.certificate }}

{{ .Data.issuing_ca }}

{{ .Data.private_key }}
{{- end -}}
EOT
  command = "systemctl restart demo-web"
}
EOF_VAULT

cat << 'EOF_VAULT_SVC' > /etc/systemd/system/vault-agent.service
[Unit]
Description=Vault Agent
Requires=network-online.target
After=network-online.target

[Service]
Restart=on-failure
ExecStart=/usr/bin/vault agent -config=/etc/vault.d/agent.hcl
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF_VAULT_SVC

cat << 'EOF' > /opt/app/app.py
from flask import Flask
import psycopg2
import os

app = Flask(__name__)

@app.route('/')
def index():
    try:
        # In a real Vault deployment, Vault agent would write these variables dynamically
        conn = psycopg2.connect(
            host='${db_host}',
            port='${db_port}',
            database='${db_name}',
            user='${db_user}',
            password='${db_password}'
        )
        cur = conn.cursor()
        cur.execute("SELECT title, message FROM demo_content LIMIT 1;")
        row = cur.fetchone()
        cur.close()
        conn.close()
        
        if row:
            title, message = row
            return f"<h1>{title}</h1><p><strong>Status:</strong> {message}</p>"
        else:
            return "<h1>Hello World!</h1><p>Database connected, but no content found.</p>"
            
    except Exception as e:
        return f"<h1>Database Error</h1><p>{str(e)}</p>"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=443, ssl_context=('/opt/app/bundle.pem', '/opt/app/bundle.pem'))
EOF

# 5. Run the web application using SystemD
cat << 'EOF' > /etc/systemd/system/demo-web.service
[Unit]
Description=Demo Flask Web App
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/app/app.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable demo-web
systemctl enable vault-agent

systemctl start vault-agent
# Give Vault Agent a moment to authenticate and fetch the initial certificate
sleep 3
# Start the web service; if Vault Agent already restarted it via the template command, this is a no-op harmless call
systemctl start demo-web || true

echo "Initialization Complete"
