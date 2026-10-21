# Shows the real App Review status of Dungeon Descent or Accessible Backrooms,
# straight from App Store Connect, and can send a stuck submission to Apple.
# Runs on your own computer; your key never leaves it.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Api = 'https://api.appstoreconnect.apple.com'

function Say($t) { Write-Host $t }
function Stop-With($t) { Say ''; Say "PROBLEM: $t"; Say 'You can run this again after fixing it.'; exit 1 }

# ---------- which app ----------
Say 'Which app do you want to check?'
Say '  1: Dungeon Descent'
Say '  2: Accessible Backrooms'
$choice = (Read-Host 'Type 1 or 2 and press Enter').Trim()
if ($choice -eq '1') { $BundleId = 'com.dungeon.descent'; $AppName = 'Dungeon Descent' }
elseif ($choice -eq '2') { $BundleId = 'com.accessible.backrooms'; $AppName = 'Accessible Backrooms' }
else { Stop-With 'Please type 1 or 2.' }

# ---------- the key ----------
$p8 = Get-ChildItem -Path $Here -Filter 'AuthKey_*.p8' | Select-Object -First 1
if (-not $p8) { Stop-With 'I could not find your key file. Put the file that starts with AuthKey_ and ends with .p8 in this same folder.' }
$KeyId = $p8.BaseName -replace '^AuthKey_', ''
Say ''
Say "Found your key file. Key ID: $KeyId"
Say 'Paste your Issuer ID and press Enter.'
$IssuerId = (Read-Host 'Issuer ID').Trim()
if ($IssuerId -notmatch '^[0-9a-fA-F-]{36}$') { Stop-With 'That does not look like an Issuer ID. It has 36 characters with dashes.' }

