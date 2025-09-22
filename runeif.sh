#!/bin/sh
set -e

SHARED_DIR="/shared"
AWS_CONFIG_FILE="$SHARED_DIR/config/aws_config"
AWS_SHARED_CREDENTIALS_FILE="$SHARED_DIR/config/aws_credentials"
AWS_PARAMS="AWS_CONFIG_FILE=$AWS_CONFIG_FILE AWS_SHARED_CREDENTIALS_FILE=$AWS_SHARED_CREDENTIALS_FILE"

echo "Starting"
echo "Some sleep..."
sleep 5

echo "Up loopback interface"
ip link set lo up || true
echo "Some sleep..."
sleep 5

echo "Setup /etc/hosts"
echo "127.0.0.2   kms.us-east-1.amazonaws.com kms.us-east-2.amazonaws.com kms.us-west-1.amazonaws.com kms.us-west-2.amazonaws.com kms.ap-south-1.amazonaws.com kms.ap-northeast-1.amazonaws.com kms.ap-northeast-2.amazonaws.com kms.ap-northeast-3.amazonaws.com kms.ap-southeast-1.amazonaws.com kms.ap-southeast-2.amazonaws.com kms.ca-central-1.amazonaws.com kms.eu-central-1.amazonaws.com kms.eu-west-1.amazonaws.com kms.eu-west-2.amazonaws.com kms.eu-west-3.amazonaws.com kms.eu-north-1.amazonaws.com kms.sa-east-1.amazonaws.com" >>/etc/hosts
echo "127.0.0.3   sts.us-east-1.amazonaws.com sts.us-east-2.amazonaws.com sts.us-west-1.amazonaws.com sts.us-west-2.amazonaws.com sts.ap-south-1.amazonaws.com sts.ap-northeast-1.amazonaws.com sts.ap-northeast-2.amazonaws.com sts.ap-northeast-3.amazonaws.com sts.ap-southeast-1.amazonaws.com sts.ap-southeast-2.amazonaws.com sts.ca-central-1.amazonaws.com sts.eu-central-1.amazonaws.com sts.eu-west-1.amazonaws.com sts.eu-west-2.amazonaws.com sts.eu-west-3.amazonaws.com sts.eu-north-1.amazonaws.com sts.sa-east-1.amazonaws.com" >>/etc/hosts

echo "Ensure loopback addresses exist"
# AWS KMS
if ! ip addr show dev lo | grep -q "127.0.0.2"; then
  ip addr add 127.0.0.2/32 dev lo:0
  ip link set dev lo:0 up
fi
# AWS STS
if ! ip addr show dev lo | grep -q "127.0.0.3"; then
  ip addr add 127.0.0.3/32 dev lo:0
  ip link set dev lo:0 up
fi
# L1 NODE
if ! ip addr show dev lo | grep -q "127.0.0.4"; then
  ip addr add 127.0.0.4/32 dev lo:0
  ip link set dev lo:0 up
fi
# L1 BEACON NODE
if ! ip addr show dev lo | grep -q "127.0.0.5"; then
  ip addr add 127.0.0.5/32 dev lo:0
  ip link set dev lo:0 up
fi
# NFS
if ! ip addr show dev lo | grep -q "127.0.0.200"; then
  ip addr add 127.0.0.200/32 dev lo:0
  ip link set dev lo:0 up
fi
echo "Some sleep..."
sleep 5

echo "Start AWS KMS egress vsock proxy"
socat TCP-LISTEN:443,bind=127.0.0.2,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8002,keepalive &
echo "Start AWS STS egress vsock proxy"
socat TCP-LISTEN:443,bind=127.0.0.3,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8003,keepalive &
echo "Start L1 node egress vsock proxy"
socat TCP-LISTEN:8546,bind=127.0.0.4,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8004,keepalive &
echo "Start L1 beacon node egress vsock proxy"
socat TCP-LISTEN:3500,bind=127.0.0.5,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8005,keepalive &
# NFS
echo "Start NFSv4 egress vsock proxy"
socat TCP-LISTEN:2049,bind=127.0.0.200,fork,reuseaddr,keepalive VSOCK-CONNECT:3:20000,keepalive &
# Supervisor
echo "Start supervisor ingress vsock proxy"
socat VSOCK-LISTEN:9001,fork,keepalive TCP:127.0.0.1:9001,keepalive &
echo "Start L2 HTTP ingress vsock proxy"
socat VSOCK-LISTEN:10000,fork,keepalive TCP:127.0.0.1:8547,keepalive &
echo "Start L2 WS ingress vsock proxy"
socat VSOCK-LISTEN:10001,fork,keepalive TCP:127.0.0.1:8548,keepalive &
echo "Some sleep..."
sleep 5

echo "Create $SHARED_DIR dir"
mkdir -p $SHARED_DIR
chown -R user:user $SHARED_DIR
echo "Mounting persistent volume to $SHARED_DIR"
mount -t nfs4 127.0.0.200:/ $SHARED_DIR
echo "Some sleep..."
sleep 5

echo "Extend /etc/hosts"
cat $SHARED_DIR/config/hosts >> /etc/hosts

echo "Create chain directory: /chain"
mkdir -p /chain
if [ ! -f $SHARED_DIR/chain.img ]; then
    echo "chain.img don't exist, exit..."
    exit 1
fi

echo "Some sleep..."
sleep 5

echo "Create $SHARED_DIR/.arbitrum/local/nitro"
su user -c "mkdir -p $SHARED_DIR/.arbitrum/local/nitro"

echo "Start supervisor"
supervisord -c /etc/supervisor/supervisord.conf
