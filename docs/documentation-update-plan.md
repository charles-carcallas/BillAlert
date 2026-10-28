# BillAlert full documentation update implementation plan

Prepared 24 October 2026

## Outcome and boundaries

Produce a revised Phase 1 Word document that consistently describes the current BillAlert project across all ten required sections. Include readable use case diagram images derived from the supplied seven-page Draw.io file. Preserve the academic submission structure, team details and original source files.

This plan concerns documentation and diagram updates. It does not authorize application changes, database migrations, deployment, live account changes or sending SMS. Requirements and acceptance targets must remain distinct from implemented behavior and verified results.

## Inputs

- Original document: `C:/Users/Charles Carcallas/Downloads/BillAlert_Phase1 Final (1).docx`.
- Working document: `docs/deliverables/BillAlert_Phase1_User_Stories_Updated.docx`, containing the revised 31-story Section 8.
- Diagram source: `C:/Users/Charles Carcallas/Documents/college/thirdyear/firstsem/Mobile Application Development/BillAlert/01_Phase1_Submission/Use Case Diagram.drawio`.
- Evidence: current application code, routing, configuration, repository tests, backend definitions and dated project notes. Older implementation reports are supporting history, not automatic proof of current behavior or live deployment.

## 1. Establish the documentation baseline

1. Copy the working document and diagram into a dedicated output workspace; retain originals unchanged.
2. Inventory all ten sections, tables, images, captions, references, page settings and headers/footers.
3. Record the source revision and review date. Build an evidence matrix with feature, current behavior, source location, test evidence, deployment evidence, affected sections and unresolved questions.
4. Classify findings as implemented in source, tested locally, verified on a device/live environment, planned, superseded or unresolved. Do not infer deployment from the existence of migrations or tests.

**Completion check:** every material change has an evidence source or is explicitly identified as a proposed requirement or unresolved point.

## 2. Reconcile current behavior and requirement identifiers

Review the following workflows against code and the newest applicable definitions:

- Username authentication, temporary-password replacement, password recovery, device unlock, role/area restrictions and sign-out.
- One-login household/work views, staff assignment and replacement, household linking and occupant handover, login suspension and President succession.
- Offline reading, amount and notice capture; owner-scoped queues; retry and uncertainty handling; online-only cash collection and account/fund actions.
- Reading validation and unpriced bills; manually entered BOHECO amounts; whole-peso rounding; configurable billing and collection schedules.
- Current collection, receipts, reserve allocations and repayments, BOHECO referrals and verified external payments, remittance and monthly Reader compensation.
- Consumer and staff Inbox behavior, SMS dispatch/delivery tracking, locally scheduled phone alerts and permission-dependent urgent reminders.
- Notice eligibility, service evidence, deadline checks, outcomes and recorded supply status.

Preserve existing FR identifiers where their meaning remains stable. Explain the absent FR-02 rather than silently shifting identifiers. Normalize malformed labels such as `FR-2 2`. Assign new identifiers above the existing highest ID for newly documented requirements, and mark replaced requirements explicitly. Cross-reference code's legacy requirement labels rather than assuming they match the academic document.

Recheck the earlier User Stories draft during this pass. In particular, settle staff-slot rules, password policy, date-range search and scannable receipts with evidence; do not leave unsupported completion claims or vague acceptance criteria.

**Completion check:** one agreed requirement register drives the prose, stories, diagrams and screen descriptions.

## 3. Update all ten document sections

| Section | Planned revision | Acceptance check |
|---|---|---|
| Cover and 1. Project Title | Preserve team/course details, clarify the revision date, repair broken text, and align the title/tagline with actual scope. Keep submission date unset unless supplied. | No invented academic or submission details. |
| 2. Problem Statement | Retain the local billing problem; remove unsupported claims about universal phone ownership, causes of nonpayment, guaranteed instant/free push delivery and browser offline limitations. | Local observations, research findings and design rationale are distinguishable. |
| 3. Objectives | Replace outdated emergency-broadcast and universal SMS-reminder promises with measurable objectives matching current notification and billing workflows. | Each objective maps to requirements and a verification method. |
| 4. Scope and Limitations | Include account lifecycle, schedules, reserve funds, remittance, external settlement verification and compensation. Correct offline-payment, supported-platform and fixed-configuration descriptions. | In-scope behavior matches the register; external integrations, physical cash and actual disconnection boundaries are clear. |
| 5. Target Users | Update the responsibilities of Consumers, Area Presidents, Readers and Cashiers, including household/work access and handovers. Qualify unverified demographic assertions. | Role descriptions match actual permissions and workflows. |
| 6. Literature Review | Verify cited works, findings, bibliographic details and current competitor claims using primary sources. Remove unsupported complaints and conclusions not established by the cited research. | Every substantive external claim has a supporting citation; comparison does not overstate BillAlert benefits. |
| 7. Requirements Analysis | Publish the reconciled FR register and measurable NFRs. Distinguish performance/security targets from observed results and confirm platform support from configuration. | Unique IDs, testable wording, priorities and explicit gaps; no target presented as a measured result. |
| 8. User Stories | Revise the existing 31-story draft against the final register; split or add stories where necessary and replace temporary extension labels with stable references. | Every active FR maps to at least one story; each row uses “As a … I want … so that …” and has at least three observable acceptance criteria. |
| 9. Use Case Diagram | Reconcile the supplied Draw.io pages, export and insert images, and rebuild the actor/use-case inventory. | Diagram, inventory, requirements and stories agree; figures remain readable at document size. |
| 10. Wireframes / Mockups | Replace stale screen images and explanations with current representative screens using synthetic or masked data. Mark conceptual screens as mockups. | Role navigation, terminology, offline states, payment routes and notices match current behavior. |

