# BillAlert full documentation change log

Revised 24 October 2026. Source baseline: Git HEAD `7256f97` plus the current uncommitted project changes. Source implementation was inspected; no live deployment, SMS or account changes were performed.

## Changes across all ten sections

1. Preserved team/course/instructor details and blank submission date; updated the title, tagline and revision context.
2. Rewrote the local problem statement without unsupported prevalence, causation or delivery guarantees.
3. Mapped objectives to the current feature scope and evaluation methods.
4. Added account lifecycle, schedule, reserve, trip, settlement and compensation scope and explicit operational limits.
5. Reconciled role responsibilities and household/work access.
6. Checked research metadata/abstracts and official competitor features; narrowed claims to the available evidence.
7. Updated all original FRs and seven NFRs; preserved unused FR-02 and added FR-38–52 for current features.
8. Revised all stories, added focused stories and generated complete FR-to-story-to-figure mapping.
9. Rebuilt the seven supplied diagram groupings and added two detail pages; corrected the notice ID to FR-37 and replaced the remote-push/escalation model.
10. Replaced stale screens with clearly labeled, synthetic schematic mockups aligned to current responsibilities.

## Requested corrections

- **FR-04 / NFR-02:** at least eight characters and matching confirmation; removed unsupported uppercase/number/symbol requirements. Described native secure storage, encrypted native database, offline verifier and web limitations without claiming a production security audit.
- **FR-16:** bill-ready app/Inbox plus optional default-enabled SMS; app-only pre-due reminder; configurable overdue channel with overdue SMS disabled by source default; notice SMS plus Inbox record. Local Android alerts use polling, not Firebase remote push. Delivery and read states remain distinct.
- **FR-25 / FR-29:** included implemented payment-date filtering and reference QR codes, with their actual limits and existing local test evidence.

## Traceability (51 FRs / 36 stories / 9 figures)

Every active FR has one or more stories, every story has at least three criteria, and every FR is present in the use-case inventory or its explicit constraints. Each story follows the requested “As a … I want … so that …” form.

