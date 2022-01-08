FROM arm64v8/alpine:3.14

RUN apk add --no-cache iptables igmpproxy

COPY entrypoint.sh udhcpc.hook.sh /

ENTRYPOINT ["/bin/ash", "./entrypoint.sh"]
