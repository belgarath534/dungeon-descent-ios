# Dungeon Descent: fills in the App Store page through the App Store Connect API.
# Store text, review notes, categories, the newest build and the screenshots.
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
Say 'It is on App Store Connect, Users and Access, Integrations, App Store Connect API, near the top.'
$IssuerId = (Read-Host 'Issuer ID').Trim()
if ($IssuerId -notmatch '^[0-9a-fA-F-]{36}$') { Stop-With 'That does not look like an Issuer ID. It has 36 characters with dashes, like 69a6de70-1234-...' }

$pem = Get-Content -Raw -Path $p8.FullName
$b64 = ($pem -replace '-----[^-]+-----', '' -replace '\s', '')
$keyBytes = [Convert]::FromBase64String($b64)
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
  $sig = $ecdsa.SignData([Text.Encoding]::UTF8.GetBytes($unsigned), [System.Security.Cryptography.HashAlgorithmName]::SHA256)
  return $unsigned + '.' + (B64Url $sig)
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
function Blank($v) { return ($null -eq $v) -or ("$v".Trim() -eq '') }

# ---------- find the app and the 1.0 version ----------
Say ''
Say 'Connecting to App Store Connect...'
try { $apps = Call GET "/v1/apps?filter[bundleId]=$BundleId" } catch { Stop-With "$_ . Check the Issuer ID, and that the key file is the one you made for Codemagic." }
if (-not $apps.data) { Stop-With "No app with bundle ID $BundleId was found on this account." }
$AppId = $apps.data[0].id
Say 'Found Dungeon Descent.'

$versions = Call GET "/v1/apps/$AppId/appStoreVersions?filter[platform]=IOS&limit=20"
$editable = 'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'
$ver = $versions.data | Where-Object { $editable -contains $_.attributes.appStoreState -or $editable -contains $_.attributes.appVersionState } | Select-Object -First 1
if (-not $ver) { Stop-With 'I could not find a version that is waiting to be filled in (Prepare for Submission). If it is already submitted, choose Remove from Review first.' }
$VersionId = $ver.id
$VersionString = $ver.attributes.versionString
Say "Found version $VersionString."

$T = (Get-Content -Raw -Encoding UTF8 -Path (Join-Path $Here 'store-text.json') | ConvertFrom-Json).en

# ---------- 1. store page text ----------
Say ''
Say '1. Store page text...'
$locs = Call GET "/v1/appStoreVersions/$VersionId/appStoreVersionLocalizations"
$loc = $locs.data | Where-Object { $_.attributes.locale -eq 'en-US' } | Select-Object -First 1
if (-not $loc) { $loc = $locs.data | Select-Object -First 1 }
$attrs = @{ description = $T.description; keywords = $T.keywords; promotionalText = $T.promo }
# Your own support and marketing links stay; these only fill empty boxes.
if (Blank $loc.attributes.supportUrl) { $attrs.supportUrl = $T.supportUrl }
if (Blank $loc.attributes.marketingUrl) { $attrs.marketingUrl = $T.marketingUrl }
Call PATCH "/v1/appStoreVersionLocalizations/$($loc.id)" @{ data = @{ type = 'appStoreVersionLocalizations'; id = $loc.id; attributes = $attrs } } | Out-Null
$LocId = $loc.id
Say '   Description, keywords and promotional text are in.'

# ---------- 2. subtitle, privacy link and categories ----------
Say ''
Say '2. Subtitle, privacy policy link and category...'
try {
  $infos = Call GET "/v1/apps/$AppId/appInfos"
  $info = $infos.data | Where-Object { $_.attributes.appStoreState -ne 'READY_FOR_SALE' -and $_.attributes.state -ne 'READY_FOR_DISTRIBUTION' } | Select-Object -First 1
  if (-not $info) { $info = $infos.data[0] }
  $ls = Call GET "/v1/appInfos/$($info.id)/appInfoLocalizations"
  $l = $ls.data | Where-Object { $_.attributes.locale -eq 'en-US' } | Select-Object -First 1
  if (-not $l) { $l = $ls.data | Select-Object -First 1 }
  $ia = @{ subtitle = $T.subtitle }
  if (Blank $l.attributes.privacyPolicyUrl) { $ia.privacyPolicyUrl = $T.privacyUrl }
  Call PATCH "/v1/appInfoLocalizations/$($l.id)" @{ data = @{ type = 'appInfoLocalizations'; id = $l.id; attributes = $ia } } | Out-Null
  Say "   Subtitle: $($T.subtitle). The app name was not changed."
  try {
    Call PATCH "/v1/appInfos/$($info.id)" @{ data = @{ type = 'appInfos'; id = $info.id; relationships = @{
      primaryCategory = @{ data = @{ type = 'appCategories'; id = 'GAMES' } };
      primarySubcategoryOne = @{ data = @{ type = 'appCategories'; id = 'GAMES_ROLE_PLAYING' } };
      primarySubcategoryTwo = @{ data = @{ type = 'appCategories'; id = 'GAMES_ADVENTURE' } } } } } | Out-Null
    Say '   Category: Games, Role Playing and Adventure.'
  } catch { Say "   Note: could not set the category ($_). Set it on the App Information page." }
} catch { Say "   Note: could not set the subtitle ($_). You can type it on the website." }

