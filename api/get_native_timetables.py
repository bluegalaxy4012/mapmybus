#!/usr/bin/env python3
"""
generat cu agent AI, momentan netestat complet
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unicodedata
import uuid
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import date
from difflib import SequenceMatcher
from itertools import zip_longest
from pathlib import Path
from typing import Any
from urllib.parse import quote, urljoin

import requests


DAY_TYPES = ("lv", "s", "d")
DAY_LABELS = {
    "lv": "Luni - Vineri",
    "s": "Sambata",
    "d": "Duminica",
}

CHISINAU_BASE_URL = "https://trolley.md/api"
IASI_PDF_URL = "https://iasitimetable.tranzy.ai/pdfs/track-{short}.pdf"
IASI_SCTP_ROUTES_URL = "https://www.aza.sctpiasi.ro/trasee"
IASI_SCTP_BASE_URL = "https://www.aza.sctpiasi.ro"
BOTOSANI_PDF_URL = (
    "https://www1.primariabt.ro/pdf/diverse/transport/microbus+autobus.pdf"
)
CTBUS_BASE_URL = "https://info.ctbus.ro/api/web/v2-6"
CTBUS_APP_KEY = "u1Mc,6L;M4kHE"
CTBUS_APP_VERSION = "0.0.0"


@dataclass
class BuildContext:
    args: argparse.Namespace
    output_dir: Path
    cache_dir: Path | None
    session: requests.Session
    records: list[dict[str, Any]] = field(default_factory=list)
    written_files: list[str] = field(default_factory=list)
    memo: dict[str, Any] = field(default_factory=dict)


@dataclass
class TimetableBuild:
    route: dict[str, Any]
    agency_id: str
    source: str
    source_url: str | None = None
    service_start: str = ""
    service_start_by_day: dict[str, str] = field(default_factory=dict)
    day_times: dict[str, list[list[str]]] = field(default_factory=dict)
    terminals: list[str] = field(default_factory=list)
    associations: dict[str, Any] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    skipped: bool = False


class NativeTimetableError(RuntimeError):
    pass


def main() -> int:
    args = parse_args()
    output_dir = args.output_dir.resolve()
    cache_dir = args.cache_dir.resolve() if args.cache_dir else None
    if not args.dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)
        if cache_dir:
            cache_dir.mkdir(parents=True, exist_ok=True)

    ctx = BuildContext(
        args=args,
        output_dir=output_dir,
        cache_dir=cache_dir,
        session=requests.Session(),
    )
    ctx.session.headers.update({"User-Agent": "mapmybus-native-timetable-builder/1.0"})

    agency_ids = split_csv_arg(args.agencies) or ["1", "2", "4", "6", "10"]
    if args.verify_samples and not args.route_ids and not args.route_shorts:
        print("verify-samples enabled: using known good and known bad sample routes")

    for agency_id in agency_ids:
        if agency_id == "1":
            generate_iasi(ctx)
        elif agency_id == "2":
            generate_cluj(ctx)
        elif agency_id == "4":
            generate_chisinau(ctx)
        elif agency_id == "6":
            generate_botosani(ctx)
        elif agency_id == "10":
            generate_constanta(ctx)
        else:
            print(f"agency {agency_id}: no native timetable source implemented")

    manifest = {
        "generated_at": date.today().isoformat(),
        "dry_run": bool(args.dry_run),
        "output_dir": str(output_dir),
        "records": ctx.records,
        "written_files": ctx.written_files,
    }
    manifest_path = output_dir / "native_timetables_manifest.json"
    if args.dry_run:
        print(f"dry-run: would write manifest {manifest_path}")
    else:
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"wrote manifest: {manifest_path}")

    written = len(ctx.written_files)
    skipped = sum(1 for record in ctx.records if record.get("skipped"))
    errors = sum(1 for record in ctx.records if record.get("errors"))
    print(
        f"done: {written} files, {len(ctx.records)} records, {skipped} skipped, {errors} with errors"
    )
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate native timetable CSVs and a route association manifest."
    )
    parser.add_argument(
        "--agencies",
        default="1,4,6,10",
        help="Comma-separated agency ids. Default: 1,4,6,10.",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        help="Directory containing agency*_routes/stops/trip_stops.json.",
    )
    parser.add_argument(
        "--agency10-data-dir",
        type=Path,
        help="Deprecated compatibility option. Prefer one --data-dir containing all agencies.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("csv"),
        help="CSV output directory. Default: ./csv.",
    )
    parser.add_argument(
        "--cache-dir",
        default="",
        help="HTTP cache directory. Default: disabled.",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Do not write CSVs or manifest."
    )
    parser.add_argument(
        "--verify-samples",
        action="store_true",
        help="Limit to researched sample routes and probe parsers/sources.",
    )
    parser.add_argument(
        "--route-ids",
        default="",
        help="Comma-separated local route ids to include.",
    )
    parser.add_argument(
        "--route-shorts",
        default="",
        help="Comma-separated route_short_name values to include.",
    )
    parser.add_argument(
        "--write-route-id-files",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Write agency{n}_route{route_id}_orar_{short}_{day}.csv files.",
    )
    parser.add_argument(
        "--write-legacy-short-files",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Write agency{n}_orar_{short}_{day}.csv files for unique short names.",
    )
    parser.add_argument(
        "--constanta-current-as-all-days",
        action="store_true",
        help=(
            "Unsafe CTBUS override: write the current stop timetable into lv/s/d files. "
            "By default CTBUS writes only today's bucket because schedules differ by day type."
        ),
    )
    parser.add_argument(
        "--botosani-expand-intervals",
        action=argparse.BooleanOptionalAction,
        default=True,
        help=(
            "Expand official Botosani frequency intervals into departure grids. "
            "Default: enabled, with manifest warnings because source trip ids are not published."
        ),
    )
    parser.add_argument(
        "--http-timeout",
        type=float,
        default=25.0,
        help="HTTP timeout in seconds. Default: 25.",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=8,
        help="Concurrent stop-time fetches for API sources. Default: 8.",
    )
    args = parser.parse_args()
    if args.cache_dir is not None and str(args.cache_dir).strip() == "":
        args.cache_dir = None
    elif args.cache_dir is not None:
        args.cache_dir = Path(args.cache_dir)
    return args


def split_csv_arg(value: str) -> list[str]:
    return [part.strip() for part in (value or "").split(",") if part.strip()]


def script_dir() -> Path:
    return Path(__file__).resolve().parent


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def find_data_file(ctx: BuildContext, agency_id: str, suffix: str) -> Path:
    filename = f"agency{agency_id}_{suffix}.json"
    candidates: list[Path] = []
    if agency_id == "10" and ctx.args.agency10_data_dir:
        candidates.append(ctx.args.agency10_data_dir)
    if ctx.args.data_dir:
        candidates.append(ctx.args.data_dir)

    base = script_dir()
    cwd = Path.cwd()
    candidates.extend(
        [
            base / "data",
            base.parent / "data",
            base.parent / "temp" / "modeltraining" / "data",
            base.parent / "temp" / "mapmybus" / "data",
            cwd / "data",
            cwd.parent / "modeltraining" / "data",
            cwd.parent / "mapmybus" / "data",
        ]
    )

    seen: set[Path] = set()
    for directory in candidates:
        directory = directory.expanduser().resolve()
        if directory in seen:
            continue
        seen.add(directory)
        path = directory / filename
        if path.exists():
            return path
    raise FileNotFoundError(f"could not find {filename}; pass --data-dir")


def load_routes(ctx: BuildContext, agency_id: str) -> list[dict[str, Any]]:
    routes = load_json(find_data_file(ctx, agency_id, "routes"))
    return [route for route in routes if route_matches_filters(ctx, route)]


def route_matches_filters(ctx: BuildContext, route: dict[str, Any]) -> bool:
    route_ids = set(split_csv_arg(ctx.args.route_ids))
    route_shorts = {part.upper() for part in split_csv_arg(ctx.args.route_shorts)}
    if route_ids and str(route.get("route_id")) not in route_ids:
        return False
    if (
        route_shorts
        and str(route.get("route_short_name", "")).upper() not in route_shorts
    ):
        return False
    return True


def apply_verify_samples(
    ctx: BuildContext, agency_id: str, routes: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    if not ctx.args.verify_samples or ctx.args.route_ids or ctx.args.route_shorts:
        return routes
    sample_ids_by_agency = {
        "1": {"41", "14", "10", "81", "87"},
        "2": set(),
        "4": {"9", "13", "38"},
        "6": {"1", "2", "3"},
        "10": set(),
    }
    sample_shorts_by_agency = {
        "1": {"1", "7", "28", "3", "101"},
        "2": {"1"},
        "4": set(),
        "6": {"101", "102", "102S"},
        "10": {"43C"},
    }
    ids = sample_ids_by_agency.get(agency_id, set())
    shorts = sample_shorts_by_agency.get(agency_id, set())
    if not ids and not shorts:
        return routes[:1]
    return [
        route
        for route in routes
        if str(route.get("route_id")) in ids
        or str(route.get("route_short_name", "")).upper() in {s.upper() for s in shorts}
    ]


def load_local_trip_endpoints(
    ctx: BuildContext, agency_id: str, route_id: str | int
) -> list[dict[str, Any]]:
    trip_stops = load_json(find_data_file(ctx, agency_id, "trip_stops"))
    stops = load_json(find_data_file(ctx, agency_id, "stops"))
    stop_names = {str(stop["stop_id"]): stop.get("stop_name", "") for stop in stops}
    prefix = f"{route_id}_"
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for item in trip_stops:
        trip_id = str(item.get("trip_id", ""))
        if trip_id.startswith(prefix):
            grouped[trip_id].append(item)

    endpoints: list[dict[str, Any]] = []
    for trip_id in sorted(grouped, key=trip_sort_key):
        rows = sorted(
            grouped[trip_id], key=lambda row: int(row.get("stop_sequence", 0))
        )
        if not rows:
            continue
        first = rows[0]
        last = rows[-1]
        endpoints.append(
            {
                "trip_id": trip_id,
                "direction_id": trip_id.split("_", 1)[1] if "_" in trip_id else "",
                "first_stop_id": first.get("stop_id"),
                "first_stop_name": stop_names.get(str(first.get("stop_id")), ""),
                "last_stop_id": last.get("stop_id"),
                "last_stop_name": stop_names.get(str(last.get("stop_id")), ""),
            }
        )

    unique: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    for endpoint in endpoints:
        key = (str(endpoint["first_stop_id"]), str(endpoint["direction_id"]))
        if key not in seen:
            unique.append(endpoint)
            seen.add(key)
    return unique


def trip_sort_key(trip_id: str) -> tuple[int, str]:
    try:
        suffix = trip_id.split("_", 1)[1]
        return int(suffix), suffix
    except (IndexError, ValueError):
        return 9999, trip_id


def route_short_counts(routes: list[dict[str, Any]]) -> Counter[str]:
    return Counter(str(route.get("route_short_name", "")) for route in routes)


def safe_file_part(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value.strip()).strip("_") or "route"


def is_safe_legacy_short(value: str) -> bool:
    return (
        bool(value)
        and "/" not in value
        and "\x00" not in value
        and value not in {".", ".."}
    )


def write_timetable_build(
    ctx: BuildContext,
    build: TimetableBuild,
    short_counts: Counter[str],
) -> None:
    route = build.route
    agency_id = build.agency_id
    route_id = str(route.get("route_id"))
    short = str(route.get("route_short_name", ""))
    safe_short = safe_file_part(short)
    unique_short = short_counts.get(short, 0) == 1
    outputs: dict[str, list[str]] = {}

    for day_type in DAY_TYPES:
        direction_times = build.day_times.get(day_type, [])
        if not direction_times or not any(direction_times):
            continue
        service_start = build.service_start_by_day.get(day_type, build.service_start)
        rows = make_timetable_rows(
            route=route,
            day_type=day_type,
            service_start=service_start,
            terminals=build.terminals,
            direction_times=direction_times,
        )
        paths: list[Path] = []
        if ctx.args.write_route_id_files:
            paths.append(
                ctx.output_dir
                / f"agency{agency_id}_route{route_id}_orar_{safe_short}_{day_type}.csv"
            )
        if (
            ctx.args.write_legacy_short_files
            and unique_short
            and is_safe_legacy_short(short)
        ):
            paths.append(
                ctx.output_dir / f"agency{agency_id}_orar_{short}_{day_type}.csv"
            )
        elif ctx.args.write_legacy_short_files and not unique_short:
            warn_once(
                build.warnings,
                f"legacy short-name file skipped because route_short_name {short!r} is duplicated",
            )
        elif ctx.args.write_legacy_short_files and not is_safe_legacy_short(short):
            warn_once(
                build.warnings,
                f"legacy short-name file skipped because route_short_name {short!r} is not a safe file name",
            )

        outputs[day_type] = [str(path) for path in paths]
        for path in paths:
            if ctx.args.dry_run:
                print(f"dry-run: would write {path}")
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open("w", encoding="utf-8", newline="") as handle:
                    writer = csv.writer(handle)
                    writer.writerows(rows)
                print(f"saved: {path}")
                ctx.written_files.append(str(path))

    record = manifest_record(build)
    record["outputs"] = outputs
    ctx.records.append(record)


def write_raw_csv_text(
    ctx: BuildContext,
    route: dict[str, Any],
    agency_id: str,
    day_type: str,
    text: str,
    short_counts: Counter[str],
    source_url: str,
) -> dict[str, list[str]]:
    short = str(route.get("route_short_name", ""))
    route_id = str(route.get("route_id"))
    safe_short = safe_file_part(short)
    unique_short = short_counts.get(short, 0) == 1
    paths: list[Path] = []
    if ctx.args.write_route_id_files:
        paths.append(
            ctx.output_dir
            / f"agency{agency_id}_route{route_id}_orar_{safe_short}_{day_type}.csv"
        )
    if (
        ctx.args.write_legacy_short_files
        and unique_short
        and is_safe_legacy_short(short)
    ):
        paths.append(ctx.output_dir / f"agency{agency_id}_orar_{short}_{day_type}.csv")

    clean_text = normalize_raw_csv_text(text)
    for path in paths:
        if ctx.args.dry_run:
            print(f"dry-run: would write {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(clean_text, encoding="utf-8")
            print(f"saved: {path}")
            ctx.written_files.append(str(path))
    return {day_type: [str(path) for path in paths]}


def normalize_raw_csv_text(text: str) -> str:
    rows = [
        row
        for row in csv.reader(io.StringIO(text))
        if row and any(cell.strip() for cell in row)
    ]
    if not rows:
        return ""

    metadata_keys = (
        "route_long_name",
        "service_name",
        "service_start",
        "in_stop_name",
        "out_stop_name",
    )
    normalized: list[list[str]] = []
    remaining = rows[:]
    for index, row in enumerate(remaining):
        if len(row) == 1:
            match = re.match(
                r"^(route_long_name|service_name|service_start|in_stop_name|out_stop_name)\s+(.+)$",
                row[0].strip(),
            )
            if match:
                remaining[index] = [match.group(1), match.group(2).strip()]

    for key in metadata_keys:
        if remaining and remaining[0][0].strip() == key:
            row = remaining.pop(0)
            normalized.append([row[0].strip(), row[1].strip() if len(row) > 1 else ""])
        else:
            normalized.append([key, ""])

    for row in remaining:
        clean_row = [cell.strip() for cell in row]
        if len(clean_row) < 2:
            clean_row.append("")
        elif len(clean_row) > 2:
            clean_row = [clean_row[0], " ".join(cell for cell in clean_row[1:] if cell)]
        normalized.append(clean_row[:2])

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerows(normalized)
    return output.getvalue()


def make_timetable_rows(
    route: dict[str, Any],
    day_type: str,
    service_start: str,
    terminals: list[str],
    direction_times: list[list[str]],
) -> list[list[str]]:
    first_terminal = terminals[0] if terminals else ""
    second_terminal = terminals[1] if len(terminals) > 1 else ""
    rows = [
        ["route_long_name", route.get("route_long_name", "")],
        ["service_name", DAY_LABELS[day_type]],
        ["service_start", service_start or date.today().strftime("%d.%m.%Y")],
        ["in_stop_name", first_terminal],
        ["out_stop_name", second_terminal],
    ]
    first_times = direction_times[0] if direction_times else []
    second_times = direction_times[1] if len(direction_times) > 1 else []
    for first, second in zip_longest(first_times, second_times, fillvalue=""):
        rows.append([first, second])
    return rows


def manifest_record(build: TimetableBuild) -> dict[str, Any]:
    route = build.route
    return {
        "agency_id": build.agency_id,
        "route_id": route.get("route_id"),
        "route_short_name": route.get("route_short_name"),
        "route_long_name": route.get("route_long_name"),
        "source": build.source,
        "source_url": build.source_url,
        "service_start": build.service_start,
        "service_start_by_day": build.service_start_by_day,
        "terminals": build.terminals,
        "associations": build.associations,
        "warnings": build.warnings,
        "errors": build.errors,
        "skipped": build.skipped,
    }


def record_skipped(
    ctx: BuildContext,
    agency_id: str,
    route: dict[str, Any],
    source: str,
    reason: str,
    source_url: str | None = None,
    associations: dict[str, Any] | None = None,
    warnings: list[str] | None = None,
) -> None:
    build = TimetableBuild(
        agency_id=agency_id,
        route=route,
        source=source,
        source_url=source_url,
        associations=associations or {},
        warnings=warnings or [],
        errors=[reason],
        skipped=True,
    )
    ctx.records.append(manifest_record(build))
    print(
        f"skip agency {agency_id} route {route.get('route_short_name')} "
        f"({route.get('route_id')}): {reason}"
    )


def warn_once(warnings: list[str], text: str) -> None:
    if text not in warnings:
        warnings.append(text)


def get_bytes(
    ctx: BuildContext,
    url: str,
    headers: dict[str, str] | None = None,
    attempts: int = 2,
) -> tuple[bytes, requests.Response | None]:
    cache_path = cache_file_for_url(ctx, url)
    if cache_path and cache_path.exists():
        return cache_path.read_bytes(), None

    last_exc: Exception | None = None
    for attempt in range(attempts):
        try:
            response = ctx.session.get(
                url, headers=headers, timeout=ctx.args.http_timeout
            )
            response.raise_for_status()
            content = response.content
            if cache_path and not ctx.args.dry_run:
                cache_path.parent.mkdir(parents=True, exist_ok=True)
                cache_path.write_bytes(content)
            return content, response
        except Exception as exc:  # requests exceptions vary by transport backend
            last_exc = exc
            if attempt + 1 < attempts:
                time.sleep(0.5 * (attempt + 1))
    raise NativeTimetableError(f"GET failed for {url}: {last_exc}")


def get_json(ctx: BuildContext, url: str) -> Any:
    content, _ = get_bytes(ctx, url)
    data = json.loads(content.decode("utf-8"))
    if isinstance(data, dict) and "data" in data and len(data) <= 2:
        return data["data"]
    return data


def cache_file_for_url(ctx: BuildContext, url: str) -> Path | None:
    if not ctx.cache_dir:
        return None
    digest = hashlib.sha1(url.encode("utf-8")).hexdigest()
    return ctx.cache_dir / f"{digest}.bin"


def download_pdf(ctx: BuildContext, url: str) -> bytes:
    content, response = get_bytes(ctx, url)
    content_type = (
        response.headers.get("Content-Type", "") if response is not None else ""
    )
    if not content.startswith(b"%PDF"):
        raise NativeTimetableError(
            f"not a PDF: {url} (content-type={content_type or 'cached/unknown'})"
        )
    return content


def require_pdftotext() -> None:
    if not shutil.which("pdftotext"):
        raise NativeTimetableError("pdftotext was not found; install poppler-utils")


def pdf_to_text(pdf_bytes: bytes, layout: bool = False) -> str:
    require_pdftotext()
    with tempfile.NamedTemporaryFile(suffix=".pdf") as handle:
        handle.write(pdf_bytes)
        handle.flush()
        cmd = ["pdftotext", "-enc", "UTF-8"]
        if layout:
            cmd.append("-layout")
        cmd.extend([handle.name, "-"])
        completed = subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True,
        )
    return completed.stdout


def pdf_to_bbox_xml(pdf_bytes: bytes) -> str:
    require_pdftotext()
    with tempfile.NamedTemporaryFile(suffix=".pdf") as handle:
        handle.write(pdf_bytes)
        handle.flush()
        completed = subprocess.run(
            ["pdftotext", "-enc", "UTF-8", "-bbox-layout", handle.name, "-"],
            check=True,
            capture_output=True,
            text=True,
        )
    return completed.stdout


def generate_cluj(ctx: BuildContext) -> None:
    agency_id = "2"
    routes = apply_verify_samples(ctx, agency_id, load_routes(ctx, agency_id))
    short_counts = route_short_counts(
        load_json(find_data_file(ctx, agency_id, "routes"))
    )
    for route in routes:
        short = str(route.get("route_short_name", ""))
        all_outputs: dict[str, list[str]] = {}
        errors: list[str] = []
        local_endpoints = load_local_trip_endpoints(ctx, agency_id, route["route_id"])
        for day_type in DAY_TYPES:
            scrape_short = cluj_scrape_short(short)
            url = f"https://ctpcj.ro/orare/csv/orar_{scrape_short}_{day_type}.csv"
            try:
                content, response = get_bytes(ctx, url)
                content_type = (
                    response.headers.get("Content-Type", "") if response else ""
                )
                text = content.decode("utf-8-sig")
                if (
                    response is not None
                    and "csv" not in content_type.lower()
                    and "," not in text[:200]
                ):
                    raise NativeTimetableError(
                        f"unexpected content-type {content_type!r}"
                    )
                outputs = write_raw_csv_text(
                    ctx, route, agency_id, day_type, text, short_counts, url
                )
                all_outputs.update(outputs)
            except Exception as exc:
                errors.append(f"{day_type}: {exc}")

        if not all_outputs:
            try:
                build = build_cluj_from_pdf(ctx, route, local_endpoints)
                write_timetable_build(ctx, build, short_counts)
                continue
            except Exception as exc:
                errors.append(f"pdf: {exc}")

        ctx.records.append(
            {
                "agency_id": agency_id,
                "route_id": route.get("route_id"),
                "route_short_name": short,
                "route_long_name": route.get("route_long_name"),
                "source": "ctpcj_csv",
                "source_url": "https://ctpcj.ro/orare/csv/",
                "service_start": "",
                "terminals": [],
                "associations": {
                    "local_route_id": route.get("route_id"),
                    "route_short_name": short,
                    "scrape_short_name": cluj_scrape_short(short),
                    "local_endpoints": local_endpoints,
                },
                "warnings": [],
                "errors": errors,
                "skipped": not bool(all_outputs),
                "outputs": all_outputs,
            }
        )


def cluj_scrape_short(short: str) -> str:
    return "39CREIC" if short == "39C" else short


def build_cluj_from_pdf(
    ctx: BuildContext,
    route: dict[str, Any],
    local_endpoints: list[dict[str, Any]],
) -> TimetableBuild:
    short = str(route.get("route_short_name", ""))
    scrape_short = quote(cluj_scrape_short(short), safe="")
    url = f"https://ctpcj.ro/orare/pdf/orar_{scrape_short}.pdf"
    pdf_bytes = download_pdf(ctx, url)
    parsed = parse_cluj_pdf_timetable(pdf_to_text(pdf_bytes, layout=True))
    if not any(any(parsed["day_times"][day_type]) for day_type in DAY_TYPES):
        raise NativeTimetableError("official PDF did not contain exact departures")

    return TimetableBuild(
        agency_id="2",
        route=route,
        source="ctpcj_pdf_fallback",
        source_url=url,
        service_start=next(
            (
                parsed["service_start_by_day"].get(day)
                for day in DAY_TYPES
                if parsed["service_start_by_day"].get(day)
            ),
            "",
        ),
        service_start_by_day=parsed["service_start_by_day"],
        day_times=parsed["day_times"],
        terminals=parsed["terminals"],
        associations={
            "local_route_id": route.get("route_id"),
            "route_short_name": short,
            "scrape_short_name": cluj_scrape_short(short),
            "local_endpoints": local_endpoints,
            "pdf_terminals": parsed["terminals"],
        },
        warnings=[
            "CTP Cluj CSV endpoint was unavailable; generated from the official CTP PDF."
        ],
    )


def parse_cluj_pdf_timetable(text: str) -> dict[str, Any]:
    if re.search(r"\d{1,2}:\d{2}\s*[-–]", text) or re.search(
        r"\b\d+\s*[-–]\s*\d+\s*min\b", text, re.I
    ):
        raise NativeTimetableError(
            "official PDF contains frequency intervals; not parsed as exact departures"
        )

    lines = text.splitlines()
    day_headers: list[tuple[int, str, str]] = []
    for index, line in enumerate(lines):
        day_type = cluj_day_type_from_heading(line)
        if day_type:
            day_headers.append((index, day_type, cluj_service_start_from_heading(line)))
    if not day_headers:
        raise NativeTimetableError("official PDF has no lv/s/d headings")

    day_times: dict[str, list[list[str]]] = {day: [] for day in DAY_TYPES}
    service_start_by_day: dict[str, str] = {}
    terminals: list[str] = []

    for header_index, day_type, service_start in day_headers:
        next_index = next(
            (
                candidate_index
                for candidate_index, _, _ in day_headers
                if candidate_index > header_index
            ),
            len(lines),
        )
        section_lines = lines[header_index + 1 : next_index]
        parsed_section = parse_cluj_pdf_day_section(section_lines)
        if not parsed_section:
            continue
        if service_start:
            service_start_by_day[day_type] = service_start
        if not terminals and parsed_section["terminals"]:
            terminals = parsed_section["terminals"]
        day_times[day_type] = parsed_section["times"]

    return {
        "day_times": day_times,
        "service_start_by_day": service_start_by_day,
        "terminals": terminals,
    }


def cluj_day_type_from_heading(line: str) -> str:
    normalized = normalize_name(re.sub(r"\(.*", "", line))
    if normalized.startswith("luni vineri"):
        return "lv"
    if normalized.startswith("sambata"):
        return "s"
    if normalized.startswith("duminica"):
        return "d"
    return ""


def cluj_service_start_from_heading(line: str) -> str:
    match = re.search(r"valabil\s+din\s+([0-9]{1,2}\.[0-9]{1,2}\.[0-9]{4})", line, re.I)
    return match.group(1) if match else ""


def parse_cluj_pdf_day_section(lines: list[str]) -> dict[str, Any] | None:
    header_index = next(
        (index for index, line in enumerate(lines) if "Plecari" in line), -1
    )
    if header_index < 0:
        return None

    header_line = lines[header_index]
    header_matches = list(
        re.finditer(r"Plecari\s+(.+?)(?=\s{2,}Plecari\s+|$)", header_line)
    )
    if not header_matches:
        return None

    terminals = [match.group(1).strip() for match in header_matches[:2]]
    centers = [(match.start() + match.end()) / 2 for match in header_matches[:2]]
    times_by_direction: list[set[str]] = [set() for _ in centers]

    for line in lines[header_index + 1 :]:
        if "Powered by" in line:
            break
        time_matches = list(re.finditer(r"\b\d{1,2}:\d{2}\b", line))
        split_index = (
            len(time_matches) // 2
            if len(centers) == 2
            and len(time_matches) > 1
            and len(time_matches) % 2 == 0
            else -1
        )
        for match_index, time_match in enumerate(time_matches):
            value = clean_hhmm(time_match.group(0))
            if not value:
                continue
            if split_index >= 0:
                direction_index = 0 if match_index < split_index else 1
            elif len(centers) == 1:
                direction_index = 0
            else:
                direction_index = min(
                    range(len(centers)),
                    key=lambda index: abs(time_match.start() - centers[index]),
                )
            times_by_direction[direction_index].add(value)

    return {
        "terminals": terminals,
        "times": [sorted(values) for values in times_by_direction],
    }


def generate_iasi(ctx: BuildContext) -> None:
    agency_id = "1"
    routes = apply_verify_samples(ctx, agency_id, load_routes(ctx, agency_id))
    all_routes = load_json(find_data_file(ctx, agency_id, "routes"))
    short_counts = route_short_counts(all_routes)
    for route in routes:
        short = str(route.get("route_short_name", ""))
        pdf_short = quote(short.lower(), safe="")
        url = IASI_PDF_URL.format(short=pdf_short)
        try:
            endpoints = load_local_trip_endpoints(ctx, agency_id, route["route_id"])
            if not endpoints:
                record_skipped(
                    ctx, agency_id, route, "iasi_pdf", "no local trip endpoints", url
                )
                continue
            build = build_iasi_from_pdf(ctx, route, endpoints, url)
            if build is None:
                build = build_iasi_from_amtpi(ctx, route, endpoints)
            write_timetable_build(ctx, build, short_counts)
        except Exception as exc:
            record_skipped(ctx, agency_id, route, "iasi_pdf", str(exc), url)


def build_iasi_from_pdf(
    ctx: BuildContext,
    route: dict[str, Any],
    endpoints: list[dict[str, Any]],
    url: str,
) -> TimetableBuild | None:
    pdf_errors: list[str] = []
    try:
        pdf = download_pdf(ctx, url)
    except Exception as exc:
        pdf_errors.append(f"download/simple source failed: {exc}")
        return None

    parsers = [
        ("iasi_pdf_pdftotext_simple", parse_iasi_pdf_sections),
        ("iasi_pdf_pdftotext_bbox_layout", parse_iasi_pdf_sections_bbox),
    ]
    for source_name, parser in parsers:
        try:
            sections = parser(pdf)
            build = build_iasi_from_sections(
                route, endpoints, sections, source_name, url
            )
            if pdf_errors:
                build.warnings.extend(pdf_errors)
            return build
        except Exception as exc:
            pdf_errors.append(f"{source_name}: {exc}")
    return None


def build_iasi_from_sections(
    route: dict[str, Any],
    endpoints: list[dict[str, Any]],
    sections: list[dict[str, Any]],
    source_name: str,
    source_url: str,
) -> TimetableBuild:
    if not sections:
        raise NativeTimetableError("PDF has no parseable station sections")

    selected = select_iasi_endpoint_sections(endpoints, sections)
    warnings: list[str] = []
    direction_times: dict[str, list[list[str]]] = {day: [] for day in DAY_TYPES}
    terminals: list[str] = []
    associations: dict[str, Any] = {"local_endpoints": []}
    for endpoint, section, section_warning in selected:
        if section_warning:
            warnings.append(section_warning)
        terminals.append(endpoint.get("first_stop_name") or section["name"])
        associations["local_endpoints"].append(
            {
                **endpoint,
                "matched_pdf_station": section["name"],
                "matched_pdf_station_index": section["index"],
                "matched_pdf_parser": source_name,
            }
        )
        for day_type in DAY_TYPES:
            direction_times[day_type].append(section["days"].get(day_type, []))

    if not direction_times["lv"] or not any(
        any(day) for day in direction_times.values()
    ):
        raise NativeTimetableError("matched station sections contain no departures")

    return TimetableBuild(
        agency_id="1",
        route=route,
        source=source_name,
        source_url=source_url,
        service_start=date.today().strftime("%d.%m.%Y"),
        day_times=direction_times,
        terminals=terminals,
        associations=associations,
        warnings=warnings,
    )


def parse_iasi_pdf_sections(pdf_bytes: bytes) -> list[dict[str, Any]]:
    text = pdf_to_text(pdf_bytes, layout=False)
    matches = list(re.finditer(r"(?m)^STATIA\s+(.+?)\s*$", text))
    sections: list[dict[str, Any]] = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        name = " ".join(match.group(1).split())
        section_text = text[start:end]
        parsed = parse_iasi_station_section(section_text)
        parsed.update(
            {
                "name": name,
                "normalized_name": normalize_name(name),
                "index": index,
            }
        )
        sections.append(parsed)
    return sections


def parse_iasi_pdf_sections_bbox(pdf_bytes: bytes) -> list[dict[str, Any]]:
    xml_text = pdf_to_bbox_xml(pdf_bytes)
    root = ET.fromstring(xml_text)
    sections: list[dict[str, Any]] = []
    current_section: dict[str, Any] | None = None

    for page in xml_pages(root):
        words = bbox_words(page)
        station_name = bbox_station_name(words)
        if station_name:
            current_section = {
                "name": station_name,
                "normalized_name": normalize_name(station_name),
                "index": len(sections),
                "days": {day: [] for day in DAY_TYPES},
                "valid": True,
                "empty": True,
                "error": "",
            }
            sections.append(current_section)
        if current_section is None:
            continue

        page_days = parse_iasi_bbox_page_days(page, words)
        for day_type in DAY_TYPES:
            if page_days[day_type]:
                current_section["days"][day_type].extend(page_days[day_type])
                current_section["empty"] = False

    for section in sections:
        for day_type in DAY_TYPES:
            section["days"][day_type] = sorted(set(section["days"][day_type]))
    return sections


def xml_local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def xml_pages(root: ET.Element) -> list[ET.Element]:
    return [element for element in root.iter() if xml_local_name(element.tag) == "page"]


def bbox_words(page: ET.Element) -> list[dict[str, Any]]:
    words: list[dict[str, Any]] = []
    for element in page.iter():
        if xml_local_name(element.tag) != "word":
            continue
        text = "".join(element.itertext()).strip()
        if not text:
            continue
        x_min = float(element.attrib["xMin"])
        y_min = float(element.attrib["yMin"])
        x_max = float(element.attrib["xMax"])
        y_max = float(element.attrib["yMax"])
        words.append(
            {
                "text": text,
                "x_min": x_min,
                "y_min": y_min,
                "x_max": x_max,
                "y_max": y_max,
                "x_center": (x_min + x_max) / 2,
                "height": y_max - y_min,
            }
        )
    return words


def bbox_station_name(words: list[dict[str, Any]]) -> str:
    for word in sorted(words, key=lambda item: (item["y_min"], item["x_min"])):
        if normalize_plain_word(word["text"]) != "statia" or word["y_min"] > 80:
            continue
        same_line = [
            candidate
            for candidate in words
            if abs(candidate["y_min"] - word["y_min"]) < 4
            and candidate["x_min"] > word["x_max"]
        ]
        name = " ".join(
            candidate["text"]
            for candidate in sorted(same_line, key=lambda item: item["x_min"])
        )
        return " ".join(name.split())
    return ""


def normalize_plain_word(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    return re.sub(r"[^\w]+", "", value.lower(), flags=re.UNICODE)


def parse_iasi_bbox_page_days(
    page: ET.Element, words: list[dict[str, Any]]
) -> dict[str, list[str]]:
    days = {day: [] for day in DAY_TYPES}
    headers: list[dict[str, Any]] = []
    for word in words:
        day_type = normalize_day_label(word["text"])
        if day_type:
            headers.append({**word, "day_type": day_type})
    best_headers: dict[str, dict[str, Any]] = {}
    for header in sorted(headers, key=lambda item: item["y_min"]):
        best_headers.setdefault(header["day_type"], header)
    if any(day not in best_headers for day in DAY_TYPES):
        return days

    page_width = float(page.attrib.get("width", 595))
    ordered_headers = sorted(best_headers.values(), key=lambda item: item["x_min"])
    boundaries: dict[str, tuple[float, float]] = {}
    for index, header in enumerate(ordered_headers):
        left = 0.0 if index == 0 else header["x_min"]
        right = (
            page_width
            if index + 1 == len(ordered_headers)
            else ordered_headers[index + 1]["x_min"]
        )
        boundaries[header["day_type"]] = (left, right)

    for day_type in DAY_TYPES:
        left, right = boundaries[day_type]
        header_y = best_headers[day_type]["y_min"]
        column_words = [
            word
            for word in words
            if left <= word["x_center"] < right
            and word["y_min"] > header_y + 5
            and re.fullmatch(r"\d{1,2}", word["text"])
        ]
        hour_words = [
            word
            for word in column_words
            if word["height"] >= 12 and 0 <= int(word["text"]) <= 29
        ]
        hour_words.sort(key=lambda item: (item["y_min"], item["x_min"]))
        for index, hour_word in enumerate(hour_words):
            hour = int(hour_word["text"])
            start_y = hour_word["y_min"] - 5
            end_y = (
                hour_words[index + 1]["y_min"] - 5
                if index + 1 < len(hour_words)
                else 10_000
            )
            minute_words = [
                word
                for word in column_words
                if word["height"] < 12
                and start_y <= word["y_min"] < end_y
                and 0 <= int(word["text"]) <= 59
            ]
            for minute_word in sorted(
                minute_words, key=lambda item: (item["y_min"], item["x_min"])
            ):
                days[day_type].append(f"{hour % 24:02d}:{int(minute_word['text']):02d}")
    return days


def build_iasi_from_amtpi(
    ctx: BuildContext,
    route: dict[str, Any],
    endpoints: list[dict[str, Any]],
) -> TimetableBuild:
    route_url = iasi_sctp_route_url(ctx, str(route.get("route_short_name", "")))
    route_html = ""
    amtpi_url = ""
    sctp_warning = ""
    if route_url:
        route_html = get_bytes(ctx, route_url)[0].decode("utf-8", errors="replace")
        try:
            return build_iasi_from_sctp_html(route, endpoints, route_html, route_url)
        except NativeTimetableError as exc:
            sctp_warning = str(exc)
        amtpi_url = iasi_amtpi_url_from_sctp_page(route_html)
    if not amtpi_url:
        amtpi_url = iasi_amtpi_route_url(ctx, str(route.get("route_short_name", "")))
    if not amtpi_url:
        if route_url:
            suffix = f"; SCTP fallback rejected: {sctp_warning}" if sctp_warning else ""
            raise NativeTimetableError(
                f"PDF parsers failed and no AMTPI timetable page was found for SCTP page: {route_url}{suffix}"
            )
        raise NativeTimetableError(
            "PDF parsers failed and no SCTP/AMTPI route page was found"
        )

    amtpi_html = get_bytes(ctx, amtpi_url)[0].decode("utf-8", errors="replace")
    schedule = parse_iasi_amtpi_schedule(amtpi_html)
    if not any(schedule[day_type] for day_type in DAY_TYPES):
        image_urls = extract_amtpi_timetable_image_urls(amtpi_html)
        if image_urls:
            preview = ", ".join(image_urls[:4])
            suffix = " ..." if len(image_urls) > 4 else ""
            sctp_suffix = (
                f"; SCTP fallback rejected: {sctp_warning}" if sctp_warning else ""
            )
            raise NativeTimetableError(
                "AMTPI page exposes timetable image(s), not parseable HTML without OCR: "
                f"{amtpi_url}; images: {preview}{suffix}{sctp_suffix}"
            )
        raise NativeTimetableError(
            f"AMTPI page has no parseable departure tables: {amtpi_url}"
        )

    selected_endpoints = endpoints[:1] if len(endpoints) == 1 else endpoints[:2]
    direction_times: dict[str, list[list[str]]] = {day: [] for day in DAY_TYPES}
    terminals: list[str] = []
    associations: dict[str, Any] = {
        "sctp_route_url": route_url,
        "amtpi_url": amtpi_url,
        "local_endpoints": [],
    }
    warnings: list[str] = [
        "Iasi PDF source had no exact terminal departures; used an AMTPI route timetable."
    ]
    if sctp_warning:
        warnings.append(f"SCTP timetable fallback was rejected: {sctp_warning}")

    for endpoint_index, endpoint in enumerate(selected_endpoints):
        terminals.append(endpoint.get("first_stop_name", ""))
        match_by_day: dict[str, dict[str, Any] | None] = {}
        for day_type in DAY_TYPES:
            match, warning = best_amtpi_departure_block(
                endpoint,
                schedule[day_type],
                endpoint_index,
            )
            if warning:
                warn_once(warnings, warning)
            match_by_day[day_type] = match
            direction_times[day_type].append(match["times"] if match else [])

        associations["local_endpoints"].append(
            {
                **endpoint,
                "matched_amtpi_titles": {
                    day_type: (
                        match_by_day[day_type]["title"]
                        if match_by_day[day_type]
                        else None
                    )
                    for day_type in DAY_TYPES
                },
            }
        )

    if not any(any(direction_times[day_type]) for day_type in DAY_TYPES):
        raise NativeTimetableError(
            f"AMTPI page did not match any local terminal: {amtpi_url}"
        )

    return TimetableBuild(
        agency_id="1",
        route=route,
        source="iasi_amtpi_html_fallback",
        source_url=amtpi_url,
        service_start=date.today().strftime("%d.%m.%Y"),
        day_times=direction_times,
        terminals=terminals,
        associations=associations,
        warnings=warnings,
    )


def build_iasi_from_sctp_html(
    route: dict[str, Any],
    endpoints: list[dict[str, Any]],
    content: str,
    source_url: str,
) -> TimetableBuild:
    schedule = parse_iasi_sctp_schedule(content)
    if not any(schedule[day_type] for day_type in DAY_TYPES):
        raise NativeTimetableError("SCTP page has no exact departure table")

    selected_endpoints = endpoints[:1] if len(endpoints) == 1 else endpoints[:2]
    direction_times: dict[str, list[list[str]]] = {day: [] for day in DAY_TYPES}
    terminals: list[str] = []
    associations: dict[str, Any] = {
        "sctp_route_url": source_url,
        "local_endpoints": [],
    }
    missing_matches: list[str] = []

    for endpoint in selected_endpoints:
        endpoint_name = endpoint.get("first_stop_name", "")
        terminals.append(endpoint_name)
        match_by_day: dict[str, dict[str, Any] | None] = {}
        for day_type in DAY_TYPES:
            match = best_strict_departure_block(endpoint_name, schedule[day_type])
            match_by_day[day_type] = match
            direction_times[day_type].append(match["times"] if match else [])

        if not any(match_by_day.values()):
            missing_matches.append(endpoint_name)

        associations["local_endpoints"].append(
            {
                **endpoint,
                "matched_sctp_titles": {
                    day_type: (
                        match_by_day[day_type]["title"]
                        if match_by_day[day_type]
                        else None
                    )
                    for day_type in DAY_TYPES
                },
            }
        )

    if missing_matches:
        raise NativeTimetableError(
            "SCTP exact table terminal mismatch for local endpoint(s): "
            + ", ".join(name for name in missing_matches if name)
        )

    if not any(any(direction_times[day_type]) for day_type in DAY_TYPES):
        raise NativeTimetableError("SCTP page did not match any local terminal")

    return TimetableBuild(
        agency_id="1",
        route=route,
        source="iasi_sctp_html_exact_table",
        source_url=source_url,
        service_start=date.today().strftime("%d.%m.%Y"),
        day_times=direction_times,
        terminals=terminals,
        associations=associations,
        warnings=[
            "Iasi PDF source had no exact terminal departures; used the official SCTP HTML timetable table."
        ],
    )


def parse_iasi_sctp_schedule(content: str) -> dict[str, list[dict[str, Any]]]:
    schedule: dict[str, list[dict[str, Any]]] = {day: [] for day in DAY_TYPES}
    widget_starts = list(
        re.finditer(
            r'<div\s+class="track_widget\s+(?:prima-cursa|ultima-cursa)"', content
        )
    )
    for index, widget_match in enumerate(widget_starts):
        block_start = widget_match.start()
        block_end = (
            widget_starts[index + 1].start()
            if index + 1 < len(widget_starts)
            else content.find('<div class="track_details"', block_start)
        )
        if block_end < 0:
            block_end = len(content)
        block = content[block_start:block_end]
        parse_iasi_sctp_schedule_block(block, schedule)
    return schedule


def parse_iasi_sctp_schedule_block(
    block: str,
    schedule: dict[str, list[dict[str, Any]]],
) -> None:
    lines = [
        html_to_text_preserve_columns(match.group(1))
        for match in re.finditer(r"<p[^>]*>(.*?)</p>", block, re.S)
    ]
    lines = [line for line in lines if line.strip()]

    target_days: tuple[str, ...] = ()
    terminal_titles: list[str] = []
    terminal_centers: list[float] = []
    times_by_direction: list[list[str]] = [[], []]

    for line in lines:
        days = sctp_day_types_from_line(line)
        if days:
            target_days = days
            terminal_titles = []
            terminal_centers = []
            times_by_direction = [[], []]
            continue

        time_matches = list(re.finditer(r"\b\d{1,2}[:.]\d{2}\b", line))
        if target_days and not terminal_titles and not time_matches:
            terminal_titles = [
                part.strip()
                for part in re.split(r" {2,}", line.strip())
                if part.strip()
            ]
            if len(terminal_titles) >= 2:
                terminal_titles = terminal_titles[:2]
                terminal_centers = []
                search_from = 0
                for title in terminal_titles:
                    pos = line.find(title, search_from)
                    if pos < 0:
                        pos = search_from
                    terminal_centers.append(pos + len(title) / 2)
                    search_from = pos + len(title)
            continue

        if not target_days or len(terminal_titles) < 2 or not time_matches:
            continue

        for match_index, time_match in enumerate(time_matches[:2]):
            value = clean_hhmm(time_match.group(0).replace(".", ":"))
            if not value:
                continue
            if len(time_matches) >= 2:
                direction_index = match_index
            else:
                direction_index = min(
                    range(2),
                    key=lambda idx: abs(time_match.start() - terminal_centers[idx]),
                )
            times_by_direction[direction_index].append(value)

    if target_days and len(terminal_titles) >= 2 and any(times_by_direction):
        for day_type in target_days:
            for title, times in zip(terminal_titles, times_by_direction):
                clean_times = sorted(set(times))
                if clean_times:
                    schedule[day_type].append({"title": title, "times": clean_times})


def sctp_day_types_from_line(line: str) -> tuple[str, ...]:
    normalized = normalize_name(line)
    if "luni" in normalized and "vineri" in normalized:
        return ("lv",)
    if "sambata" in normalized and "duminica" in normalized:
        return ("s", "d")
    if "luni" in normalized and "duminica" in normalized:
        return DAY_TYPES
    return ()


def best_strict_departure_block(
    endpoint_name: str,
    blocks: list[dict[str, Any]],
) -> dict[str, Any] | None:
    target = normalize_departure_title(endpoint_name)
    best_block: dict[str, Any] | None = None
    best_score = 0.0
    for block in blocks:
        score = fuzzy_name_score(target, normalize_departure_title(block["title"]))
        if score > best_score:
            best_block = block
            best_score = score
    return best_block if best_block and best_score >= 0.55 else None


def html_to_text_preserve_columns(value: str) -> str:
    text = html.unescape(value).replace("\xa0", " ")
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    return text.strip()


def iasi_sctp_route_url(ctx: BuildContext, route_short_name: str) -> str:
    route_index = ctx.memo.get("iasi_sctp_route_index")
    if route_index is None:
        content = get_bytes(ctx, IASI_SCTP_ROUTES_URL)[0].decode(
            "utf-8", errors="replace"
        )
        route_index = parse_iasi_sctp_route_index(content)
        ctx.memo["iasi_sctp_route_index"] = route_index
    normalized = normalize_route_short(route_short_name)
    return route_index.get(normalized, "")


def iasi_amtpi_route_url(ctx: BuildContext, route_short_name: str) -> str:
    route_index = ctx.memo.get("iasi_amtpi_route_index")
    if route_index is None:
        content = get_bytes(ctx, "https://www.amtpi.ro/trasee/")[0].decode(
            "utf-8", errors="replace"
        )
        route_index = parse_iasi_amtpi_route_index(content)
        ctx.memo["iasi_amtpi_route_index"] = route_index
    return route_index.get(normalize_route_short(route_short_name), "")


def parse_iasi_sctp_route_index(content: str) -> dict[str, str]:
    route_index: dict[str, str] = {}
    for match in re.finditer(
        r'<a\s+[^>]*href="(/trasee/\d+/[^"]+)"[^>]*>(.*?)</a>', content, re.S
    ):
        href, inner_html = match.groups()
        short_match = re.search(
            r'<span[^>]*class="[^"]*track_number[^"]*"[^>]*>(.*?)</span>',
            inner_html,
            re.S,
        )
        if not short_match:
            continue
        short = html_to_text(short_match.group(1)).strip()
        if not short:
            continue
        url = urljoin(IASI_SCTP_BASE_URL, href)
        normalized = normalize_route_short(short)
        route_index.setdefault(normalized, url)
        if normalized.endswith("*"):
            route_index.setdefault(normalized.rstrip("*"), url)
    return route_index


def parse_iasi_amtpi_route_index(content: str) -> dict[str, str]:
    route_index: dict[str, str] = {}
    for href, label_html in re.findall(
        r'<a[^>]+href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', content, re.S
    ):
        if "www.amtpi.ro" not in href:
            continue
        label = html_to_text(label_html)
        codes = iasi_route_codes_from_label(label)
        if not codes:
            continue
        for code in codes:
            route_index.setdefault(normalize_route_short(code), href)
    return route_index


def iasi_route_codes_from_label(label: str) -> list[str]:
    candidates: list[str] = []
    leading = re.match(r"\s*(\d{1,3}[A-Z]?(?:/\d{0,3}[A-Z]?)*)", label)
    tokens = [leading.group(1)] if leading else []
    tokens.extend(match.group(1) for match in re.finditer(r"/(\d{1,3}[A-Z]?)\b", label))
    for token in tokens:
        parts = token.split("/")
        previous_number = ""
        for part in parts:
            match = re.fullmatch(r"(\d{0,3})([A-Z]?)", part)
            if not match:
                continue
            number, suffix = match.groups()
            if number:
                previous_number = number
            if not previous_number:
                continue
            candidates.append(f"{previous_number}{suffix}")
    return candidates


def iasi_amtpi_url_from_sctp_page(content: str) -> str:
    urls: list[str] = []
    for href in re.findall(r'href="(https?://www\.amtpi\.ro/[^"]+)"', content):
        clean = html.unescape(href)
        if "/wp-content/" in clean or clean.rstrip("/") == "https://www.amtpi.ro":
            continue
        if clean not in urls:
            urls.append(clean)
    return urls[0] if urls else ""


def parse_iasi_amtpi_schedule(content: str) -> dict[str, list[dict[str, Any]]]:
    schedule: dict[str, list[dict[str, Any]]] = {day: [] for day in DAY_TYPES}
    headings = list(
        re.finditer(
            r'<h2[^>]*class="[^"]*elementor-heading-title[^"]*"[^>]*>(.*?)</h2>',
            content,
            re.S,
        )
    )
    for index, heading_match in enumerate(headings):
        heading = normalize_name(html_to_text(heading_match.group(1)))
        block_start = heading_match.end()
        block_end = (
            headings[index + 1].start() if index + 1 < len(headings) else len(content)
        )
        target_days: tuple[str, ...] = ()
        if heading == "orare":
            target_days = ("lv",)
        elif "sambata" in heading and "duminica" in heading:
            target_days = ("s", "d")
        elif "luni" in heading and "duminica" in heading:
            target_days = DAY_TYPES
        if not target_days:
            continue

        block = content[block_start:block_end]
        for title, body in re.findall(
            r'<a[^>]*class="[^"]*elementor-toggle-title[^"]*"[^>]*>(.*?)</a>.*?'
            r'<div[^>]*class="[^"]*elementor-tab-content[^"]*"[^>]*>(.*?)</div>',
            block,
            re.S,
        ):
            clean_title = html_to_text(title)
            times = sorted(
                {clean_hhmm(value) for value in re.findall(r"\b\d{1,2}:\d{2}\b", body)}
            )
            times = [value for value in times if value]
            if not times:
                continue
            item = {"title": clean_title, "times": times}
            for day_type in target_days:
                schedule[day_type].append(item)
    return schedule


def extract_amtpi_timetable_image_urls(content: str) -> list[str]:
    urls: list[str] = []
    for img_tag in re.findall(r"<img\b[^>]*>", content, re.S | re.I):
        src_match = re.search(r'\bsrc=["\']([^"\']+)["\']', img_tag, re.I)
        if not src_match:
            continue
        url = html.unescape(src_match.group(1))
        lower = url.lower()
        if "/wp-content/uploads/" not in lower:
            continue
        if not re.search(r"\.(?:png|jpe?g|webp)(?:[?#].*)?$", lower):
            continue
        if any(skip in lower for skip in ("logo", "cropped-logo", "here-it-is")):
            continue
        if url not in urls:
            urls.append(url)
    return urls


def best_amtpi_departure_block(
    endpoint: dict[str, Any],
    blocks: list[dict[str, Any]],
    fallback_index: int,
) -> tuple[dict[str, Any] | None, str]:
    if not blocks:
        return None, ""
    target = normalize_departure_title(endpoint.get("first_stop_name", ""))
    best_block: dict[str, Any] | None = None
    best_score = 0.0
    for block in blocks:
        score = fuzzy_name_score(target, normalize_departure_title(block["title"]))
        if score > best_score:
            best_block = block
            best_score = score
    if best_block and best_score >= 0.42:
        return best_block, ""

    if fallback_index < len(blocks):
        fallback = blocks[fallback_index]
        return (
            fallback,
            (
                f"AMTPI title for endpoint {endpoint.get('first_stop_name')!r} was weakly matched; "
                f"used timetable block {fallback.get('title')!r} by endpoint order"
            ),
        )
    return (
        None,
        f"AMTPI has no timetable block for endpoint {endpoint.get('first_stop_name')!r}",
    )


def normalize_departure_title(value: str) -> str:
    normalized = normalize_name(value)
    tokens = [
        token
        for token in normalized.split()
        if token not in {"plecari", "plecare", "din", "catre"}
    ]
    return " ".join(tokens)


def html_to_text(value: str) -> str:
    without_tags = re.sub(r"<[^>]+>", " ", value)
    return " ".join(html.unescape(without_tags).split())


def parse_iasi_station_section(section_text: str) -> dict[str, Any]:
    lines = []
    for raw_line in section_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.lower().startswith("observatii") or "www." in line.lower():
            break
        lines.append(line)

    header_positions: dict[str, int] = {}
    for idx, line in enumerate(lines):
        normalized = normalize_day_label(line)
        if normalized and normalized not in header_positions:
            header_positions[normalized] = idx
    missing_headers = [day for day in DAY_TYPES if day not in header_positions]
    numeric_lines_exist = any(
        re.fullmatch(r"\d{1,2}(?:\s+\d{1,2})*", line) and len(line.split()) > 1
        for line in lines
    )
    if missing_headers:
        # Some Iasi circular-route PDFs place the Luni-Vineri header in the
        # decorative map text before the STATIA marker. The rows still appear as
        # lv/s/d triples, so s+d headers are enough to parse them safely.
        can_infer_lv = set(missing_headers) == {"lv"} and {"s", "d"} <= set(
            header_positions
        )
        if not can_infer_lv:
            if not numeric_lines_exist:
                return {
                    "days": {day: [] for day in DAY_TYPES},
                    "valid": True,
                    "empty": True,
                    "error": "missing day headers",
                }
            return {
                "days": {day: [] for day in DAY_TYPES},
                "valid": False,
                "empty": False,
                "error": f"missing day headers: {', '.join(missing_headers)}",
            }

    data_start = max(header_positions.values()) + 1
    data_lines: list[str] = []
    for line in lines[data_start:]:
        if re.fullmatch(r"\d{1,2}(?:\s+\d{1,2})*", line):
            data_lines.append(line)
        elif data_lines:
            return {
                "days": {day: [] for day in DAY_TYPES},
                "valid": False,
                "empty": False,
                "error": f"unexpected text in time table: {line!r}",
            }

    if not data_lines:
        return {
            "days": {day: [] for day in DAY_TYPES},
            "valid": True,
            "empty": True,
            "error": "",
        }
    if len(data_lines) % 3 != 0:
        return {
            "days": {day: [] for day in DAY_TYPES},
            "valid": False,
            "empty": False,
            "error": f"time rows not divisible by 3 ({len(data_lines)})",
        }

    days = {day: [] for day in DAY_TYPES}
    seen_hours = {day: set() for day in DAY_TYPES}
    last_hours = {day: -1 for day in DAY_TYPES}
    errors: list[str] = []
    for idx in range(0, len(data_lines), 3):
        for offset, day_type in enumerate(DAY_TYPES):
            line = data_lines[idx + offset]
            hour, minutes = parse_hour_minutes_line(line)
            if hour is None:
                errors.append(f"cannot parse row {line!r}")
                continue
            if hour < last_hours[day_type]:
                errors.append(
                    f"{day_type} hour order regressed from {last_hours[day_type]} to {hour}"
                )
            if hour in seen_hours[day_type]:
                errors.append(f"{day_type} hour {hour} appears more than once")
            if minutes != sorted(minutes):
                errors.append(f"{day_type} minutes are not sorted in row {line!r}")
            if any(minute > 59 for minute in minutes):
                errors.append(f"{day_type} minute above 59 in row {line!r}")
            seen_hours[day_type].add(hour)
            last_hours[day_type] = hour
            days[day_type].extend(f"{hour:02d}:{minute:02d}" for minute in minutes)

    if errors:
        return {
            "days": {day: [] for day in DAY_TYPES},
            "valid": False,
            "empty": False,
            "error": "; ".join(errors[:4]),
        }

    for day_type in DAY_TYPES:
        days[day_type] = sorted(set(days[day_type]))
    return {
        "days": days,
        "valid": True,
        "empty": not any(days.values()),
        "error": "",
    }


def normalize_day_label(value: str) -> str | None:
    normalized = normalize_name(value)
    if normalized in {"luni vineri", "luni-vineri", "luni pana vineri"}:
        return "lv"
    if normalized == "sambata":
        return "s"
    if normalized == "duminica":
        return "d"
    return None


def parse_hour_minutes_line(line: str) -> tuple[int | None, list[int]]:
    parts = [int(part) for part in line.split()]
    if not parts:
        return None, []
    hour = parts[0]
    minutes = parts[1:]
    if hour > 29:
        return None, []
    return hour, minutes


def select_iasi_endpoint_sections(
    endpoints: list[dict[str, Any]], sections: list[dict[str, Any]]
) -> list[tuple[dict[str, Any], dict[str, Any], str]]:
    if len(endpoints) == 1:
        endpoints_to_match = endpoints[:1]
    else:
        endpoints_to_match = endpoints[:2]

    selected: list[tuple[dict[str, Any], dict[str, Any], str]] = []
    for endpoint in endpoints_to_match:
        endpoint_name = endpoint.get("first_stop_name", "")
        best_index, best_score = best_iasi_section_index(endpoint_name, sections)
        if best_index is None or best_score < 0.45:
            raise NativeTimetableError(
                f"no PDF station match for endpoint {endpoint_name!r}"
            )
        section = sections[best_index]
        warning = ""
        if not section.get("valid"):
            raise NativeTimetableError(
                f"station {section['name']!r} matched for {endpoint_name!r} failed validation: {section.get('error')}"
            )
        if section.get("empty"):
            fallback = nearest_nonempty_iasi_section(best_index, sections)
            if fallback is None:
                raise NativeTimetableError(
                    f"station {section['name']!r} has no departures"
                )
            warning = (
                f"PDF station {section['name']!r} matched endpoint {endpoint_name!r} "
                f"but has no departures; used nearby station {fallback['name']!r}"
            )
            section = fallback
        selected.append((endpoint, section, warning))
    return selected


def best_iasi_section_index(
    endpoint_name: str, sections: list[dict[str, Any]]
) -> tuple[int | None, float]:
    target = normalize_name(endpoint_name)
    best_index: int | None = None
    best_score = 0.0
    for idx, section in enumerate(sections):
        candidate = section["normalized_name"]
        score = fuzzy_name_score(target, candidate)
        if score > best_score:
            best_index = idx
            best_score = score
    return best_index, best_score


def nearest_nonempty_iasi_section(
    index: int, sections: list[dict[str, Any]]
) -> dict[str, Any] | None:
    for distance in range(1, 4):
        for candidate_index in (index + distance, index - distance):
            if 0 <= candidate_index < len(sections):
                section = sections[candidate_index]
                if section.get("valid") and not section.get("empty"):
                    return section
    return None


def normalize_name(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = value.lower()
    value = re.sub(r"[^\w]+", " ", value, flags=re.UNICODE)
    aliases = {
        "providenta": "elytis",
    }
    tokens = [
        aliases.get(token, token)
        for token in value.split()
        if token
        and token
        not in {
            "statia",
            "st",
            "str",
            "bd",
            "bld",
            "bulevard",
            "piata",
            "rond",
            "cap",
            "linie",
            "linia",
            "de",
            "la",
            "spre",
            "nr",
        }
    ]
    return " ".join(tokens)


def fuzzy_name_score(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    if a in b or b in a:
        return 0.92
    a_tokens = set(a.split())
    b_tokens = set(b.split())
    overlap = len(a_tokens & b_tokens) / max(len(a_tokens | b_tokens), 1)
    ratio = SequenceMatcher(None, a, b).ratio()
    return max(ratio, 0.55 * ratio + 0.45 * overlap)


def generate_chisinau(ctx: BuildContext) -> None:
    agency_id = "4"
    routes = apply_verify_samples(ctx, agency_id, load_routes(ctx, agency_id))
    all_routes = load_json(find_data_file(ctx, agency_id, "routes"))
    short_counts = route_short_counts(all_routes)
    try:
        calendar = get_json(ctx, f"{CHISINAU_BASE_URL}/calendar")
        active_services = chisinau_active_services_by_day(calendar)
        service_start = chisinau_service_start(calendar)
    except Exception as exc:
        for route in routes:
            record_skipped(
                ctx, agency_id, route, "trolley_md_api", f"calendar fetch failed: {exc}"
            )
        return

    for route in routes:
        route_id = str(route.get("route_id"))
        try:
            warnings: list[str] = []
            try:
                api_route = get_json(ctx, f"{CHISINAU_BASE_URL}/routes/{route_id}")
            except Exception as exc:
                api_route = None
                warnings.append(
                    f"route metadata fetch failed; continued with trips endpoint: {exc}"
                )
            trips = get_json(
                ctx, f"{CHISINAU_BASE_URL}/trips?route_id={route_id}&limit=1000"
            )
            if isinstance(trips, dict) and "items" in trips:
                trips = trips["items"]
            if not isinstance(trips, list) or not trips:
                record_skipped(
                    ctx,
                    agency_id,
                    route,
                    "trolley_md_api",
                    "no trips returned",
                    warnings=warnings,
                )
                continue

            if len(trips) >= 1000:
                warnings.append(
                    "trip response hit limit=1000; output may be incomplete"
                )
            if api_route:
                api_short = str(
                    api_route.get("route_short_name")
                    or api_route.get("short_name")
                    or ""
                )
                if api_short and api_short != str(route.get("route_short_name")):
                    warnings.append(
                        f"local short name differs from API short name {api_short!r}"
                    )

            endpoint_map = chisinau_fetch_departures(ctx, trips, active_services)
            if not any(endpoint_map["day_times"].values()):
                record_skipped(
                    ctx,
                    agency_id,
                    route,
                    "trolley_md_api",
                    "no active departures found",
                )
                continue
            local_endpoints = load_local_trip_endpoints(ctx, agency_id, route_id)
            terminals = chisinau_terminals_from_local_endpoints(
                local_endpoints, endpoint_map
            )
            associations = {
                "source_route_id": route_id,
                "source_trips_count": len(trips),
                "services_by_day": {
                    day: sorted(active_services[day]) for day in DAY_TYPES
                },
                "local_endpoints": local_endpoints,
                "directions": endpoint_map["direction_meta"],
            }
            build = TimetableBuild(
                agency_id=agency_id,
                route=route,
                source="trolley_md_gtfs_api",
                source_url=f"{CHISINAU_BASE_URL}/routes/{route_id}",
                service_start=service_start,
                day_times=endpoint_map["day_times"],
                terminals=terminals,
                associations=associations,
                warnings=warnings,
            )
            write_timetable_build(ctx, build, short_counts)
        except Exception as exc:
            record_skipped(
                ctx,
                agency_id,
                route,
                "trolley_md_api",
                str(exc),
                f"{CHISINAU_BASE_URL}/routes/{route_id}",
            )


def chisinau_active_services_by_day(
    calendar: list[dict[str, Any]],
) -> dict[str, set[str]]:
    active = {day: set() for day in DAY_TYPES}
    for service in calendar:
        service_id = str(service.get("service_id", ""))
        if not service_id:
            continue
        if any(
            int(service.get(day, 0) or 0)
            for day in ("monday", "tuesday", "wednesday", "thursday", "friday")
        ):
            active["lv"].add(service_id)
        if int(service.get("saturday", 0) or 0):
            active["s"].add(service_id)
        if int(service.get("sunday", 0) or 0):
            active["d"].add(service_id)
    return active


def chisinau_service_start(calendar: list[dict[str, Any]]) -> str:
    dates: list[str] = []
    for service in calendar:
        value = str(service.get("start_date") or "")
        if re.fullmatch(r"\d{8}", value):
            dates.append(value)
    if not dates:
        return date.today().strftime("%d.%m.%Y")
    first = min(dates)
    return f"{first[6:8]}.{first[4:6]}.{first[0:4]}"


def chisinau_fetch_departures(
    ctx: BuildContext,
    trips: list[dict[str, Any]],
    active_services: dict[str, set[str]],
) -> dict[str, Any]:
    active_trip_ids: set[str] = set()
    trips_by_id: dict[str, dict[str, Any]] = {}
    for trip in trips:
        trip_id = str(trip.get("trip_id", ""))
        if not trip_id:
            continue
        service_id = str(trip.get("service_id", ""))
        if any(service_id in active_services[day] for day in DAY_TYPES):
            active_trip_ids.add(trip_id)
            trips_by_id[trip_id] = trip

    stop_times_by_trip: dict[str, dict[str, Any] | None] = {}
    with ThreadPoolExecutor(max_workers=max(1, ctx.args.workers)) as executor:
        future_map = {
            executor.submit(chisinau_first_stop_time, ctx, trip_id): trip_id
            for trip_id in sorted(active_trip_ids)
        }
        for future in as_completed(future_map):
            trip_id = future_map[future]
            try:
                stop_times_by_trip[trip_id] = future.result()
            except Exception:
                stop_times_by_trip[trip_id] = None

    direction_meta: dict[str, dict[str, Any]] = {}
    day_times_map: dict[str, dict[str, set[str]]] = {
        day: defaultdict(set) for day in DAY_TYPES
    }

    for trip_id, trip in trips_by_id.items():
        first_stop_time = stop_times_by_trip.get(trip_id)
        if not first_stop_time:
            continue
        departure = clean_hhmm(
            first_stop_time.get("departure_time")
            or first_stop_time.get("arrival_time")
            or ""
        )
        if not departure:
            continue
        direction_id = str(trip.get("direction_id", "0"))
        if direction_id not in direction_meta:
            direction_meta[direction_id] = {
                "direction_id": direction_id,
                "first_stop_id": first_stop_time.get("stop_id"),
                "first_stop_name": stop_name_from_stop_time(first_stop_time),
                "sample_trip_id": trip_id,
                "trip_headsign": trip.get("trip_headsign") or trip.get("headsign"),
            }
        service_id = str(trip.get("service_id", ""))
        for day_type in DAY_TYPES:
            if service_id in active_services[day_type]:
                day_times_map[day_type][direction_id].add(departure)

    day_times: dict[str, list[list[str]]] = {}
    direction_order = sorted(
        direction_meta,
        key=lambda value: int(value) if str(value).isdigit() else str(value),
    )
    for day_type in DAY_TYPES:
        day_times[day_type] = [
            sorted(day_times_map[day_type].get(direction_id, set()))
            for direction_id in direction_order[:2]
        ]
    return {"day_times": day_times, "direction_meta": direction_meta}


def chisinau_first_stop_time(ctx: BuildContext, trip_id: str) -> dict[str, Any] | None:
    rows = get_json(
        ctx, f"{CHISINAU_BASE_URL}/stop_times?trip_id={quote(trip_id, safe='')}"
    )
    if isinstance(rows, dict) and "items" in rows:
        rows = rows["items"]
    if not isinstance(rows, list) or not rows:
        return None
    return sorted(rows, key=lambda row: int(row.get("stop_sequence", 0)))[0]


def chisinau_terminals_from_local_endpoints(
    local_endpoints: list[dict[str, Any]],
    endpoint_map: dict[str, Any],
) -> list[str]:
    terminals_by_direction: dict[str, str] = {}
    for endpoint in local_endpoints:
        direction_id = str(endpoint.get("direction_id", ""))
        if direction_id:
            terminals_by_direction[direction_id] = str(
                endpoint.get("first_stop_name", "")
            )

    direction_meta = endpoint_map["direction_meta"]
    terminals: list[str] = []
    for direction_id in sorted(
        direction_meta, key=lambda value: int(value) if value.isdigit() else value
    ):
        name = (
            terminals_by_direction.get(direction_id)
            or direction_meta[direction_id].get("first_stop_name")
            or direction_meta[direction_id].get("trip_headsign")
            or ""
        )
        terminals.append(str(name))
    return terminals[:2]


def stop_name_from_stop_time(row: dict[str, Any]) -> str:
    for key in ("stop_name", "name"):
        if row.get(key):
            return str(row[key])
    nested = row.get("stop")
    if isinstance(nested, dict):
        for key in ("stop_name", "name"):
            if nested.get(key):
                return str(nested[key])
    return ""


def clean_hhmm(value: str) -> str:
    match = re.match(r"^(\d{1,2}):(\d{2})(?::\d{2})?$", str(value).strip())
    if not match:
        return ""
    hour = int(match.group(1))
    minute = int(match.group(2))
    if minute > 59:
        return ""
    return f"{hour % 24:02d}:{minute:02d}"


def generate_botosani(ctx: BuildContext) -> None:
    agency_id = "6"
    routes = apply_verify_samples(ctx, agency_id, load_routes(ctx, agency_id))
    all_routes = load_json(find_data_file(ctx, agency_id, "routes"))
    short_counts = route_short_counts(all_routes)
    try:
        pdf = download_pdf(ctx, BOTOSANI_PDF_URL)
        text = pdf_to_text(pdf, layout=True)
        source_note = botosani_source_note(text)
    except Exception as exc:
        source_note = f"PDF verification failed: {exc}"
    for route in routes:
        endpoints = []
        try:
            endpoints = load_local_trip_endpoints(ctx, agency_id, route["route_id"])
        except Exception:
            pass
        if ctx.args.botosani_expand_intervals:
            try:
                build = build_botosani_interval_timetable(route, endpoints, source_note)
                write_timetable_build(ctx, build, short_counts)
                continue
            except Exception as exc:
                record_skipped(
                    ctx,
                    agency_id,
                    route,
                    "botosani_pdf_interval_expansion",
                    str(exc),
                    BOTOSANI_PDF_URL,
                    associations={"local_endpoints": endpoints},
                    warnings=[source_note],
                )
                continue

        record_skipped(
            ctx,
            agency_id,
            route,
            "botosani_pdf_interval_only",
            "source is interval-only; exact terminal departure CSV was not generated",
            BOTOSANI_PDF_URL,
            associations={"local_endpoints": endpoints},
            warnings=[source_note],
        )


def build_botosani_interval_timetable(
    route: dict[str, Any],
    endpoints: list[dict[str, Any]],
    source_note: str,
) -> TimetableBuild:
    if not endpoints:
        raise NativeTimetableError("no local trip endpoints")
    short = normalize_route_short(str(route.get("route_short_name", "")))
    day_times = {day: [] for day in DAY_TYPES}
    segments_by_day: dict[str, list[dict[str, Any]]] = {}
    for day_type in DAY_TYPES:
        segments = botosani_segments(short, day_type)
        segments_by_day[day_type] = segments
        departures = expand_botosani_segments(segments)
        if departures:
            for _endpoint in endpoints[:2]:
                day_times[day_type].append(departures)

    if not any(any(day_times[day_type]) for day_type in DAY_TYPES):
        raise NativeTimetableError(
            "no configured interval schedule for this Botosani route"
        )

    terminals = [endpoint.get("first_stop_name", "") for endpoint in endpoints[:2]]
    return TimetableBuild(
        agency_id="6",
        route=route,
        source="botosani_official_pdf_interval_expansion",
        source_url=BOTOSANI_PDF_URL,
        service_start=date.today().strftime("%d.%m.%Y"),
        day_times=day_times,
        terminals=terminals,
        associations={
            "local_endpoints": endpoints,
            "interval_segments_by_day": segments_by_day,
        },
        warnings=[
            source_note,
            "Official Botosani PDF publishes route frequency intervals, not individual trip ids.",
            "CSV departures were generated by expanding those official intervals; both terminal directions use the same grid.",
        ],
    )


def botosani_segments(route_short: str, day_type: str) -> list[dict[str, Any]]:
    if route_short == "101":
        return {
            "lv": [
                {"start": "04:50", "end": "08:00", "step_minutes": 10},
                {"start": "08:00", "end": "12:00", "step_minutes": 12},
                {"start": "12:00", "end": "17:00", "step_minutes": 10},
                {"start": "17:00", "end": "20:00", "step_minutes": 12},
                {"start": "20:00", "end": "23:00", "step_minutes": 15},
            ],
            "s": [
                {"start": "04:50", "end": "15:00", "step_minutes": 12},
                {"start": "15:00", "end": "19:45", "step_minutes": 15},
            ],
            "d": [
                {"start": "06:12", "end": "14:00", "step_minutes": 12},
                {"start": "14:00", "end": "19:45", "step_minutes": 15},
            ],
        }[day_type]

    if route_short == "102":
        return {
            "lv": [
                {
                    "start": "05:00",
                    "end": "08:00",
                    "step_minutes": 10,
                    "variant": "G.Enescu-Mobila",
                },
                {
                    "start": "12:00",
                    "end": "17:00",
                    "step_minutes": 10,
                    "variant": "G.Enescu-Mobila",
                },
            ],
            "s": [
                {
                    "start": "04:50",
                    "end": "08:00",
                    "step_minutes": 12,
                    "variant": "G.Enescu-B-ra Catamarasti",
                },
                {
                    "start": "12:00",
                    "end": "15:00",
                    "step_minutes": 12,
                    "variant": "G.Enescu-B-ra Catamarasti",
                },
            ],
            "d": [
                {
                    "start": "06:12",
                    "end": "08:00",
                    "step_minutes": 12,
                    "variant": "G.Enescu-B-ra Catamarasti",
                },
            ],
        }[day_type]

    if route_short == "102S":
        return {
            "lv": [
                {
                    "start": "08:00",
                    "end": "12:00",
                    "step_minutes": 12,
                    "variant": "G.Enescu-St.UTIL",
                },
                {
                    "start": "17:00",
                    "end": "20:00",
                    "step_minutes": 12,
                    "variant": "G.Enescu-St.UTIL",
                },
                {
                    "start": "20:00",
                    "end": "22:50",
                    "step_minutes": 15,
                    "variant": "G.Enescu-St.UTIL",
                    "include_end": True,
                },
            ],
            "s": [
                {
                    "start": "08:00",
                    "end": "12:00",
                    "step_minutes": 12,
                    "variant": "G.Enescu-Util",
                },
                {
                    "start": "15:00",
                    "end": "19:45",
                    "step_minutes": 15,
                    "variant": "G.Enescu-Util",
                },
            ],
            "d": [
                {
                    "start": "08:00",
                    "end": "14:00",
                    "step_minutes": 12,
                    "variant": "G.Enescu-Util",
                },
                {
                    "start": "14:00",
                    "end": "19:45",
                    "step_minutes": 15,
                    "variant": "G.Enescu-Util",
                },
            ],
        }[day_type]

    return []


def expand_botosani_segments(segments: list[dict[str, Any]]) -> list[str]:
    departures: set[str] = set()
    for segment in segments:
        start = minutes_from_hhmm(segment["start"])
        end = minutes_from_hhmm(segment["end"])
        step = int(segment["step_minutes"])
        current = start
        while current <= end:
            departures.add(hhmm_from_minutes(current))
            current += step
        if segment.get("include_end"):
            departures.add(hhmm_from_minutes(end))
    return sorted(departures)


def minutes_from_hhmm(value: str) -> int:
    match = re.fullmatch(r"(\d{1,2}):(\d{2})", value)
    if not match:
        raise NativeTimetableError(f"bad HH:MM value {value!r}")
    return int(match.group(1)) * 60 + int(match.group(2))


def hhmm_from_minutes(value: int) -> str:
    hour, minute = divmod(value, 60)
    return f"{hour % 24:02d}:{minute:02d}"


def botosani_source_note(text: str) -> str:
    normalized = normalize_name(text[:5000])
    if "interval" in normalized or "intervale" in normalized or "minute" in normalized:
        return "PDF was parsed with pdftotext and contains interval/first-last schedule text, not exact departures."
    return "PDF was parsed with pdftotext, but no exact departure table format was detected."


def generate_constanta(ctx: BuildContext) -> None:
    agency_id = "10"
    routes = apply_verify_samples(ctx, agency_id, load_routes(ctx, agency_id))
    all_routes = load_json(find_data_file(ctx, agency_id, "routes"))
    short_counts = route_short_counts(all_routes)
    try:
        client = CtbusClient(ctx)
        source_lines = client.get_lines()
    except Exception as exc:
        for route in routes:
            record_skipped(
                ctx,
                agency_id,
                route,
                "ctbus_protobuf_api",
                f"CTBUS auth/lines probe failed: {exc}",
            )
        return

    source_by_short = {
        normalize_route_short(line["name"]): line for line in source_lines
    }
    for route in routes:
        short = str(route.get("route_short_name", ""))
        line = source_by_short.get(normalize_route_short(short))
        if not line:
            record_skipped(
                ctx,
                agency_id,
                route,
                "ctbus_protobuf_api",
                "route_short_name was not found in CTBUS /lines response",
                f"{CTBUS_BASE_URL}/lines?lang=ro",
                warnings=[
                    f"available CTBUS lines: {', '.join(sorted(item['name'] for item in source_lines))}"
                ],
            )
            continue

        try:
            direction_times: dict[str, list[list[str]]] = {day: [] for day in DAY_TYPES}
            terminals: list[str] = []
            current_date = date.today()
            target_day_types = (
                list(DAY_TYPES)
                if ctx.args.constanta_current_as_all_days
                else ctbus_current_day_types(current_date)
            )
            associations = {
                "ctbus_line": line,
                "directions": [],
                "current_date": current_date.isoformat(),
                "written_day_types": target_day_types,
            }
            # CTBUS page order is direction 0 first, then direction 1.
            for direction in (0, 1):
                detail = client.get_line_detail(int(line["id"]), direction)
                if not detail.get("stops"):
                    continue
                terminal_stop = detail["stops"][0]
                times = client.get_stop_departures(
                    int(line["id"]), direction, int(terminal_stop["id"])
                )
                terminals.append(terminal_stop.get("name", ""))
                associations["directions"].append(
                    {
                        "direction": direction,
                        "terminal_stop": terminal_stop,
                        "departures_count": len(times),
                    }
                )
                for day_type in target_day_types:
                    direction_times[day_type].append(times)

            warnings = [
                "CTBUS endpoint exposes exact departures for the currently active schedule only."
            ]
            if not any(any(direction_times[day_type]) for day_type in DAY_TYPES):
                record_skipped(
                    ctx,
                    agency_id,
                    route,
                    "ctbus_protobuf_api",
                    "current-day terminal timetable was empty",
                    f"{CTBUS_BASE_URL}/lines?lang=ro",
                    associations=associations,
                    warnings=warnings,
                )
                continue
            if ctx.args.constanta_current_as_all_days:
                warn_once(
                    warnings,
                    "same current CTBUS timetable was written to lv/s/d by explicit opt-in",
                )
            else:
                warn_once(
                    warnings,
                    f"generated only today's CTBUS day bucket(s): {', '.join(target_day_types)}",
                )

            build = TimetableBuild(
                agency_id=agency_id,
                route=route,
                source="ctbus_protobuf_api_current_schedule",
                source_url=f"{CTBUS_BASE_URL}/lines?lang=ro",
                service_start=current_date.strftime("%d.%m.%Y"),
                day_times=direction_times,
                terminals=terminals,
                associations=associations,
                warnings=warnings,
            )
            write_timetable_build(ctx, build, short_counts)
        except Exception as exc:
            record_skipped(
                ctx,
                agency_id,
                route,
                "ctbus_protobuf_api",
                str(exc),
                f"{CTBUS_BASE_URL}/lines?lang=ro",
            )


def normalize_route_short(value: str) -> str:
    return re.sub(r"\s+", "", value).upper()


def ctbus_current_day_types(current_date: date) -> list[str]:
    weekday = current_date.weekday()
    if weekday < 5:
        return ["lv"]
    if weekday == 5:
        return ["s"]
    return ["d"]


class CtbusClient:
    def __init__(self, ctx: BuildContext) -> None:
        self.ctx = ctx
        self.app_id = str(uuid.uuid4())
        auth_headers = {"App-key": CTBUS_APP_KEY, "App-Id": self.app_id}
        response = ctx.session.get(
            f"{CTBUS_BASE_URL}/proxy/user/auth",
            headers=auth_headers,
            timeout=ctx.args.http_timeout,
        )
        response.raise_for_status()
        user_info = response.json()["data"]["userInfo"]
        self.headers = {
            "App-key": CTBUS_APP_KEY,
            "App-Id": self.app_id,
            "App-Version": CTBUS_APP_VERSION,
            "OS-Type": "Web",
            "OS-Version": os.name,
            "Device-Name": "mapmybus-native-timetable-builder",
            "Lang": "ro",
            "User-Info": user_info,
        }

    def get_bytes(self, path: str) -> bytes:
        url = f"{CTBUS_BASE_URL}{path}"
        content, _ = get_bytes(self.ctx, url, headers=self.headers)
        return content

    def get_lines(self) -> list[dict[str, Any]]:
        content = self.get_bytes("/lines?lang=ro")
        return decode_ctbus_lines(content)

    def get_line_detail(self, line_id: int, direction: int) -> dict[str, Any]:
        content = self.get_bytes(f"/lines/{line_id}/direction/{direction}?lang=ro")
        return decode_ctbus_line_detail(content)

    def get_stop_departures(
        self, line_id: int, direction: int, stop_id: int
    ) -> list[str]:
        content = self.get_bytes(f"/lines/v2/{line_id}/stops/{stop_id}?lang=ro")
        return decode_ctbus_stop_departures(content, line_id, direction)


def decode_ctbus_lines(content: bytes) -> list[dict[str, Any]]:
    lines: list[dict[str, Any]] = []
    for line_msg in pb_messages(content, 1):
        line_id = pb_int(line_msg, 1)
        name = pb_str(line_msg, 2)
        if line_id is not None and name:
            lines.append({"id": line_id, "name": name})
    return lines


def decode_ctbus_line_detail(content: bytes) -> dict[str, Any]:
    stops: list[dict[str, Any]] = []
    for stop_msg in pb_messages(content, 12):
        stop_id = pb_int(stop_msg, 1)
        name = pb_str(stop_msg, 4)
        if stop_id is not None:
            stops.append({"id": stop_id, "name": name})
    return {
        "id": pb_int(content, 1),
        "name": pb_str(content, 2),
        "direction_name_1": pb_str(content, 10),
        "direction_name_2": pb_str(content, 11),
        "stops": stops,
    }


def decode_ctbus_stop_departures(
    content: bytes, line_id: int, direction: int
) -> list[str]:
    times: list[str] = []
    for transport_msg in pb_messages(content, 1):
        for line_msg in pb_messages(transport_msg, 2):
            parsed_line_id = pb_int(line_msg, 1)
            parsed_direction = pb_int(line_msg, 6)
            if parsed_line_id != line_id or parsed_direction != direction:
                continue
            for hour_msg in pb_messages(line_msg, 11):
                hour = ctbus_time_part(hour_msg, 1)
                if hour is None or hour > 29:
                    continue
                minute_values = pb_strs(hour_msg, 2)
                minutes = [int(value) for value in minute_values if value.isdigit()]
                if not minutes:
                    minutes = pb_ints(hour_msg, 2)
                for minute in minutes:
                    if 0 <= minute <= 59:
                        times.append(f"{hour % 24:02d}:{minute:02d}")
    return sorted(set(times))


def ctbus_time_part(content: bytes, field_number: int) -> int | None:
    string_value = pb_str(content, field_number)
    if string_value.isdigit():
        return int(string_value)
    return pb_int(content, field_number)


def pb_fields(content: bytes) -> list[tuple[int, int, Any]]:
    fields: list[tuple[int, int, Any]] = []
    index = 0
    length = len(content)
    while index < length:
        key, index = pb_read_varint(content, index)
        field_number = key >> 3
        wire_type = key & 7
        if wire_type == 0:
            value, index = pb_read_varint(content, index)
        elif wire_type == 1:
            value = content[index : index + 8]
            index += 8
        elif wire_type == 2:
            size, index = pb_read_varint(content, index)
            value = content[index : index + size]
            index += size
        elif wire_type == 5:
            value = content[index : index + 4]
            index += 4
        else:
            raise NativeTimetableError(f"unsupported protobuf wire type {wire_type}")
        fields.append((field_number, wire_type, value))
    return fields


def pb_read_varint(content: bytes, index: int) -> tuple[int, int]:
    shift = 0
    value = 0
    while True:
        if index >= len(content):
            raise NativeTimetableError("truncated protobuf varint")
        byte = content[index]
        index += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, index
        shift += 7
        if shift > 70:
            raise NativeTimetableError("protobuf varint is too long")


def pb_messages(content: bytes, field_number: int) -> list[bytes]:
    return [
        value
        for current_field, wire_type, value in pb_fields(content)
        if current_field == field_number and wire_type == 2
    ]


def pb_int(content: bytes, field_number: int) -> int | None:
    values = pb_ints(content, field_number)
    return values[0] if values else None


def pb_ints(content: bytes, field_number: int) -> list[int]:
    values: list[int] = []
    for current_field, wire_type, value in pb_fields(content):
        if current_field != field_number:
            continue
        if wire_type == 0:
            values.append(int(value))
        elif wire_type == 2:
            index = 0
            while index < len(value):
                parsed, index = pb_read_varint(value, index)
                values.append(parsed)
    return values


def pb_str(content: bytes, field_number: int) -> str:
    values = pb_strs(content, field_number)
    return values[0] if values else ""


def pb_strs(content: bytes, field_number: int) -> list[str]:
    values: list[str] = []
    for current_field, wire_type, value in pb_fields(content):
        if current_field == field_number and wire_type == 2:
            try:
                values.append(value.decode("utf-8"))
            except UnicodeDecodeError:
                continue
    return values


if __name__ == "__main__":
    raise SystemExit(main())
