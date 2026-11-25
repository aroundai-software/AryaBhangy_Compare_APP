from compare.engine import compare
from compare.load import load_tally, load_tracksheet
from compare.normalize import as_date

ALL_BRANCHES = "All branches"


def filter_records(records, start, end, branch):
    chosen = []
    branch_name = (branch or "").strip()
    for record in records:
        if start and record.on and record.on < start:
            continue
        if end and record.on and record.on > end:
            continue
        if branch_name and branch_name != ALL_BRANCHES and record.branch:
            if record.branch.lower() != branch_name.lower():
                continue
        chosen.append(record)
    return chosen


def merge_tracksheet_for_tally_jcs(track_records, tally_records, branch, fetch_by_jc):
    """Add Tracksheet rows for Tally JCs whose Job Card Date is outside From–To.

    From–To still limits which Hirise bills are read. For each bill JC/vehicle
    not already in the date-window Tracksheet pull, fetch that JC from the site
    (any date) and keep branch-matching rows.
    """
    have = {(record.job_card, record.vehicle) for record in track_records if record.job_card and record.vehicle}
    needed = sorted(
        {
            record.job_card
            for record in tally_records
            if record.job_card and (record.job_card, record.vehicle) not in have
        }
    )
    if not needed:
        return list(track_records)

    fetched = fetch_by_jc(needed) or []
    branch_name = (branch or "").strip()
    merged = list(track_records)
    for record in fetched:
        if not record.job_card or not record.vehicle:
            continue
        if branch_name and branch_name != ALL_BRANCHES and record.branch:
            if record.branch.lower() != branch_name.lower():
                continue
        key = (record.job_card, record.vehicle)
        if key in have:
            continue
        merged.append(record)
        have.add(key)
    return merged


def company_branch(company_name, branches):
    """The tracksheet branch named in the open Tally company."""
    folded = (company_name or "").lower()
    matches = [name for name in branches if name and name.lower() in folded]
    if not matches:
        return ""
    return max(matches, key=len)


def branches_in(records):
    names = []
    for record in records:
        if record.branch and record.branch not in names:
            names.append(record.branch)
    return names


def run_compare(track_path, tally_path, start_text, end_text, branch):
    start = as_date(start_text)
    end = as_date(end_text)
    if start_text and start is None:
        raise ValueError("From date could not be read. Use a date like 09 Nov 2026.")
    if end_text and end is None:
        raise ValueError("To date could not be read. Use a date like 16 Nov 2026.")
    if start and end and start > end:
        raise ValueError("From date is after To date.")
    track_records = filter_records(load_tracksheet(track_path), start, end, branch)
    tally = load_tally(tally_path)
    tally_records = filter_records(tally.records, start, end, branch)
    result = compare(track_records, tally_records)
    return result, tally_records, tally.skipped
