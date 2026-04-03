#!/bin/sh
set -eu

sanitize_weight() {
  value="${1:-1}"
  case "$value" in
    ''|*[!0-9]*)
      echo 1
      ;;
    *)
      if [ "$value" -lt 1 ]; then
        echo 1
      else
        echo "$value"
      fi
      ;;
  esac
}

normalize_backend() {
  raw="$1"
  scheme="http"
  case "$raw" in
    https://*) scheme="https"; raw="${raw#https://}" ;;
    http://*)  raw="${raw#http://}" ;;
  esac
  host_port="${raw%%/*}"
  host="${host_port%%:*}"
  port="${host_port#*:}"
  if [ "$host" = "$port" ]; then
    case "$scheme" in
      https) port="443" ;;
      *)     port="3003" ;;
    esac
  fi
  echo "${scheme}://${host}:${port}"
}

build_split_clients() {
  urls=""
  weights=""
  total_weight=0
  any_https=0
  count=0

  i=1
  while [ "$i" -le 10 ]; do
    eval "backend=\"\${ML_BACKEND_${i}:-}\""
    if [ -n "$backend" ]; then
      eval "weight=\$(sanitize_weight \"\${ML_BACKEND_${i}_WEIGHT:-1}\")"
      url=$(normalize_backend "$backend")
      if [ "$count" -gt 0 ]; then
        urls="${urls} ${url}"
        weights="${weights} ${weight}"
      else
        urls="${url}"
        weights="${weight}"
      fi
      total_weight=$((total_weight + weight))
      count=$((count + 1))
      case "$url" in
        https://*) any_https=1 ;;
      esac
    fi
    i=$((i + 1))
  done

  if [ "$count" -eq 0 ]; then
    echo "No ML_BACKEND_* configured" >&2
    exit 1
  fi

  sc=""
  cumulative=0
  idx=0
  for w in $weights; do
    cumulative=$((cumulative + w))
    url=$(echo "$urls" | cut -d' ' -f$((idx + 1)))
    pct=$(awk "BEGIN {printf \"%.2f\", ($cumulative/$total_weight)*100}")
    if [ "$idx" -eq $((count - 1)) ]; then
      sc="${sc}    *        ${url};
"
    else
      sc="${sc}    ${pct}%   ${url};
"
    fi
    idx=$((idx + 1))
  done

  ML_SPLIT_CLIENTS="  split_clients \"\${request_id}\" \$ml_backend_url {
${sc}  }"
  ML_USE_SSL="off"
  [ "$any_https" -eq 1 ] && ML_USE_SSL="on"
}

echo "[ml-balancer] Removing default nginx configs..."
rm -f /etc/nginx/conf.d/default.conf

if [ ! -f /opt/immich-ml-balancer/nginx.conf.template ]; then
  echo "[ml-balancer] ERROR: Template not found at /opt/immich-ml-balancer/nginx.conf.template" >&2
  exit 1
fi

echo "[ml-balancer] Building split_clients config..."
build_split_clients
export ML_SPLIT_CLIENTS ML_USE_SSL

echo "[ml-balancer] Rendering nginx.conf..."
envsubst '${ML_SPLIT_CLIENTS} ${ML_USE_SSL} ${ML_PROXY_CONNECT_TIMEOUT} ${ML_PROXY_SEND_TIMEOUT} ${ML_PROXY_READ_TIMEOUT} ${ML_PROXY_NEXT_UPSTREAM_TRIES}' \
  < /opt/immich-ml-balancer/nginx.conf.template > /etc/nginx/nginx.conf

echo "[ml-balancer] Final nginx.conf:"
cat /etc/nginx/nginx.conf

echo "[ml-balancer] Testing config..."
nginx -t

echo "[ml-balancer] Starting nginx..."
exec nginx -g 'daemon off;'
