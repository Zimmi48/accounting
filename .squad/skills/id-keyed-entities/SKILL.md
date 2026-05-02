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
- Keep the name-based UI boundary stable temporarily: frontend requests/responses can still use strings while backend helpers translate names to IDs (`find*ByName`, `find*NameById`).
- Convert stored ID-keyed membership back to name-keyed dictionaries only at the boundary where frontend calculations still expect names.
- Reuse one allocator (`nextId`) across related entity types when IDs share the same lookup space or appear together in other persisted identifiers.
- After the type refactor, regenerate codecs and validate compile/test/live-server seams before touching Evergreen work.

## Examples
- `src/Types.elm`: `BackendModel.groups : Dict GroupId StoredGroup`, `persons : Dict PersonId Person`, `Person.name`, and `StoredGroup.name`.
- `src/Backend.elm`: `storedGroupMembersForNames` converts `Dict String Share` UI payloads into `Dict PersonId Share`, and `groupMembersForFrontend` converts stored IDs back into names for `ListUserGroups`.
- `src/Codecs.elm`: integer-keyed dictionaries serialize through tuple lists rather than `Codec.dict`.

## Anti-Patterns
- Do not keep using entity names as persisted dictionary keys after adding numeric IDs; that duplicates identity models and invites drift.
- Do not leak ID-keyed membership dictionaries straight to the frontend when existing UI helpers still expect names.
- Do not start Evergreen generation just because runtime storage changed if the user has explicitly deferred migration work.
