#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class InputError(Exception):
    pass


@dataclass(frozen=True, order=True)
class LineSummary:
    year: int
    month: int
    day: int
    side: str
    group: str
    amount: int
    secondary_description: str
    status: str


@dataclass(frozen=True, order=True)
class SpendingSummary:
    description: str
    total: int
    status: str
    lines: tuple[LineSummary, ...]


@dataclass(frozen=True, order=True)
class GroupTransactionSummary:
    year: int
    month: int
    day: int
    date_text: str
    description: str
    total: int
    total_text: str
    share: int
    share_text: str


@dataclass(frozen=True)
class CurrentTransactionRecord:
    spending_id: int
    secondary_description: str
    group: str
    amount: int
    side: str
    status: str


@dataclass
class NormalizedExport:
    source_format: str
    person_names: tuple[str, ...]
    groups: dict[str, dict[str, int]]
    next_person_id: int
    logical_spendings: tuple[SpendingSummary, ...]
    active_group_transactions: dict[str, tuple[GroupTransactionSummary, ...]]
    totals_by_path: dict[str, dict[str, dict[str, int]]]
    integrity_issues: list[str]


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise InputError(message)


def expect_type(value: Any, expected_type: type, context: str) -> Any:
    expect(isinstance(value, expected_type), f"{context} must be a {expected_type.__name__}")
    return value


def load_json(path: Path) -> Any:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError as exc:
        raise InputError(f"{path} does not exist") from exc
    except json.JSONDecodeError as exc:
        raise InputError(f"{path} is not valid JSON: {exc}") from exc


def decode_tagged(value: Any, expected_tag: str | None = None, context: str = "value") -> tuple[str, list[Any]]:
    obj = expect_type(value, dict, context)
    tag = obj.get("tag")
    args = obj.get("args")
    expect(isinstance(tag, str), f"{context}.tag must be a string")
    expect(isinstance(args, list), f"{context}.args must be a list")
    if expected_tag is not None:
        expect(tag == expected_tag, f"{context} must have tag {expected_tag!r}, got {tag!r}")
    return tag, args


def decode_amount(value: Any, context: str) -> int:
    _, args = decode_tagged(value, "Amount", context)
    expect(len(args) == 1 and isinstance(args[0], int), f"{context} must be Amount(Int)")
    return args[0]


def decode_share(value: Any, context: str) -> int:
    _, args = decode_tagged(value, "Share", context)
    expect(len(args) == 1 and isinstance(args[0], int), f"{context} must be Share(Int)")
    return args[0]


def decode_status(value: Any, context: str) -> str:
    tag, args = decode_tagged(value, None, context)
    expect(tag in {"Active", "Deleted", "Replaced"}, f"{context} has unknown status {tag!r}")
    expect(args == [], f"{context} should not carry arguments")
    return tag


def decode_side(value: Any, context: str) -> str:
    tag, args = decode_tagged(value, None, context)
    expect(tag in {"CreditTransaction", "DebitTransaction"}, f"{context} has unknown side {tag!r}")
    expect(args == [], f"{context} should not carry arguments")
    return tag


def decode_string_keyed_dict(value: Any, value_decoder, context: str) -> dict[str, Any]:
    obj = expect_type(value, dict, context)
    return {
        key: value_decoder(item, f"{context}[{key!r}]")
        for key, item in sorted(obj.items())
    }


def decode_int_keyed_pairs(value: Any, context: str) -> list[tuple[int, Any]]:
    if isinstance(value, dict):
        try:
            return sorted((int(key), item) for key, item in value.items())
        except ValueError as exc:
            raise InputError(f"{context} keys must be integers") from exc

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


def detect_export_format(model: Any) -> str:
    obj = expect_type(model, dict, "export root")
    if "spendings" in obj:
        return "current"

    for _, year in decode_int_keyed_pairs(obj.get("years", []), "export root.years"):
        for _, month in decode_int_keyed_pairs(year.get("months", []), "year.months"):
            for _, day in decode_int_keyed_pairs(month.get("days", []), "month.days"):
                if isinstance(day, dict) and "spendings" in day:
                    return "legacy"
                if isinstance(day, dict) and "transactions" in day:
                    return "current"

    raise InputError("Could not detect export format")


