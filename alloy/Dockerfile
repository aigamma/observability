# Fleet OTel collector image: the official Alloy plus our pipeline config.
# Pin to a digest/tag once verified; :latest is used for the first bring-up.
FROM grafana/alloy:latest

COPY alloy/config.alloy /etc/alloy/config.alloy

# OTLP gRPC, OTLP HTTP, Faro RUM, Alloy UI/health.
EXPOSE 4317 4318 12347 12345

# The image entrypoint is the alloy binary; pass it the run subcommand + flags.
# --stability.level=experimental enables otelcol.exporter.debug (the Wave 0
# verification oracle). Once Grafana Cloud egress is verified you can drop the
# debug exporter and this flag.
CMD ["run", "/etc/alloy/config.alloy", \
     "--server.http.listen-addr=0.0.0.0:12345", \
     "--stability.level=experimental", \
     "--storage.path=/var/lib/alloy/data"]
