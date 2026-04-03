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

build_upstream_servers() {
  i=1
  any=0

  while [ "$i" -le 10 ]; do
    backend_var="ML_BACKEND_${i}"
    weight_var="ML_BACKEND_${i}_WEIGHT"

    backend=$(eval "printf '%s' \"\${$backend_var:-}\"")
    if [ -n "$backend" ]; then
      any=1
      weight_raw=$(eval "printf '%s' \"\${$weight_var:-1}\"")
      weight=$(sanitize_weight "$weight_raw")

      if [ "${ML_LB_METHOD:-round_robin}" = "weighted" ]; then
        printf '    server %s max_fails=%s fail_timeout=%s weight=%s;\n' \
          "$backend" "${ML_BACKEND_MAX_FAILS:-2}" "${ML_BACKEND_FAIL_TIMEOUT:-10s}" "$weight"
      else
        printf '    server %s max_fails=%s fail_timeout=%s;\n' \
          "$backend" "${ML_BACKEND_MAX_FAILS:-2}" "${ML_BACKEND_FAIL_TIMEOUT:-10s}"
      fi
    fi

    i=$((i + 1))
  done

  if [ "$any" -ne 1 ]; then
    printf '    server 127.0.0.1:9 down;\n'
  fi
}

set_lb_method_directive() {
  case "${ML_LB_METHOD:-round_robin}" in
    least_conn)
      printf '    least_conn;\n'
      ;;
    ip_hash)
      printf '    ip_hash;\n'
      ;;
    weighted|round_robin)
      printf ''
      ;;
    *)
      printf ''
      ;;
  esac
}

ML_UPSTREAM_SERVERS="$(build_upstream_servers)"
ML_LB_METHOD_DIRECTIVE="$(set_lb_method_directive)"
export ML_UPSTREAM_SERVERS ML_LB_METHOD_DIRECTIVE

envsubst '${ML_LB_KEEPALIVE} ${ML_UPSTREAM_SERVERS} ${ML_LB_METHOD_DIRECTIVE} ${ML_PROXY_CONNECT_TIMEOUT} ${ML_PROXY_SEND_TIMEOUT} ${ML_PROXY_READ_TIMEOUT} ${ML_PROXY_NEXT_UPSTREAM_TRIES}' \
  < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf

nginx -t
