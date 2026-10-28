# Application Codebase Documentation

## 1. System Overview & Technology Stack
- **Framework & Runtime:**
  - **Flutter SDK:** Flutter 3.44.0 (stable channel, uses Material Design 3).
  - **Dart SDK:** `^3.12.0` (as specified in [pubspec.yaml](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L7)).
  - **Android Target:** `compileSdk 36`, `minSdk 24` (declared in [android/app/build.gradle.kts](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/android/app/build.gradle.kts)).
  - **Deno / TypeScript Runtime:** Supabase Edge Functions on Deno runtime using `npm:@supabase/supabase-js@2`.
- **State Management & Data Fetching:**
  - **State Management:** [flutter_riverpod](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L19) (`^3.4.3`) using `Provider`, `Notifier`, `AsyncNotifier`, and `FutureProvider`.
  - **Routing & Guards:** [go_router](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L25) (`^18.0.1`) with a top-level `ShellRoute` for role-based navigation tabs and full-screen task routes outside the shell.
  - **HTTP & Network Layer:** Custom [FailFastHttpClient](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/network/fail_fast_http_client.dart) wrapping `package:http` (`^1.6.0`) with [NetworkStatus](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/network/network_status.dart) and [connectivity_plus](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L10) (`^7.3.1`).
- **Database & Backend Services:**
  - **Remote Database (Backend as a Service):** Supabase ([supabase_flutter](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L32) `^2.17.2`) powered by PostgreSQL 15+ with Row-Level Security (RLS), custom database views (`security_invoker = on`), transactional stored functions (RPCs), and `pg_cron` background scheduling.
  - **Local On-Device Database:** [drift](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L13) (`^2.34.4`) with [sqlite3](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L31) (`^3.5.2`) built via Dart build hook overriding upstream SQLite with SQLCipher (`hooks.user_defines.sqlite3.source: sqlcipher`).
  - **Hardware Key Storage & Biometrics:** [flutter_secure_storage](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L24) (`^10.3.1`) backed by Android Keystore (AES-GCM 256-bit encryption key) and [local_auth](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L27) (`^3.0.2`) for biometric fingerprint unlock.
  - **Background Tasks & Telemetry:** [workmanager](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L35) (`^0.10.10`), [flutter_local_notifications](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L18) (`^22.3.1`), and optional [firebase_core](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L15) (`^4.15.0`) / [firebase_analytics](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/pubspec.yaml#L14) (`^12.6.0`).
- **Styling / UI Library:**
  - Flutter Material Design 3 (`uses-material-design: true`), configured via [lib/presentation/theme.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/theme.dart) with responsive layout break-points in [lib/presentation/common/responsive_layout.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/common/responsive_layout.dart).
- **Directory Structure:**
  ```text
  BillAlert/
  ├── android/                     # Native Android Gradle configuration (compileSdk 36, minSdk 24)
  ├── docs/                        # Specifications, worksheets, screenshots, and architecture diagrams
  ├── lib/                         # Application Dart source tree
  │   ├── core/                    # Pure Dart core primitives (zero external dependencies)
  │   │   ├── config/              # AppConfig (--dart-define compile-time parameters)
  │   │   ├── errors/              # Sealed AppFailure hierarchy
  │   │   └── result/              # Sealed Result<T> (Ok<T>, Err<T>)
  │   ├── domain/                  # Domain layer (pure Dart: entities, value objects, use cases)
  │   │   ├── entities/            # AppUser, Bill, Consumer, AreaRoster, BillingSchedule, etc.
  │   │   ├── notifications/       # Domain notification models and interfaces
  │   │   ├── outbox/              # Sealed OutboxOperation, OutboxGateway, OutboxEntry
  │   │   ├── repositories/        # Abstract repository interfaces (BillRepository, AuthRepository, etc.)
  │   │   ├── security/            # DeviceUnlock, FingerprintSetting, PasswordVerifier contracts
  │   │   ├── time/                # PhClock abstraction for Philippine Standard Time
  │   │   ├── usecases/            # Role-scoped use case classes (Admin, Reader, Cashier, Consumer, Auth)
  │   │   └── value_objects/       # Money (centavos), Kwh (hundredths), PhDate, CycleLabel, IDs
  │   ├── data/                    # Data layer (Supabase, Drift ORM, SQLCipher, DTOs, network)
  │   │   ├── analytics/           # Non-blocking Firebase telemetry startup
  │   │   ├── dto/                 # JSON parsing and mapping (profile_dto, consumer_dto)
  │   │   ├── local/               # Drift tables, AppDatabase, SQLCipher PRAGMA key, query caching
  │   │   ├── network/             # FailFastHttpClient, NetworkStatus, foreground polling
  │   │   ├── notifications/       # Android notification channels, alert feeds, workmanager
  │   │   ├── repositories/        # Concrete implementations of domain repository interfaces
  │   │   ├── security/            # LocalAuth biometric unlock, secure storage password verification
  │   │   ├── supabase/            # FailureMapper (PostgrestException to AppFailure), network error handling
  │   │   └── sync/                # SyncService outbox drain engine, SupabaseOutboxGateway, OutboxCodec
  │   ├── presentation/            # Presentation layer (Widgets, Riverpod Notifiers, GoRouter)
  │   │   ├── admin/               # Admin / Area President screens, controllers, and account management
  │   │   ├── auth/                # Sign-in screen, app lock gate, change password, biometric prompt
  │   │   ├── cashier/             # Cash collection counter, receipts ledger, remittance panel
  │   │   ├── common/              # RoleShell, shared UI widgets, QR codes, search fields, failure banners
  │   │   ├── consumer/            # Consumer bill screen, bill history, notification inbox, contact editor
  │   │   ├── reader/              # Meter reading entry, route roster, reading sheet, remittance overview
  │   │   ├── app.dart             # Root BillAlertApp widget and theme binding
  │   │   ├── providers.dart       # Riverpod dependency injection registry (inward interface binding)
  │   │   ├── router.dart          # GoRouter configuration, route redirects, and access guards
  │   │   └── theme.dart           # Material 3 theme data, custom palettes, typography
  │   ├── firebase_options.dart    # Optional Firebase configuration
  │   └── main.dart                # Application entry point, Supabase initialization, offline HTTP ping
  ├── supabase/                    # Supabase backend of record
  │   ├── functions/               # Deno TypeScript Edge Functions (manage-accounts, create-staff, send-sms)
  │   ├── migrations/              # SQL migrations (01_schema.sql to 20_staff_alerts.sql & timestamped)
  │   ├── operations/              # Operational scripts, pause/resume jobs, verification checks
  │   └── tests/                   # SQL test suite (pgTAP / custom SQL verification)
  └── test/                        # Comprehensive Flutter test suite (610 automated tests)
      ├── architecture/            # Architectural invariant tests (domain imports, double prevention)
      ├── data/                    # Data layer tests (SQLCipher encryption, offline cache, outbox)
      ├── domain/                  # Pure domain tests (Money, Kwh, PhDate, CycleLabel, Use cases)
      ├── presentation/            # Widget and controller tests for all 4 roles
      └── support/                 # In-memory test doubles, fakes, and mock factories
  ```

---

## 2. Core Architectural Design & Layering

The codebase strictly enforces Clean Architecture principles through four concentric layers:

```text
Presentation Layer    ──> [ Screens, ViewModels/Notifiers, Routing ]
       │  (calls)
Domain Layer          ──> [ Entities, Value Objects, Use Cases, Abstract Repositories ] (Pure Dart)
       ▲  (implements)
Data Layer            ──> [ Concrete Repositories, Drift Local DB, SQLCipher, Supabase, SyncService ]
       │  (references)
Core Layer            ──> [ Result<T>, AppFailure, AppConfig ] (Pure Dart)
```

### The Inward Dependency Rule
- **`lib/domain/` imports no external packages.** It does not import Flutter, Supabase, Drift, HTTP, or even `intl`.
- **Architectural Enforcement:** This rule is mechanically enforced by [test/architecture/domain_has_no_dependencies_test.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/test/architecture/domain_has_no_dependencies_test.dart#L1-L60), which inspects all imports in `lib/domain/` and fails the build if any forbidden dependency is referenced.
- **Dependency Inversion:** Repositories are declared as abstract contracts in `lib/domain/repositories/` and implemented in `lib/data/repositories/`. In [lib/presentation/providers.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/providers.dart#L191-L238), every provider explicitly types its interface as the domain abstract type (`Provider<BillRepository>`, `Provider<ConsumerRepository>`, etc.).

### Result Pattern vs. Exceptions
- The application completely avoids throwing runtime exceptions across architectural boundaries.
- **The Sealed `Result<T>` Type:** Declared in [lib/core/result/result.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/core/result/result.dart#L19-L33) as:
  ```dart
  sealed class Result<T> { const Result(); }
  final class Ok<T> extends Result<T> { final T value; const Ok(this.value); }
  final class Err<T> extends Result<T> { final AppFailure failure; const Err(this.failure); }
  ```
- **The Sealed `AppFailure` Hierarchy:** Declared in [lib/core/errors/app_failure.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/core/errors/app_failure.dart#L11-L84). It maps user-facing messages in plain English while isolating raw Postgres error details in `debugDetail`:
  - `NetworkFailure`: Connection unavailability. Differentiates general offline failures from outbox work saved locally.
  - `AuthFailure`: Session expired, bad credentials, or account disabled.
  - `PermissionFailure`: Access blocked by Row-Level Security across service area boundaries.
  - `ValidationFailure`: Invalid user input, meter dial decreases, non-numeric values.
  - `ConflictFailure`: Clashing operations (e.g., duplicate reading for the same cycle under FR-23).
  - `ServerFailure`: Unhandled backend errors.
- **Isolated Error Translation:** [lib/data/supabase/failure_mapper.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/supabase/failure_mapper.dart) is the **only file** in the codebase allowed to inspect `PostgrestException` codes (e.g., `23505` unique violation, `P0001` raise exception, `42501` RLS violation) and map them into `AppFailure` instances.

### Domain Invariants & Precision Types
1. **Money Invariant ([lib/domain/value_objects/money.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/value_objects/money.dart)):**
   - Money is never stored or calculated as a `double`. Binary floating-point cannot accurately represent decimal fractions like ₱0.10.
   - `Money` holds an immutable `int centavos` (₱1,975.35 = `197535`).
   - Parsing reads directly from decimal text strings returned by Postgres `numeric(12,2)` columns.
   - **No multiplication or division:** The app deliberately does not derive bill amounts from consumption. Bill amounts are determined by the electric cooperative (BOHECO I) and transcribed by the Area President.
   - **Whole-Peso Ceiling Rule (`roundUpToWholePeso()`):** Centavos are rounded UP to the next whole peso (e.g., ₱499.01 and ₱499.99 both become ₱500.00). The fraction funds the Reserve Fund ("Pondo") and the Meter Reader's compensation.
2. **Kwh Invariant ([lib/domain/value_objects/kwh.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/value_objects/kwh.dart)):**
   - Held as an `int hundredths` of a kilowatt-hour (`numeric(12,2)`).
   - Allows only subtraction (`current - previous`) to compute consumption.
3. **Philippine Time Invariant ([lib/domain/value_objects/ph_date.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/value_objects/ph_date.dart) & [cycle_label.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/value_objects/cycle_label.dart)):**
   - Billing cycles and due dates are anchored to Asia/Manila (UTC+08:00 fixed, no DST).
   - The device clock is never trusted for billing cycle resolution.

---

## 3. Database Schema & Backend Infrastructure

### Remote PostgreSQL Schema (Supabase)
The database structure is codified in `supabase/migrations/`:
- **Core Entities & Tables ([01_schema.sql](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/01_schema.sql)):**
  - `areas`: The 4 service areas of Barangay Tubod, Clarin, Bohol (`code`, `name`, `is_active`).
  - `settings`: System-wide singleton table (`id = 1`) defining cooperative name, PSGC codes, notification channels, and disconnection courtesy hours.
  - `profiles`: User identity records (`id` referencing `auth.users`, `username`, `first_name`, `last_name`, `role`, `area_id`, `must_change_password`, `account_status`). Unique index `uq_area_one_active_staff_per_role` guarantees at most one active Admin, Meter Reader, and Cashier per area.
  - `consumers`: Household records (`id`, `consumer_no`, `profile_id`, `first_name`, `last_name`, `contact_number`, `meter_serial_no`, `area_id`, `purok`, `account_status`).
  - `billing_cycles`: Discrete calendar cycles (`cycle_year`, `cycle_month`, `period_start`, `period_end`) with non-overlapping GiST date-range exclusion constraints.
  - `meter_readings`: Dial captures (`consumer_id`, `billing_cycle_id`, `previous_reading`, `current_reading`, `consumption`, `reading_date`, `captured_at`, `client_uuid`). `UNIQUE (consumer_id, billing_cycle_id)` enforces one reading per household per cycle (FR-23).
  - `bills`: Billing ledger (`bill_no`, `consumer_id`, `billing_cycle_id`, `meter_reading_id`, `consumption`, `total_amount`, `cooperative_amount`, `due_date`, `priced_at`, `amount_paid`, `balance`, `status`, `waiver_amount`, `external_paid`). Enforced by constraint `bills_pricing_consistent`: `total_amount`, `due_date`, and `priced_at` must be all null (unpriced) or all set together.
  - `payment_transactions`: Cash handovers (`receipt_no`, `verification_code`, `consumer_id`, `area_id`, `cashier_id`, `total_collected`, `cash_tendered`, `change_due`, `paid_at`, `client_uuid`).
  - `payments`: Line-item allocations per bill (`transaction_id`, `bill_id`, `consumer_id`, `amount_paid`, `payment_method = 'cash'`).
  - `disconnection_notices`: Formal statutory notices (`notice_no`, `consumer_id`, `reason`, `served_at`, `earliest_lawful_at`, `status`, `closed_at`, `closed_by`, `outcome_notes`).
  - `notifications`: Multi-channel alerts (`consumer_id`, `notif_type`, `channel`, `message_content`, `status`, `failed_reason`, `is_read`, `read_at`).
  - `remit_handovers` ([18_remit_handovers.sql](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/18_remit_handovers.sql)): Cashier-to-Reader remittance records (`area_id`, `remit_month`, `to_boheco`, `reader_pay`, `gap`, `handed_by`, `handed_to`).
  - `boheco_trips`, `bill_settlements`, `pondo_ledger`, `boheco_payment_evidence` ([20261004015207_pondo_boheco_settlement.sql](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/20261004015207_pondo_boheco_settlement.sql)): Reserve fund ledger and BOHECO cutoff trip settlement tracking.
  - `reader_compensation` ([20261004070000_reader_monthly_compensation.sql](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/20261004070000_reader_monthly_compensation.sql)): Monthly PHP 500 compensation payouts from the reserve fund.

- **Transactional Stored Procedures / RPCs ([02_functions.sql](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/02_functions.sql)):**
  - `fn_record_meter_reading`: Idempotently verifies previous reading, creates the billing cycle, inserts `meter_readings`, and creates the initial `unpriced` bill (`total_amount` null, `due_date` null).
  - `fn_post_bill_amount`: Admin-only RPC. Locks the bill `FOR UPDATE`, sets the whole-peso ceiling (`ceil(p_amount)`), stores `cooperative_amount`, updates due date, and automatically queues the consumer's bill-ready notification.
  - `fn_record_payment`: Cashier-only RPC. Atomically settles multiple bills under one `payment_transactions` record, generates an official receipt number (`BIEC-YYYY-MM-XXXXXX`) and short verification code, writes `payments` lines, and updates bill balances.
  - `fn_issue_disconnection_notice`: Validates overdue bills, calculates `earliest_lawful_disconnection` (incorporating ERC 48-hour statutory rule, holidays, weekdays, and 8:00 AM - 3:00 PM cutoff), and creates active notice.
  - `fn_earliest_lawful_disconnection`: Evaluates statutory notice periods against `ph_holidays` and business hours.
  - `fn_record_remit_handover`: Freezes collected amounts and rounding shares during Cashier-to-Reader cash handovers.

- **Database Views ([03_views.sql](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/03_views.sql)):**
  - `v_bill_status`: Single source of truth for bill state (`is_unpriced`, `is_overdue`, `days_overdue`).
  - `v_consumer_current_bill`: Consumer's active bill (deliberately includes unpriced bills to show consumption during the 7-day cooperative lag).
  - `v_readings_awaiting_amount`: Admin's pending pricing queue, sorted oldest first.
  - `v_meter_reader_progress`: Progress tracker (read count, unread count, completion percentage).
  - `v_cashier_collection_progress`: Cashier's collection metrics (payable count, total collected, total outstanding).
  - `v_consumer_outstanding`: Roll-up of unpaid amounts and overdue counts per consumer.
  - `v_cashier_daily_summary`: Cashier's daily collection ledger.
  - `v_payment_history`: Settled bills with receipt and transaction details.
  - `v_active_disconnection_warnings`: Active notices with overdue balances.
  - **Critical Security Configuration:** Every view executes with `security_invoker = on` (lines 390–401), ensuring that PostgREST queries through views execute with caller privileges and adhere to underlying RLS policies.

- **Row-Level Security (RLS) ([04_rls.sql](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/04_rls.sql)):**
  - Admins are **Area Presidents, not superusers**. Staff queries are scoped via `app.staff_in_area(area_id)`.
  - Consumers can only read their own profile, bills, readings, payments, and notifications (`profile_id = auth.uid()` or `consumer_id = app.current_consumer_id()`).
  - Inserts on `meter_readings` are restricted to Meter Readers in their assigned area.
  - Updates on `bills` are restricted to Admins (pricing) and Cashiers (payments) in their assigned area.

- **Deno Edge Functions (`supabase/functions/`):**
  - `create-staff-account`: Service-role authenticated provisioning of Meter Reader and Cashier accounts.
  - `create-household-login`: Grants household login credentials tied to an existing consumer record.
  - `manage-accounts`: Account lifecycle management (disabling/enabling logins, banning auth users, reassignments).
  - `reset-account-password`: Area President password reset requiring forced password change on next login.
  - `send-sms` & `httpsms-webhook`: Automated SMS dispatch and delivery status callback tracking.

### Local On-Device Database (Drift + SQLCipher)
Defined in [lib/data/local/tables.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/local/tables.dart) and [app_database.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/local/app_database.dart):
- **Encrypted Tables:**
  - `CachedConsumers`: Cached roster with `previousReadingHundredths` and `lastReadCycle`.
  - `CachedBills`: Offline bill storage with `consumptionHundredths`, `totalAmountCentavos`, `amountPaidCentavos`.
  - `CachedPayments`: Recent payments and receipts with `amountPaidCentavos` and `bohecoShareCentavos`.
  - `CachedNotifications`: Offline alert inbox.
  - `CacheOwner`: User profile binding ensuring cache isolation across sign-ins (`id = 1` check).
  - `CachedQueries`: PostgREST JSON cache for read queries without dedicated tables.
  - `SyncMeta`: Tracking `last_refreshed_at` timestamps per table for stale data warnings (GEN-11).
  - `OutboxRows`: Local write queue storing `client_uuid`, `operation`, `payload_json`, `captured_at`, `status`, `attempts`, `last_error`.
  - `OutboxReadingKeys`: Uniqueness tracking table with `UNIQUE (consumer_id, cycle_label)` preventing duplicate offline readings at the meter.
- **Hardware Encryption ([lib/data/local/database_key.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/local/database_key.dart) & [native_connection.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/local/connection/native_connection.dart)):**
  - Generates 32 cryptographically secure random bytes via `Random.secure()`, stored in `FlutterSecureStorage` (Android Keystore AES-GCM).
  - Opens the database using `LazyDatabase` and executes `PRAGMA key = '...';` as the first statement before any schema operations.

---

## 4. Authentication, Session & Access Control

### Identity Resolution & Supabase Auth
- **Domain Mapping ([lib/core/config/app_config.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/core/config/app_config.dart#L27-L37)):**
  - Users sign in with a simple username (e.g., `ledesman.dormal`).
  - [AuthRepositoryImpl.emailForUsername](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/repositories/auth_repository_impl.dart#L60-L75) converts the username to a synthetic email (`username@billalert.local`) before dispatching to Supabase Auth.
- **Sealed `AppUser` Hierarchy ([lib/domain/entities/app_user.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/entities/app_user.dart#L38-L235)):**
  ```dart
  sealed class AppUser {
    final ProfileId id;
    final String username;
    final String firstName;
    final String lastName;
    final AreaId? areaId;
    final bool mustChangePassword;
    final int accessVersion;
    String get homeRoute;
    List<AppTab> get permittedTabs;
  }
  final class AdminUser extends AppUser { ... homeRoute => '/admin'; }
  final class MeterReaderUser extends AppUser { ... homeRoute => '/reader'; }
  final class CashierUser extends AppUser { ... homeRoute => '/cashier'; }
  final class ConsumerUser extends AppUser { ... homeRoute => '/consumer'; }
  ```
  This sealed polymorphism eliminates brittle switch statements across the presentation layer. The router queries `user.homeRoute` directly.

### Routing Engine & Route Guards ([lib/presentation/router.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/router.dart))
The `routerProvider` executes a prioritized redirect evaluation:
1. **Startup Initialization:** Holds on `Routes.splash` (`/`) while `auth.isLoading && !auth.hasValue`.
2. **Unauthenticated Users:** Bounces to `Routes.login` (`/login`).
3. **App Biometric Lock:** If `appLockControllerProvider.locked` is true, keeps the user on the login screen to prompt for fingerprint/device unlock.
4. **Temporary Password Guard (GEN-04):** If `user.mustChangePassword` is true, traps the user on `Routes.changePassword` (`/change-password`). No other screen can be visited.
5. **Authenticated Landing:** If a signed-in user sits on `/login`, `/`, or `/change-password`, redirects immediately to `user.homeRoute`.
6. **Role Guard (`mayVisit(user, location)`):** Prevents cross-role tab visits (e.g., Cashier attempting to visit `/admin`).
7. **Linked Household Support:** Staff users who also maintain a linked household login can access consumer routes via `linkedHouseholdProvider`.

---

## 5. Role-Based Modules & Detailed Implementation Traces

### 5.1 Admin Module (Area President)
- **Assigned Architect / Developer:** Charles B. Carcallas (Lead)
- **Role Identity:** `AdminUser`, role code `'admin'`, home route `/admin`.
- **Primary Responsibilities:**
  1. Transcribe and post cooperative-provided bill amounts, applying the whole-peso ceiling rule.
  2. Review overdue accounts and serve / close statutory disconnection notices.
  3. Manage service area personnel (Meter Reader and Cashier creation, reassignment, account disabling).
  4. Create household records and provision consumer logins.
  5. Audit the Reserve Fund ("Pondo") and inspect BOHECO collection cutoffs.

#### Code Trace & Component Mapping:
- **Presentation Layer:**
  - [PostBillAmountScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/admin/post_bill_amount_screen.dart): Displays the queue of unpriced bills awaiting amounts.
  - [PostBillAmountController](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/admin/post_bill_amount_controller.dart): Manages amount input, whole-peso preview, and due date validation.
  - [AdminOverdueWorkspaceScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/admin/overdue_workspace_screen.dart): Tabbed overdue workspace for active notices, notice history, and referral actions.
  - [ServeNoticeScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/admin/serve_notice_screen.dart): Form to serve a disconnection warning to an overdue consumer.
  - [NoticeDocumentScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/admin/notice_document_screen.dart): Renders the formal legal notice document with statutory deadlines.
  - [AdminAccountsScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/admin/accounts_screen.dart) & [AccountManagementScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/admin/account_management_screen.dart): Account directory, staff assignment, and login status management.
  - [ReserveFundReportScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/admin/reserve_fund_report_screen.dart): Reserve fund audit report.
- **Domain Layer:**
  - [PostBillAmount](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/admin/post_bill_amount.dart): Applies `roundUpToWholePeso()`, creates `PostAmountOperation`, and queues it into the outbox.
  - [IssueDisconnectionNotice](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/admin/issue_disconnection_notice.dart): Creates `IssueNoticeOperation` with statutory `capturedAt`.
  - [RecordNoticeOutcome](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/admin/issue_disconnection_notice.dart#L104): Calls `NoticeRepository.closeNotice` (settled, cancelled, referred).
  - [CreateStaffAccount](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/admin/create_staff_account.dart), [RegisterHousehold](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/admin/register_household.dart), [CreateHouseholdLogin](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/admin/create_household_login.dart), [ResetAccountPassword](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/admin/reset_account_password.dart).
- **Data & Backend Layer:**
  - Database Views: `v_readings_awaiting_amount`, `v_active_disconnection_warnings`.
  - Stored Functions: `fn_post_bill_amount`, `fn_issue_disconnection_notice`, `fn_close_disconnection_notice`.
  - Edge Functions: `manage-accounts`, `create-staff-account`, `reset-account-password`.

---

### 5.2 Meter Reader Module
- **Assigned Architect / Developer:** Mary Tiffany I. Busalanan
- **Role Identity:** `MeterReaderUser`, role code `'meter_reader'`, home route `/reader`.
- **Primary Responsibilities:**
  1. Inspect physical meters across the assigned service area without requiring cellular signal.
  2. Input dial readings, validating against previous readings (preventing reverse dials).
  3. Prevent duplicate readings locally at the meter (FR-23).
  4. View the area route roster and monthly route completion progress.
  5. Inspect the monthly reading sheet submitted to BOHECO.
  6. Review cash remittance handover summaries.

#### Code Trace & Component Mapping:
- **Presentation Layer:**
  - [RosterScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/reader/roster_screen.dart): Displays the service area route tracker ("14 of 62 read", "48 not yet read").
  - [RosterController](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/reader/roster_controller.dart): Manages area roster state and offline cache loading.
  - [ReaderConsumersScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/reader/consumers_screen.dart): Searchable and filterable household directory.
  - [ReadingEntryScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/reader/reading_entry_screen.dart): Meter dial entry form (full-screen task outside shell).
  - [ReadingEntryController](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/reader/reading_entry_controller.dart): Validates numeric input into `Kwh`, checks plausible readings, and calls use case.
  - [HouseholdDetailsSheet](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/reader/household_details_sheet.dart): Bottom sheet showing meter number, previous reading date, and status.
  - [ReadingSheetScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/reader/reading_sheet_screen.dart): Tabular summary of all readings in the active cycle.
  - [RemittanceScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/reader/remittance_screen.dart): Cash remittance and handover status display.
- **Domain Layer:**
  - [RecordMeterReading](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/reader/record_meter_reading.dart): Checks consumer active status, checks server cycle status, verifies local outbox duplicates via `ReadingRepository.isReadingQueuedFor`, derives consumption (`current - previous`), creates `RecordReadingOperation`, and writes to `OutboxRepository`.
  - [LoadAreaRoster](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/reader/load_area_roster.dart): Loads cached consumers and overlays pending outbox readings.
  - [LoadReadingSheet](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/reader/load_reading_sheet.dart): Assembles completed reading records for cooperative submission.
- **Data & Backend Layer:**
  - Local Drift Tables: `CachedConsumers`, `OutboxRows`, `OutboxReadingKeys` (`UNIQUE (consumer_id, cycle_label)`).
  - Stored Functions: `fn_record_meter_reading` (creates unpriced bill under `bills_pricing_consistent`).
  - Views: `v_meter_reader_progress`.

---

### 5.3 Consumer Module
- **Assigned Architect / Developer:** Krisha Mae I. Basio
- **Role Identity:** `ConsumerUser`, role code `'consumer'`, home route `/consumer`.
- **Primary Responsibilities:**
  1. Inspect the current month's electricity bill, consumption dial figures, and due date.
  2. Understand the bill status during the 7-day cooperative billing lag (displaying "Awaiting amount").
  3. Browse past bills and settled official payment receipts with QR verification codes.
  4. Receive and review billing alerts, pre-due reminders, overdue notices, and disconnection warnings.
  5. Update the household's official SMS contact number.

#### Code Trace & Component Mapping:
- **Presentation Layer:**
  - [CurrentBillScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/consumer/current_bill_screen.dart): Consumer home dashboard displaying current bill card, status chip, and consumption breakdown.
  - [CurrentBillController](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/consumer/current_bill_controller.dart): Resolves signed-in household via `ConsumerRepository.signedInConsumer()`, loads `currentBillFor`, and maintains unpriced bill state.
  - [BillDetailsSheet](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/consumer/bill_details_sheet.dart): Modal displaying dial numbers (`previous_reading`, `current_reading`), reading date, and tariff notes.
  - [HistoryScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/consumer/history_screen.dart): Tabular/list view of historical billing cycles and payment receipts.
  - [HistoryController](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/consumer/history_controller.dart): Fetches settled receipts and bill archive.
  - [ConsumerReceiptScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/consumer/receipt_screen.dart): Formal digital duplicate of the official receipt with scannable QR code.
  - [InboxScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/consumer/inbox_screen.dart) & [InboxController](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/consumer/inbox_controller.dart): Notification list with unread badges, message details, and mark-as-read actions.
  - [EditContactNumberSheet](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/consumer/edit_contact_number_sheet.dart) & [ContactNumberController](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/consumer/contact_number_controller.dart): Validates and updates mobile number via authenticated RPC.
- **Domain Layer:**
  - [UpdateOwnContactNumber](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/consumer/update_own_contact_number.dart): Normalizes Philippine mobile format and invokes `ConsumerRepository.updateOwnContactNumber`.
  - [RefreshPhoneAlerts](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/consumer/refresh_phone_alerts.dart): Syncs foreground notifications and schedules local device alarms.
  - [OpenTappedNotice](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/consumer/open_tapped_notice.dart): Deep-link handler directing tapped push notifications to the corresponding bill or notice.
- **Data & Backend Layer:**
  - Database Views: `v_consumer_current_bill` (filters by consumer profile, preserves unpriced status), `v_payment_history`, `v_bill_status`.
  - Stored Functions: `fn_update_own_contact_number` ([10_consumer_contact_number.sql](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/10_consumer_contact_number.sql)).
  - RLS Policies: Strictly limits consumers to rows where `consumer_id = app.current_consumer_id()` or `profile_id = auth.uid()`.

---

### 5.4 Cashier Module
- **Assigned Architect / Developer:** Cristell D. Obiso
- **Role Identity:** `CashierUser`, role code `'cashier'`, home route `/cashier`.
- **Primary Responsibilities:**
  1. Lookup households at the payment counter and view outstanding payable balances.
  2. Refuse payments on unpriced bills (no cooperative amount yet).
  3. Accept cash tendered, calculate exact change due, and settle one or more bills in one atomic transaction.
  4. Issue official collection receipts with unique verification codes (`BIEC-YYYY-MM-XXXXXX`).
  5. Review the daily collection ledger, receipts history, and area collection totals.
  6. Track the monthly Remittance Handover and the Rounding Fund ("Pondo").

#### Code Trace & Component Mapping:
- **Presentation Layer:**
  - [RecordPaymentScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/cashier/record_payment_screen.dart): Three-step counter flow (Select household -> Choose bills / Enter cash -> Confirm & Receipt).
  - [RecordPaymentController](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/cashier/record_payment_controller.dart): Manages household selection, multi-bill balance sum, cash tendered calculation, change due computation, and outbox submission.
  - [ReceiptsScreen](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/cashier/receipts_screen.dart): Ledger of all receipts issued in the area, daily totals, and remaining area debt.
  - [ReceiptsController](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/cashier/receipts_controller.dart): Loads `v_payment_history` and `AreaOutstanding` roll-up.
  - [ReceiptDetailsSheet](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/cashier/receipt_details_sheet.dart): Modal showing full receipt breakdown and settled bills.
  - [CashierRemitPanel](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/cashier/cashier_remit_panel.dart) & [RoundingFundCard](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/presentation/cashier/rounding_fund_card.dart): Displays the month's collections, BOHECO's share, Meter Reader pay, and Pondo balance.
- **Domain Layer:**
  - [RecordCashPayment](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/cashier/record_cash_payment.dart): Validates non-empty bill selection, rejects unpriced bills, ensures amounts match or fall below balances, verifies cash tendered exceeds total, mints `RecordPaymentOperation`, and persists to outbox.
- **Data & Backend Layer:**
  - Database Views: `v_consumer_outstanding`, `v_cashier_daily_summary`, `v_cashier_collection_progress`, `v_payment_history`.
  - Stored Functions: `fn_record_payment` (locks bills `FOR UPDATE`, generates receipt from `receipt_no_seq`, writes `payment_transactions` and `payments`, recalculates bill balance via trigger), `fn_record_remit_handover`.
  - Local Drift Tables: `CachedPayments`, `OutboxRows`.

---

## 6. Offline-First Synchronization & Outbox Pipeline

The application treats offline operation as normal field conditions rather than an error state.

```text
[ User Action on Screen ]
         │
         ▼
[ Use Case Validates Input ]
         │
         ▼
[ Synchronous Write to Drift OutboxRows Table ] ──> [ UI Confirms Immediately ]
         │
         ▼ (Background / Online Reconnect)
[ SyncService Drains Outbox Queue ]
         │
         ▼
[ OutboxOperation.submit(OutboxGateway) ]
         │
         ▼ (PostgreSQL RPC with p_client_uuid)
[ Supabase Transaction Executes Atomically ]
         │
         ├──> [ Success ] ──> Marked 'synced' in local DB
         └──> [ Failure ] ──> Marked 'failed' with server error (never silently dropped)
```

### The Outbox Contract & Sealed Operations
Declared in [lib/domain/outbox/outbox_operation.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/outbox/outbox_operation.dart):
- `OutboxOperation` is a sealed class with four polymorphic implementations:
  1. `RecordReadingOperation` (`operationCode = 'record_reading'`): Submits meter reading via `gateway.submitReading()`.
  2. `PostAmountOperation` (`operationCode = 'post_amount'`): Submits posted cooperative amount via `gateway.submitPostedAmount()`.
  3. `RecordPaymentOperation` (`operationCode = 'record_payment'`): Submits multi-bill cash payment via `gateway.submitPayment()`.
  4. `IssueNoticeOperation` (`operationCode = 'issue_notice'`): Submits disconnection notice via `gateway.submitNotice()`.
- **Elimination of Switch Statements:** `SyncService` iterates over queued operations and invokes `operation.submit(gateway)` polymorphically. The only decoding switch exists in [lib/data/sync/outbox_codec.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/sync/outbox_codec.dart) to reconstitute rows from SQLite storage.

### Idempotency & Legal Semantics
- **`ClientUuid`:** Every operation mints a unique UUID on the phone at the moment of creation. This UUID is passed as `p_client_uuid` to PostgreSQL stored procedures. If a network connection drops mid-flight and the sync retries, PostgreSQL locates the existing `client_uuid` and returns the existing record rather than duplicating bills, readings, or receipts.
- **`capturedAt` Timestamp:** The legal timestamp recorded on server records is the exact device capture time (`captured_at`), not the later synchronization time. For disconnection notices, the 48-hour statutory countdown begins at `captured_at`.
- **Immediate Local Duplicate Prevention:** The Drift table `OutboxReadingKeys` has a unique constraint `UNIQUE (consumer_id, cycle_label)`. If a Meter Reader attempts to log a reading for a household that is already queued in the local outbox, SQLite rejects the operation immediately while the reader is still standing at the meter.

### Sync Engine Execution ([lib/data/sync/sync_service.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/sync/sync_service.dart))
- Monitors network connectivity via `connectivity_plus` and `FailFastHttpClient`.
- When connectivity is restored, `syncNow()` initiates a serialized `_drain()` loop:
  - Fetches pending entries sorted by `captured_at ASC`.
  - Submits each operation through [SupabaseOutboxGateway](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/data/sync/supabase_outbox_gateway.dart).
  - Handles auth token expirations gracefully without cross-account contamination via `OutboxSession`.
  - In case of non-retryable server rejection, updates status to `'failed'` and persists `last_error` so failures remain fully auditable and visible to users.

---

## 7. Financial Domain Rules, Business Logic & Calculations

### Summary of Financial & Operational Formulas

| Rule / Concept | Formula / Logic | Enforcing Code Location |
|---|---|---|
| **No Client-Side Tariff** | `totalAmount` is transcribed from cooperative statement, never derived from kWh. | [ARCHITECTURE.md](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/ARCHITECTURE.md#L78-L100), [PostBillAmount](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/usecases/admin/post_bill_amount.dart#L17-L23) |
| **Whole-Peso Ceiling** | `total_amount = ceil(cooperative_amount)` | [Money.roundUpToWholePeso()](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/value_objects/money.dart#L86-L90), [fn_post_bill_amount](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/02_functions.sql#L424) |
| **Rounding Reserve ("Pondo")** | `rounding_share = total_amount - cooperative_amount` (centavos difference < ₱1.00) | [17_bill_cooperative_amount.sql](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/17_bill_cooperative_amount.sql#L49-L58), [20261007105843_regular_rounding_reserve_credit.sql](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/20261007105843_regular_rounding_reserve_credit.sql) |
| **Energy Consumption** | `consumption = current_reading - previous_reading` | [Kwh.operator -](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/value_objects/kwh.dart#L53), [meter_readings.consumption](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/01_schema.sql#L314) |
| **Outstanding Balance** | `balance = total_amount - amount_paid - waiver_amount - external_paid` | [Bill.balance](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/lib/domain/entities/bill.dart#L150-L152), [trg_bills_sync_derived](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/01_schema.sql#L380) |
| **Change Due** | `change_due = cash_tendered - total_collected` | [fn_record_payment](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/02_functions.sql#L537) |
| **Meter Reader Compensation** | ₱500 / month (₱200 salary + ₱300 transport), funded from Reserve Fund | [fn_pay_reader_compensation](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/20261004070000_reader_monthly_compensation.sql#L22-L36) |
| **Disconnection Window** | Served time + courtesy hours (>= 48h), rolled to weekday non-holidays between 8:00 AM – 3:00 PM | [fn_earliest_lawful_disconnection](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/supabase/migrations/02_functions.sql#L136-L179) |

---

## 8. Testing & Verification Architecture

The test harness incorporates **610 automated tests**, all passing across unit, integration, architecture, and widget categories:

- **Architectural Guard Tests (`test/architecture/`):**
  - [domain_has_no_dependencies_test.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/test/architecture/domain_has_no_dependencies_test.dart): Verifies that `lib/domain/` imports only pure Dart and `lib/core/`.
  - Verifies that no peso amount is represented by a `double` anywhere across `lib/`.
  - [vocabulary_test.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/test/architecture/vocabulary_test.dart): Asserts terminology consistency across code and schema.
- **Domain Logic Tests (`test/domain/`):**
  - [money_test.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/test/domain/money_test.dart): Verifies integer centavo arithmetic and tests binary floating point failures beside passing `Money` tests.
  - [kwh_test.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/test/domain/kwh_test.dart): Verifies hundredths parsing, subtraction, and database string formatting.
  - [bill_test.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/test/domain/bill_test.dart): Tests `isUnpriced`, `isPayable`, `isSettled`, and due date suggestions.
  - Use case tests covering `RecordMeterReading`, `PostBillAmount`, `RecordCashPayment`, and `IssueDisconnectionNotice`.
- **Data & Security Tests (`test/data/`):**
  - [encryption_test.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/test/data/encryption_test.dart): Asserts that the local SQLite cache file is unreadable without the SQLCipher key and that wrong keys fail.
  - [outbox_repository_test.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/test/data/outbox_repository_test.dart): Tests outbox queue ordering, serialization, and status updates.
  - [consumer_offline_cache_test.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/test/data/consumer_offline_cache_test.dart): Tests roster persistence across simulated offline restarts.
- **Presentation & Widget Tests (`test/presentation/`):**
  - Tests covering login flows, app lock biometric gates, role routing guards, and UI screens for Admin, Reader, Consumer, and Cashier modules.
- **Test Double Infrastructure (`test/support/`):**
  - Hand-written pure Dart fakes in [test/support/fakes.dart](file:///c:/Users/Charles%20Carcallas/Documents/Atigravity/BillAlert/test/support/fakes.dart) allow executing comprehensive use case and repository tests without network access, database processes, or Flutter bindings.
