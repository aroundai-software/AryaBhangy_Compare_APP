from dataclasses import dataclass, field


@dataclass
class Record:
    source: str
    branch: str
    on: object
    financial_year: str
    job_card: str
    vehicle: str
    customer: str
    bill: str
    amount: str
    voucher_type: str
    status: str
    service: str
    adviser: str
    row_number: int
    phone: str = ""
    model: str = ""
    booking: str = ""
    technician: str = ""
    labour: str = ""
    spares: str = ""
    vas: str = ""
    payment: str = ""
    items: str = ""
    ledgers: str = ""
    ledamts: str = ""


@dataclass
class Outcome:
    mark: str
    reason: str
    job_card: str = ""
    vehicle: str = ""
    customer: str = ""
    when: str = ""
    branch: str = ""
    tally_bills: str = ""
    track_bill: str = ""
    adviser: str = ""
    status: str = ""
    service: str = ""
    amount: str = ""
    category: str = ""
    phone: str = ""
    model: str = ""
    booking: str = ""
    technician: str = ""
    labour: str = ""
    spares: str = ""
    vas: str = ""
    payment: str = ""
    items: str = ""
    tally_labour: str = ""
    tally_spares: str = ""
    tally_vas: str = ""
    tally_total: str = ""
    tally_when: str = ""
    sheet_bill: str = ""
    sheet_labour: str = ""
    sheet_spares: str = ""
    sheet_total: str = ""
    sheet_vas: str = ""
    sheet_when: str = ""
    details: list = field(default_factory=list)


@dataclass
class VoucherRow:
    """One Tally voucher for the separate vouchers table (not on the Job Card)."""

    voucher_number: str
    when: str = ""
    branch: str = ""
    registration: str = ""
    job_card: str = ""
    labour: str = ""
    spares: str = ""
    vas: str = ""
    items: str = ""
    has_job_card: bool = True
    note: str = ""


@dataclass
class CompareResult:
    outcomes: list
    vouchers: list
    track_rows: int
    tally_rows: int
    uncovered_rows: int
    track_from: str
    track_to: str
    tally_from: str
    tally_to: str

    def count(self, mark: str) -> int:
        return sum(1 for outcome in self.outcomes if outcome.mark == mark)

    def count_category(self, category: str) -> int:
        return sum(1 for outcome in self.outcomes if outcome.category == category)