## 4. Prepare and integrate the use case diagram images

The supplied file has seven pages: Context, Shared – Authenticated User, Consumer, Meter Reader, Cashier, Admin and Notification Engine.

1. Keep an untouched copy and edit a separate Draw.io source.
2. Correct the confirmed Admin-page error: “Issue Disconnection Notice” references FR-22 but belongs to FR-37 in the existing document. Recheck all other labels against the final register.
3. Recalculate the context-page counts; they currently disagree with some detail pages. Remove presentation counts if they add maintenance burden without helping readers.
4. Review actor associations, system boundaries, generalization and `include`/`extend` directions. Represent constraints such as Philippine time and duplicate-reading prevention as constraints, not standalone user goals.
5. Correct the old sync associations and SMS-escalation model to match the verified offline and notification workflows. Distinguish app/local notifications from a remote push service unless a remote service is actually implemented.
6. Add current account, schedule, reserve fund, remittance, compensation and BOHECO verification use cases. Split dense pages into additional detail pages if necessary. BOHECO verification must not imply an automated BOHECO API integration.
7. Export the context overview and each detail page as tightly cropped, high-resolution PNG images, sized for readable text at approximately 300 dpi. Retain SVG exports if supported for future editing.
8. Insert the overview first in Section 9, followed by captioned detail figures. Use landscape sections where required instead of shrinking labels. Provide meaningful alternative text and update the inventory and figure references.
9. Check every exported image for clipped connectors, missing labels, unreadable text and incorrect arrow direction.

**Completion check:** the final DOCX embeds the diagram images, and a separately editable updated `.drawio` file reproduces them.

## 5. Build and validate the revised Word file

- Preserve the template's overall academic style while repairing headings, broken characters, inconsistent capitalization and spacing.
- Use proper heading styles, fixed table widths within page margins, repeating table headers and appropriate row/page breaks.
- Remove obsolete guidance or unresolved drafting language from final prose; keep necessary limitations and explicitly planned requirements.
- Refresh page/figure references and any generated fields. Preserve images and content outside intentional revisions.
- Check the FR-to-story-to-use-case matrix automatically for missing IDs, duplicate IDs, uncovered requirements and stories with fewer than three criteria.
- Verify bill amounts are never described as calculated from consumption; reserve repayments are not counted as second BOHECO remittances; external settlements do not invent Cashier receipts.
- Verify disconnection timing claims against authoritative sources before describing them as legal guarantees. Distinguish recorded notices from actual cooperative field action.
- Render the final DOCX and inspect every page for readable figures, complete tables, clipping, orphaned headings, unwanted blank pages and header/footer placement.

**Known prerequisite:** the previous render attempt failed because LibreOffice was unavailable. Resolve access to an approved document renderer before claiming visual verification; structural validation alone cannot establish page-layout quality.

## Execution order and review gates

1. Baseline and evidence audit.
2. Requirement reconciliation and identifier mapping.
3. Sections 1–8 and source verification.
4. Diagram reconciliation and Section 9 images.
5. Current screen evidence and Section 10.
6. Cross-document consistency checks, rendering and final corrections.

Continue independently where evidence is sufficient. Ask only about substantive unresolved scope choices or missing factual details; group those questions after the audit. Do not silently implement missing application features to make the documentation appear complete.

## Final deliverables

- `docs/deliverables/BillAlert_Phase1_Fully_Updated.docx` — revised complete document with embedded diagram images.
- `docs/deliverables/BillAlert_Use_Case_Diagram_Updated.drawio` — matching editable diagram source.
- `docs/deliverables/BillAlert_Documentation_Change_Log.md` — concise section-by-section changes, traceability summary and remaining verification gaps.

Keep render previews, scripts and image intermediates in the working folder. Completion requires consistent content, complete requirement coverage, embedded readable diagrams and a successful visual review—not merely a saved Word file.

## Execution completed — 24 October 2026

The full document update is complete in `docs/deliverables/BillAlert_Phase1_Fully_Updated.docx`. All ten sections were revised, including FR-16, FR-04 and NFR-02, and the implemented FR-25/FR-29 behavior. The register now has 51 active FRs mapped to 36 stories, each with at least three criteria. Nine use-case figures and four paired schematic mockup figures are embedded. The matching editable diagram and detailed evidence/change log are in the same deliverables folder.

The Windows renderer was located, the document rendered successfully, and all 36 pages were visually reviewed. Requirement coverage, document structure and diagram associations passed automated checks. Device, live deployment and operational acceptance checks remain explicitly separated from source implementation.
