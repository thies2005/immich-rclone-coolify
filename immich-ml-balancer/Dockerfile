FROM docker.io/library/nginx:1.27-alpine

COPY nginx.conf.template /opt/immich-ml-balancer/nginx.conf.template
COPY render-nginx.sh /opt/immich-ml-balancer/render-nginx.sh

RUN chmod +x /opt/immich-ml-balancer/render-nginx.sh

CMD ["sh", "/opt/immich-ml-balancer/render-nginx.sh"]
