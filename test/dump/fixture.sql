-- A database using combu: catalog, two datasets, entities with claims, edges, an alias, a
-- geometry, and an application's own attribute table in the registry schema (as themes add).
SET client_min_messages = warning;
CREATE EXTENSION combu CASCADE;

INSERT INTO registry.entity_type (code, name) VALUES ('site', 'Site');
INSERT INTO registry.hierarchy (code, name) VALUES ('sites', 'Sites');
INSERT INTO registry.hierarchy_rule (hierarchy_id, parent_type_id, child_type_id)
SELECT h.id, NULL, t.id FROM registry.hierarchy h, registry.entity_type t;
INSERT INTO registry.dataset (key, kind, priority) VALUES ('a', 'curated', 0), ('b', 'source', 100);
INSERT INTO registry.entity (type_id, key, name, lifetime)
SELECT t.id, 's' || i, 'Site ' || i, tstzrange('2020-01-01', NULL)
FROM registry.entity_type t, generate_series(1, 3) i;
INSERT INTO registry.entity_claim (entity_id, dataset_id, name, lifetime)
SELECT e.id, d.id, e.name, e.lifetime FROM registry.entity e, registry.dataset d;
INSERT INTO registry.hierarchy_edge (hierarchy_id, child_id, valid, parent_id, dataset_id)
SELECT h.id, e.id, e.lifetime, NULL, d.id
FROM registry.hierarchy h, registry.entity e, registry.dataset d WHERE d.key = 'a';
INSERT INTO registry.entity_alias (scheme, code, valid, entity_id, dataset_id)
SELECT 'ext', upper(e.key), e.lifetime, e.id, d.id
FROM registry.entity e, registry.dataset d WHERE d.key = 'b';
INSERT INTO registry.entity_geometry (entity_id, role, valid, geom, dataset_id)
SELECT e.id, 'location', e.lifetime, ST_SetSRID(ST_MakePoint(-70, -33 - e.id), 4326), d.id
FROM registry.entity e, registry.dataset d WHERE d.key = 'b';

CREATE TABLE registry.site (
  entity_id bigint NOT NULL, valid tstzrange NOT NULL,
  dataset_id smallint NOT NULL REFERENCES registry.dataset, capacity_mw numeric,
  PRIMARY KEY (entity_id, dataset_id, valid WITHOUT OVERLAPS),
  FOREIGN KEY (entity_id, PERIOD valid) REFERENCES registry.entity (id, PERIOD lifetime));
INSERT INTO registry.site SELECT id, lifetime, 1, 10 * id FROM registry.entity;
