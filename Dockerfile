FROM alpine:3.22
RUN apk add --no-cache curl jq
COPY --chmod=755 fetch.sh /fetch.sh
ENTRYPOINT ["/fetch.sh"]
