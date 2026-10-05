# Project Log - Music Trends for Radio Hosts

[Return to README](README.md)

**Repository:** [Nohka/dataeng_spotify](https://github.com/Nohka/dataeng_spotify)  
**Log started:** 2026-10-05  
**Date convention:** `YYYY-MM-DD`; use Europe/Tallinn for project activity timestamps when times are included.

This log records project progress, decisions, evidence and lessons for interim and final reporting. It is a human-maintained project record, not a pipeline execution log or an automatic copy of Git history.

## Recording rules

Record actual outcomes, not just intentions. Identify the people who did the work separately from the person responsible for the next step. Link artifacts, commits, pull requests, source profiles or review notes; do not invent links or assign unconfirmed work to a team member.

Use these statuses consistently:

| Status | Meaning |
|---|---|
| Planned | Work has been identified; no completed output is claimed |
| Drafted | An output exists and needs review |
| In review | Review is underway; name the reviewer when known |
| Verified | The stated acceptance check is satisfied and evidence is recorded |
| Blocked | Progress depends on a named unresolved issue |
| Deferred | Deliberately outside the current scope |

State what was verified. A reviewed design is not the same as executable SQL, and successful SQL execution is not the same as correct source data or a running pipeline. Use "not recorded" for an unknown fact; it must not be interpreted as zero work or a failed test.

Add new entries at the top of the dated-updates section. For retrospective entries, record both the activity date and the date added to the log; retain uncertainty instead of guessing. For a correction, add a new entry identifying the earlier entry and its replacement conclusion. Preserve the original sequence of decisions.

## Dated updates

### LOG-004 | 2026-10-05 | README, project log and full team roster drafted

**Status:** Drafted. **Recorded on:** 2026-10-05.  
**Contributors:** ChatGPT-assisted documentation draft; the requesting team member supplied the four full names. Individual human authorship and review are not assigned by this entry.

**Change and purpose:** Prepared a repository README and this project log. Added Kristel Saul, Kadi-Liis Kivi, Laura Jõgi and Tarvo Metspalu, using the working responsibilities in the original project draft. Added a consistent update template, a decision register, report snapshots and an LLM-disclosure register so later reports can trace outcomes to evidence.

**Evidence:** [README.md](README.md), [PROJECT_LOG.md](PROJECT_LOG.md), the original `part1_submission.docx`, and the project discussion dated 2026-10-05. These are documentation artifacts; no GitHub commit or merge is asserted.

**Review/result:** Contribution percentages remain unassigned. Historical work is not attributed to people merely because they own a workstream. Team acceptance and repository integration are pending.

**Next action:** All four members confirm their responsibilities and the initial entries; nominate a rotating log maintainer and agree how final contribution percentages will be recorded. No deadline has been set in the supplied material.

### LOG-003 | 2026-10-05 | Three-page report and minimal v1 companion drafted

**Status:** Drafted. **Recorded on:** 2026-10-05.  
**Contributors:** ChatGPT-assisted drafting in the project discussion; individual team contributions and approvals are not recorded.

**Change and purpose:** Condensed the proposal into an editable three-page report and a matching core package. The minimal v1 uses one daily-track fact, four dimensions and three supporting tables. Defined Weekly Hotness, Weekly Momentum and Top-20 Consistency, and drafted five SQL queries aligned to the five business questions. Recorded the repository location supplied by the team; this is not a claim about when the repository was created.

**Evidence:** `music_trends_3_page_report.docx`; `music_trends_repo_companion.zip`, containing `sql/01_core_schema.sql`, `sql/02_metric_views.sql`, `sql/03_demo_queries.sql` and the two v1 dictionaries. The companion uses the separate `music_report_v1` namespace.

**Review/result:** The report draft was supplied as three pages. Final pagination must be checked after edits and PDF export. The SQL was supplied as design SQL, without source loading or PostgreSQL execution evidence. Contribution percentages, shared-chat links, source profiles and the agreed European panel remain to be completed.

**Next action:** Kristel reviews business questions and architecture; Laura and Kadi-Liis review sources/tooling and queries within their workstreams; Tarvo reviews model/dictionary alignment. The group reconciles the files with the repository and accepts or revises the v1 proposal.

### LOG-002 | 2026-10-05 | Localisation and AI-origin scope clarified

**Status:** Drafted. **Recorded on:** 2026-10-05.  
**Contributors:** Project discussion with ChatGPT; individual team review is not recorded.

**Change and purpose:** Distinguished chart-market popularity from artist geographic association and recording language. Proposed MusicBrainz as a second source for identity and locality evidence. Proposed a rule making a track local when at least one credited artist has a reviewed primary association with the market. Considered AI-origin assessment, but retained it as a separate evidence-based extension rather than an inferred Boolean.

**Evidence:** Project discussion dated 2026-10-05; expanded drafts `music_trends_data_dictionary.xlsx` and `music_trends_schema.sql`; the narrowed scope subsequently recorded in the report-v1 DOCX and companion.

**Review/result:** This was a source and model proposal, not a performed artist-matching exercise or an AI-detection experiment. No locality coverage, detector accuracy, or track-level AI labels were measured. The later minimal v1 supersedes the expanded model for the three-page report; retain the larger design only with a clear separate label.

**Next action:** Laura and Kadi-Liis assess the proposed extracts and matching evidence; Tarvo checks that accepted locality rules and unknown handling are represented consistently in the core model. Team approval is pending.

### LOG-001 | 2026-10-05 | Initial project draft reviewed as the baseline

**Status:** Drafted. **Recorded on:** 2026-10-05.  
**Contributors:** The original draft is team-supplied; exact authoring dates and completed per-person work are not established by this log.

**Change and purpose:** Used the existing draft as the starting point for the business brief, data-source selection, tooling, architecture, model, dictionary and demo queries. Identified required deliverables: a maximum-three-page report, roles/contribution percentages, LLM-chat links, a README and relevant SQL. The source requirements include two distinct datasets of at least 1,000 rows and eight columns each.

**Evidence:** `part1_submission.docx`, including its workstream labels and requirements. This entry records review of an existing draft, not the date that draft was originally written.

**Review/result:** The initial draft contained an unresolved country-listener question and a candidate mixed daily-track/weekly-album fact. Subsequent v1 proposals changed Q5 to distinct chart-presence days and separated measurement grains. Dataset counts and source-to-warehouse mappings remain subject to verification.

**Next action:** Review the later v1 artifacts against the original requirements; preserve accepted changes and record any further revisions rather than treating the original draft as a validated implementation.

## Decision register

The rows below capture the **current v1 proposals**, not unrecorded team approvals. Update the status and add the accepting/revising log entry when the team decides. Do not silently overwrite a superseded decision.

| ID | Proposal and rationale | Status / evidence |
|---|---|---|
| DEC-001 | Use daily track charts plus reviewed artist-locality enrichment as the minimal scope. Keep other measurement grains in separate future facts. | Proposed; LOG-002, LOG-003 |
| DEC-002 | Use explicit identifiers and a track-artist bridge rather than name-only joins or pipe-separated foreign keys. | Proposed in v1 schema; LOG-003 |
| DEC-003 | Require complete market weeks and a fixed comparison panel; use distinct presence counts to prevent collaboration-related duplication. | Proposed in v1 metrics/queries; LOG-003 |
| DEC-004 | Interpret label and locality using current supplied/reviewed attribution. Do not claim reconstructed historical ownership or nationality. | Proposed in v1 report/dictionary; LOG-003 |
| DEC-005 | Defer AI-origin classification until recording-level evidence, a suitable assessment source and an evaluation plan exist. | Proposed scope boundary; LOG-002, LOG-003 |

## Next review queue

Working review leads are taken from the original draft; they do not imply these tasks have already been completed. Agree any changes and deadlines as a group.

| Item | Working review lead(s) | Evidence needed to close the item |
|---|---|---|
| Accept the business questions and KPI meanings | Kristel Saul, with query review by Kadi-Liis Kivi | Recorded decision; aligned report and Q1-Q5 |
| Verify both source extracts and identity-matching feasibility | Laura Jõgi and Kadi-Liis Kivi | Actual versions, row/column counts, coverage, missingness and matching findings |
| Accept the core model and dictionary | Tarvo Metspalu, with initial dictionary support from Kadi-Liis Kivi | Schema/dictionary consistency review and SCD rationale |
| Confirm architecture, refresh plan and coverage rules | Kristel Saul and Laura Jõgi | Review of data flow, quality checks and agreed European panel |
| Finalise the submission and contribution record | All four members | Agreed percentages totalling 100%, accessible LLM links, reviewed repository files and final PDF pagination |

A running pipeline is outside the stated Part 1 requirement. Log implementation work separately if the team later adds it; do not label the design submission incomplete solely because the proposed services are not deployed.

## Update template

Copy this block for a real activity and replace the bracketed instructions. Record unperformed checks as "Not run" and unknown values as "Not recorded". One meaningful work-session entry is normally more useful than one entry per minor edit.

```markdown
### LOG-NNN | YYYY-MM-DD | Specific outcome or change

**Status:** Planned / Drafted / In review / Verified / Blocked / Deferred
**Activity date:** YYYY-MM-DD, or a documented range
**Recorded on:** YYYY-MM-DD
**Contributors:** Names and each person's actual contribution
**Reviewer:** Name and review date, or Not reviewed

**Change:** What changed from the previous state?
**Why it matters:** Which business question, requirement or risk does it address?
**Evidence:** File path, commit, pull request, issue, source profile or review note.
**Checks/results:** What was checked, how, and the observed outcome? Say Not run when applicable.
**Decision or limitation:** What was accepted, rejected, deferred, or remains uncertain?
**Next action:** Named owner, concrete next step and an agreed date if one exists.
**LLM use:** Disclosure ID or No LLM use for this entry.
```

For a data-related update, record source versions, input/output row counts and the reason for changes; distinguish removed duplicates, rejected records and missing data. For a query update, record the reporting dates, market panel, query version and test or review evidence. These details make later progress statements reproducible.

## Reporting snapshots

### SNAP-001 | 2026-10-05 | Initial documented position

**Period covered:** 2026-10-05. **Basis:** LOG-001 to LOG-004. **Review status:** Draft; awaiting team confirmation.

The project has progressed from an initial multi-file chart-analysis draft to a narrower v1 proposal focused on daily track trends and reviewed artist localisation. An editable three-page report, core schema, dictionary, metric views and five business-question queries have been drafted. A README and structured project log now provide a basis for tracking later work. Source profiling, team approval of the model and metrics, contribution percentages and LLM disclosure links remain open. No validated music-trend findings, completed locality matching or executed pipeline results are claimed by this snapshot.

**Individual contributions:** Working responsibilities are listed in the README, but completed work and contribution percentages must be confirmed by the team. Do not use this snapshot to infer equal contributions.

### Reporting snapshot template

```markdown
### SNAP-NNN | YYYY-MM-DD | Reporting checkpoint

**Period covered:** YYYY-MM-DD to YYYY-MM-DD
**Prepared/reviewed by:** Names
**Evidence entries:** LOG-NNN, LOG-NNN; relevant commits or artifact versions

**Starting position:** What was the status at the start of this period?
**Progress and outputs:** What changed, and which outputs were produced or accepted?
**Verification:** Which checks passed, failed or were not run? Include the evidence.
**Decisions and learning:** Which assumptions, methods or scope choices changed, and why?
**Contributions:** What did each participating team member actually do?
**Open risks/blockers:** What remains unresolved and what is its impact?
**Next period:** Priorities, owners and agreed dates, if any.

**Report-ready summary:** A short paragraph linking progress to evidence and clearly
separating completed work from proposals and remaining tasks.
```

Use snapshots as evidence for the short report rather than pasting the entire log into it. Do not report a percentage complete without an agreed task list and completion rule. Count reviewed deliverables, measured source coverage or completed checks only when their denominators and evidence are recorded.

## LLM disclosure register

Add an entry for **every AI/LLM conversation used**. Include accessible shared links in the final report and check that they do not expose credentials or unrelated private material.

| ID | Date / scope | Tool | Shared conversation link | Review status |
|---|---|---|---|---|
| LLM-001 | 2026-10-05: source/locality and AI-scope discussion; model, KPIs, SQL, dictionary, report, README and log drafting in this project conversation | ChatGPT | To be added by the team | Team review and disclosure-link verification pending |

The initial project draft also mentions LLM advice on KPIs. Confirm whether that came from a separate conversation and add its link when applicable; the current entry must not be assumed to cover an unidentified earlier chat. Each member should add any other project-related LLM use before submission.

## Evidence basis and limits

Initial entries were reconstructed on 2026-10-05 from the team-supplied `part1_submission.docx`, `music_trends_3_page_report.docx`, `music_trends_repo_companion.zip`, the earlier model/dictionary drafts and the dated project discussion. They do not establish GitHub commit history, original authoring dates, unrecorded meetings, source-data validation or individual contribution percentages. Add repository evidence and corrections as the team reviews the entries.