def decode_transaction_id(value: Any, context: str) -> tuple[int, int, int, int]:
    obj = expect_type(value, dict, context)
    year = obj.get("year")
    month = obj.get("month")
    day = obj.get("day")
    index = obj.get("index")
    expect(all(isinstance(part, int) for part in [year, month, day, index]), f"{context} must contain integer year/month/day/index")
    return year, month, day, index


def decode_person_names_and_ids(model: dict[str, Any]) -> tuple[tuple[str, ...], dict[int, str]]:
    persons = expect_type(model.get("persons"), dict, "export root.persons")
    person_names = tuple(sorted(persons.keys()))
    id_to_name: dict[int, str] = {}

    for name, raw_person in persons.items():
        person = expect_type(raw_person, dict, f"person {name!r}")
        person_id = person.get("id")
        expect(isinstance(person_id, int), f"person {name!r}.id must be an integer")
        id_to_name[person_id] = name

    return person_names, id_to_name


def normalize_group_members_key(raw_key: str, id_to_name: dict[int, str]) -> str:
    if raw_key == "":
        return "(empty)"

    names: list[str] = []
    for raw_id in raw_key.split(","):
        raw_id = raw_id.strip()
        expect(raw_id != "", f"groupMembersKey {raw_key!r} contains an empty id")
        expect(raw_id.lstrip("-").isdigit(), f"groupMembersKey {raw_key!r} contains a non-integer id")
        person_id = int(raw_id)
        names.append(id_to_name.get(person_id, f"<unknown-person-id:{person_id}>"))

    return " + ".join(sorted(set(names)))


def normalize_totals(raw_totals: Any, id_to_name: dict[int, str], context: str) -> dict[str, dict[str, int]]:
    totals = expect_type(raw_totals, dict, context)
    normalized: dict[str, dict[str, int]] = {}

    for raw_members_key, raw_group_totals in sorted(totals.items()):
        members_key = normalize_group_members_key(raw_members_key, id_to_name)
        normalized[members_key] = decode_string_keyed_dict(
            raw_group_totals,
            decode_amount,
            f"{context}[{raw_members_key!r}]",
        )

    return normalized


def normalize_groups(model: dict[str, Any]) -> dict[str, dict[str, int]]:
    return decode_string_keyed_dict(
        model.get("groups"),
        lambda group, context: decode_string_keyed_dict(group, decode_share, context),
        "export root.groups",
    )


def format_date(year: int, month: int, day: int) -> str:
    return f"{year:04d}-{month:02d}-{day:02d}"


def render_listing_date(year: int, month: int, day: int) -> str:
    return f"{year}-{month}-{day}"


def view_amount(amount: int) -> str:
    sign = "-" if amount < 0 else ""
    absolute_amount = abs(amount)
    return f"{sign}{absolute_amount // 100}.{absolute_amount % 100:02d}"


def build_totals_by_path(model: dict[str, Any], id_to_name: dict[int, str]) -> dict[str, dict[str, dict[str, int]]]:
    years = decode_int_keyed_pairs(model.get("years"), "export root.years")
    totals_by_path = {
        "root": normalize_totals(model.get("totalGroupCredits"), id_to_name, "export root.totalGroupCredits")
    }

    for year, raw_year in years:
        year_obj = expect_type(raw_year, dict, f"year {year}")
        totals_by_path[f"year {year:04d}"] = normalize_totals(
            year_obj.get("totalGroupCredits"),
            id_to_name,
            f"year {year}.totalGroupCredits",
        )

        for month, raw_month in decode_int_keyed_pairs(year_obj.get("months"), f"year {year}.months"):
            month_obj = expect_type(raw_month, dict, f"month {year}-{month}")
            totals_by_path[f"month {year:04d}-{month:02d}"] = normalize_totals(
                month_obj.get("totalGroupCredits"),
                id_to_name,
                f"month {year}-{month}.totalGroupCredits",
            )

            for day, raw_day in decode_int_keyed_pairs(month_obj.get("days"), f"month {year}-{month}.days"):
                day_obj = expect_type(raw_day, dict, f"day {year}-{month}-{day}")
                totals_by_path[f"day {format_date(year, month, day)}"] = normalize_totals(
                    day_obj.get("totalGroupCredits"),
                    id_to_name,
                    f"day {year}-{month}-{day}.totalGroupCredits",
                )

    return totals_by_path


