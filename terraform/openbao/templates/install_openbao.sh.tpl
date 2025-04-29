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

az keyvault secret download --file /tmp/openbao-tls.pem --id "${tls_keyvault_secret.id}"
openssl pkcs12 -export -in /tmp/openbao-tls.pem -out /tmp/openbao-tls.pfx -passout pass:
openssl pkcs12 -in /tmp/openbao-tls.pfx -nokeys -clcerts -passin pass: -out /opt/openbao/tls/cert.pem
openssl pkcs12 -in /tmp/openbao-tls.pfx -nodes -nocerts -passin pass: -passout pass: -out /opt/openbao/tls/key.pem
openssl pkcs12 -in /tmp/openbao-tls.pfx -nodes -nokeys -cacerts -passin pass: -out /opt/openbao/tls/ca.pem
chown openbao:openbao /opt/openbao/tls/*

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
    leader_ca_cert_file = "/opt/openbao/tls/ca.pem"
    leader_client_cert_file = "/opt/openbao/tls/cert.pem"
    leader_client_key_file = "/opt/openbao/tls/key.pem"
  }
}

cluster_addr = "https://$local_ipv4:8201"
api_addr = "https://$local_ipv4:8200"

listener "tcp" {
  address = "[::]:8200"
  cluster_address = "[::]:8201"
  tls_disable = false
  tls_cert_file = "/opt/openbao/tls/cert.pem"
  tls_key_file = "/opt/openbao/tls/key.pem"
  tls_client_ca_file = "/opt/openbao/tls/ca.pem"
}

seal "azurekeyvault" {
  tenant_id = "${tenant_id}"
  vault_name = "${keyvault.name}"
  key_name = "${keyvault_key.name}"
}

EOF

# openbao.hcl should be readable by the vault group only
chown root:root /etc/openbao
chown root:openbao /etc/openbao/openbao.hcl
chmod 640 /etc/openbao/openbao.hcl

systemctl enable openbao
systemctl start  openbao

echo "Setup OpenBAO profile"
cat <<EOF > /etc/profile.d/openbao.sh
export OPENBAO_ADDR="https://127.0.0.1:8200"
export OPENBAO_CACERT="/opt/openbao/tls/ca.pem"
EOF
