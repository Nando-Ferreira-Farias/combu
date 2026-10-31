# PostgreSQL 18 with TimescaleDB, PostGIS and combu installed (CREATE EXTENSION combu CASCADE).
# Build from the repository root: docker build -f docker/Dockerfile -t combu .
ARG BASE=timescale/timescaledb-ha:pg18.6-ts2.30.2
FROM ${BASE}

USER root
COPY combu.control sql/combu--*.sql /tmp/combu/
RUN cp /tmp/combu/* "$(pg_config --sharedir)/extension/" && rm -r /tmp/combu
USER postgres
