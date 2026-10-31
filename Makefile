# combu is pure SQL: `make install` copies the control file and scripts into PostgreSQL's
# extension directory, `make installcheck` runs the regression tests against a running server.
EXTENSION = combu
DATA = $(wildcard sql/combu--*.sql)

REGRESS = install registry config_dump
REGRESS_OPTS = --inputdir=test --outputdir=test

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Dump a database that uses combu, restore it, compare (docs/backups.md). Needs a running server.
.PHONY: dumpcheck
dumpcheck:
	test/dump/run.sh