$pem = Get-Content -Raw -Path $p8.FullName
$keyBytes = [Convert]::FromBase64String(($pem -replace '-----[^-]+-----', '' -replace '\s', ''))
try {
  $cng = [System.Security.Cryptography.CngKey]::Import($keyBytes, [System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
  $ecdsa = New-Object System.Security.Cryptography.ECDsaCng($cng)
} catch {
  $ecdsa = [System.Security.Cryptography.ECDsa]::Create()
  $read = 0; $ecdsa.ImportPkcs8PrivateKey($keyBytes, [ref]$read)
}
function B64Url([byte[]]$b) { [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
function New-Token {
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $h = '{"alg":"ES256","kid":"' + $KeyId + '","typ":"JWT"}'
  $p = '{"iss":"' + $IssuerId + '","iat":' + $now + ',"exp":' + ($now + 1100) + ',"aud":"appstoreconnect-v1"}'
  $unsigned = (B64Url ([Text.Encoding]::UTF8.GetBytes($h))) + '.' + (B64Url ([Text.Encoding]::UTF8.GetBytes($p)))
  return $unsigned + '.' + (B64Url ($ecdsa.SignData([Text.Encoding]::UTF8.GetBytes($unsigned), [System.Security.Cryptography.HashAlgorithmName]::SHA256)))
}
$script:Token = New-Token
function Call($Method, $Path, $Body) {
  $url = if ($Path.StartsWith('http')) { $Path } else { $Api + $Path }
  $req = @{ Method = $Method; Uri = $url; Headers = @{ Authorization = "Bearer $($script:Token)" } }
  if ($Body) { $req.ContentType = 'application/json; charset=utf-8'; $req.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10)) }
  try { return Invoke-RestMethod @req }
  catch {
    $msg = $_.Exception.Message
    try {
      $r = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $raw = $r.ReadToEnd()
      $j = $raw | ConvertFrom-Json
      $msg = ($j.errors | ForEach-Object { "$($_.title): $($_.detail)" }) -join ' / '
      # Apple lists exactly what is wrong under associatedErrors, one list per item.
      $list = @()
      foreach ($e in $j.errors) {
        $assoc = $e.meta.associatedErrors
        if ($assoc) { foreach ($prop in $assoc.PSObject.Properties) { foreach ($x in @($prop.Value)) { $list += "  - $($x.title) $($x.detail) [$($x.code)]" } } }
      }
      if ($list.Count) { $msg += "`r`nWhat is wrong:`r`n" + ($list -join "`r`n") }
      # Save Apple's whole answer so it can be copied and sent to Claude.
      Set-Content -Path (Join-Path $Here 'apple-answer.txt') -Value $raw -Encoding UTF8
    } catch {}
    throw "Apple said: $msg"
  }
}

# Plain words for Apple's status codes.
$VersionWords = @{
  PREPARE_FOR_SUBMISSION = 'not sent yet (Prepare for Submission)'
  READY_FOR_REVIEW = 'ready, but not sent yet'
  WAITING_FOR_REVIEW = 'in line, waiting for a reviewer'
  IN_REVIEW = 'being reviewed right now'
  DEVELOPER_REJECTED = 'pulled back by you, not sent'
  REJECTED = 'rejected, Apple asked for changes or information'
  METADATA_REJECTED = 'rejected because of the store page text or pictures'
  UNRESOLVED_ISSUES = 'Apple asked something, and it was not resubmitted yet'
  PENDING_DEVELOPER_RELEASE = 'APPROVED! Waiting for you to press Release'
  PENDING_APPLE_RELEASE = 'APPROVED! Apple will release it soon'
  PROCESSING_FOR_DISTRIBUTION = 'APPROVED! Being prepared for the App Store'
  READY_FOR_DISTRIBUTION = 'LIVE on the App Store'
  ACCEPTED = 'APPROVED'
  INVALID_BINARY = 'the uploaded build has a problem'
}
$SubWords = @{
  READY_FOR_REVIEW = 'a DRAFT that was never sent to Apple'
  WAITING_FOR_REVIEW = 'SENT, in line, waiting for a reviewer'
  IN_REVIEW = 'SENT, being reviewed right now'
  UNRESOLVED_ISSUES = 'Apple asked something, and it was NOT resubmitted after your reply'
  CANCELING = 'being cancelled'
  COMPLETING = 'finishing up'
  COMPLETE = 'finished'
}
function Words($table, $code) { if ($table.ContainsKey($code)) { "$($table[$code]) [$code]" } else { $code } }

# ---------- read everything ----------
Say ''
Say 'Connecting to App Store Connect...'
try { $apps = Call GET "/v1/apps?filter[bundleId]=$BundleId" } catch { Stop-With "$_ . Check the Issuer ID and the key file." }
if (-not $apps.data) { Stop-With "No app with bundle ID $BundleId was found." }
$AppId = $apps.data[0].id

Say ''
Say "===== $AppName ====="
$versions = @((Call GET "/v1/apps/$AppId/appStoreVersions?filter[platform]=IOS&limit=5").data)
foreach ($v in $versions) {
  $st = if ($v.attributes.appVersionState) { $v.attributes.appVersionState } else { $v.attributes.appStoreState }
  Say "Version $($v.attributes.versionString): $(Words $VersionWords $st)"
}

$subs = @((Call GET "/v1/reviewSubmissions?filter[app]=$AppId&filter[platform]=IOS&limit=20").data | Where-Object { $_.attributes.state -ne 'COMPLETE' })
Say ''
if (-not $subs) { Say 'There are no open review submissions.' }
$info = @()
foreach ($s in $subs) {
  $items = @((Call GET "/v1/reviewSubmissions/$($s.id)/items?include=appStoreVersion&limit=200").data)
  $hasVersion = @($items | Where-Object { $_.relationships.appStoreVersion.data }).Count -gt 0
  $others = $items.Count - [int]$hasVersion
  $what = @()
  if ($hasVersion) { $what += 'the app version' }
  if ($others) { $what += "$others other items (like Game Center achievements)" }
  if (-not $what) { $what = @('nothing') }
  $when = if ($s.attributes.submittedDate) { ', sent on ' + ([DateTime]$s.attributes.submittedDate).ToString('dddd, MMMM d') } else { '' }
  Say "Submission: $(Words $SubWords $s.attributes.state)$when."
  Say "  It contains: $($what -join ' and ')."
  $info += [pscustomobject]@{ Sub = $s; State = $s.attributes.state; HasVersion = $hasVersion; Count = $items.Count }
}

# ---------- what to do ----------
Say ''
Say '===== What this means ====='
$active = $info | Where-Object { 'WAITING_FOR_REVIEW', 'IN_REVIEW' -contains $_.State } | Select-Object -First 1
$unresolved = $info | Where-Object { $_.State -eq 'UNRESOLVED_ISSUES' } | Select-Object -First 1
$draft = $info | Where-Object { $_.State -eq 'READY_FOR_REVIEW' } | Select-Object -First 1
$target = $null

if ($active) {
  Say 'Good news: Apple HAS your submission. It is in line or being reviewed. Nothing is stuck on your side.'
  if ($draft) { Say 'There is also an extra draft that was never sent. It can only be sent after the current review finishes. That is normal.' }
} elseif ($unresolved) {
  Say 'FOUND IT. Apple asked you something. You replied, but the submission was never sent back to Apple, so nobody is reviewing it.'
  $target = $unresolved
} elseif ($draft) {
  Say 'FOUND IT. Your submission is a DRAFT. It was never sent to Apple, so nobody is reviewing it.'
  $target = $draft
} else {
  Say 'Nothing is waiting to be sent. If a version above says not sent yet, it may need a build or a new submission in App Store Connect.'
}

if (-not $target) { Say ''; Say 'Done. Nothing was changed.'; exit 0 }

# A draft without the app version in it would only send the extras, so add the version first.
$version = $versions | Select-Object -First 1
$vState = if ($version.attributes.appVersionState) { $version.attributes.appVersionState } else { $version.attributes.appStoreState }
$canAdd = 'PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'UNRESOLVED_ISSUES' -contains $vState
Say ''
$q = 'Do you want me to send it to Apple now'
if (-not $target.HasVersion -and $canAdd) { $q += ", and add version $($version.attributes.versionString) to it" }
$erdOld = $version.attributes.earliestReleaseDate
if ($erdOld -and ([DateTime]$erdOld).ToUniversalTime() -lt [DateTime]::UtcNow) {
  Say "Also found: the release date is set to $(([DateTime]$erdOld).ToString('MMMM d')), which already passed. Apple refuses that. I will change it to: release as soon as Apple approves."
}
$answer = (Read-Host "${q}? Type Y and press Enter, or just press Enter to stop").Trim()
if ($answer -notmatch '^[Yy]') { Say 'OK, nothing was changed.'; exit 0 }

if (-not $target.HasVersion -and $canAdd) {
  try {
    Call POST '/v1/reviewSubmissionItems' @{ data = @{ type = 'reviewSubmissionItems'; relationships = @{
      reviewSubmission = @{ data = @{ type = 'reviewSubmissions'; id = $target.Sub.id } };
      appStoreVersion = @{ data = @{ type = 'appStoreVersions'; id = $version.id } } } } } | Out-Null
    Say "Added version $($version.attributes.versionString)."
  } catch { Say "Could not add the version: $_" }
}
# Apple refuses a version whose "release no earlier than" date has passed.
$erd = $version.attributes.earliestReleaseDate
if ($erd -and ([DateTime]$erd).ToUniversalTime() -lt [DateTime]::UtcNow) {
  try {
    Call PATCH "/v1/appStoreVersions/$($version.id)" @{ data = @{ type = 'appStoreVersions'; id = $version.id; attributes = @{ releaseType = 'AFTER_APPROVAL'; earliestReleaseDate = $null } } } | Out-Null
    Say 'Fixed the release date: it was set to a day that already passed. The app will now be released as soon as Apple approves it.'
  } catch { Say "Could not fix the release date: $_" }
}
try {
  Call PATCH "/v1/reviewSubmissions/$($target.Sub.id)" @{ data = @{ type = 'reviewSubmissions'; id = $target.Sub.id; attributes = @{ submitted = $true } } } | Out-Null
  Say ''
  Say "SENT! $AppName is now with Apple. The status should change to Waiting for Review."
} catch {
  Say ''
  Say 'Apple would not send it. Here is exactly what Apple said:'
  Say "  $_"
  Say 'Apple''s full answer was also saved in this folder as apple-answer.txt. Send that file, or a photo of this window, to Claude.'
}
