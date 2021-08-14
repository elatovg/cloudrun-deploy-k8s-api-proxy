FROM mirror.gcr.io/library/alpine
RUN apk add -U curl privoxy jq && \
    mv /etc/privoxy/templates /etc/privoxy-templates && \
    rm -rf /var/cache/apk/* /etc/privoxy/* && \
    mv /etc/privoxy-templates /etc/privoxy/templates
ADD --chown=privoxy:privoxy configs/config \
    /etc/privoxy/
ADD --chown=privoxy:privoxy configs/k8s-only.action \
    /etc/privoxy/
ADD --chown=privoxy:privoxy configs/k8s-rewrite-internal.filter \
    /etc/privoxy/
ADD configs/k8s-api-proxy.sh /
RUN chmod +x /k8s-api-proxy.sh

EXPOSE 8118/tcp

ENTRYPOINT ["./k8s-api-proxy.sh"]
