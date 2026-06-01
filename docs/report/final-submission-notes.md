# CryptoFlow — Final Submission Notes (Exercise 8)

**Team:** Ioannis Theodosiadis (25-603-457), Cyril Gabriele (21-558-358)

The attached report is the final, combined version. It addresses all Assignment 1 requirements
and is the version to be graded together with Assignment 2.

## Final release

- **v1.1.0 (final, graded):** <https://github.com/cyrilgabriele/EDPO-Project-FS26/releases/tag/v1.1.0>
- v1.0.0 (original Assignment 1): <https://github.com/cyrilgabriele/EDPO-Project-FS26/releases/tag/v1.0.0>

## Changes since the previous submission (v1.0.0 → v1.1.0)

- **Combined report.** For the final submission we merged the Assignment 1 report into a single
  report and added chapters covering the second half of the course, so it now covers the full
  course objectives. The Assignment 1 content and process-oriented model are unchanged except
  for the BPMN change below.
- **`placeOrder` BPMN human intervention (ADR-0035).** The two operations tasks no longer
  terminate the process; after the intervention the flow now continues. An approval failure
  loops back to *Approve Order* and retries; a publication failure skips forward to *Send Order
  Executed Email*, because the approved-order event is already published and the portfolio
  update is choreographed downstream — nothing is left for the process to revert, so the
  remaining outbox-bookkeeping anomaly is resolved out of band by a human ops member.
