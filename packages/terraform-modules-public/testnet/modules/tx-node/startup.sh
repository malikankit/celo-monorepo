#!/bin/bash

# ---- Set Up Logging ----

curl -sSO https://dl.google.com/cloudagents/install-logging-agent.sh
bash install-logging-agent.sh

# ---- Install Docker ----

echo "Installing Docker..."
apt update && apt upgrade
apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg2
curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
apt update && apt upgrade
apt install -y docker-ce
systemctl start docker

echo "Configuring Docker..."
cat <<'EOF' > '/etc/docker/daemon.json'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3" 
  }
}
EOF
systemctl restart docker

# ---- Set Up and Run Geth ----

DATA_DIR=/root/.celo

GETH_NODE_DOCKER_IMAGE=${geth_node_docker_image_repository}:${geth_node_docker_image_tag}

echo "Address: ${txnode_account_address}"
echo "Private Key: ${txnode_private_key}"

echo "Bootnode enode address: ${bootnode_enode_address}"

BOOTNODE_ENODE=${bootnode_enode_address}@${bootnode_ip_address}:30301
echo "Bootnode enode: $BOOTNODE_ENODE"

echo "Pulling geth..."
docker pull $GETH_NODE_DOCKER_IMAGE

IN_MEMORY_DISCOVERY_TABLE_FLAG=""
[[ ${in_memory_discovery_table} == "true" ]] && IN_MEMORY_DISCOVERY_TABLE_FLAG="--use-in-memory-discovery-table"

mkdir -p $DATA_DIR/account
echo -n '${genesis_content_base64}' | base64 -d > $DATA_DIR/genesis.json
echo -n '${rid}' > $DATA_DIR/replica_id
echo -n '${ip_address}' > $DATA_DIR/ipAddress
echo -n '${txnode_private_key}' > $DATA_DIR/pkey
echo -n '${txnode_account_address}' > $DATA_DIR/address
echo -n '${bootnode_enode_address}' > $DATA_DIR/bootnodeEnodeAddress
echo -n '$BOOTNODE_ENODE' > $DATA_DIR/bootnodeEnode
echo -n '${txnode_geth_account_secret}' > $DATA_DIR/account/accountSecret


echo "Starting geth..."
# We need to override the entrypoint in the geth image (which is originally `geth`)
docker run \
  --rm \
  --net=host \
  -v $DATA_DIR:$DATA_DIR \
  --entrypoint /bin/sh \
  -i $GETH_NODE_DOCKER_IMAGE \
  -c "geth init $DATA_DIR/genesis.json && geth account import --password $DATA_DIR/account/accountSecret $DATA_DIR/pkey | true"

cat <<EOF >/etc/systemd/system/geth.service
[Unit]
Description=Docker Container %N
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/docker run \\
  --name geth \\
  --restart=always \\
  --net=host \\
  -v $DATA_DIR:$DATA_DIR \\
  --entrypoint /bin/sh \\
  $GETH_NODE_DOCKER_IMAGE -c "\\
    geth \\
      --bootnodes=enode://$BOOTNODE_ENODE \\
      --lightserv 90 \\
      --lightpeers 1000 \\
      --maxpeers 1100 \\
      --rpc \\
      --rpcaddr 0.0.0.0 \\
      --rpcapi=eth,net,web3,debug \\
      --rpccorsdomain='*' \\
      --rpcvhosts=* \\
      --ws \\
      --wsaddr 0.0.0.0 \\
      --wsorigins=* \\
      --wsapi=eth,net,web3,debug \\
      --nodekey=$DATA_DIR/pkey \\
      --etherbase=$ACCOUNT_ADDRESS \\
      --networkid=${network_id} \\
      --syncmode=full \\
      --consoleformat=json \\
      --consoleoutput=stdout \\
      --verbosity=${geth_verbosity} \\
      --ethstats=${tx_node_name}:$ETHSTATS_WEBSOCKETSECRET@${ethstats_host} \\
      --nat=extip:${ip_address} \\
      --metrics \\
      $IN_MEMORY_DISCOVERY_TABLE_FLAG \\
  "
ExecStop=/usr/bin/docker rm -f %N

[Install]
WantedBy=default.target
EOF

systemctl daemon-reload
systemctl enable geth.service
systemctl restart geth.service

# ---- Set Up and Run Geth Exporter ----

GETH_EXPORTER_DOCKER_IMAGE=${geth_exporter_docker_image_repository}:${geth_exporter_docker_image_tag}

echo "Pulling geth exporter..."
docker pull $GETH_EXPORTER_DOCKER_IMAGE

cat <<EOF >/etc/systemd/system/geth-exporter.service
[Unit]
Description=Docker Container %N
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/docker run \\
  --name geth-exporter \\
  --restart=always \\
  -v $DATA_DIR:$DATA_DIR \\
  --net=host \\
  $GETH_EXPORTER_DOCKER_IMAGE \\
  /usr/local/bin/geth_exporter \\
    -ipc $DATA_DIR/geth.ipc \\
    -filter "(.*overall|percentiles_95)"
ExecStop=/usr/bin/docker rm -f %N

[Install]
WantedBy=default.target
EOF

systemctl daemon-reload
systemctl enable geth-exporter.service
systemctl restart geth-exporter.service
