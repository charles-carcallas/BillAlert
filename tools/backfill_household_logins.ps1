<#
User-run only. Preview by default; no live operation was run by Codex.
Input CSV: household_id,username,first_name,last_name
Review missing-household people FIRST and link them in-app; exclude those
households from this CSV. Never create another login for an existing person.
Output contains credentials: private directory outside the repository only.
#>
param(
  [Parameter(Mandatory=$true)][string]$Manifest,
  [Parameter(Mandatory=$true)][string]$PrivateOutput,
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$outputFile = [IO.Path]::GetFullPath($PrivateOutput)
if ($outputFile.StartsWith($repoRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Credentials must be stored privately OUTSIDE the repository.'
}
$rows = @(Import-Csv -LiteralPath $Manifest)
if (!$rows.Count) { throw 'The reviewed manifest is empty.' }
$ids = @{}; $names = @{}
foreach ($row in $rows) {
  $parsed = [guid]::Empty
  if (![guid]::TryParse($row.household_id, [ref]$parsed) -or
      $row.username -cnotmatch '^[a-z][a-z0-9._-]{2,49}$' -or
      [string]::IsNullOrWhiteSpace($row.first_name) -or [string]::IsNullOrWhiteSpace($row.last_name)) {
    throw 'Manifest needs valid household_id, username, first_name and last_name on every row.'
  }
  if ($ids.ContainsKey($row.household_id) -or $names.ContainsKey($row.username)) { throw 'Duplicate household or username in manifest.' }
  $ids[$row.household_id]=$true; $names[$row.username]=$true
}
Write-Host ('Reviewed accounts in manifest: ' + $rows.Count)
if (!$Apply) { Write-Host 'Preview only. Nothing sent. Review the manifest, then use -Apply to create these accounts.'; return }
if (Test-Path -LiteralPath $outputFile) { throw 'Output already exists. Check its results and uncertain entries before preparing a NEW manifest; this script never blindly retries.' }
$projectUrl = (Read-Host 'Supabase project URL (https://...supabase.co)').TrimEnd('/')
if ($projectUrl -notmatch '^https://[a-z0-9-]+\.supabase\.co$') { throw 'Enter the project HTTPS URL.' }
$key = Read-Host 'Publishable/anon key (enter privately; do not paste in chat)'
$email = Read-Host 'Area President login email'
$secret = Read-Host 'Area President password' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
$session = $null
try {
  try { $session = Invoke-RestMethod -Method Post -Uri "$projectUrl/auth/v1/token?grant_type=password" -Headers @{apikey=$key} -ContentType 'application/json' -Body (@{email=$email;password=$password}|ConvertTo-Json) }
  catch { throw 'Sign-in failed. No creation attempted. Check credentials privately.' }
  $password=$null
  $headers=@{apikey=$key;Authorization=('Bearer ' + $session.access_token)}
  $workspace=Invoke-RestMethod -Method Post -Uri "$projectUrl/rest/v1/rpc/fn_account_workspace" -Headers $headers -ContentType 'application/json' -Body '{}'
  # Check every row before creating the first one; server rechecks under lock.
  foreach($row in $rows) {
    $matches=@($workspace.households | Where-Object { $_.id -eq $row.household_id -and $_.account_status -eq 'active' -and !$_.profile_id })
    if($matches.Count -ne 1) { throw 'A requested household is unavailable or already linked. Refresh the inventory; no creation attempted.' }
    if(@($workspace.people | Where-Object {$_.username -eq $row.username}).Count) { throw 'A username already exists. Reuse that account instead of creating another.' }
  }
  New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($outputFile)) | Out-Null
  $results=[Collections.Generic.List[object]]::new()
  foreach($row in $rows) {
    $bytes=New-Object byte[] 24
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $temporary='Ba1!' + [Convert]::ToBase64String($bytes)
    $entry=[pscustomobject]@{household_id=$row.household_id;username=$row.username;temporary_password=$temporary;status='attempted_unconfirmed';profile_id=''}
    $results.Add($entry)
    $results | Export-Csv -LiteralPath $outputFile -NoTypeInformation -Encoding UTF8
    $body=@{action='create_account';role='consumer';username=$row.username;first_name=$row.first_name;last_name=$row.last_name;
      temporary_password=$temporary;reason='Reviewed legacy household login setup';household=@{mode='existing';id=$row.household_id;confirmed=$true}} | ConvertTo-Json -Depth 5
    try { $result=Invoke-RestMethod -Method Post -Uri "$projectUrl/functions/v1/manage-accounts" -Headers $headers -ContentType 'application/json' -Body $body }
    catch { throw 'Request outcome uncertain. STOPPED. Check the private output and accounts before retrying; do not rerun this manifest.' }
    if($result.ok -ne $true) {
      $entry.status = if($result.kind -in @('validation','rejected','conflict','permission')) {'rejected'} else {'uncertain'}
      $results | Export-Csv -LiteralPath $outputFile -NoTypeInformation -Encoding UTF8
      throw 'Account setup not confirmed. STOPPED. Review private results and live account state; do not repeat blindly.'
    }
    $createdId = [guid]::Empty
    if (![guid]::TryParse([string]$result.id, [ref]$createdId)) { throw 'Malformed creation response. STOPPED; check accounts before retrying.' }
    $entry.status='created'; $entry.profile_id=$result.id
    $results | Export-Csv -LiteralPath $outputFile -NoTypeInformation -Encoding UTF8
    Write-Host ('Created ' + $results.Count + ' of ' + $rows.Count + '. Credentials saved privately.')
  }
} finally {
  $password=$null; $body=$null; $temporary=$null
  if($session) {
    try { Invoke-RestMethod -Method Post -Uri "$projectUrl/auth/v1/logout?scope=local" -Headers @{apikey=$key;Authorization=('Bearer ' + $session.access_token)} | Out-Null }
    catch { Write-Host 'Could not confirm script session logout.' }
  }
}
