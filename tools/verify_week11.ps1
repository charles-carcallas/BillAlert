$ErrorActionPreference = 'Stop'
dart analyze
flutter test test/architecture/
flutter test
Write-Host ""
Write-Host "Automated checks passed."
Write-Host "These are NOT automated — see docs/week11/evidence_log.md:"
Write-Host "  offline save · app restart · sync · replayed clientUuid · Supabase row"