def sort_spending_lines(lines: list[LineSummary]) -> tuple[LineSummary, ...]:
    return tuple(sorted(lines))


def normalize_group_transaction_description(description: str, secondary_description: str) -> str:
    if secondary_description.strip() == "":
        return description

    return f"{description} — {secondary_description}"


def to_group_transaction_summary(
    year: int,
    month: int,
    day: int,
    description: str,
    total: int,
    side: str,
    amount: int,
) -> GroupTransactionSummary:
    share = -amount if side == "CreditTransaction" else amount
    total_text = view_amount(total)
    share_text = view_amount(share)
    return GroupTransactionSummary(
        year=year,
        month=month,
        day=day,
        date_text=render_listing_date(year, month, day),
        description=description,
        total=total,
        total_text=total_text,
        share=share,
        share_text=share_text,
    )


def finalize_group_transaction_lists(
    transactions_by_group: dict[str, list[GroupTransactionSummary]]
) -> dict[str, tuple[GroupTransactionSummary, ...]]:
    return {
        group: tuple(reversed(transactions))
        for group, transactions in sorted(transactions_by_group.items())
    }


def decode_current_transactions(model: dict[str, Any]) -> dict[tuple[int, int, int, int], CurrentTransactionRecord]:
    transactions_by_id: dict[tuple[int, int, int, int], CurrentTransactionRecord] = {}
    years = decode_int_keyed_pairs(model.get("years"), "export root.years")

    for year, raw_year in years:
        year_obj = expect_type(raw_year, dict, f"year {year}")
        for month, raw_month in decode_int_keyed_pairs(year_obj.get("months"), f"year {year}.months"):
            month_obj = expect_type(raw_month, dict, f"month {year}-{month}")
            for day, raw_day in decode_int_keyed_pairs(month_obj.get("days"), f"month {year}-{month}.days"):
                day_obj = expect_type(raw_day, dict, f"day {year}-{month}-{day}")
                transactions = expect_type(day_obj.get("transactions"), list, f"day {year}-{month}-{day}.transactions")

                for index, raw_transaction in enumerate(transactions):
                    context = f"transaction {format_date(year, month, day)}[{index}]"
                    transaction = expect_type(raw_transaction, dict, context)
                    spending_id = transaction.get("spendingId")
                    expect(isinstance(spending_id, int), f"{context}.spendingId must be an integer")
                    transaction_id = (year, month, day, index)
                    transactions_by_id[transaction_id] = CurrentTransactionRecord(
                        spending_id=spending_id,
                        secondary_description=expect_type(
                            transaction.get("secondaryDescription"),
                            str,
                            f"{context}.secondaryDescription",
                        ),
                        group=expect_type(transaction.get("group"), str, f"{context}.group"),
                        amount=decode_amount(transaction.get("amount"), f"{context}.amount"),
                        side=decode_side(transaction.get("side"), f"{context}.side"),
                        status=decode_status(transaction.get("status"), f"{context}.status"),
                    )

    return transactions_by_id


