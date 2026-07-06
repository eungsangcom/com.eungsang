FROM docker.n8n.io/n8nio/n8n:latest

USER root
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
COPY workflows /import/workflows
USER node

ENTRYPOINT ["/docker-entrypoint.sh"]
