#!/bin/sh
set -e

echo "Starting"
sleep 5

echo "Up loopback interface"
ip link set lo up || true
sleep 5

echo "Setup /etc/hosts"
echo "127.0.0.2   kms.us-east-1.amazonaws.com kms.us-east-2.amazonaws.com kms.us-west-1.amazonaws.com kms.us-west-2.amazonaws.com kms.ap-south-1.amazonaws.com kms.ap-northeast-1.amazonaws.com kms.ap-northeast-2.amazonaws.com kms.ap-northeast-3.amazonaws.com kms.ap-southeast-1.amazonaws.com kms.ap-southeast-2.amazonaws.com kms.ca-central-1.amazonaws.com kms.eu-central-1.amazonaws.com kms.eu-west-1.amazonaws.com kms.eu-west-2.amazonaws.com kms.eu-west-3.amazonaws.com kms.eu-north-1.amazonaws.com kms.sa-east-1.amazonaws.com" >>/etc/hosts
echo "127.0.0.3   sts.us-east-1.amazonaws.com sts.us-east-2.amazonaws.com sts.us-west-1.amazonaws.com sts.us-west-2.amazonaws.com sts.ap-south-1.amazonaws.com sts.ap-northeast-1.amazonaws.com sts.ap-northeast-2.amazonaws.com sts.ap-northeast-3.amazonaws.com sts.ap-southeast-1.amazonaws.com sts.ap-southeast-2.amazonaws.com sts.ca-central-1.amazonaws.com sts.eu-central-1.amazonaws.com sts.eu-west-1.amazonaws.com sts.eu-west-2.amazonaws.com sts.eu-west-3.amazonaws.com sts.eu-north-1.amazonaws.com sts.sa-east-1.amazonaws.com" >>/etc/hosts
echo "127.0.0.4   l1-node" >>/etc/hosts
echo "127.0.0.5   l1-beacon-node" >>/etc/hosts

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
sleep 5

echo "Start vsock proxies"
socat TCP-LISTEN:443,bind=127.0.0.2,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8002,keepalive &
socat TCP-LISTEN:443,bind=127.0.0.3,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8003,keepalive &
socat TCP-LISTEN:8546,bind=127.0.0.4,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8004,keepalive &
socat TCP-LISTEN:3500,bind=127.0.0.5,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8005,keepalive &
# NFS
socat TCP-LISTEN:2049,bind=127.0.0.200,fork,reuseaddr,keepalive VSOCK-CONNECT:3:20000,keepalive &
# Supervisor
socat VSOCK-LISTEN:9001,fork,keepalive TCP:127.0.0.1:9001,keepalive &
socat VSOCK-LISTEN:10000,fork,keepalive TCP:127.0.0.1:8547,keepalive &
socat VSOCK-LISTEN:10001,fork,keepalive TCP:127.0.0.1:8548,keepalive &
sleep 5

echo "Mounting persistent volume to /home/user/export"
su user -c 'mkdir -p /home/user/export'
mount -t nfs4 127.0.0.200:/ /home/user/export
sleep 5

echo "Start supervisor"
supervisord -c /etc/supervisor/supervisord.conf
