#!/bin/sh
set -e

sanitize_weight() {
  value="${1:-1}"
  case "$value" in
    ''|*[!0-9]*) echo 1 ;;
    *)
      [ "$value" -lt 1 ] && echo 1 || echo "$value"
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
    backend=$(echo "$backend" | tr -d '\r')
    if [ -n "$backend" ]; then
      weight_raw=$(eval echo "\"\${ML_BACKEND_${i}_WEIGHT:-1}\"")
      weight_raw=$(echo "$weight_raw" | tr -d '\r')
      weight=$(sanitize_weight "$weight_raw")
      url=$(normalize_backend "$backend")
      if [ "$count" -gt 0 ]; then
        urls="${urls}|${url}"
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
    echo "[ml-balancer] ERROR: No ML_BACKEND_* configured" >&2
    exit 1
  fi

  echo "[ml-balancer] Backends ($count): $urls" >&2
  echo "[ml-balancer] Weights: $weights (total=$total_weight)" >&2

  sc=""
  cumulative=0
  idx=0
  oldifs="$IFS"
  IFS='|'
  for url in $urls; do
    w=$(echo "$weights" | cut -d' ' -f$((idx + 1)))
    cumulative=$((cumulative + w))
    pct=$((cumulative * 100 / total_weight))
    if [ "$idx" -eq $((count - 1)) ]; then
      sc="${sc}    *        ${url};
"
    else
      sc="${sc}    ${pct}%   ${url};
"
    fi
    idx=$((idx + 1))
  done
  IFS="$oldifs"

  ML_SPLIT_CLIENTS="  split_clients \"\${request_id}\" \$ml_backend_url {
${sc}  }"
  ML_USE_SSL="off"
  [ "$any_https" -eq 1 ] && ML_USE_SSL="on"
}

echo "[ml-balancer] Starting..." >&2
echo "[ml-balancer] Removing default nginx configs..." >&2
rm -f /etc/nginx/conf.d/default.conf

if [ ! -f /opt/immich-ml-balancer/nginx.conf.template ]; then
  echo "[ml-balancer] ERROR: Template not found at /opt/immich-ml-balancer/nginx.conf.template" >&2
  exit 1
fi

echo "[ml-balancer] Building split_clients config..." >&2
build_split_clients
export ML_SPLIT_CLIENTS ML_USE_SSL

export ML_PROXY_CONNECT_TIMEOUT=$(echo "${ML_PROXY_CONNECT_TIMEOUT:-3s}" | tr -d '\r')
export ML_PROXY_SEND_TIMEOUT=$(echo "${ML_PROXY_SEND_TIMEOUT:-300s}" | tr -d '\r')
export ML_PROXY_READ_TIMEOUT=$(echo "${ML_PROXY_READ_TIMEOUT:-300s}" | tr -d '\r')
export ML_PROXY_NEXT_UPSTREAM_TRIES=$(echo "${ML_PROXY_NEXT_UPSTREAM_TRIES:-3}" | tr -d '\r')

echo "[ml-balancer] Rendering nginx.conf..." >&2
envsubst '${ML_SPLIT_CLIENTS} ${ML_USE_SSL} ${ML_PROXY_CONNECT_TIMEOUT} ${ML_PROXY_SEND_TIMEOUT} ${ML_PROXY_READ_TIMEOUT} ${ML_PROXY_NEXT_UPSTREAM_TRIES}' \
  < /opt/immich-ml-balancer/nginx.conf.template > /etc/nginx/nginx.conf

echo "[ml-balancer] Generated nginx.conf:" >&2
cat /etc/nginx/nginx.conf >&2

echo "[ml-balancer] Testing nginx config..." >&2
nginx -t 2>&1 || { echo "[ml-balancer] nginx -t FAILED" >&2; exit 1; }

echo "[ml-balancer] Starting nginx..." >&2
exec nginx -g 'daemon off;'
