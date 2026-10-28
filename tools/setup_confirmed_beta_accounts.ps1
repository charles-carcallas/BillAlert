<# Creates missing confirmed people through the existing account API.
Preview default. No passwords are saved. Existing passwords are NOT reset.
Accounts initially use Consumer role; SQL 30 assigns the verified staff roles.
#>
param([switch]$Apply, [string]$EnvFile=(Join-Path $PSScriptRoot '../env.json'))
$ErrorActionPreference='Stop'
$people=@(
  @{username='ledesman.dormal';first_name='Ledesman';last_name='Dormal';consumer_no='BETA-LEDESMAN'},
  @{username='mercedita.gales';first_name='Mercedita';last_name='Gales';consumer_no='BETA-MERCEDITA'},
  @{username='virgilio.busalanan';first_name='Virgilio';last_name='Busalanan';consumer_no='BETA-VIRGILIO'}
)
$people | ForEach-Object { Write-Host ($_.username + ' -> provisional household ' + $_.consumer_no) }
if(!$Apply) { Write-Host 'Preview only. Use -Apply after reviewing SQL 00. Existing accounts will be reused.'; return }
$config=Get-Content -LiteralPath $EnvFile -Raw | ConvertFrom-Json
$projectUrl=([string]$config.SUPABASE_URL).TrimEnd('/')
$key=[string]$config.SUPABASE_ANON_KEY
if($projectUrl -ne 'https://thbnomjwovsdvwulkaub.supabase.co' -or !$key) {
  throw 'Expected BillAlert project URL and anon key in env.json. No requests sent.'
}
function Read-PrivateText([string]$Prompt) {
  $secure=Read-Host $Prompt -AsSecureString
  $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
}
$session=$null; $password=$null; $temporary=$null; $body=$null
try {
  $password=Read-PrivateText 'Current Mario Admin password'
  try {
    $session=Invoke-RestMethod -Method Post -Uri "$projectUrl/auth/v1/token?grant_type=password" `
      -Headers @{apikey=$key} -ContentType 'application/json' `
      -Body (@{email='mario.ombajin@billalert.local';password=$password}|ConvertTo-Json)
  } catch { throw 'Admin sign-in failed. No accounts created. Check credentials privately.' }
  $password=$null
  $headers=@{apikey=$key;Authorization=('Bearer '+$session.access_token)}
  try {
    $workspace=Invoke-RestMethod -Method Post -Uri "$projectUrl/rest/v1/rpc/fn_account_workspace" `
      -Headers $headers -ContentType 'application/json' -Body '{}'
  } catch { throw 'Could not load Admin account inventory. Nothing created.' }
  $missing=@()
  foreach($person in $people) {
    $existing=@($workspace.people | Where-Object { $_.username -eq $person.username })
    if($existing.Count -eq 1) {
      $linked=@($workspace.households | Where-Object { $_.profile_id -eq $existing[0].id })
      if($linked.Count -ne 1) { throw ('Existing '+$person.username+' needs its household link inspected. No creation attempted.') }
      Write-Host ('Reusing '+$person.username+'; password unchanged.')
    } elseif($existing.Count -gt 1) { throw 'Duplicate identity in inventory; inspect before continuing.' }
    else {
      if(@($workspace.households | Where-Object { $_.consumer_no -eq $person.consumer_no }).Count) {
        throw ('Provisional household '+$person.consumer_no+' already exists. Inspect/link it; do not create a duplicate.')
      }
      $missing+=,$person
    }
  }
  if(!$missing.Count) { Write-Host 'All three accounts already exist. Continue with SQL 20 and 30.'; return }
  $temporary=Read-PrivateText 'Temporary beta password for NEW accounts only (minimum 8 characters)'
  if($temporary.Length -lt 8 -or $temporary.Length -gt 256) { throw 'Password length must be 8-256 characters.' }
  foreach($person in $missing) {
    $body=@{action='create_account';role='consumer';username=$person.username;
      first_name=$person.first_name;last_name=$person.last_name;temporary_password=$temporary;
      reason='BETA setup: confirmed person; provisional household number; unknown contact and meter';
      household=@{mode='new';confirmed=$true;consumer_no=$person.consumer_no}} | ConvertTo-Json -Depth 5
    try { $result=Invoke-RestMethod -Method Post -Uri "$projectUrl/functions/v1/manage-accounts" `
      -Headers $headers -ContentType 'application/json' -Body $body }
    catch { throw ('Creation not confirmed for '+$person.username+'. STOP: run SQL 00 and inspect Auth before retrying. No automatic retry.') }
    if($result.ok -ne $true -or !$result.id) {
      throw ('Creation not confirmed for '+$person.username+'. STOP: inspect SQL 00 and Auth before retrying.')
    }
    Write-Host ('Created '+$person.username+' with linked provisional household. First sign-in requires a password change.')
  }
  Write-Host 'Account setup complete. Review/apply SQL 20, then SQL 30 for final roles.'
} finally {
  $password=$null; $temporary=$null; $body=$null
  if($session) {
    try { Invoke-RestMethod -Method Post -Uri "$projectUrl/auth/v1/logout?scope=local" `
      -Headers @{apikey=$key;Authorization=('Bearer '+$session.access_token)} | Out-Null }
    catch { Write-Host 'Script session logout could not be confirmed.' }
  }
}
