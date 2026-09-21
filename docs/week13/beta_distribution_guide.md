# Week 13 — BillAlert beta distribution guide

Prepared 17 September 2026. Goal: distribute a beta APK through Firebase App
Distribution to at least three actual testers, collect their feedback, and
document the results. Supabase remains BillAlert's backend.

## 1. Finalize the Android identity

The current `android/app/build.gradle.kts` has:

```kotlin
namespace = "ph.edu.bisu.billalert"
applicationId = "ph.edu.bisu.billalert"
```

Both settings now agree. Register/select **ph.edu.bisu.billalert** in Firebase.
The Android manifest and MainActivity package must continue to resolve together.

Changing application ID installs a separate app. Sync pending work in the old
app first; its session, cached records and outbox do not transfer automatically.
Testers must uninstall the old example-package BillAlert build before installing
this beta, but **only after all pending work has synced and been verified**.
Do not uninstall an app with work waiting to sync. If it cannot sync, stop and
contact the coordinator; uninstalling removes its local queue and cache.

## 2. Decide signing and versioning

Release builds read `android/key.properties` when it exists. Without that file,
they fall back to debug signing so other developers can build locally. An
incomplete properties file fails explicitly; it does not silently fall back.
**Use the release key for every tester build.**

1. From the repository root, run this once (not on every build):

   ```powershell
   keytool -genkeypair -v -keystore "$env:USERPROFILE\billalert-release.jks" -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias billalert
   ```

   Choose strong passwords at the prompts, never as command-line arguments.
   If `keytool` is not on PATH, use the `keytool.exe` in your JDK's `bin`
   directory (Android Studio's bundled JDK is another option).
   If this keystore already exists, do not replace it; reuse the original key.

2. Create `android/key.properties` privately in your editor:

   ```properties
   storeFile=C:/Users/Charles Carcallas/billalert-release.jks
   storePassword=REPLACE_LOCALLY
   keyAlias=billalert
   keyPassword=REPLACE_LOCALLY
   ```

   Replace placeholders with your chosen passwords. Use forward slashes in
   Windows paths; relative paths resolve from `android/`. Do not paste the
   completed file into chat, screenshots, documentation or GitHub.

3. Confirm exclusions without displaying the file contents:

   ```powershell
   git check-ignore android/key.properties
   ```

   `key.properties`, `*.jks` and `*.keystore` are ignored. Keep an encrypted
   backup of the keystore and its passwords outside the repository, and record
   who holds it. Sign every tester update with this same key and application ID.
   A previously debug-signed install cannot be updated with the new release key:
   sync and verify its queued work first, then uninstall it and install the beta.

See [Flutter's signing guide](https://docs.flutter.dev/deployment/android).

Current beta version in `pubspec.yaml`:

```yaml
version: 0.2.0+2
```

If a higher build number has already been distributed, choose a higher unused
number. Increase the build number for each beta update, such as `0.2.0+3`.
Record the version and source commit with each uploaded APK.

## 3. Build and check the beta

In PowerShell:

```powershell
Set-Location 'C:\Users\Charles Carcallas\Documents\Atigravity\BillAlert'
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=env.json
```

Use the project's private `env.json` containing the Supabase URL and anon key.
The SMS API key and Supabase service-role key must remain server-side.

Expected analyzer baseline: seven existing issues confined to `scratch/`.
All remaining tests must pass. The built-in demo implementation has been removed;
use assigned Supabase accounts, not `admin` / `demo`.

Output:

```text
C:\Users\Charles Carcallas\Documents\Atigravity\BillAlert\build\app\outputs\flutter-apk\app-release.apk
```

Install this exact APK on your own phone. Confirm startup, sign-in, role
navigation and backend access before inviting testers. Record its version and
optionally its SHA-256:

```powershell
Get-FileHash -Algorithm SHA256 'build\app\outputs\flutter-apk\app-release.apk'
git rev-parse HEAD
git status --short
```

If the tree has uncommitted changes, record that fact; a commit ID alone does
not describe that build. Archive the submitted APK privately so later builds
do not overwrite your only copy. Never include `env.json` in the submission.

## 4. Set up Firebase App Distribution

1. Open the [Firebase console](https://console.firebase.google.com/).
2. Create a project named **BillAlert**, or select your existing project.
3. Google Analytics is optional for this distribution workflow.
4. From Project Overview, add an **Android** app.
5. Enter the final `applicationId` as **Android package name**. It is
   case-sensitive and cannot be changed on that registered Firebase app.
6. Use **BillAlert Android Beta** as an optional nickname. SHA-1 is not required
   for this APK distribution workflow.
7. Register the app and return to the console. For App Distribution alone,
   project creation and app registration are sufficient; no Firebase SDK or
   `google-services.json` integration is needed.
8. Open **App Distribution** (use the console product search if needed), select
   the Android app, and click **Get started**.

Use the APK workflow for this assignment. Follow the
[official Firebase console distribution guide](https://firebase.google.com/docs/app-distribution/android/distribute-console)
if labels differ in your console.

## 5. Upload and invite testers

### Privacy note to share with testers

BillAlert uses **Google Analytics for Firebase** to understand beta usage and
engagement. The SDK sends Google automatic events such as first open, sessions
and engagement, an app-instance identifier, and app/device information such as
app version, device model, operating system and language. Approximate location
can be derived from IP addresses; advertising identifiers may also be collected
where available and permitted by the device and SDK configuration. Do not
describe this as collecting no personal data. See Google's
[Analytics data collection description](https://support.google.com/analytics/answer/11593727?hl=en).

Our integration does not deliberately attach household names, mobile numbers,
passwords, bill amounts or Supabase user IDs to Analytics events. Billing and
authentication remain in Supabase. Analytics is optional for Firebase App
Distribution itself, but enabled in this build. Give testers this notice before
installation; there is currently no in-app Analytics opt-out control.

1. On **Releases**, upload `app-release.apk`.
2. Add at least three tester email addresses or a tester group.
3. Add release notes, then click **Distribute**.
4. Capture the release/version and invitation status as evidence.

Suggested release notes:

```text
BillAlert — Week 13 beta
Version: [actual version and build number]
Test your assigned role, search/sort, appearance and account access.
For offline tests, confirm queued work survives closing and reopening the app.
Use only the test households assigned by the coordinator.
Report results using the shared feedback form.
```

Firebase's [distribution guide](https://firebase.google.com/docs/app-distribution/android/distribute-console)
describes the upload and invitation flow. Send BillAlert account credentials
privately, separately from release notes.

## 6. Have testers install through Firebase

Send each tester these instructions:

1. Open the Firebase invitation email on your Android phone.
2. Follow the invitation link, sign in with your Google account and accept.
3. Download the assigned build and install it. If Android requests permission
   to install from that browser or App Tester, allow that source for installation.
4. Open BillAlert and sign in using the separate BillAlert credentials supplied
   privately. The Firebase Google account is not your BillAlert login.
5. Record your phone model, Android version and beta version in your feedback.

See [Firebase's Android tester setup](https://firebase.google.com/docs/app-distribution/get-set-up-as-a-tester?platform=android).
An invitation or download alone does not prove testing: collect task results
from each participant. Avoid uninstalling during testing because it removes
local data, including pending offline work.

## 7. Coordinate the tests

Suggested allocation: Charles coordinates/Admin; Busalanan tests Meter Reader;
Obiso tests Cashier; Basio tests Consumer. Confirm actual participation and
whether your instructor permits teammates as the three testers.

| Role | Required tasks | Evidence |
| --- | --- | --- |
| Everyone | Sign in/out; appearance; search and sorting where available | Result, build and phone details |
| Admin | Create an authorized test account; review and post a cooperative amount | Confirmation, resulting bill or queued status |
| Meter Reader | Record offline; close/force-stop; reopen offline; reconnect | Queue before and after reopening, then successful sync |
| Cashier | Find assigned household; collect an agreed payment; open receipt | Receipt reference and correct details |
| Consumer | Open bills, history and alerts; reopen offline; biometric/password access | Cached data and access results |
| Consumer/coordinator | Check SMS and due-date notification on the intended phone | Arrival time, related bill and permission state |

Assign a household and billing cycle to each test before starting. A second
reading in the same cycle is blocked; a payment consumes a payable bill.
Use agreed test transactions and preserve records needed by other testers.
Do not invent a tariff. Record offline persistence separately from reconnect
success. For notification timing, record whether Android force-stop was used,
since that can affect background delivery until the app is reopened.

## 8. Collect feedback and retest fixes

Use a shared form or document with these fields:

- Tester name and assigned role
- Phone model, Android version, app version/build
- Task and steps performed
- Expected result and actual result
- Pass/fail/blocked, plus screenshot or recording if useful
- Date, network state and comments

Track each issue with an ID, severity, owner, status, fixed build and retest
result. Prioritize inability to sign in, lost queued work, incorrect billing
or receipt results, crashes and data-access problems.

After a fix, increase the build number, run relevant checks, build with the
same application ID and signing key, upload to the same Firebase app and
redistribute. Ask affected testers to repeat their failed steps.

## 9. Assemble the Week 13 submission

Keep evidence under `docs/week13/`, excluding secrets and unnecessary personal
data. Submit the APK separately through the instructor's required channel.

- Beta APK and recorded version/build, application ID and build date
- Firebase release screenshot and tester acceptance/download evidence
- Completed feedback from at least three actual testers
- Bug log with fixes, retest results and unresolved items
- Short test summary identifying which role flows passed or remain blocked

Week 13 is complete when the build has been distributed through Firebase and
at least three people have actually tested it and provided recorded feedback.
Creating a Firebase project or sending invitations alone does not complete it.
