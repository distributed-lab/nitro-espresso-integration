#!/bin/sh
dnf install aws-nitro-enclaves-cli -y
dnf install aws-nitro-enclaves-cli-devel -y
usermod -aG ne $USER
usermod -aG docker $USER

# Configure allocator
readonly NE_ALLOCATOR_SPEC_PATH="/etc/nitro_enclaves/allocator.yaml"
# Node resources that will be allocated for Nitro Enclaves
readonly CPU_COUNT=4
readonly MEMORY_MIB=8192
# Update enclave's allocator specification: allocator.yaml
sed -i "s/cpu_count:.*/cpu_count: $CPU_COUNT/g" $NE_ALLOCATOR_SPEC_PATH
sed -i "s/memory_mib:.*/memory_mib: $MEMORY_MIB/g" $NE_ALLOCATOR_SPEC_PATH

systemctl enable --now nitro-enclaves-allocator.service
systemctl enable --now docker

# TODO: Build socat in docker and just copy binary
yum install -y wget tar gcc
wget http://www.dest-unreach.org/socat/download/socat-1.7.4.4.tar.gz
tar -xzf socat-1.7.4.4.tar.gz
cd socat-1.7.4.4
./configure
make
make install

# Install supervisor
yum install -y python3-pip
pip3 install supervisor

# Setup NFS
yum install -y nfs-utils

# Setup folders
readonly EC2_USER_EXPORT="/export/ec2-user"
mkdir -p $EC2_USER_EXPORT/.arbitrum/local/nitro
mkdir -p $EC2_USER_EXPORT/.aws
mkdir -p $EC2_USER_EXPORT/config
chmod 700 $EC2_USER_EXPORT
chown -R ec2-user:ec2-user $EC2_USER_EXPORT

# Configure NFS
sh -c 'echo "/export/ec2-user 127.0.0.1/32(rw,insecure,fsid=0,crossmnt,no_subtree_check,sync)" >> /etc/exports'
systemctl restart nfs-server
systemctl enable nfs-server

# Start vsock proxies
readonly ENCLAVE_CID=16
readonly AWS_REGION="us-east-1"
readonly L1_NODE="127.0.0.1:8546"
readonly REDIS="127.0.0.1:6379"

# Outbound enclave connections

# AWS KMS
socat VSOCK-LISTEN:8003,fork,keepalive TCP:sts.$AWS_REGION.amazonaws.com:443,keepalive &
# AWS STS
socat VSOCK-LISTEN:8002,fork,keepalive TCP:kms.$AWS_REGION.amazonaws.com:443,keepalive &
# L1 NODE
socat VSOCK-LISTEN:8004,fork,keepalive TCP:$L1_NODE,keepalive &
# REDIS
socat VSOCK-LISTEN:8005,fork,keepalive TCP:$REDIS,keepalive &
# NFS Server
socat VSOCK-LISTEN:20000,fork,keepalive TCP:127.0.0.1:2049,keepalive &

# Inbound enclave connections

# Supervisor API
socat TCP-LISTEN:9001,fork,reuseaddr,keepalive,bind=127.0.0.1 VSOCK-CONNECT:$ENCLAVE_CID:9001,keepalive &
# RPC HTTP
# socat TCP-LISTEN:8547,fork,reuseaddr,keepalive VSOCK-CONNECT:$ENCLAVE_CID:10000,keepalive &
# RPC WS
# socat TCP-LISTEN:8548,fork,reuseaddr,keepalive VSOCK-CONNECT:$ENCLAVE_CID:10001,keepalive &

nitro-cli run-enclave --eif-path /home/nitro.eif --enclave-cid $ENCLAVE_CID --cpu-count $CPU_COUNT --memory $MEMORY_MIB
enclave_id=$(nitro-cli describe-enclaves | jq -r ".[0].EnclaveID")
echo "-------------------------------"
echo "Enclave ID is $enclave_id"
echo "-------------------------------"

nitro-cli console --enclave-id $enclave_id # blocking call.
