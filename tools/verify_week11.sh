#!/usr/bin/env bash
set -e
dart analyze
flutter test test/architecture/
flutter test
echo
echo "Automated checks passed."
echo "These are NOT automated — see docs/week11/evidence_log.md:"
echo "  offline save · app restart · sync · replayed clientUuid · Supabase row"