def normalize_legacy_spendings(model: dict[str, Any]) -> tuple[SpendingSummary, ...]:
    normalized: list[SpendingSummary] = []
    years = decode_int_keyed_pairs(model.get("years"), "export root.years")

    for year, raw_year in years:
        year_obj = expect_type(raw_year, dict, f"year {year}")
        for month, raw_month in decode_int_keyed_pairs(year_obj.get("months"), f"year {year}.months"):
            month_obj = expect_type(raw_month, dict, f"month {year}-{month}")
            for day, raw_day in decode_int_keyed_pairs(month_obj.get("days"), f"month {year}-{month}.days"):
                day_obj = expect_type(raw_day, dict, f"day {year}-{month}-{day}")
                spendings = expect_type(day_obj.get("spendings"), list, f"day {year}-{month}-{day}.spendings")

                for index, raw_spending in enumerate(spendings):
                    context = f"legacy spending {format_date(year, month, day)}[{index}]"
                    spending = expect_type(raw_spending, dict, context)
                    status = decode_status(spending.get("status"), f"{context}.status")
                    lines: list[LineSummary] = []

                    for group, amount in decode_string_keyed_dict(spending.get("credits"), decode_amount, f"{context}.credits").items():
                        lines.append(
                            LineSummary(
                                year=year,
                                month=month,
                                day=day,
                                side="credit",
                                group=group,
                                amount=amount,
                                secondary_description="",
                                status=status,
                            )
                        )

                    for group, amount in decode_string_keyed_dict(spending.get("debits"), decode_amount, f"{context}.debits").items():
                        lines.append(
                            LineSummary(
                                year=year,
                                month=month,
                                day=day,
                                side="debit",
                                group=group,
                                amount=amount,
                                secondary_description="",
                                status=status,
                            )
                        )

                    normalized.append(
                        SpendingSummary(
                            description=expect_type(spending.get("description"), str, f"{context}.description"),
                            total=decode_amount(spending.get("total"), f"{context}.total"),
                            status=status,
                            lines=sort_spending_lines(lines),
                        )
                    )

    return tuple(sorted(normalized))


def normalize_legacy_active_group_transactions(model: dict[str, Any]) -> dict[str, tuple[GroupTransactionSummary, ...]]:
    transactions_by_group: dict[str, list[GroupTransactionSummary]] = {}
    years = decode_int_keyed_pairs(model.get("years"), "export root.years")

    for year, raw_year in years:
        year_obj = expect_type(raw_year, dict, f"year {year}")
        for month, raw_month in decode_int_keyed_pairs(year_obj.get("months"), f"year {year}.months"):
            month_obj = expect_type(raw_month, dict, f"month {year}-{month}")
            for day, raw_day in decode_int_keyed_pairs(month_obj.get("days"), f"month {year}-{month}.days"):
                day_obj = expect_type(raw_day, dict, f"day {year}-{month}-{day}")
                spendings = expect_type(day_obj.get("spendings"), list, f"day {year}-{month}-{day}.spendings")

                for index, raw_spending in enumerate(spendings):
                    context = f"legacy spending {format_date(year, month, day)}[{index}]"
                    spending = expect_type(raw_spending, dict, context)
                    status = decode_status(spending.get("status"), f"{context}.status")
                    if status != "Active":
                        continue

                    description = expect_type(spending.get("description"), str, f"{context}.description")
                    total = decode_amount(spending.get("total"), f"{context}.total")

                    for group, amount in decode_string_keyed_dict(spending.get("credits"), decode_amount, f"{context}.credits").items():
                        transactions_by_group.setdefault(group, []).append(
                            to_group_transaction_summary(
                                year=year,
                                month=month,
                                day=day,
                                description=description,
                                total=total,
                                side="CreditTransaction",
                                amount=amount,
                            )
                        )

                    for group, amount in decode_string_keyed_dict(spending.get("debits"), decode_amount, f"{context}.debits").items():
                        transactions_by_group.setdefault(group, []).append(
                            to_group_transaction_summary(
                                year=year,
                                month=month,
                                day=day,
                                description=description,
                                total=total,
                                side="DebitTransaction",
                                amount=amount,
                            )
                        )

    return finalize_group_transaction_lists(transactions_by_group)


