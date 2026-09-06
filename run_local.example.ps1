# Copy to run_local.ps1 (which is gitignored) and fill in your own values.
# The repository must never contain the URL or the key.

$env:BILLALERT_URL = "https://YOUR-PROJECT.supabase.co"
$env:BILLALERT_KEY = "YOUR-ANON-KEY"

flutter run `
  --dart-define=SUPABASE_URL=$env:BILLALERT_URL `
  --dart-define=SUPABASE_ANON_KEY=$env:BILLALERT_KEY
