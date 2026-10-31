-- combu-db core 0002: the entity registry's functions and triggers.
--
-- - registry.as_of(): the instant the asof views show (session setting combu.as_of,
--   default now).
-- - Type functions: entity_type_descendants, entity_type_lineage.
-- - Hierarchy functions: hierarchy_edges (each child's edge in force, from the highest-priority
--   dataset that has one), and on top of it hierarchy_tree, entity_ancestors, entity_ancestor,
--   entity_descendants.
-- - Integrity triggers: no entities of abstract types, typed references (require_type), and
--   hierarchy edges that follow the rules and form no cycle.
--
-- Every name is schema-qualified, so the functions work whatever the caller's search_path.

CREATE FUNCTION registry.as_of() RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('combu.as_of', true), '')::timestamptz, now())
$$;
COMMENT ON FUNCTION registry.as_of() IS
  'The instant the asof views show: SET combu.as_of = ''2020-01-01'' (default: now).';

CREATE FUNCTION registry.entity_type_descendants(type_code text) RETURNS SETOF smallint
LANGUAGE sql STABLE AS $$
  WITH RECURSIVE t AS (
    SELECT id FROM registry.entity_type WHERE code = type_code
    UNION ALL
    SELECT c.id FROM registry.entity_type c JOIN t ON c.parent_id = t.id)
  SELECT id FROM t
$$;
COMMENT ON FUNCTION registry.entity_type_descendants(text) IS 'The type and all its subtypes.';

CREATE FUNCTION registry.entity_type_lineage(start_type smallint) RETURNS SETOF smallint
LANGUAGE sql STABLE AS $$
  WITH RECURSIVE t AS (
    SELECT id, parent_id FROM registry.entity_type WHERE id = start_type
    UNION ALL
    SELECT p.id, p.parent_id FROM registry.entity_type p JOIN t ON p.id = t.parent_id)
  SELECT id FROM t
$$;
COMMENT ON FUNCTION registry.entity_type_lineage(smallint) IS 'The type and all its ancestors.';

CREATE FUNCTION registry.hierarchy_edges(
  hierarchy_code text, ts timestamptz DEFAULT registry.as_of())
RETURNS TABLE (child_id bigint, parent_id bigint, dataset_id smallint)
LANGUAGE sql STABLE AS $$
  SELECT DISTINCT ON (e.child_id) e.child_id, e.parent_id, e.dataset_id
  FROM registry.hierarchy_edge e
  JOIN registry.hierarchy h ON h.id = e.hierarchy_id
  JOIN registry.dataset d ON d.id = e.dataset_id
  WHERE h.code = hierarchy_code AND e.valid @> ts
  ORDER BY e.child_id, d.priority, d.key
$$;
COMMENT ON FUNCTION registry.hierarchy_edges(text, timestamptz) IS
  'Each child''s edge in force at an instant, from the highest-priority dataset that has one.';

CREATE FUNCTION registry.hierarchy_tree(
  hierarchy_code text, ts timestamptz DEFAULT registry.as_of(), root_id bigint DEFAULT NULL)
RETURNS TABLE (entity_id bigint, parent_id bigint, depth int, path bigint[])
LANGUAGE sql STABLE AS $$
  WITH RECURSIVE edges AS (
    SELECT child_id, parent_id FROM registry.hierarchy_edges(hierarchy_code, ts)),
  tree AS (
    SELECT ed.child_id, ed.parent_id, 0, ARRAY[ed.child_id]
    FROM edges ed
    WHERE (root_id IS NULL AND ed.parent_id IS NULL) OR ed.child_id = root_id
    UNION ALL
    SELECT ed.child_id, ed.parent_id, t.depth + 1, t.path || ed.child_id
    FROM edges ed JOIN tree t (entity_id, parent_id, depth, path) ON ed.parent_id = t.entity_id
    WHERE NOT ed.child_id = ANY (t.path))
  SELECT * FROM tree
$$;
COMMENT ON FUNCTION registry.hierarchy_tree(text, timestamptz, bigint) IS
  'The hierarchy at an instant, from its roots (or from root_id): one row per node.';

CREATE FUNCTION registry.entity_ancestors(
  start_id bigint, hierarchy_code text, ts timestamptz DEFAULT registry.as_of())
RETURNS TABLE (entity_id bigint, depth int)
LANGUAGE sql STABLE AS $$
  WITH RECURSIVE edges AS (
    SELECT child_id, parent_id FROM registry.hierarchy_edges(hierarchy_code, ts)
    WHERE parent_id IS NOT NULL),
  up AS (
    SELECT ed.parent_id, 1 FROM edges ed WHERE ed.child_id = start_id
    UNION ALL
    SELECT ed.parent_id, u.depth + 1
    FROM edges ed JOIN up u (entity_id, depth) ON ed.child_id = u.entity_id
    WHERE u.depth < 100)
  SELECT * FROM up
$$;
COMMENT ON FUNCTION registry.entity_ancestors(bigint, text, timestamptz) IS
  'Parent (depth 1), grandparent (depth 2), ... of an entity in a hierarchy at an instant.';

CREATE FUNCTION registry.entity_ancestor(
  start_id bigint, hierarchy_code text, type_code text, ts timestamptz DEFAULT registry.as_of())
RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT a.entity_id
  FROM registry.entity_ancestors(start_id, hierarchy_code, ts) a
  JOIN registry.entity e ON e.id = a.entity_id
  WHERE e.type_id IN (SELECT registry.entity_type_descendants(type_code))
  ORDER BY a.depth LIMIT 1
$$;
COMMENT ON FUNCTION registry.entity_ancestor(bigint, text, text, timestamptz) IS
  'The nearest ancestor of a given type, e.g. the region of a commune; independent of depth.';

CREATE FUNCTION registry.entity_descendants(
  start_id bigint, hierarchy_code text, ts timestamptz DEFAULT registry.as_of())
RETURNS TABLE (entity_id bigint, depth int)
LANGUAGE sql STABLE AS $$
  SELECT t.entity_id, t.depth FROM registry.hierarchy_tree(hierarchy_code, ts, start_id) t
  WHERE t.depth > 0
$$;
COMMENT ON FUNCTION registry.entity_descendants(bigint, text, timestamptz) IS
  'Children (depth 1), grandchildren (depth 2), ... of an entity in a hierarchy at an instant.';

CREATE FUNCTION registry.entity_check() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT is_abstract FROM registry.entity_type WHERE id = NEW.type_id) THEN
    RAISE EXCEPTION 'registry: entity % has abstract type %', NEW.key,
      (SELECT code FROM registry.entity_type WHERE id = NEW.type_id)
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER entity_check BEFORE INSERT OR UPDATE OF type_id ON registry.entity
FOR EACH ROW EXECUTE FUNCTION registry.entity_check();

-- Arguments come in pairs: (column, type code). Each non-null column must reference an entity
-- of that type or one of its subtypes.
CREATE FUNCTION registry.require_type() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  i int;
  ref bigint;
BEGIN
  FOR i IN 0 .. TG_NARGS - 1 BY 2 LOOP
    ref := (to_jsonb(NEW) ->> TG_ARGV[i])::bigint;
    IF ref IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM registry.entity e
      WHERE e.id = ref
        AND e.type_id IN (SELECT registry.entity_type_descendants(TG_ARGV[i + 1])))
    THEN
      RAISE EXCEPTION 'registry: %.% must be a %, but % is a %', TG_TABLE_NAME, TG_ARGV[i],
        TG_ARGV[i + 1], (SELECT key FROM registry.entity WHERE id = ref),
        (SELECT t.code FROM registry.entity e JOIN registry.entity_type t ON t.id = e.type_id
         WHERE e.id = ref)
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

-- Deferred to commit, so a writer can insert a whole tree in any order. The cycle check walks
-- the edges of every dataset: sources that would form a cycle together are refused, even if
-- priorities would never show both edges at once.
CREATE FUNCTION registry.edge_check() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  child_type smallint;
  parent_type smallint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM registry.hierarchy_edge
    WHERE hierarchy_id = NEW.hierarchy_id AND child_id = NEW.child_id
      AND dataset_id = NEW.dataset_id AND valid = NEW.valid
      AND parent_id IS NOT DISTINCT FROM NEW.parent_id)
  THEN
    RETURN NULL;  -- changed or deleted later in the transaction; that version gets checked
  END IF;
  SELECT type_id INTO child_type FROM registry.entity WHERE id = NEW.child_id;
  SELECT type_id INTO parent_type FROM registry.entity WHERE id = NEW.parent_id;
  IF NOT EXISTS (
    SELECT 1 FROM registry.hierarchy_rule r
    WHERE r.hierarchy_id = NEW.hierarchy_id
      AND r.child_type_id IN (SELECT registry.entity_type_lineage(child_type))
      AND ((NEW.parent_id IS NULL AND r.parent_type_id IS NULL)
        OR r.parent_type_id IN (SELECT registry.entity_type_lineage(parent_type))))
  THEN
    RAISE EXCEPTION 'registry: hierarchy % does not allow a % under %',
      (SELECT code FROM registry.hierarchy WHERE id = NEW.hierarchy_id),
      (SELECT code FROM registry.entity_type WHERE id = child_type),
      coalesce((SELECT code FROM registry.entity_type WHERE id = parent_type), 'no parent (root)')
      USING ERRCODE = 'check_violation',
            DETAIL = format('child %s, parent %s',
              (SELECT key FROM registry.entity WHERE id = NEW.child_id),
              (SELECT key FROM registry.entity WHERE id = NEW.parent_id));
  END IF;
  IF NEW.parent_id IS NOT NULL AND EXISTS (
    WITH RECURSIVE up (node, span) AS (
      SELECT NEW.parent_id, NEW.valid
      UNION
      SELECT e.parent_id, u.span * e.valid
      FROM registry.hierarchy_edge e JOIN up u ON e.child_id = u.node
      WHERE e.hierarchy_id = NEW.hierarchy_id AND e.parent_id IS NOT NULL
        AND e.valid && u.span)
    SELECT 1 FROM up WHERE node = NEW.child_id)
  THEN
    RAISE EXCEPTION 'registry: edge % -> % in hierarchy % creates a cycle',
      (SELECT key FROM registry.entity WHERE id = NEW.child_id),
      (SELECT key FROM registry.entity WHERE id = NEW.parent_id),
      (SELECT code FROM registry.hierarchy WHERE id = NEW.hierarchy_id)
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER edge_check AFTER INSERT OR UPDATE ON registry.hierarchy_edge
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION registry.edge_check();