| FR | Stories | Diagram figures | Source evidence |
|---|---|---|---|
| FR-01 | US-01 | 1, 2 | `lib/data/repositories/auth_repository_impl.dart` |
| FR-03 | US-02 | 1, 2 | `lib/presentation/auth/change_password_screen.dart` |
| FR-04 | US-02 | 1, 2 | `lib/domain/usecases/auth/change_password.dart` |
| FR-05 | US-03 | 1, 2 | `lib/data/security/local_auth_device_unlock.dart; lib/data/security/secure_password_verifier.dart` |
| FR-06 | US-04 | 1, 2 | `lib/data/repositories/auth_repository_impl.dart; lib/data/sync/outbox_session.dart` |
| FR-07 | US-05 | 1, 2 | `lib/presentation/consumer/phone_alerts_gate.dart; lib/presentation/common/profile_screen.dart` |
| FR-08 | US-06 | 1, 2 | `lib/presentation/consumer/contact_number_controller.dart` |
| FR-09 | US-07 | 1, 2, 3 | `lib/data/local/query_cache.dart; lib/data/repositories/bill_repository_impl.dart` |
| FR-10 | US-08 | 1, 2, 4 | `lib/data/repositories/outbox_repository_impl.dart; lib/data/sync/supabase_outbox_gateway.dart` |
| FR-11 | US-08 | 1, 2, 4 | `lib/data/sync/sync_service.dart; lib/data/network/foreground_poll.dart` |
| FR-12 | US-07, US-08 | 1, 2, 4 | `lib/presentation/common/saved_list_time.dart; lib/data/sync/sync_service.dart` |
| FR-13 | US-09 | 1, 6, 7 | `supabase/migrations/17_bill_cooperative_amount.sql` |
| FR-14 | US-10 | 1, 7 | `lib/domain/usecases/consumer/refresh_phone_alerts.dart` |
| FR-15 | US-10 | 1, 7 | `supabase/migrations/13_sms_delivery.sql` |
| FR-16 | US-09, US-10, US-20 | 1, 6, 7 | `supabase/migrations/13_sms_delivery.sql; supabase/migrations/14_bill_sms.sql; lib/data/notifications/supabase_alert_feed.dart` |
| FR-17 | US-11 | 1, 3, 7 | `lib/domain/usecases/consumer/load_notification_details.dart` |
| FR-18 | US-11 | 1, 3, 7 | `lib/data/repositories/notification_repository_impl.dart` |
| FR-19 | US-12 | 1, 4 | `lib/presentation/reader/roster_controller.dart` |
| FR-20 | US-12, US-36 | 1, 4 | `lib/presentation/reader/reading_entry_screen.dart` |
| FR-21 | US-13, US-36 | 1, 4 | `lib/data/repositories/reading_repository_impl.dart` |
| FR-22 | US-13 | 1, 4 | `lib/data/repositories/reading_repository_impl.dart; supabase/migrations/01_schema.sql` |
| FR-23 | US-14 | 1, 3 | `lib/presentation/consumer/current_bill_screen.dart; lib/presentation/consumer/bill_details_sheet.dart` |
| FR-24 | US-15 | 1, 3 | `lib/presentation/consumer/history_screen.dart` |
| FR-25 | US-32 | 1, 3 | `lib/presentation/consumer/payment_history_filter.dart; lib/presentation/consumer/history_screen.dart` |
| FR-26 | US-15 | 1, 3 | `lib/presentation/consumer/receipt_screen.dart` |
| FR-27 | US-20 | 1, 3 | `lib/presentation/consumer/notification_details_controller.dart` |
| FR-28 | US-16, US-28 | 1, 5 | `lib/domain/usecases/cashier/record_cash_payment.dart; lib/data/repositories/payment_repository_impl.dart` |
| FR-29 | US-17, US-28 | 1, 3, 5 | `lib/presentation/common/receipt_qr_code.dart; lib/presentation/cashier/record_payment_screen.dart` |
| FR-30 | US-17 | 1, 5 | `lib/presentation/cashier/receipt_details_sheet.dart` |
| FR-31 | US-18 | 1, 6, 8 | `lib/presentation/admin/create_account_screen.dart; docs/week13/household_required_accounts.md` |
| FR-32 | US-21 | 1, 6 | `lib/presentation/admin/disconnections_screen.dart; supabase/migrations/20261002034514_disconnection_review.sql` |
| FR-33 | US-22, US-25 | 1, 2 | `lib/domain/time/ph_clock.dart; lib/domain/value_objects/ph_date.dart` |
| FR-34 | US-16 | 1, 5 | `lib/presentation/cashier/receipts_screen.dart` |
| FR-35 | US-17 | 1, 5 | `lib/presentation/cashier/receipts_controller.dart; docs/week13/billing_schedule.md` |
| FR-36 | US-19 | 1, 6 | `lib/domain/usecases/admin/post_bill_amount.dart; supabase/migrations/17_bill_cooperative_amount.sql` |
| FR-37 | US-20, US-21 | 1, 6, 7 | `supabase/migrations/20261004060000_referred_disconnection_notices.sql` |
| FR-38 | US-23 | 1, 2, 8 | `lib/presentation/common/account_view_menu.dart` |
| FR-39 | US-24 | 1, 8 | `lib/data/repositories/account_management_repository.dart; docs/week13/account_management.md` |
| FR-40 | US-33 | 1, 8 | `lib/presentation/admin/staff_assignments.dart` |
| FR-41 | US-34 | 1, 8 | `lib/presentation/common/account_transfer_screen.dart` |
| FR-42 | US-25 | 1, 6 | `docs/week13/billing_schedule.md; lib/data/repositories/billing_schedule_repository.dart` |
| FR-43 | US-26 | 1, 5, 9 | `docs/week13/regular_rounding_fix.md; lib/data/local/pending_fund_request.dart` |
| FR-44 | US-26 | 1, 9 | `docs/week13/automatic_boheco_routing.md` |
| FR-45 | US-27 | 1, 9 | `lib/presentation/reader/remittance_screen.dart; docs/week13/automatic_boheco_routing.md` |
| FR-46 | US-27 | 1, 9 | `lib/presentation/common/settlement_panel.dart; docs/week13/pondo_boheco_rollout.md` |
| FR-47 | US-28 | 1, 5, 9 | `lib/presentation/cashier/record_payment_screen.dart; docs/week13/pondo_boheco_rollout.md` |
| FR-48 | US-29 | 1, 5, 9 | `docs/week13/reader_compensation.md` |
| FR-49 | US-30 | 1, 6, 9 | `lib/presentation/admin/reserve_fund_report_screen.dart; docs/week13/retry_and_offline_fixes.md` |
| FR-50 | US-31 | 1, 4, 5, 6, 7 | `lib/presentation/common/staff_alerts.dart; lib/data/notifications/staff_phone_alerts.dart` |
| FR-51 | US-35 | 1, 2 | `lib/presentation/auth/forgot_password_sheet.dart; lib/presentation/admin/reset_password_screen.dart` |
| FR-52 | US-36 | 1, 4 | `lib/presentation/reader/reading_sheet_screen.dart` |

## Evidence and remaining verification

- FR-25/29 focused local tests and independent QR image decoding were completed in the preceding implementation work; see `docs/week13/payment_history_receipt_qr.md`. This documentation task does not claim to rerun application suites.
- Other relevant local test reports and source checks are recorded in the mapped project notes. They are not proof of live migration state.
- Remaining operational checks include backend/migration alignment, scheduled jobs and actual SMS settings, delivery on real phones, QR camera scanning, offline multi-phone handovers, physical cash reconciliation, performance benchmarks and full accessibility review.
- Research review used available publisher/institutional pages and indexed abstracts. The 2024 cooperative paper full text was not accessible; no full-text review is claimed.
- Diagrams and image assets are generated from the same actor/use-case definitions; the `.drawio` file contains editable UML-style actor associations and the nine pages embedded in Word.
- Final document rendering and visual review are recorded below after layout QA.

## Completed document QA

- Rendered the final Word file successfully with the packaged document-rendering workflow and the native Windows LibreOffice renderer.
- Reviewed all 36 pages, including every requirement/story table, all nine landscape diagrams and all four paired mockup figures. Corrected an overflow page, removed inherited title borders and adjusted actor connectors to clear labels.
- The final small correction changed only page 4 and diagram connector regions on pages 23–31; pixel comparison confirmed the other 26 pages were unchanged. The changed page and all changed regions were reviewed again.
- Automated checks passed: 51 unique active FRs; 36 stories; at least three criteria per story; complete FR coverage; seven NFRs; 13 embedded images with descriptions; nine editable Draw.io pages with valid actor/use-case associations; all cited local evidence paths present; valid DOCX archive.
- The original DOCX and original Draw.io file remain unchanged. Render previews stay in the working folder; the deliverables are the updated DOCX, editable Draw.io diagram and this change log.
