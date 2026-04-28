#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class InputError(Exception):
    pass


@dataclass(frozen=True)
class SpendingRecord:
    spending_id: int
    total: int
    status: str
    transaction_ids: tuple[tuple[int, int, int, int], ...]


@dataclass(frozen=True)
class TransactionRecord:
    transaction_id: tuple[int, int, int, int]
    spending_id: int
    group: str
    amount: int
    side: str
    group_members_key: str
    group_members: frozenset[str]
    status: str


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise InputError(message)


def expect_type(value: Any, expected_type: type, context: str) -> Any:
    expect(isinstance(value, expected_type), f"{context} must be a {expected_type.__name__}")
    return value


def decode_tagged(value: Any, context: str, expected_tag: str | None = None) -> tuple[str, list[Any]]:
    obj = expect_type(value, dict, context)
    tag = obj.get("tag")
    args = obj.get("args")
    expect(isinstance(tag, str), f"{context}.tag must be a string")
    expect(isinstance(args, list), f"{context}.args must be a list")
    if expected_tag is not None:
        expect(tag == expected_tag, f"{context} must have tag {expected_tag!r}, got {tag!r}")
    return tag, args


def decode_amount(value: Any, context: str) -> int:
    _, args = decode_tagged(value, context, "Amount")
    expect(len(args) == 1 and isinstance(args[0], int), f"{context} must be Amount(Int)")
    return args[0]


def decode_status(value: Any, context: str) -> str:
    tag, args = decode_tagged(value, context)
    expect(tag in {"Active", "Deleted", "Replaced"}, f"{context} has unknown status {tag!r}")
    expect(args == [], f"{context} should not carry arguments")
    return tag


def decode_side(value: Any, context: str) -> str:
    tag, args = decode_tagged(value, context)
    expect(tag in {"CreditTransaction", "DebitTransaction"}, f"{context} has unknown side {tag!r}")
    expect(args == [], f"{context} should not carry arguments")
    return tag


def decode_transaction_id(value: Any, context: str) -> tuple[int, int, int, int]:
    obj = expect_type(value, dict, context)
    year = obj.get("year")
    month = obj.get("month")
    day = obj.get("day")
    index = obj.get("index")
    expect(
        all(isinstance(part, int) for part in [year, month, day, index]),
        f"{context} must contain integer year/month/day/index",
    )
    return (year, month, day, index)


def decode_string_set(value: Any, context: str) -> set[str]:
    items = expect_type(value, list, context)
    result = set()
    for index, item in enumerate(items):
        expect(isinstance(item, str), f"{context}[{index}] must be a string")
        result.add(item)
    return result


def decode_int_keyed_pairs(value: Any, context: str) -> list[tuple[int, Any]]:
    pairs = expect_type(value, list, context)
    decoded: list[tuple[int, Any]] = []
    for index, pair in enumerate(pairs):
        pair_context = f"{context}[{index}]"
        pair_list = expect_type(pair, list, pair_context)
        expect(len(pair_list) == 2, f"{pair_context} must contain exactly two items")
        key, item = pair_list
        expect(isinstance(key, int), f"{pair_context}[0] must be an integer")
        decoded.append((key, item))
    decoded.sort(key=lambda item: item[0])
    return decoded


def load_json(path: Path) -> Any:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError as exc:
        raise InputError(f"{path} does not exist") from exc
    except json.JSONDecodeError as exc:
        raise InputError(f"{path} is not valid JSON: {exc}") from exc


def detect_current_export(model: Any) -> dict[str, Any]:
    obj = expect_type(model, dict, "export root")
    expect("spendings" in obj and "years" in obj, "export root does not look like the current backend model")
    return obj


