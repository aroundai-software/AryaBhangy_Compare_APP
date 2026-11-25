"""Aryabhangy Compare window."""

import queue
import threading
import tkinter as tk
from datetime import date
from tkinter import filedialog, messagebox, ttk

from tkcalendar import DateEntry

from compare.engine import ADDED, CHECK, REMOVED, compare
from compare.normalize import as_date, format_date
from compare.report import summary_lines, write_report
from compare.session import (
    ALL_BRANCHES,
    branches_in,
    company_branch,
    filter_records,
    merge_tracksheet_for_tally_jcs,
)
from compare.tally_gateway import current_company, hirise_vouchers, tally_status
from compare.tracksheet_site import SITE, branch_names, job_cards, job_cards_by_numbers

COLUMNS = (
    ("job_card", "Job card", 110),
    ("vehicle", "Vehicle", 140),
    ("customer", "Customer", 180),
    ("when", "Date", 120),
    ("adviser", "Adviser", 140),
    ("reason", "Reason", 720),
)

MARKS = (ADDED, REMOVED, CHECK)
WATCH_MS = 3000


class CompareApp(tk.Tk):
    def __init__(self, visible=True):
        super().__init__()
        self.title("Aryabhangy Compare")
        self.geometry("1180x720")
        self.minsize(960, 560)
        self.configure(bg="#f7f4ee")
        self.result = None
        self.tally_records = []
        self.skipped = 0
        self.branch = tk.StringVar(value=ALL_BRANCHES)
        self.mark = tk.StringVar(value=CHECK)
        self.company = tk.StringVar(value="Tally: Checking")
        self.tally_line = tk.StringVar(value="Waiting for Tally")
        self._active_company = ""
        self._tally_online = False
        self._status_key = None
        self._updates = queue.Queue()
        self._tally_status = queue.Queue()
        self._branch_updates = queue.Queue()
        self._site_branches = []
        self._busy = False
        self._watch_running = False
        self.status = tk.StringVar(
            value="Choose From and To, then run compare. Tally and the tracksheet are only read."
        )
        self._build()
        if not visible:
            self.withdraw()
        else:
            self.after(100, self._watch_tally)
            self.after(150, self._start_branch_load)
            self.after(200, self._apply_tally_status)
            self.after(200, self._apply_branch_updates)

    def _build(self):
        self.option_add("*Font", ("Segoe UI", 10))
        header = tk.Frame(self, bg="#f7f4ee")
        header.pack(fill="x", padx=16, pady=(14, 6))
        tk.Label(header, text="Aryabhangy Compare", bg="#f7f4ee", font=("Segoe UI", 18)).pack(anchor="w")
        tk.Label(
            header,
            text="Hirise Invoice Service. Tally is only read. The tracksheet is not changed.",
            bg="#f7f4ee",
            fg="#57534e",
        ).pack(anchor="w")
        company_row = tk.Frame(header, bg="#f7f4ee")
        company_row.pack(fill="x", pady=(8, 0))
        self.company_label = tk.Label(
            company_row,
            textvariable=self.company,
            bg="#f7f4ee",
            fg="#1c1917",
            anchor="w",
            justify="left",
            wraplength=1100,
        )
        self.company_label.pack(fill="x")

        sources = tk.Frame(self, bg="#f7f4ee")
        sources.pack(fill="x", padx=16, pady=(8, 2))
        tk.Label(sources, text="Tally", bg="#f7f4ee", width=12, anchor="w").grid(row=0, column=0, sticky="w")
        tk.Label(sources, textvariable=self.tally_line, bg="#f7f4ee", fg="#44403c", anchor="w").grid(
            row=0, column=1, sticky="w"
        )
        tk.Label(sources, text="Tracksheet", bg="#f7f4ee", width=12, anchor="w").grid(row=1, column=0, sticky="w")
        tk.Label(sources, text=SITE, bg="#f7f4ee", fg="#44403c").grid(row=1, column=1, sticky="w")

        tools = tk.Frame(self, bg="#f7f4ee")
        tools.pack(fill="x", padx=16, pady=6)
        tk.Label(tools, text="Branch", bg="#f7f4ee").grid(row=0, column=0, sticky="w")
        self.branch_list = ttk.Combobox(tools, textvariable=self.branch, state="readonly", width=28)
        self.branch_list["values"] = (ALL_BRANCHES,)
        self.branch_list.grid(row=1, column=0, padx=(0, 10), sticky="w")
        tk.Label(tools, text="From", bg="#f7f4ee").grid(row=0, column=1, sticky="w")
        self.from_picker = DateEntry(
            tools,
            width=14,
            date_pattern="dd-mm-yyyy",
            background="#1f4d3a",
            foreground="#f7f4ee",
            headersbackground="#1f4d3a",
            headersforeground="#f7f4ee",
            selectbackground="#2f6b52",
            selectforeground="#f7f4ee",
            borderwidth=1,
        )
        self.from_picker.grid(row=1, column=1, padx=(0, 10), sticky="w")
        tk.Label(tools, text="To", bg="#f7f4ee").grid(row=0, column=2, sticky="w")
        self.to_picker = DateEntry(
            tools,
            width=14,
            date_pattern="dd-mm-yyyy",
            background="#1f4d3a",
            foreground="#f7f4ee",
            headersbackground="#1f4d3a",
            headersforeground="#f7f4ee",
            selectbackground="#2f6b52",
            selectforeground="#f7f4ee",
            borderwidth=1,
        )
        self.to_picker.grid(row=1, column=2, padx=(0, 10), sticky="w")
        today = date.today()
        self.from_picker.set_date(today)
        self.to_picker.set_date(today)
        self.run_button = tk.Button(
            tools,
            text="Run compare",
            command=self.run_compare,
            bg="#1f4d3a",
            fg="#f7f4ee",
            activebackground="#2f6b52",
            activeforeground="#f7f4ee",
            relief="flat",
            padx=12,
            pady=6,
        )
        self.run_button.grid(row=1, column=3, padx=(0, 8))
        self.save_button = tk.Button(
            tools,
            text="Save Excel",
            command=self.save_excel,
            relief="flat",
            padx=12,
            pady=6,
            state="disabled",
        )
        self.save_button.grid(row=1, column=4)

        marks = tk.Frame(self, bg="#f7f4ee")
        marks.pack(fill="x", padx=16, pady=(10, 6))
        self.mark_buttons = {}
        for name in MARKS:
            button = tk.Button(
                marks,
                text=f"{name}  0",
                command=lambda chosen=name: self.show_mark(chosen),
                relief="flat",
                padx=12,
                pady=6,
            )
            button.pack(side="left", padx=(0, 8))
            self.mark_buttons[name] = button
        self._paint_marks()

        table = tk.Frame(self, bg="#f7f4ee")
        table.pack(fill="both", expand=True, padx=16, pady=6)
        table.rowconfigure(0, weight=1)
        table.columnconfigure(0, weight=1)
        self.tree = ttk.Treeview(table, columns=[key for key, _, _ in COLUMNS], show="headings")
        for key, title, width in COLUMNS:
            self.tree.heading(key, text=title)
            self.tree.column(key, width=width, minwidth=80, anchor="w", stretch=False)
        yscroll = ttk.Scrollbar(table, orient="vertical", command=self.tree.yview)
        xscroll = ttk.Scrollbar(table, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=yscroll.set, xscrollcommand=xscroll.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        yscroll.grid(row=0, column=1, sticky="ns")
        xscroll.grid(row=1, column=0, sticky="ew")
        self.tree.bind("<<TreeviewSelect>>", self._show_selected)

        detail_frame = tk.Frame(self, bg="#f7f4ee")
        detail_frame.pack(fill="x", padx=16)
        self.detail = tk.Text(
            detail_frame,
            height=3,
            wrap="word",
            bg="#f7f4ee",
            fg="#44403c",
            relief="flat",
            borderwidth=0,
            font=("Segoe UI", 10),
        )
        self.detail.pack(side="left", fill="x", expand=True)
        self.detail.configure(state="disabled")
        detail_scroll = ttk.Scrollbar(detail_frame, orient="vertical", command=self.detail.yview)
        detail_scroll.pack(side="right", fill="y")
        self.detail.configure(yscrollcommand=detail_scroll.set)
        tk.Label(
            self,
            textvariable=self.status,
            bg="#f7f4ee",
            fg="#57534e",
            anchor="w",
            wraplength=1100,
            justify="left",
        ).pack(fill="x", padx=16, pady=(4, 12))

    def _dates(self):
        start = self.from_picker.get_date()
        end = self.to_picker.get_date()
        if not isinstance(start, date):
            start = as_date(start)
        if not isinstance(end, date):
            end = as_date(end)
        if start is None or end is None:
            raise ValueError("Choose a From date and a To date.")
        if start > end:
            raise ValueError("From date is after To date.")
        return start, end

    def _status_signature(self, online, name):
        return (bool(online), name or "")

    def _remember_company(self, online, name, period=None):
        self._tally_online = bool(online)
        self._active_company = name or ""
        self._status_key = self._status_signature(online, name)
        if not online:
            self.company.set("Tally: Offline")
            self.tally_line.set("Offline")
            self.company_label.configure(fg="#9b2c2c")
            return
        if not name:
            self.company.set("Tally: Online    No company is loaded")
            self.tally_line.set("Online. No company is loaded")
            self.company_label.configure(fg="#1f4d3a")
            return
        self.company.set("Tally: Online    " + name)
        self.tally_line.set("Active company: " + name)
        self.company_label.configure(fg="#1f4d3a")
        self._prefer_company_branch()

    def _set_branches(self, names):
        ordered = []
        for name in names:
            if name and name not in ordered:
                ordered.append(name)
        self._site_branches = ordered
        values = [ALL_BRANCHES, *ordered]
        self.branch_list["values"] = tuple(values)
        self._prefer_company_branch()
        if self.branch.get() not in values:
            self.branch.set(ALL_BRANCHES)

    def _prefer_company_branch(self):
        if not self._site_branches or not self._active_company:
            return
        if self.branch.get() not in (ALL_BRANCHES, ""):
            return
        matched = company_branch(self._active_company, self._site_branches)
        if matched:
            self.branch.set(matched)

    def _start_branch_load(self):
        threading.Thread(target=self._read_branches, daemon=True).start()

    def _read_branches(self):
        try:
            self._branch_updates.put(("ok", branch_names()))
        except Exception as error:
            self._branch_updates.put(("error", str(error)))

    def _apply_branch_updates(self):
        if not self.winfo_exists():
            return
        try:
            while True:
                kind, payload = self._branch_updates.get_nowait()
                if kind == "ok":
                    self._set_branches(payload)
                elif kind == "error" and not self._site_branches:
                    self.status.set("Branches could not be read from the tracksheet yet. Run compare will try again.")
        except queue.Empty:
            pass
        self.after(200, self._apply_branch_updates)

    def _set_detail(self, text):
        self.detail.configure(state="normal")
        self.detail.delete("1.0", "end")
        if text:
            self.detail.insert("1.0", text)
        self.detail.configure(state="disabled")

    def _watch_tally(self):
        if not self.winfo_exists():
            return
        if not self._busy and not self._watch_running:
            self._watch_running = True
            threading.Thread(target=self._read_tally_status, daemon=True).start()
        self.after(WATCH_MS, self._watch_tally)

    def _read_tally_status(self):
        try:
            self._tally_status.put(tally_status(timeout=3))
        except Exception:
            self._tally_status.put({"online": False, "name": "", "period": None})

    def _apply_tally_status(self):
        if not self.winfo_exists():
            return
        try:
            while True:
                status = self._tally_status.get_nowait()
                self._watch_running = False
                if self._busy:
                    continue
                online = bool(status.get("online"))
                name = status.get("name") or ""
                key = self._status_signature(online, name)
                if key == self._status_key:
                    continue
                self._remember_company(online, name)
        except queue.Empty:
            pass
        self.after(200, self._apply_tally_status)

    def run_compare(self):
        if self._busy:
            return
        if not self._tally_online or not self._active_company:
            messagebox.showerror(
                "Aryabhangy Compare",
                "Tally is offline, or no company is loaded. Open a company in Tally and wait until the app shows Online.",
            )
            return
        try:
            start, end = self._dates()
        except ValueError as error:
            messagebox.showerror("Aryabhangy Compare", str(error))
            return
        self._busy = True
        self.run_button.configure(state="disabled")
        self._set_detail("")
        self.status.set("Reading the company that is open in Tally.")
        branch = self.branch.get()
        threading.Thread(target=self._load, args=(start, end, branch), daemon=True).start()
        self.after(200, self._poll_load)

    def _load(self, start, end, branch):
        try:
            name = current_company()
            self._updates.put(("company", True, name))

            def track_progress(day, count):
                self._updates.put(("progress", "Tracksheet", day, count))

            loaded = job_cards(start, end, progress=track_progress)
            names = branches_in(loaded)
            used = branch if branch and branch != ALL_BRANCHES else company_branch(name, names)

            def tally_progress(day, count):
                self._updates.put(("progress", "Tally", day, count))

            tally_records = hirise_vouchers(start, end, progress=tally_progress)
            for record in tally_records:
                record.branch = used
            track_records = filter_records(loaded, start, end, used or branch)
            track_records = merge_tracksheet_for_tally_jcs(
                track_records,
                tally_records,
                used or branch,
                job_cards_by_numbers,
            )
            result = compare(track_records, tally_records)
        except Exception as error:
            self._updates.put(("error", str(error)))
            return
        self._updates.put(("done", name, loaded, used or branch, start, end, result, tally_records))

    def _poll_load(self):
        try:
            while True:
                item = self._updates.get_nowait()
                kind = item[0]
                if kind == "company":
                    self._remember_company(item[1], item[2])
                elif kind == "progress":
                    self.status.set(
                        "Reading " + item[1] + " for " + format_date(item[2]) + ". " + str(item[3]) + " read so far."
                    )
                elif kind == "error":
                    self._busy = False
                    self.run_button.configure(state="normal")
                    messagebox.showerror("Aryabhangy Compare", item[1])
                    return
                elif kind == "done":
                    self._show_loaded(*item[1:])
                    return
        except queue.Empty:
            pass
        if self._busy:
            self.after(200, self._poll_load)

    def _show_loaded(self, name, loaded, branch, start, end, result, tally_records):
        try:
            merged = list(self._site_branches)
            for name in branches_in(loaded):
                if name not in merged:
                    merged.append(name)
            self._set_branches(merged)
            names = [ALL_BRANCHES, *merged]
            if branch in names:
                self.branch.set(branch)
            elif self.branch.get() not in names:
                self.branch.set(ALL_BRANCHES)
            self.result = result
            self.tally_records = tally_records
            self.skipped = 0
            if result is None:
                self.save_button.configure(state="disabled")
                for mark in MARKS:
                    self.mark_buttons[mark].configure(text=f"{mark}  0")
                note = "The compare did not finish."
                self._set_detail(note)
                self.status.set(note)
                return
            self.save_button.configure(state="normal")
            for mark in MARKS:
                self.mark_buttons[mark].configure(text=f"{mark}  {result.count(mark)}")
            chosen = CHECK if result.count(CHECK) else ADDED if result.count(ADDED) else REMOVED
            self.show_mark(chosen)
            branch_text = branch or "the open company"
            note = (
                f"{ADDED} {result.count(ADDED)}. {REMOVED} {result.count(REMOVED)}. "
                f"{CHECK} {result.count(CHECK)}. "
                f"Hirise bills {len(tally_records)}. "
                f"Tracksheet rows for {branch_text} {result.track_rows}."
            )
            if not tally_records:
                note += " Tally returned no Hirise Invoice Service bills for these dates."
            self.status.set(note)
        finally:
            self._busy = False
            self.run_button.configure(state="normal")

    def show_mark(self, mark):
        self.mark.set(mark)
        self._paint_marks()
        children = self.tree.get_children()
        if children:
            self.tree.delete(*children)
        self._set_detail("")
        if self.result is None:
            return
        for index, outcome in enumerate(outcome for outcome in self.result.outcomes if outcome.mark == mark):
            self.tree.insert(
                "",
                "end",
                iid=str(index),
                values=(
                    outcome.job_card,
                    outcome.vehicle,
                    outcome.customer,
                    outcome.when,
                    outcome.adviser,
                    outcome.reason,
                ),
            )
        if not self.tree.get_children():
            self._set_detail(self._empty_text(mark))

    def _empty_text(self, mark):
        if mark == ADDED:
            return "No bill was added. A bill is added only when the job-card number and the vehicle number are the same in Tally and on the tracksheet."
        if mark == REMOVED:
            return "No row was removed. A row is removed only when both numbers match and the tracksheet bill is missing in Tally."
        return "Nothing needs a manual check for this run."

    def _paint_marks(self):
        colors = {
            ADDED: "#e7f5ee",
            REMOVED: "#fdecec",
            CHECK: "#fbf3e4",
        }
        for name, button in self.mark_buttons.items():
            button.configure(bg=colors[name] if self.mark.get() == name else "#ffffff")

    def _show_selected(self, _event):
        selected = self.tree.selection()
        if not selected:
            return
        values = self.tree.item(selected[0], "values")
        if values:
            self._set_detail(values[-1])

    def save_excel(self):
        if self.result is None:
            return
        path = filedialog.asksaveasfilename(
            title="Save Excel",
            defaultextension=".xlsx",
            initialfile="Aryabhangy_compare.xlsx",
            filetypes=[("Excel", "*.xlsx")],
        )
        if not path:
            return
        lines = summary_lines(
            self.result,
            SITE,
            self._active_company or self.company.get(),
            self.tally_records,
            self.skipped,
        )
        write_report(path, lines, self.result.outcomes, vouchers=self.result.vouchers)
        self.status.set(f"Saved {path}")


def main():
    app = CompareApp()
    app.mainloop()


if __name__ == "__main__":
    main()
