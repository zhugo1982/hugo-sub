#!/bin/bash

echo "==> 1. 清理并停止旧服务..."
systemctl stop sing-box 2>/dev/null

echo "==> 2. 生成全新 8 协议凭证..."
mkdir -p /etc/sing-box

# 生成 Reality 密钥
KEYPAIR=$(sing-box generate reality-keypair)
PRIV_KEY=$(echo "$KEYPAIR" | grep "PrivateKey" | awk '{print $2}')
PUB_KEY=$(echo "$KEYPAIR" | grep "PublicKey" | awk '{print $2}')

# 生成通用凭证
UUID=$(cat /proc/sys/kernel/random/uuid)
HY2_PASS=$(cat /proc/sys/kernel/random/uuid | cut -d'-' -f1)
TUIC_PASS=$(cat /proc/sys/kernel/random/uuid)
SS_PASS=$(openssl rand -base64 16)
TROJAN_PASS=$(cat /proc/sys/kernel/random/uuid | cut -d'-' -f1)
PROXY_USER="hugo"
PROXY_PASS=$(openssl rand -hex 6)

SHORT_ID="0123456789abcdef"
SNI="gateway.icloud.com"

# 获取 IP
IP=$(curl -s https://api.ipify.org)
if [ -z "$IP" ]; then
    IP="3.141.65.96"
fi

echo "==> 3. 写入包含新 xtls-reality (8881) 的 8 协议完整配置文件..."
cat > /etc/sing-box/config.json << CONFIG
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-tcp",
      "listen": "0.0.0.0",
      "listen_port": 443,
      "users": [
        {
          "name": "hugo-tcp",
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$SNI",
            "server_port": 443
          },
          "private_key": "$PRIV_KEY",
          "short_id": [
            "$SHORT_ID"
          ]
        }
      }
    },
    {
      "type": "vless",
      "tag": "vless-grpc",
      "listen": "0.0.0.0",
      "listen_port": 444,
      "users": [
        {
          "name": "hugo-grpc",
          "uuid": "$UUID"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$SNI",
            "server_port": 443
          },
          "private_key": "$PRIV_KEY",
          "short_id": [
            "$SHORT_ID"
          ]
        }
      },
      "transport": {
        "type": "grpc",
        "service_name": "hugogrpc"
      }
    },
    {
      "type": "vless",
      "tag": "xtls-reality-extra",
      "listen": "0.0.0.0",
      "listen_port": 8881,
      "users": [
        {
          "name": "hugo-xtls-8881",
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$SNI",
            "server_port": 443
          },
          "private_key": "$PRIV_KEY",
          "short_id": [
            "$SHORT_ID"
          ]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "0.0.0.0",
      "listen_port": 8443,
      "users": [
        {
          "password": "$HY2_PASS"
        }
      ],
      "masquerade": "https://bing.com",
      "tls": {
        "enabled": true,
        "alpn": [
          "h3"
        ],
        "certificate_path": "/etc/sing-box/hy2.crt",
        "key_path": "/etc/sing-box/hy2.key"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "0.0.0.0",
      "listen_port": 9443,
      "users": [
        {
          "uuid": "$UUID",
          "password": "$TUIC_PASS"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": [
          "h3"
        ],
        "certificate_path": "/etc/sing-box/hy2.crt",
        "key_path": "/etc/sing-box/hy2.key"
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "listen_port": 6443,
      "method": "2022-blake3-aes-128-gcm",
      "password": "$SS_PASS"
    },
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "0.0.0.0",
      "listen_port": 7443,
      "users": [
        {
          "name": "hugo-trojan",
          "password": "$TROJAN_PASS"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/hy2.crt",
        "key_path": "/etc/sing-box/hy2.key"
      }
    },
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "0.0.0.0",
      "listen_port": 5443,
      "users": [
        {
          "username": "$PROXY_USER",
          "password": "$PROXY_PASS"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
CONFIG

# 生成证书
openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/sing-box/hy2.key -out /etc/sing-box/hy2.crt -days 3650 -subj "/CN=bing.com" 2>/dev/null

echo "==> 4. 重启服务..."
systemctl restart sing-box

# 链接拼接
VLESS_TCP="vless://$UUID@$IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUB_KEY&sid=$SHORT_ID&type=tcp#Hugo-Reality-TCP"
VLESS_GP="vless://$UUID@$IP:444?encryption=none&security=reality&sni=$SNI&fp=chrome&pbk=$PUB_KEY&sid=$SHORT_ID&type=grpc&serviceName=hugogrpc#Hugo-Reality-gRPC"
XTLS_EXTRA="vless://$UUID@$IP:8881?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUB_KEY&sid=$SHORT_ID&type=tcp#Hugo-XTLS-Reality-8881"
HY2_LINK="hysteria2://$HY2_PASS@$IP:8443?insecure=1&sni=bing.com#Hugo-Hysteria2"
TUIC_LINK="tuic://$UUID:$TUIC_PASS@$IP:9443?congestion_control=bbr&alpn=h3&allow_insecure=1#Hugo-TuicV5"
TROJAN_LINK="trojan://$TROJAN_PASS@$IP:7443?security=tls&allowInsecure=1#Hugo-Trojan"
SOCKS_LINK="socks5://$PROXY_USER:$PROXY_PASS@$IP:5443#Hugo-Socks5"

SS_RAW="2022-blake3-aes-128-gcm:$SS_PASS"
SS_ENCODED=$(echo -n "$SS_RAW" | base64 | tr -d '\n')
SS_LINK="ss://$SS_ENCODED@$IP:6443#Hugo-Shadowsocks"

echo "============================================================"
echo "✨ 部署成功！8 大核心协议专属订阅链接如下："
echo "============================================================"
echo -e "\033[32m[1] VLESS-Reality-TCP (443):\033[0m"
echo "$VLESS_TCP"
echo "------------------------------------------------------------"
echo -e "\033[34m[2] VLESS-Reality-gRPC (444):\033[0m"
echo "$VLESS_GP"
echo "------------------------------------------------------------"
echo -e "\033[36m[3] XTLS-Reality-Extra (8881):\033[0m"
echo "$XTLS_EXTRA"
echo "------------------------------------------------------------"
echo -e "\033[35m[4] Hysteria 2 (8443):\033[0m"
echo "$HY2_LINK"
echo "------------------------------------------------------------"
echo -e "\033[33m[5] TUIC v5 (9443):\033[0m"
echo "$TUIC_LINK"
echo "------------------------------------------------------------"
echo -e "\033[31m[6] Shadowsocks 2022 (6443):\033[0m"
echo "$SS_LINK"
echo "------------------------------------------------------------"
echo -e "\033[37m[7] Trojan (7443):\033[0m"
echo "$TROJAN_LINK"
echo "------------------------------------------------------------"
echo -e "\033[32m[8] SOCKS5/HTTP Mixed (5443):\033[0m"
echo "$SOCKS_LINK"
echo "============================================================"