def normalize_totals(raw_totals: Any, context: str) -> dict[str, dict[str, int]]:
    totals_obj = expect_type(raw_totals, dict, context)
    normalized: dict[str, dict[str, int]] = {}
    for group_members_key, raw_group_totals in sorted(totals_obj.items()):
        expect(isinstance(group_members_key, str), f"{context} keys must be strings")
        group_totals_obj = expect_type(raw_group_totals, dict, f"{context}[{group_members_key!r}]")
        group_totals: dict[str, int] = {}
        for group, raw_amount in sorted(group_totals_obj.items()):
            expect(isinstance(group, str), f"{context}[{group_members_key!r}] keys must be strings")
            group_totals[group] = decode_amount(raw_amount, f"{context}[{group_members_key!r}][{group!r}]")
        normalized[group_members_key] = group_totals
    return normalized


def canonicalize_totals(totals: dict[str, dict[str, int]]) -> dict[str, dict[str, int]]:
    canonical: dict[str, dict[str, int]] = {}
    for group_members_key, group_totals in sorted(totals.items()):
        non_zero = {group: amount for group, amount in sorted(group_totals.items()) if amount != 0}
        if non_zero:
            canonical[group_members_key] = non_zero
    return canonical


def encode_amount(value: int) -> dict[str, Any]:
    return {"tag": "Amount", "args": [value]}


def encode_totals(totals: dict[str, dict[str, int]]) -> dict[str, dict[str, Any]]:
    return {
        group_members_key: {group: encode_amount(amount) for group, amount in group_totals.items()}
        for group_members_key, group_totals in canonicalize_totals(totals).items()
    }


def add_group_credit(totals: dict[str, dict[str, int]], group_members_key: str, group: str, amount: int) -> None:
    groups = totals.setdefault(group_members_key, {})
    groups[group] = groups.get(group, 0) + amount
    if groups[group] == 0:
        del groups[group]
    if not groups:
        del totals[group_members_key]


