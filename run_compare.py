import argparse
from pathlib import Path

from compare.engine import compare
from compare.load import load_tally, load_tracksheet
from compare.report import summary_lines, write_report
from compare.sample_tally import write_sample

ROOT = Path(__file__).resolve().parent
DEFAULT_TRACKSHEET = Path(r"C:\Users\admin\Downloads\JobCards_2026-11-16_1127rows.xlsx")
DEFAULT_TALLY = ROOT / "samples" / "tally_known_invoices.xlsx"
DEFAULT_OUTPUT = ROOT / "output" / "Aryabhangy_compare_2026-11-16.xlsx"


def main():
    parser = argparse.ArgumentParser(description="Compare a tracksheet export with a Tally export.")
    parser.add_argument("--tracksheet", type=Path, default=DEFAULT_TRACKSHEET)
    parser.add_argument("--tally", type=Path, default=DEFAULT_TALLY)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.tally == DEFAULT_TALLY:
        args.tally.parent.mkdir(parents=True, exist_ok=True)
        write_sample(args.tally)

    track_records = load_tracksheet(args.tracksheet)
    tally = load_tally(args.tally)
    result = compare(track_records, tally.records)
    lines = summary_lines(result, args.tracksheet, args.tally, tally.records, tally.skipped)
    write_report(args.output, lines, result.outcomes, vouchers=result.vouchers)
    print("\n".join(lines))
    print(f"\nSaved {args.output}")


if __name__ == "__main__":
    main()