def normalize_current_spendings(model: dict[str, Any]) -> tuple[tuple[SpendingSummary, ...], list[str]]:
    issues: list[str] = []
    transactions_by_id = decode_current_transactions(model)

    normalized: list[SpendingSummary] = []
    spendings = expect_type(model.get("spendings"), list, "export root.spendings")
    referenced_transaction_ids: Counter[tuple[int, int, int, int]] = Counter()

    for spending_id, raw_spending in enumerate(spendings):
        context = f"spending[{spending_id}]"
        spending = expect_type(raw_spending, dict, context)
        status = decode_status(spending.get("status"), f"{context}.status")
        lines: list[LineSummary] = []
        transaction_ids = expect_type(spending.get("transactionIds"), list, f"{context}.transactionIds")

        for index, raw_transaction_id in enumerate(transaction_ids):
            transaction_id = decode_transaction_id(raw_transaction_id, f"{context}.transactionIds[{index}]")
            referenced_transaction_ids[transaction_id] += 1
            transaction = transactions_by_id.get(transaction_id)

            if transaction is None:
                issues.append(f"{context} references missing transaction {transaction_id}")
                continue

            if transaction.spending_id != spending_id:
                issues.append(
                    f"{context} references transaction {transaction_id} owned by spending {transaction.spending_id}"
                )

            if transaction.status != status:
                issues.append(
                    f"{context} status {status} does not match transaction {transaction_id} status {transaction.status}"
                )

            lines.append(
                LineSummary(
                    year=transaction_id[0],
                    month=transaction_id[1],
                    day=transaction_id[2],
                    side="credit" if transaction.side == "CreditTransaction" else "debit",
                    group=transaction.group,
                    amount=transaction.amount,
                    secondary_description=transaction.secondary_description,
                    status=transaction.status,
                )
            )

        normalized.append(
            SpendingSummary(
                description=expect_type(spending.get("description"), str, f"{context}.description"),
                total=decode_amount(spending.get("total"), f"{context}.total"),
                status=status,
                lines=sort_spending_lines(lines),
            )
        )

    unreferenced = sorted(transaction_id for transaction_id in transactions_by_id if referenced_transaction_ids[transaction_id] == 0)
    if unreferenced:
        issues.append(f"{len(unreferenced)} stored transactions are not referenced by any spending")

    duplicates = sorted(transaction_id for transaction_id, count in referenced_transaction_ids.items() if count > 1)
    if duplicates:
        issues.append(f"{len(duplicates)} transaction ids are referenced more than once")

    return tuple(sorted(normalized)), issues


def current_group_transaction_for_list(
    spendings: list[Any],
    transaction_id: tuple[int, int, int, int],
    transaction: CurrentTransactionRecord,
) -> tuple[str, GroupTransactionSummary] | None:
    if transaction.status != "Active":
        return None

    if transaction.spending_id < 0 or transaction.spending_id >= len(spendings):
        return None

    spending = expect_type(spendings[transaction.spending_id], dict, f"spending[{transaction.spending_id}]")
    spending_status = decode_status(spending.get("status"), f"spending[{transaction.spending_id}].status")
    if spending_status != "Active":
        return None

    description = normalize_group_transaction_description(
        expect_type(spending.get("description"), str, f"spending[{transaction.spending_id}].description"),
        transaction.secondary_description,
    )
    total = decode_amount(spending.get("total"), f"spending[{transaction.spending_id}].total")
    year, month, day, _ = transaction_id
    return (
        transaction.group,
        to_group_transaction_summary(
            year=year,
            month=month,
            day=day,
            description=description,
            total=total,
            side=transaction.side,
            amount=transaction.amount,
        ),
    )


def normalize_current_active_group_transactions(model: dict[str, Any]) -> dict[str, tuple[GroupTransactionSummary, ...]]:
    spendings = expect_type(model.get("spendings"), list, "export root.spendings")
    transactions_by_group: dict[str, list[GroupTransactionSummary]] = {}
    years = decode_int_keyed_pairs(model.get("years"), "export root.years")
    transactions_by_id = decode_current_transactions(model)

    for year, raw_year in years:
        year_obj = expect_type(raw_year, dict, f"year {year}")
        for month, raw_month in decode_int_keyed_pairs(year_obj.get("months"), f"year {year}.months"):
            month_obj = expect_type(raw_month, dict, f"month {year}-{month}")
            for day, raw_day in decode_int_keyed_pairs(month_obj.get("days"), f"month {year}-{month}.days"):
                day_obj = expect_type(raw_day, dict, f"day {year}-{month}-{day}")
                transactions = expect_type(day_obj.get("transactions"), list, f"day {year}-{month}-{day}.transactions")

                for index, _ in enumerate(transactions):
                    transaction_id = (year, month, day, index)
                    transaction = transactions_by_id[transaction_id]
                    group_transaction = current_group_transaction_for_list(spendings, transaction_id, transaction)
                    if group_transaction is None:
                        continue

                    group, summary = group_transaction
                    transactions_by_group.setdefault(group, []).append(summary)

    return finalize_group_transaction_lists(transactions_by_group)


