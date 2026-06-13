# Fleet OTel collector image: the official Alloy plus our pipeline config.
# Pin to a digest/tag once verified; :latest is used for the first bring-up.
FROM grafana/alloy:latest

COPY alloy/config.alloy /etc/alloy/config.alloy

# OTLP gRPC, OTLP HTTP, Faro RUM, Alloy UI/health.
EXPOSE 4317 4318 12347 12345

# The image entrypoint is the alloy binary; pass it the run subcommand + flags.
CMD ["run", "/etc/alloy/config.alloy", \
     "--server.http.listen-addr=0.0.0.0:12345", \
     "--storage.path=/var/lib/alloy/data"]