def json_compact(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def compare_lists(name: str, expected: list[str], stored: list[str], issues: list[str]) -> None:
    if expected != stored:
        issues.append(f"{name} mismatch: stored {stored}, expected {expected}")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate derived totals and person membership sets in a Lamdera accounting export. "
            "The input must be a full /json export from the current backend model."
        )
    )
    parser.add_argument("input", type=Path, help="Path to a full exported backend JSON file")
    parser.add_argument(
        "--write-fixed",
        type=Path,
        help=(
            "Write a corrected copy of the export to this path. "
            "Only derived fields are rewritten: totalGroupCredits at every level and persons.*.belongsTo."
        ),
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Allow --write-fixed to overwrite an existing file",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()

    try:
        model = detect_current_export(load_json(args.input))
        issues, fixed_model, fix_applied = validate_and_optionally_fix(model, args.write_fixed is not None)
    except InputError as exc:
        print(f"Input error: {exc}", file=sys.stderr)
        return 2

    if args.write_fixed is not None and fix_applied:
        if args.write_fixed.exists() and not args.overwrite:
            print(
                f"Refusing to overwrite existing file: {args.write_fixed} (pass --overwrite to allow it)",
                file=sys.stderr,
            )
            return 2

        with args.write_fixed.open("w", encoding="utf-8") as handle:
            json.dump(fixed_model, handle, indent=2, ensure_ascii=False)
            handle.write("\n")

    print_report(args.input, issues, args.write_fixed, fix_applied)
    return 1 if issues else 0


def validate_and_optionally_fix(model: dict[str, Any], apply_fix: bool) -> tuple[list[str], dict[str, Any], bool]:
    issues: list[str] = []
    fixed_model = json.loads(json.dumps(model))
    path_nodes: dict[str, dict[str, Any]] = {"root": fixed_model}
    stored_totals_by_path: dict[str, dict[str, dict[str, int]]] = {}
    all_transactions: list[TransactionRecord] = []

    spendings_raw = expect_type(model.get("spendings"), list, "export root.spendings")
    spendings: dict[int, SpendingRecord] = {}
    for spending_id, raw_spending in enumerate(spendings_raw):
        spending_obj = expect_type(raw_spending, dict, f"spendings[{spending_id}]")
        transaction_ids_raw = expect_type(
            spending_obj.get("transactionIds"),
            list,
            f"spendings[{spending_id}].transactionIds",
        )
        spending = SpendingRecord(
            spending_id=spending_id,
            total=decode_amount(spending_obj.get("total"), f"spendings[{spending_id}].total"),
            status=decode_status(spending_obj.get("status"), f"spendings[{spending_id}].status"),
            transaction_ids=tuple(
                decode_transaction_id(
                    transaction_id,
                    f"spendings[{spending_id}].transactionIds[{index}]",
                )
                for index, transaction_id in enumerate(transaction_ids_raw)
            ),
        )
        spendings[spending_id] = spending

    stored_totals_by_path["root"] = normalize_totals(model.get("totalGroupCredits"), "export root.totalGroupCredits")

    years = decode_int_keyed_pairs(model.get("years"), "export root.years")
    years_fixed = decode_int_keyed_pairs(fixed_model.get("years"), "fixed export root.years")
    expect(
        [year for year, _ in years] == [year for year, _ in years_fixed],
        "fixed model years layout changed unexpectedly",
    )

    for (year, raw_year), (_, fixed_year) in zip(years, years_fixed, strict=True):
        year_key = f"year {year:04d}"
        year_obj = expect_type(raw_year, dict, f"year {year}")
        fixed_year_obj = expect_type(fixed_year, dict, f"fixed year {year}")
        path_nodes[year_key] = fixed_year_obj
        stored_totals_by_path[year_key] = normalize_totals(year_obj.get("totalGroupCredits"), f"{year_key}.totalGroupCredits")

        months = decode_int_keyed_pairs(year_obj.get("months"), f"{year_key}.months")
        fixed_months = decode_int_keyed_pairs(fixed_year_obj.get("months"), f"fixed {year_key}.months")
        expect(
            [month for month, _ in months] == [month for month, _ in fixed_months],
            f"fixed model months layout changed unexpectedly for {year_key}",
        )

        for (month, raw_month), (_, fixed_month) in zip(months, fixed_months, strict=True):
            month_key = f"month {year:04d}-{month:02d}"
            month_obj = expect_type(raw_month, dict, f"month {year}-{month}")
            fixed_month_obj = expect_type(fixed_month, dict, f"fixed month {year}-{month}")
            path_nodes[month_key] = fixed_month_obj
            stored_totals_by_path[month_key] = normalize_totals(
                month_obj.get("totalGroupCredits"),
                f"{month_key}.totalGroupCredits",
            )

            days = decode_int_keyed_pairs(month_obj.get("days"), f"{month_key}.days")
            fixed_days = decode_int_keyed_pairs(fixed_month_obj.get("days"), f"fixed {month_key}.days")
            expect(
                [day for day, _ in days] == [day for day, _ in fixed_days],
                f"fixed model days layout changed unexpectedly for {month_key}",
            )

            for (day, raw_day), (_, fixed_day) in zip(days, fixed_days, strict=True):
                day_key = f"day {year:04d}-{month:02d}-{day:02d}"
                day_obj = expect_type(raw_day, dict, f"day {year}-{month}-{day}")
                fixed_day_obj = expect_type(fixed_day, dict, f"fixed day {year}-{month}-{day}")
                path_nodes[day_key] = fixed_day_obj
                stored_totals_by_path[day_key] = normalize_totals(
                    day_obj.get("totalGroupCredits"),
                    f"{day_key}.totalGroupCredits",
                )

                transactions = expect_type(day_obj.get("transactions"), list, f"{day_key}.transactions")
                for index, raw_transaction in enumerate(transactions):
                    transaction_obj = expect_type(raw_transaction, dict, f"{day_key}.transactions[{index}]")
                    all_transactions.append(
                        TransactionRecord(
                            transaction_id=(year, month, day, index),
                            spending_id=expect_type(
                                transaction_obj.get("spendingId"),
                                int,
                                f"{day_key}.transactions[{index}].spendingId",
                            ),
                            group=expect_type(
                                transaction_obj.get("group"),
                                str,
                                f"{day_key}.transactions[{index}].group",
                            ),
                            amount=decode_amount(
                                transaction_obj.get("amount"),
                                f"{day_key}.transactions[{index}].amount",
                            ),
                            side=decode_side(
                                transaction_obj.get("side"),
                                f"{day_key}.transactions[{index}].side",
                            ),
                            group_members_key=expect_type(
                                transaction_obj.get("groupMembersKey"),
                                str,
                                f"{day_key}.transactions[{index}].groupMembersKey",
                            ),
                            group_members=frozenset(
                                decode_string_set(
                                    transaction_obj.get("groupMembers"),
                                    f"{day_key}.transactions[{index}].groupMembers",
                                )
                            ),
                            status=decode_status(
                                transaction_obj.get("status"),
                                f"{day_key}.transactions[{index}].status",
                            ),
                        )
                    )

    transaction_by_id = {transaction.transaction_id: transaction for transaction in all_transactions}
    actual_transaction_ids_by_spending: dict[int, list[tuple[int, int, int, int]]] = defaultdict(list)
    transactions_by_spending: dict[int, list[TransactionRecord]] = defaultdict(list)
    for transaction in all_transactions:
        actual_transaction_ids_by_spending[transaction.spending_id].append(transaction.transaction_id)
        transactions_by_spending[transaction.spending_id].append(transaction)

    for spending_id, spending in spendings.items():
        if len(spending.transaction_ids) != len(set(spending.transaction_ids)):
            issues.append(f"spending {spending_id} has duplicate transactionIds")

        actual_ids = sorted(actual_transaction_ids_by_spending.get(spending_id, []))
        referenced_ids = sorted(spending.transaction_ids)
        if actual_ids != referenced_ids:
            issues.append(
                f"spending {spending_id} transactionIds do not match transactions stored with spendingId={spending_id}: "
                f"stored {referenced_ids}, actual {actual_ids}"
            )

        for transaction_id in spending.transaction_ids:
            if transaction_id not in transaction_by_id:
                issues.append(f"spending {spending_id} references missing transaction {transaction_id}")
                continue
            transaction = transaction_by_id[transaction_id]
            if transaction.spending_id != spending_id:
                issues.append(
                    f"spending {spending_id} references transaction {transaction_id} "
                    f"but that transaction points to spending {transaction.spending_id}"
                )

        spending_transactions = transactions_by_spending.get(spending_id, [])
        active_transactions = [transaction for transaction in spending_transactions if transaction.status == "Active"]
        active_credits = sum(transaction.amount for transaction in active_transactions if transaction.side == "CreditTransaction")
        active_debits = sum(transaction.amount for transaction in active_transactions if transaction.side == "DebitTransaction")

        if spending.status == "Active":
            if not active_transactions:
                issues.append(f"active spending {spending_id} has no active transactions")
            if active_credits != active_debits or active_credits != spending.total:
                issues.append(
                    f"active spending {spending_id} total mismatch: "
                    f"stored total={spending.total}, active credits={active_credits}, active debits={active_debits}"
                )
        elif active_transactions:
            issues.append(
                f"inactive spending {spending_id} still has active transactions: "
                f"{[transaction.transaction_id for transaction in active_transactions]}"
            )

    for spending_id in sorted(set(transactions_by_spending) - set(spendings)):
        issues.append(f"transactions exist for missing spending {spending_id}")

    expected_totals_by_path: dict[str, dict[str, dict[str, int]]] = {path: {} for path in stored_totals_by_path}
    expected_belongs_to: dict[str, set[str]] = defaultdict(set)

    for transaction in all_transactions:
        spending = spendings.get(transaction.spending_id)
        if spending is None:
            continue
        if spending.status != "Active" or transaction.status != "Active":
            continue

        signed_amount = transaction.amount if transaction.side == "CreditTransaction" else -transaction.amount
        for path in (
            "root",
            f"year {transaction.transaction_id[0]:04d}",
            f"month {transaction.transaction_id[0]:04d}-{transaction.transaction_id[1]:02d}",
            f"day {transaction.transaction_id[0]:04d}-{transaction.transaction_id[1]:02d}-{transaction.transaction_id[2]:02d}",
        ):
            add_group_credit(expected_totals_by_path[path], transaction.group_members_key, transaction.group, signed_amount)

        for person_name in transaction.group_members:
            expected_belongs_to[person_name].add(transaction.group_members_key)

    for path in sorted(stored_totals_by_path):
        stored = canonicalize_totals(stored_totals_by_path[path])
        expected = canonicalize_totals(expected_totals_by_path[path])
        if stored != expected:
            issues.append(f"{path} totalGroupCredits mismatch: stored {json_compact(stored)}, expected {json_compact(expected)}")

    persons_raw = expect_type(model.get("persons"), dict, "export root.persons")
    fixed_persons = expect_type(fixed_model.get("persons"), dict, "fixed export root.persons")
    for person_name in sorted(expected_belongs_to):
        if person_name not in persons_raw:
            issues.append(
                f"active transactions reference unknown person {person_name!r} in groupMembers, so belongsTo cannot be repaired for that name"
            )

    for person_name in sorted(persons_raw):
        person_obj = expect_type(persons_raw[person_name], dict, f"person {person_name!r}")
        fixed_person_obj = expect_type(fixed_persons[person_name], dict, f"fixed person {person_name!r}")
        stored_belongs_to = sorted(
            decode_string_set(person_obj.get("belongsTo"), f"person {person_name!r}.belongsTo")
        )
        expected_for_person = sorted(expected_belongs_to.get(person_name, set()))
        compare_lists(f"person {person_name!r}.belongsTo", expected_for_person, stored_belongs_to, issues)
        if apply_fix:
            fixed_person_obj["belongsTo"] = expected_for_person

    fix_applied = False
    if apply_fix:
        for path, node in path_nodes.items():
            expected = expected_totals_by_path[path]
            if canonicalize_totals(normalize_totals(node.get("totalGroupCredits"), f"fixed {path}.totalGroupCredits")) != canonicalize_totals(expected):
                fix_applied = True
            node["totalGroupCredits"] = encode_totals(expected)

        for person_name in sorted(persons_raw):
            person_obj = expect_type(persons_raw[person_name], dict, f"person {person_name!r}")
            fixed_person_obj = expect_type(fixed_persons[person_name], dict, f"fixed person {person_name!r}")
            stored_belongs_to = sorted(
                decode_string_set(person_obj.get("belongsTo"), f"person {person_name!r}.belongsTo")
            )
            expected_for_person = sorted(expected_belongs_to.get(person_name, set()))
            if stored_belongs_to != expected_for_person:
                fix_applied = True
            fixed_person_obj["belongsTo"] = expected_for_person

    return issues, fixed_model, fix_applied


def print_report(input_path: Path, issues: list[str], fixed_path: Path | None, fix_applied: bool) -> None:
    print(f"Validated export: {input_path}")
    if not issues:
        print("No derived total or belongsTo mismatches found.")
        if fixed_path is not None:
            print("Nothing was written because the export was already clean.")
        return

    print(f"Found {len(issues)} issue(s):")
    for issue in issues:
        print(f"- {issue}")

    if fixed_path is None:
        print(
            "Run again with --write-fixed FIXED.json to write a corrected copy. "
            "The script only rewrites derived totals and persons.*.belongsTo."
        )
    elif fix_applied:
        print(f"Wrote corrected copy to {fixed_path}")
        print("Review that file, then import it via the app's /import route if it looks right.")
    else:
        print("No fixable derived-field mismatches were found, so no corrected copy was written.")


if __name__ == "__main__":
    raise SystemExit(main())