def normalize_export(model: Any) -> NormalizedExport:
    export_root = expect_type(model, dict, "export root")
    source_format = detect_export_format(export_root)
    person_names, id_to_name = decode_person_names_and_ids(export_root)

    if source_format == "legacy":
        logical_spendings = normalize_legacy_spendings(export_root)
        active_group_transactions = normalize_legacy_active_group_transactions(export_root)
        integrity_issues: list[str] = []
    else:
        logical_spendings, integrity_issues = normalize_current_spendings(export_root)
        active_group_transactions = normalize_current_active_group_transactions(export_root)

    next_person_id = export_root.get("nextPersonId")
    expect(isinstance(next_person_id, int), "export root.nextPersonId must be an integer")

    return NormalizedExport(
        source_format=source_format,
        person_names=person_names,
        groups=normalize_groups(export_root),
        next_person_id=next_person_id,
        logical_spendings=logical_spendings,
        active_group_transactions=active_group_transactions,
        totals_by_path=build_totals_by_path(export_root, id_to_name),
        integrity_issues=integrity_issues,
    )


def render_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def render_line(line: LineSummary) -> str:
    parts = [
        format_date(line.year, line.month, line.day),
        line.side,
        line.group,
        str(line.amount),
    ]
    if line.secondary_description:
        parts.append(f"“{line.secondary_description}”")
    if line.status != "Active":
        parts.append(f"[{line.status}]")
    return " | ".join(parts)


def render_spending(spending: SpendingSummary) -> str:
    if spending.lines:
        line_text = "; ".join(render_line(line) for line in spending.lines)
    else:
        line_text = "(no resolved lines)"
    return f"{spending.description!r} total={spending.total} status={spending.status} :: {line_text}"


def render_group_transaction(transaction: GroupTransactionSummary) -> str:
    return (
        f"{transaction.date_text} | {transaction.description!r} | "
        f"share={transaction.share_text} | total={transaction.total_text}"
    )


def first_group_transaction_difference(
    before: tuple[GroupTransactionSummary, ...],
    after: tuple[GroupTransactionSummary, ...],
) -> list[str]:
    max_length = max(len(before), len(after))
    for index in range(max_length):
        before_transaction = before[index] if index < len(before) else None
        after_transaction = after[index] if index < len(after) else None
        if before_transaction != after_transaction:
            details = [
                f"      first differing row index: {index}",
                f"        before: {render_group_transaction(before_transaction) if before_transaction is not None else '(no row)'}",
                f"        after:  {render_group_transaction(after_transaction) if after_transaction is not None else '(no row)'}",
            ]
            if before_transaction is not None and after_transaction is not None:
                if before_transaction.description != after_transaction.description:
                    details.append("        note: description composition differs")
                if before_transaction.share_text != after_transaction.share_text:
                    details.append("        note: rendered share/sign differs")
                if before_transaction.total_text != after_transaction.total_text:
                    details.append("        note: rendered total differs")
            return details

    return []


def collect_mapping_diffs(section: str, before: Any, after: Any) -> list[str]:
    diffs: list[str] = []

    def walk(path: list[str], left: Any, right: Any) -> None:
        if isinstance(left, dict) and isinstance(right, dict):
            left_keys = set(left.keys())
            right_keys = set(right.keys())
            for key in sorted(left_keys - right_keys):
                diffs.append(f"{section} {' / '.join(path + [str(key)])}: only in before = {render_json(left[key])}")
            for key in sorted(right_keys - left_keys):
                diffs.append(f"{section} {' / '.join(path + [str(key)])}: only in after = {render_json(right[key])}")
            for key in sorted(left_keys & right_keys):
                walk(path + [str(key)], left[key], right[key])
            return

        if left != right:
            diffs.append(
                f"{section} {' / '.join(path)}: before = {render_json(left)}, after = {render_json(right)}"
            )

    walk([], before, after)
    return diffs


