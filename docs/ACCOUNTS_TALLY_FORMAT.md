# Tally format for accounts (JC + registration)

The compare app reads **Hirise Invoice Service** vouchers (and uses every bill found for the same JC when checking VAS).

## Registration (vehicle)
Put the registration in the **Party A/c name**, after the customer name.

Examples that parse correctly:
- `SANEESH - KL 41W 6899`
- `MUBEENA KL40U2463`
- `ANTONY KL 39  U 6930`

Pattern: Indian plate `KL` + district digits + letters + number (spaces optional).

## Job card number
Put the JC in the **Narration** in this form:

`Jobcard.No :JC-KL100001-02-2627-007322 ,Jobcard.Date :12-Nov-26, Vehicle Model :DIO, Customer Name :MUBEENA C S`

Minimum needed: a token like `JC-…-007322` (six-digit JC at the end) or `007322/26`.

## Why this matters
- Registration is taken from **party name**
- JC is taken from **narration**
- If either is missing or mistyped, the voucher is marked **Check manually** / appears on **Vouchers** as no job card
