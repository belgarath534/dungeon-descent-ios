# Dungeon Descent: gives every Game Center achievement its icon and sends them all
# to App Review in one go, through the App Store Connect API.
# Runs on your own computer; your key never leaves it.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$BundleId = 'com.dungeon.descent'
$Api = 'https://api.appstoreconnect.apple.com'

function Say($t) { Write-Host $t }
function Stop-With($t) { Say ''; Say "PROBLEM: $t"; Say 'You can run this again after fixing it.'; exit 1 }

# ---------- the key ----------
$p8 = Get-ChildItem -Path $Here -Filter 'AuthKey_*.p8' | Select-Object -First 1
if (-not $p8) { Stop-With 'I could not find your key file. Put the file that starts with AuthKey_ and ends with .p8 in this same folder.' }
$KeyId = $p8.BaseName -replace '^AuthKey_', ''
Say "Found your key file. Key ID: $KeyId"
Say ''
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
$script:TokenTime = Get-Date
function Call($Method, $Path, $Body) {
  if (((Get-Date) - $script:TokenTime).TotalMinutes -gt 15) { $script:Token = New-Token; $script:TokenTime = Get-Date }
  $url = if ($Path.StartsWith('http')) { $Path } else { $Api + $Path }
  $req = @{ Method = $Method; Uri = $url; Headers = @{ Authorization = "Bearer $($script:Token)" } }
  if ($Body) { $req.ContentType = 'application/json; charset=utf-8'; $req.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10)) }
  try { return Invoke-RestMethod @req }
  catch {
    $msg = $_.Exception.Message
    try { $r = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $msg = $r.ReadToEnd() } catch {}
    throw "Apple said: $msg"
  }
}
function Get-All($Path) {
  $all = @(); $next = $Path
  while ($next) { $page = Call GET $next; $all += $page.data; $next = $page.links.next }
  return $all
}

# ---------- find the app and its Game Center ----------
Say ''
Say 'Connecting to App Store Connect...'
try { $apps = Call GET "/v1/apps?filter[bundleId]=$BundleId" } catch { Stop-With "$_ . Check the Issuer ID and the key file." }
if (-not $apps.data) { Stop-With "No app with bundle ID $BundleId was found." }
$AppId = $apps.data[0].id
try { $GcId = (Call GET "/v1/apps/$AppId/gameCenterDetail").data.id } catch { $GcId = $null }
if (-not $GcId) { Stop-With 'Game Center is not set up for Dungeon Descent yet.' }

$achievements = Get-All "/v1/gameCenterDetails/$GcId/gameCenterAchievementsV2?limit=200"
$achievements = @($achievements | Where-Object { -not $_.attributes.archived })
Say "Found $($achievements.Count) achievements."

# ---------- icons, and which ones still need review ----------
$toSubmit = @(); $already = 0; $noText = @(); $n = 0
foreach ($a in $achievements) {
  $n++
  $vid = $a.attributes.vendorIdentifier
  $versions = @((Call GET "/v2/gameCenterAchievements/$($a.id)/versions?limit=20").data | Sort-Object { [int]$_.attributes.version } -Descending)
  $v = $versions | Select-Object -First 1
  if (-not $v) { Say "  $vid has no version, skipping."; continue }
  $state = $v.attributes.state
  if ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'ACCEPTED', 'PENDING_RELEASE', 'LIVE' -contains $state) { $already++; continue }

  $locs = @((Call GET "/v2/gameCenterAchievementVersions/$($v.id)/localizations?include=image&limit=50").data)
  if (-not $locs) { $noText += $vid; continue }
  $icon = Join-Path $Here "icons\$vid.png"
  foreach ($l in $locs) {
    if ($l.relationships.image.data) { continue }
    if (-not (Test-Path $icon)) { Say "  No icon file for $vid, it may need one added by hand."; continue }
    $bytes = [IO.File]::ReadAllBytes($icon)
    $img = (Call POST '/v2/gameCenterAchievementImages' @{ data = @{ type = 'gameCenterAchievementImages'; attributes = @{ fileName = "$vid.png"; fileSize = $bytes.Length }; relationships = @{ localization = @{ data = @{ type = 'gameCenterAchievementLocalizations'; id = $l.id } } } } }).data
    foreach ($op in $img.attributes.uploadOperations) {
      $chunk = New-Object byte[] $op.length
      [Array]::Copy($bytes, $op.offset, $chunk, 0, $op.length)
      $h = @{}; $ct = 'image/png'
      foreach ($rh in $op.requestHeaders) { if ($rh.name -eq 'Content-Type') { $ct = $rh.value } else { $h[$rh.name] = $rh.value } }
      Invoke-WebRequest -Method $op.method -Uri $op.url -Headers $h -ContentType $ct -Body $chunk -UseBasicParsing | Out-Null
    }
    Call PATCH "/v2/gameCenterAchievementImages/$($img.id)" @{ data = @{ type = 'gameCenterAchievementImages'; id = $img.id; attributes = @{ uploaded = $true } } } | Out-Null
  }
  $toSubmit += @{ vid = $vid; id = $v.id }
  Say "  $n of $($achievements.Count): $vid is ready."
}
Say ''
Say "$already were already sent to Apple. $($toSubmit.Count) are ready to send now."
if ($noText.Count) { Say "These have no name or description yet, so they were skipped: $($noText -join ', ')" }
if (-not $toSubmit.Count) { Say 'Nothing left to send. ALL DONE!'; exit 0 }

# Apple needs a moment to process the new icons before they can be reviewed.
Say 'Giving Apple a minute to process the icons...'
Start-Sleep -Seconds 60

# ---------- one review submission with all of them ----------
Say ''
Say 'Adding them to a review submission...'
$sub = $null
try { $sub = (Call GET "/v1/reviewSubmissions?filter[app]=$AppId&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW&limit=5").data | Select-Object -First 1 } catch {}
if (-not $sub) {
  try { $sub = (Call POST '/v1/reviewSubmissions' @{ data = @{ type = 'reviewSubmissions'; attributes = @{ platform = 'IOS' }; relationships = @{ app = @{ data = @{ type = 'apps'; id = $AppId } } } } }).data }
  catch { Stop-With "Apple would not start a new review submission ($_). The game's own review may need to finish first; run this again after that." }
}
$added = 0; $failed = @()
foreach ($t in $toSubmit) {
  try {
    Call POST '/v1/reviewSubmissionItems' @{ data = @{ type = 'reviewSubmissionItems'; relationships = @{
      reviewSubmission = @{ data = @{ type = 'reviewSubmissions'; id = $sub.id } };
      gameCenterAchievementVersion = @{ data = @{ type = 'gameCenterAchievementVersions'; id = $t.id } } } } } | Out-Null
    $added++
  } catch { $failed += "$($t.vid): $_" }
}
Say "$added added."
if ($failed.Count) { Say 'These could not be added:'; $failed | Select-Object -First 10 | ForEach-Object { Say "  $_" } }
if (-not $added) { Stop-With 'None could be added, see the reasons above.' }

Say ''
try {
  Call PATCH "/v1/reviewSubmissions/$($sub.id)" @{ data = @{ type = 'reviewSubmissions'; id = $sub.id; attributes = @{ submitted = $true } } } | Out-Null
  Say "ALL DONE! $added achievements were sent to App Review."
} catch {
  Say "The achievements are waiting in a draft submission, but Apple would not send it yet:"
  Say "  $_"
  Say 'This usually means the game itself is still being reviewed. When that finishes, run this again, or open App Store Connect, App Review, and press Submit for Review.'
}
