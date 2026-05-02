---
name: "id-keyed-entities"
description: "Refactoring Lamdera entities to store numeric IDs internally while preserving name-based frontend boundaries"
domain: "data-modeling"
confidence: "high"
source: "earned"
---

## Context
Use this when a Lamdera model needs durable numeric IDs for stored entities, but the existing UI messages and forms still speak in human-readable names. This lets backend storage stop depending on names as dictionary keys before a larger protocol or Evergreen migration phase is approved.

## Patterns
- Move persisted root dictionaries to `Dict IdType Record`, and add `name` inside each stored record.
- If nested membership maps currently key by name, convert them to `Dict ChildId value` so all durable relationships use IDs end-to-end.
- If a record already lives in `Dict IdType Record`, do not also persist the same `id` inside the record unless another subsystem truly needs that field independent of the dictionary key.
- Keep the name-based UI boundary stable temporarily: frontend requests/responses can still use strings while backend helpers translate names to IDs (`find*ByName`, `find*NameById`).
- When a name lookup still needs to feed ID-routed backend logic, return `(Id, Record)` from the lookup or recover the id from `Dict.toList`; do not reintroduce redundant `record.id` reads just to satisfy callers.
- Convert stored ID-keyed membership back to name-keyed dictionaries only at the boundary where frontend calculations still expect names.
- Reuse one allocator (`nextId`) across related entity types when IDs share the same lookup space or appear together in other persisted identifiers.
- After the type refactor, regenerate codecs and validate compile/test/live-server seams before touching Evergreen work.

## Examples
- `src/Types.elm`: `BackendModel.groups : Dict GroupId StoredGroup`, `persons : Dict PersonId Person`, `Person.name`, and `StoredGroup.name`.
- `src/Backend.elm`: `storedGroupMembersForNames` converts `Dict String Share` UI payloads into `Dict PersonId Share`, and `groupMembersForFrontend` converts stored IDs back into names for `ListUserGroups`.
- `src/Backend.elm`: after removing redundant `Person.id` and `StoredGroup.id`, `findGroupByName` returns `( GroupId, StoredGroup )` and `findPersonIdByName` scans `Dict.toList` so helpers like `groupIdForName` and `updateGroupByName` keep using the authoritative dict key.
- `src/Codecs.elm`: integer-keyed dictionaries serialize through tuple lists rather than `Codec.dict`.

## Anti-Patterns
- Do not keep using entity names as persisted dictionary keys after adding numeric IDs; that duplicates identity models and invites drift.
- Do not keep both `Dict GroupId StoredGroup` and `StoredGroup.id : GroupId` (same for persons) unless there is a demonstrated persistence or protocol need for both representations.
- Do not leak ID-keyed membership dictionaries straight to the frontend when existing UI helpers still expect names.
- Do not start Evergreen generation just because runtime storage changed if the user has explicitly deferred migration work.