def spending_similarity(before: SpendingSummary, after: SpendingSummary) -> tuple[int, int, int]:
    before_dates = {(line.year, line.month, line.day) for line in before.lines}
    after_dates = {(line.year, line.month, line.day) for line in after.lines}
    before_groups = {(line.side, line.group) for line in before.lines}
    after_groups = {(line.side, line.group) for line in after.lines}

    score = 0
    if before.description == after.description:
        score += 4
    if before.total == after.total:
        score += 3
    if before.status == after.status:
        score += 2
    if len(before.lines) == len(after.lines):
        score += 1
    score += len(before_dates & after_dates)
    score += len(before_groups & after_groups)
    return score, len(before.lines), len(after.lines)


def pair_changed_spendings(
    only_before: list[SpendingSummary], only_after: list[SpendingSummary]
) -> tuple[list[tuple[SpendingSummary, SpendingSummary]], list[SpendingSummary], list[SpendingSummary]]:
    remaining_after = list(only_after)
    paired: list[tuple[SpendingSummary, SpendingSummary]] = []
    leftovers_before: list[SpendingSummary] = []

    for candidate in only_before:
        best_index = -1
        best_score = (0, 0, 0)
        for index, other in enumerate(remaining_after):
            score = spending_similarity(candidate, other)
            if score > best_score:
                best_score = score
                best_index = index

        if best_index >= 0 and best_score[0] >= 5:
            paired.append((candidate, remaining_after.pop(best_index)))
        else:
            leftovers_before.append(candidate)

    return paired, leftovers_before, remaining_after


def spending_diff_lines(before: SpendingSummary, after: SpendingSummary) -> list[str]:
    lines: list[str] = []
    if before.description != after.description:
        lines.append(f"description: {before.description!r} -> {after.description!r}")
    if before.total != after.total:
        lines.append(f"total: {before.total} -> {after.total}")
    if before.status != after.status:
        lines.append(f"status: {before.status} -> {after.status}")

    before_counter = Counter(before.lines)
    after_counter = Counter(after.lines)
    only_before = list((before_counter - after_counter).elements())
    only_after = list((after_counter - before_counter).elements())

    for line in only_before:
        lines.append(f"line removed: {render_line(line)}")
    for line in only_after:
        lines.append(f"line added: {render_line(line)}")

    return lines


def append_group_transaction_counter_lines(
    report_lines: list[str],
    label: str,
    entries: Counter[GroupTransactionSummary],
) -> None:
    if not entries:
        return

    report_lines.append(f"      {label}:")
    for transaction in sorted(entries):
        count = entries[transaction]
        prefix = f"{count} × " if count > 1 else ""
        report_lines.append(f"        * {prefix}{render_group_transaction(transaction)}")


