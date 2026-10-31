# SQL reference

Every name is schema-qualified, so the functions work whatever the caller's `search_path`. Functions that read a hierarchy take the instant explicitly; it defaults to `registry.as_of()`.

## Time

| Function | Returns | |
|---|---|---|
| `registry.as_of()` | `timestamptz` | The instant point-in-time reads use: the session setting `combu.as_of`, or now. |

## Types

| Function | Returns | |
|---|---|---|
| `registry.entity_type_descendants(type_code text)` | `SETOF smallint` | The type and all its subtypes. |
| `registry.entity_type_lineage(start_type smallint)` | `SETOF smallint` | The type and all its ancestors. |

## Hierarchies

| Function | Returns | |
|---|---|---|
| `registry.hierarchy_edges(hierarchy_code text, ts timestamptz)` | `(child_id, parent_id, dataset_id)` | Each child's edge in force at `ts`, from the highest-priority dataset that has one. The others build on it. |
| `registry.hierarchy_tree(hierarchy_code text, ts timestamptz, root_id bigint DEFAULT NULL)` | `(entity_id, parent_id, depth, path)` | The tree at `ts`, from its roots or from `root_id`. |
| `registry.entity_ancestors(start_id bigint, hierarchy_code text, ts timestamptz)` | `(entity_id, depth)` | Parent (depth 1), grandparent (depth 2), ... |
| `registry.entity_ancestor(start_id bigint, hierarchy_code text, type_code text, ts timestamptz)` | `bigint` | The nearest ancestor of a type (or a subtype of it), whatever the depth. |
| `registry.entity_descendants(start_id bigint, hierarchy_code text, ts timestamptz)` | `(entity_id, depth)` | Children (depth 1), grandchildren (depth 2), ... |

## Triggers

| Trigger | On | Checks |
|---|---|---|
| `entity_check` (`registry.entity_check()`) | `registry.entity`, before insert or type change | The type isn't abstract. |
| `edge_check` (`registry.edge_check()`) | `registry.hierarchy_edge`, deferred to commit | The parent and child types follow the hierarchy's rules, and the edge forms no cycle with any dataset's edges. |
| `registry.require_type(column, type, …)` | any attribute or relation table, attached by its owner | Each listed column references an entity of that type or a subtype. |

Attach `require_type` like this:

```sql
CREATE TRIGGER type_check BEFORE INSERT OR UPDATE ON registry.supply
FOR EACH ROW EXECUTE FUNCTION registry.require_type('machine_id', 'machine', 'site_id', 'site');
```

## Settings

| Setting | |
|---|---|
| `combu.as_of` | The instant for `registry.as_of()`, e.g. `'2019-06-01'`; empty or unset means now. |
