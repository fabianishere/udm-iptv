FROM arm64v8/alpine:3.14

RUN apk add --no-cache iptables igmpproxy

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/bin/ash", "./entrypoint.sh"]