def compare_exports(before: NormalizedExport, after: NormalizedExport) -> tuple[list[str], bool]:
    report_lines: list[str] = []
    has_differences = False

    if before.integrity_issues:
        report_lines.append("Before export integrity warnings:")
        report_lines.extend(f"  - {issue}" for issue in before.integrity_issues)
        has_differences = True

    if after.integrity_issues:
        report_lines.append("After export integrity warnings:")
        report_lines.extend(f"  - {issue}" for issue in after.integrity_issues)
        has_differences = True

    person_before = set(before.person_names)
    person_after = set(after.person_names)
    if person_before != person_after:
        has_differences = True
        report_lines.append("Person-name differences:")
        for name in sorted(person_before - person_after):
            report_lines.append(f"  - only in before: {name}")
        for name in sorted(person_after - person_before):
            report_lines.append(f"  - only in after: {name}")

    if before.next_person_id != after.next_person_id:
        has_differences = True
        report_lines.append(
            f"nextPersonId differs: before={before.next_person_id}, after={after.next_person_id}"
        )

    group_diffs = collect_mapping_diffs("Group", before.groups, after.groups)
    if group_diffs:
        has_differences = True
        report_lines.append("Group differences:")
        report_lines.extend(f"  - {diff}" for diff in group_diffs)

    changed_group_transactions: list[
        tuple[
            str,
            tuple[GroupTransactionSummary, ...],
            tuple[GroupTransactionSummary, ...],
            Counter[GroupTransactionSummary],
            Counter[GroupTransactionSummary],
        ]
    ] = []
    for group in sorted(set(before.active_group_transactions) | set(after.active_group_transactions)):
        before_transactions = before.active_group_transactions.get(group, ())
        after_transactions = after.active_group_transactions.get(group, ())
        before_counter = Counter(before_transactions)
        after_counter = Counter(after_transactions)
        if before_transactions != after_transactions:
            changed_group_transactions.append(
                (
                    group,
                    before_transactions,
                    after_transactions,
                    before_counter - after_counter,
                    after_counter - before_counter,
                )
            )

    if changed_group_transactions:
        has_differences = True
        report_lines.append("Active group transaction differences:")
        for group, before_transactions, after_transactions, only_before, only_after in changed_group_transactions:
            report_lines.append(f"  - group {group!r}:")
            if Counter(before_transactions) == Counter(after_transactions):
                report_lines.append("      listing order differs")
            report_lines.extend(first_group_transaction_difference(before_transactions, after_transactions))
            append_group_transaction_counter_lines(report_lines, "only in before", only_before)
            append_group_transaction_counter_lines(report_lines, "only in after", only_after)

    totals_diffs = collect_mapping_diffs("Totals", before.totals_by_path, after.totals_by_path)
    if totals_diffs:
        has_differences = True
        report_lines.append("Aggregated totalGroupCredits differences:")
        report_lines.extend(f"  - {diff}" for diff in totals_diffs)

    before_counter = Counter(before.logical_spendings)
    after_counter = Counter(after.logical_spendings)
    only_before = sorted((before_counter - after_counter).elements())
    only_after = sorted((after_counter - before_counter).elements())

    paired, leftovers_before, leftovers_after = pair_changed_spendings(only_before, only_after)

    if paired or leftovers_before or leftovers_after:
        has_differences = True
        report_lines.append("Logical spending differences:")

        for original, changed in paired:
            report_lines.append(f"  - possible changed spending:")
            report_lines.append(f"      before: {render_spending(original)}")
            report_lines.append(f"      after:  {render_spending(changed)}")
            for detail in spending_diff_lines(original, changed):
                report_lines.append(f"        * {detail}")

        for spending in leftovers_before:
            report_lines.append(f"  - only in before: {render_spending(spending)}")

        for spending in leftovers_after:
            report_lines.append(f"  - only in after: {render_spending(spending)}")

    return report_lines, has_differences


def build_summary(before: NormalizedExport, after: NormalizedExport) -> list[str]:
    return [
        "Semantic export comparison",
        f"- before format: {before.source_format}",
        f"- after format: {after.source_format}",
        f"- person names: {len(before.person_names)} before / {len(after.person_names)} after",
        f"- groups: {len(before.groups)} before / {len(after.groups)} after",
        f"- logical spendings: {len(before.logical_spendings)} before / {len(after.logical_spendings)} after",
        (
            "- active group transactions: "
            f"{sum(len(transactions) for transactions in before.active_group_transactions.values())} before / "
            f"{sum(len(transactions) for transactions in after.active_group_transactions.values())} after "
            f"across {len(before.active_group_transactions)} before-group lists / "
            f"{len(after.active_group_transactions)} after-group lists"
        ),
        f"- total snapshots: {len(before.totals_by_path)} before / {len(after.totals_by_path)} after",
    ]


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare two JSON exports semantically. The first file is typically the "
            "pre-migration export from main/production, and the second file is the "
            "post-migration export from the current branch."
        )
    )
    parser.add_argument("before", type=Path, help="JSON export captured before the migration")
    parser.add_argument("after", type=Path, help="JSON export captured after the migration")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    try:
        before = normalize_export(load_json(args.before))
        after = normalize_export(load_json(args.after))
    except InputError as exc:
        print(f"Input error: {exc}", file=sys.stderr)
        return 2

    summary_lines = build_summary(before, after)
    details, has_differences = compare_exports(before, after)

    print("\n".join(summary_lines))
    print()

    if has_differences:
        print("Differences detected.")
        print()
        print("\n".join(details))
        return 1

    print("No semantic differences detected.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
