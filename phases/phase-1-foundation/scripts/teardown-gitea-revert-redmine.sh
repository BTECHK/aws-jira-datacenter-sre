#!/usr/bin/env bash
# teardown-gitea-revert-redmine.sh
#
# WHERE TO RUN: on the REDMINE box (mds-tools-redmine, private IP 10.20.10.106) via SSM,
#               i.e. the box where Gitea got mistakenly colocated.
# HOW:          sudo bash teardown-gitea-revert-redmine.sh
#
# WHAT IT DOES (two things, on this one box):
#   1) Reverts Redmine to the guide's canonical systemd unit on port 3000
#      (undoes the 3001 / config/puma.rb workaround from the colocation).
#   2) Removes Gitea from this box (Gitea belongs on mds-tools-gitea).
#      It LEAVES the shared RDS `gitea` database intact, so the Ansible
#      clean-install on the gitea box reconnects to it (your mdsadmin user persists).
#
# After this, install Gitea on its own box with the companion play:
#   ansible-playbook -i inventory.aws_ec2.yml gitea.yml -e rds_host=$(terraform -chdir=../terraform output -raw rds_endpoint)

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root:  sudo bash $0"
  exit 1
fi

# --- safety guard -------------------------------------------------------------
# Only proceed on the COLOCATED redmine box, which is the only box that has BOTH
# Redmine and Gitea. This prevents the script from ever tearing down the real,
# correctly-installed Gitea box.
if [[ ! -d /opt/redmine-app || ! -f /etc/systemd/system/redmine.service ]]; then
  echo "ABORT: Redmine not found here. This script must run on the redmine box."
  echo "       (If you ran it on the gitea box by mistake — good instinct to stop.)"
  exit 1
fi
if [[ ! -f /etc/systemd/system/gitea.service && ! -x /usr/local/bin/gitea ]]; then
  echo "ABORT: no Gitea on this box — nothing to tear down. This box is already clean."
  exit 1
fi
echo "Confirmed: this box has BOTH Redmine and Gitea (the colocated redmine box). Proceeding."
echo

# --- 1) revert Redmine to the guide's canonical unit on :3000 -----------------
echo "[redmine] restoring canonical systemd unit on port 3000 ..."
cat > /etc/systemd/system/redmine.service <<'EOF'
[Unit]
Description=Redmine (Puma)
After=network.target
[Service]
Type=simple
User=redmine
WorkingDirectory=/opt/redmine-app
Environment=RAILS_ENV=production
ExecStart=/usr/local/bin/bundle exec rails server -b 0.0.0.0 -p 3000
LimitNOFILE=65535
Restart=always
[Install]
WantedBy=multi-user.target
EOF
chown root:root /etc/systemd/system/redmine.service
chmod 644 /etc/systemd/system/redmine.service
# the workaround added a puma config bound to 3001; `rails server -p 3000` doesn't need it
rm -f /opt/redmine-app/config/puma.rb
systemctl daemon-reload
systemctl restart redmine

# --- 2) remove Gitea from this box (RDS `gitea` DB is left intact) ------------
echo "[gitea] removing service, binary, data and user from this box ..."
systemctl disable --now gitea 2>/dev/null || true
rm -f /etc/systemd/system/gitea.service
systemctl daemon-reload
rm -f /usr/local/bin/gitea
rm -rf /var/lib/gitea /etc/gitea
userdel -r gitea 2>/dev/null || true   # -r also removes the /opt/gitea home

# --- verify (don't let a failing check abort the script) ----------------------
set +e
echo
echo "Done."
echo "  - Redmine: reverted to :3000 and restarted."
echo "  - Gitea:   removed from this box. RDS 'gitea' database left intact for the new box."
echo
sleep 5
echo "[verify] Redmine HTTP on :3000 (expect a 200/302 status line):"
curl -sI http://localhost:3000 | head -1
echo "[verify] who is listening on :3000 (expect ruby/redmine, NOT gitea):"
ss -tlnp | grep ':3000' || echo "  (nothing on :3000 yet — check: journalctl -u redmine -n 50)"
echo
echo "Next, from your laptop/WSL (in phases/phase-1-foundation/ansible/):"
echo "  ansible-playbook -i inventory.aws_ec2.yml gitea.yml -e rds_host=\$(terraform -chdir=../terraform output -raw rds_endpoint)"
