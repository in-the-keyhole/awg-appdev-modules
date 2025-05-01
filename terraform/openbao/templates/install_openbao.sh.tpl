#!/usr/bin/env bash

set -e -o pipefail

export instance_name="$(curl -sH Metadata:true --noproxy '*' 'http://169.254.169.254/metadata/instance/compute/name?api-version=2020-09-01&format=text')"
export local_ipv4="$(curl -sH Metadata:true --noproxy '*' 'http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2020-09-01&format=text')"

# install package
curl -Lso bao_2.2.1_linux_amd64.deb https://github.com/openbao/openbao/releases/download/v2.2.1/bao_2.2.1_linux_amd64.deb
dpkg -i bao_2.2.1_linux_amd64.deb
apt-get update
apt-get -f install -y

# install azure-cli
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# configuring Azure CLI for use with VM managed identity
az login --identity --client-id ${client_id} --allow-no-subscriptions

echo "Configuring system time"
timedatectl set-timezone UTC

cat << EOF > /etc/openbao/openbao.hcl
disable_performance_standby = true
ui = true

storage "raft" {
  path = "/opt/openbao/data"
  node_id = "$instance_name"
  retry_join {
    auto_join = "provider=azure subscription_id=${subscription_id} resource_group=${resource_group.name} vm_scale_set=${vm_scale_set_name}"
    auto_join_scheme = "https"
    leader_tls_servername = "${leader_tls_servername}"
    leader_client_cert_file = "/opt/openbao/tls/tls.crt"
    leader_client_key_file = "/opt/openbao/tls/tls.key"
    leader_ca_cert_file = "/etc/ssl/certs/awg.pem"
  }
}

api_addr = "https://$local_ipv4:8200"
cluster_addr = "https://$local_ipv4:8201"

listener "tcp" {
  address = "[::]:8200"
  cluster_address = "[::]:8201"
  tls_disable = false
  tls_cert_file = "/opt/openbao/tls/tls.crt"
  tls_key_file = "/opt/openbao/tls/tls.key"
  tls_client_ca_file = "/etc/ssl/certs/awg.pem"
}

seal "azurekeyvault" {
  tenant_id = "${tenant_id}"
  vault_name = "${keyvault.name}"
  key_name = "${keyvault_key.name}"
}

EOF

# openbao.hcl should be readable by the group only
chown root:root /etc/openbao
chown root:openbao /etc/openbao/openbao.hcl
chmod 640 /etc/openbao/openbao.hcl

systemctl enable openbao
systemctl start  openbao

echo "Setup OpenBAO profile"
cat <<EOF > /etc/profile.d/openbao.sh
export OPENBAO_ADDR="https://127.0.0.1:8200"
export OPENBAO_CACERT="/etc/ssl/certs/awg.pem"
EOF
