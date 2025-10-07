#!/bin/sh
set -e

SHARED_DIR="/shared"

echo "Starting"
echo "Some sleep..."
sleep 5

echo "Up loopback interface"
ip link set lo up || true
echo "Some sleep..."
sleep 5

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

# Decaf query node 1
if ! ip addr show dev lo | grep -q "127.0.0.6"; then
  ip addr add 127.0.0.6/32 dev lo:0
  ip link set dev lo:0 up
fi
# Decaf query node 2
if ! ip addr show dev lo | grep -q "127.0.0.7"; then
  ip addr add 127.0.0.7/32 dev lo:0
  ip link set dev lo:0 up
fi
# Decaf query node 3
if ! ip addr show dev lo | grep -q "127.0.0.8"; then
  ip addr add 127.0.0.8/32 dev lo:0
  ip link set dev lo:0 up
fi
# Decaf query node 4
if ! ip addr show dev lo | grep -q "127.0.0.9"; then
  ip addr add 127.0.0.9/32 dev lo:0
  ip link set dev lo:0 up
fi

# NFS
if ! ip addr show dev lo | grep -q "127.0.0.200"; then
  ip addr add 127.0.0.200/32 dev lo:0
  ip link set dev lo:0 up
fi
# AWS IMDS
if ! ip addr show dev lo | grep -q "169.254.169.254"; then
  ip addr add 169.254.169.254/32 dev lo:0
  ip link set dev lo:0 up
fi

echo "Some sleep..."
sleep 5

echo "Start AWS KMS egress vsock proxy"
socat TCP-LISTEN:443,bind=127.0.0.2,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8002,keepalive &
echo "Start AWS STS egress vsock proxy"
socat TCP-LISTEN:443,bind=127.0.0.3,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8003,keepalive &
echo "Start L1 node egress vsock proxy"
socat TCP-LISTEN:443,bind=127.0.0.4,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8004,keepalive &
echo "Start L1 beacon node egress vsock proxy"
socat TCP-LISTEN:443,bind=127.0.0.5,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8005,keepalive &

echo "Start Decaf query node 1 egress vsock proxy"
socat TCP-LISTEN:443,bind=127.0.0.6,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8006,keepalive &
echo "Start Decaf query node 2 egress vsock proxy"
socat TCP-LISTEN:443,bind=127.0.0.7,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8007,keepalive &
echo "Start Decaf query node 3 egress vsock proxy"
socat TCP-LISTEN:443,bind=127.0.0.8,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8008,keepalive &
echo "Start Decaf query node 4 egress vsock proxy"
socat TCP-LISTEN:443,bind=127.0.0.9,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8009,keepalive &

# NFS
echo "Start NFSv4 egress vsock proxy"
socat TCP-LISTEN:2049,bind=127.0.0.200,fork,reuseaddr,keepalive VSOCK-CONNECT:3:20000,keepalive &

# IMDS
echo "Start AWS IMDS egress vsock proxy"
socat TCP-LISTEN:80,bind=169.254.169.254,fork,reuseaddr,keepalive VSOCK-CONNECT:3:16900,keepalive &

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

# Get instance region from IMDS
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
echo "Token: $TOKEN"
AWS_REGION=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region`
if [[ ! "$AWS_REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
  echo "Invalid region format: $AWS_REGION"
  exit 1
fi
echo "Region: $AWS_REGION"

# Setup AWS services in /etc/hosts
echo "Setup /etc/hosts"
echo "127.0.0.2   kms.$AWS_REGION.amazonaws.com" >>/etc/hosts
echo "127.0.0.3   sts.$AWS_REGION.amazonaws.com" >>/etc/hosts

# TODO: Replace to be more strict
echo "Extend /etc/hosts"
cat $SHARED_DIR/config/hosts >> /etc/hosts

echo "Create $SHARED_DIR/.arbitrum/local/nitro"
su user -c "mkdir -p $SHARED_DIR/.arbitrum/local/nitro"

echo "Start supervisor"
AWS_REGION=$AWS_REGION supervisord -c /etc/supervisor/supervisord.conf