# ---------- 3. App Review information ----------
Say ''
Say '3. App Review notes...'
$rd = $null
try { $rd = (Call GET "/v1/appStoreVersions/$VersionId/appStoreReviewDetail").data } catch { $rd = $null }
$ra = @{ notes = $T.reviewNotes; demoAccountRequired = $false }
$need = @(
  @{ k = 'contactFirstName'; q = 'Your first name' },
  @{ k = 'contactLastName'; q = 'Your last name' },
  @{ k = 'contactPhone'; q = 'Your phone number with country code, like +1 555 123 4567' },
  @{ k = 'contactEmail'; q = 'Your email' })
foreach ($n in $need) {
  if (-not $rd -or (Blank $rd.attributes.($n.k))) {
    Say "   Apple needs your contact details for the reviewer (only Apple sees them)."
    $v = (Read-Host "   $($n.q)").Trim()
    if (-not (Blank $v)) { $ra[$n.k] = $v }
  }
}
try {
  if ($rd) { Call PATCH "/v1/appStoreReviewDetails/$($rd.id)" @{ data = @{ type = 'appStoreReviewDetails'; id = $rd.id; attributes = $ra } } | Out-Null }
  else { Call POST '/v1/appStoreReviewDetails' @{ data = @{ type = 'appStoreReviewDetails'; attributes = $ra; relationships = @{ appStoreVersion = @{ data = @{ type = 'appStoreVersions'; id = $VersionId } } } } } | Out-Null }
  Say '   Review notes are in, and "Sign-in required" is off.'
} catch { Say "   Note: could not save the review notes ($_). Paste them from store-text.json into App Review Information, Notes." }

# ---------- 4. newest build ----------
Say ''
Say '4. Choosing the newest build...'
try {
  $builds = Call GET "/v1/builds?filter[app]=$AppId&filter[processingState]=VALID&filter[preReleaseVersion.version]=$VersionString&sort=-uploadedDate&limit=1"
  if ($builds.data) {
    $b = $builds.data[0]
    Call PATCH "/v1/appStoreVersions/$VersionId/relationships/build" @{ data = @{ type = 'builds'; id = $b.id } } | Out-Null
    Say "   Build $($b.attributes.version) is attached."
  } else { Say '   No finished build found yet. Pick it on the version page later.' }
} catch { Say "   Note: could not attach the build ($_). Pick it on the version page." }

# ---------- 5. screenshots ----------
function Upload-Set($Types, $Folder, $Label) {
  $files = Get-ChildItem -Path (Join-Path $Here $Folder) -Filter '*.png' | Sort-Object Name
  if (-not $files) { Say "   No screenshots found in $Folder, skipping."; return }
  $sets = Call GET "/v1/appStoreVersionLocalizations/$LocId/appScreenshotSets"
  $set = $null
  foreach ($t in $Types) {
    $set = $sets.data | Where-Object { $_.attributes.screenshotDisplayType -eq $t } | Select-Object -First 1
    if ($set) { break }
  }
  if (-not $set) {
    foreach ($t in $Types) {
      try { $set = (Call POST '/v1/appScreenshotSets' @{ data = @{ type = 'appScreenshotSets'; attributes = @{ screenshotDisplayType = $t }; relationships = @{ appStoreVersionLocalization = @{ data = @{ type = 'appStoreVersionLocalizations'; id = $LocId } } } } }).data; break } catch { $set = $null }
    }
  }
  if (-not $set) { Say "   Could not create the $Label screenshot slot."; return }
  $old = Call GET "/v1/appScreenshotSets/$($set.id)/appScreenshots"
  foreach ($o in $old.data) { Call DELETE "/v1/appScreenshots/$($o.id)" | Out-Null }
  $n = 0
  foreach ($f in $files) {
    $n++
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $shot = (Call POST '/v1/appScreenshots' @{ data = @{ type = 'appScreenshots'; attributes = @{ fileName = $f.Name; fileSize = $bytes.Length }; relationships = @{ appScreenshotSet = @{ data = @{ type = 'appScreenshotSets'; id = $set.id } } } } }).data
    foreach ($op in $shot.attributes.uploadOperations) {
      $chunk = New-Object byte[] $op.length
      [Array]::Copy($bytes, $op.offset, $chunk, 0, $op.length)
      $h = @{}; $ct = 'image/png'
      foreach ($rh in $op.requestHeaders) { if ($rh.name -eq 'Content-Type') { $ct = $rh.value } else { $h[$rh.name] = $rh.value } }
      Invoke-WebRequest -Method $op.method -Uri $op.url -Headers $h -ContentType $ct -Body $chunk -UseBasicParsing | Out-Null
    }
    $md5 = -join ([Security.Cryptography.MD5]::Create().ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    Call PATCH "/v1/appScreenshots/$($shot.id)" @{ data = @{ type = 'appScreenshots'; id = $shot.id; attributes = @{ uploaded = $true; sourceFileChecksum = $md5 } } } | Out-Null
    Say "   $Label $n of $($files.Count) uploaded."
  }
}

Say ''
Say '5. Uploading screenshots. This takes a few minutes...'
Upload-Set @('APP_IPHONE_67', 'APP_IPHONE_69') 'screenshots\iphone' 'iPhone'
Upload-Set @('APP_IPAD_PRO_3GEN_129', 'APP_IPAD_PRO_129') 'screenshots\ipad' 'iPad'

Say ''
Say 'ALL DONE! Open App Store Connect and refresh the page.'
Say 'Still to do on the website: App Privacy, Age Rating, and Game Center on the version page.'
