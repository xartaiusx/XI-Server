param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$RuntimeRoot = "C:\Github Repo's\FFXI\Runtime",
    [string]$Player = 'Twills'
)

$ErrorActionPreference = 'Stop'

$trustDir = Join-Path $RepoRoot 'scripts\actions\spells\trust'
$modulePath = Join-Path $RepoRoot 'modules\custom\lua\trust_retail_parity.lua'
$baseSpellSqlPath = Join-Path $RepoRoot 'sql\mob_spell_lists.sql'
$baseSkillSqlPath = Join-Path $RepoRoot 'sql\mob_skill_lists.sql'
$customSqlPath = Join-Path $RepoRoot 'modules\custom\sql\trust_retail_parity.sql'
$logPath = Join-Path $RuntimeRoot "logs\trust_actions\live\$Player.log"
$reportDir = Join-Path $RuntimeRoot 'reports'
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path $reportDir "trust-parity-audit-$stamp.md"
$skillNameOverrides = @{
    '23'   = 'dancing_edge'
    '47'   = 'sanguine_blade'
    '61'   = 'dimidiation'
    '128'  = 'blade_rin'
    '129'  = 'blade_retsu'
    '133'  = 'blade_ei'
    '134'  = 'blade_jin'
    '2016' = 'dark_shot'
    '3741' = 'doctors_orders'
    '4253' = 'mix_panacea-1'
}
$messageNameOverrides = @{
    '231' = 'disappear_num'
    '668' = 'vallation_gain'
    '669' = 'valiance_gain_party_member'
}
$spellNameOverrides = @{
    '338' = 'utsusemi_ichi'
    '462' = 'magic_finale'
}

function Get-StringField {
    param(
        [hashtable]$Fields,
        [string]$Key,
        [string]$Default = ''
    )

    if ($Fields.ContainsKey($Key)) {
        return $Fields[$Key]
    }

    return $Default
}

function Get-IntOrNull {
    param(
        [hashtable]$Fields,
        [string]$Key
    )

    if (-not $Fields.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Fields[$Key])) {
        return $null
    }

    try {
        return [int]$Fields[$Key]
    } catch {
        return $null
    }
}

function Get-DoubleOrNull {
    param(
        [hashtable]$Fields,
        [string]$Key
    )

    if (-not $Fields.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Fields[$Key])) {
        return $null
    }

    try {
        return [double]::Parse($Fields[$Key], [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $null
    }
}

$trustScripts = Get-ChildItem -LiteralPath $trustDir -Filter '*.lua' | Sort-Object Name
$moduleText = Get-Content -LiteralPath $modulePath -Raw
$profileKeys = [regex]::Matches($moduleText, '^\s*([a-z0-9_]+)\s*=\s*\{\s*name\s*=', 'Multiline') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique
$generatedProfileCount = [Math]::Max(0, $trustScripts.Count - $profileKeys.Count)

$activeTrusts = @()
$parsedLogRows = @()
if (Test-Path -LiteralPath $logPath) {
    $activeTrusts = Select-String -LiteralPath $logPath -Pattern "`ttrust=([^\t]+)" |
        ForEach-Object {
            if ($_.Line -match "`ttrust=([^\t]+)") { $matches[1] }
        } |
        Sort-Object -Unique

    $parsedLogRows = Get-Content -LiteralPath $logPath | ForEach-Object {
        $fields = @{}
        foreach ($part in ($_ -split "`t")) {
            $idx = $part.IndexOf('=')
            if ($idx -gt 0) {
                $fields[$part.Substring(0, $idx)] = $part.Substring($idx + 1)
            }
        }

        if ($fields.ContainsKey('trust')) {
            $actionCategoryName = Get-StringField -Fields $fields -Key 'action_category_name'
            $skillId = if ($fields.ContainsKey('skill_id')) {
                $fields['skill_id']
            } elseif ($fields.ContainsKey('action_id') -and $actionCategoryName -match 'Skill') {
                $fields['action_id']
            } else {
                ''
            }
            $skillName = if ($fields.ContainsKey('skill_name')) { $fields['skill_name'] } else { '' }
            if (($skillName -match '^skill_\d+$' -or [string]::IsNullOrWhiteSpace($skillName)) -and $skillNameOverrides.ContainsKey($skillId)) {
                $skillName = $skillNameOverrides[$skillId]
            }

            $spellId = if ($fields.ContainsKey('spell_id')) {
                $fields['spell_id']
            } elseif ($fields.ContainsKey('action_id') -and $actionCategoryName -match 'Magic') {
                $fields['action_id']
            } else {
                ''
            }
            $spellName = if ($fields.ContainsKey('spell_name')) { $fields['spell_name'] } else { '' }
            if (($spellName -match '^spell_\d+$' -or [string]::IsNullOrWhiteSpace($spellName)) -and $spellNameOverrides.ContainsKey($spellId)) {
                $spellName = $spellNameOverrides[$spellId]
            }

            $messageId = if ($fields.ContainsKey('message_id')) { $fields['message_id'] } else { '' }
            $messageName = if ($fields.ContainsKey('message_name')) { $fields['message_name'] } else { '' }
            if (($messageName -eq 'msg_unknown' -or [string]::IsNullOrWhiteSpace($messageName)) -and $messageNameOverrides.ContainsKey($messageId)) {
                $messageName = $messageNameOverrides[$messageId]
            }

            $actionName = if (-not [string]::IsNullOrWhiteSpace($skillName)) {
                $skillName
            } elseif (-not [string]::IsNullOrWhiteSpace($spellName)) {
                $spellName
            } elseif (-not [string]::IsNullOrWhiteSpace($messageName)) {
                $messageName
            } elseif (-not [string]::IsNullOrWhiteSpace($actionCategoryName)) {
                $actionCategoryName
            } else {
                ''
            }

            [pscustomobject]@{
                Trust = $fields['trust']
                Event = Get-StringField -Fields $fields -Key 'event' -Default 'unknown'
                Time = Get-StringField -Fields $fields -Key 'time'
                Hpp = Get-StringField -Fields $fields -Key 'trust_hpp'
                Mpp = Get-StringField -Fields $fields -Key 'trust_mpp'
                Target = Get-StringField -Fields $fields -Key 'target_name'
                RestMode = Get-StringField -Fields $fields -Key 'trust_rest_mode_name'
                RestBlock = Get-StringField -Fields $fields -Key 'trust_rest_block'
                SpellName = $spellName
                SpellId = $spellId
                SkillId = $skillId
                SkillName = $skillName
                MessageId = $messageId
                MessageName = $messageName
                ActionName = $actionName
                Source = Get-StringField -Fields $fields -Key 'source'
                ActionCategory = Get-StringField -Fields $fields -Key 'action_category'
                ActionCategoryName = $actionCategoryName
                ActionId = Get-StringField -Fields $fields -Key 'action_id'
                FocusReason = Get-StringField -Fields $fields -Key 'focus_reason'
                FocusReasonName = Get-StringField -Fields $fields -Key 'focus_reason_name'
                GambitTarget = Get-StringField -Fields $fields -Key 'gambit_target'
                GambitReaction = Get-StringField -Fields $fields -Key 'gambit_reaction'
                GambitSelect = Get-StringField -Fields $fields -Key 'gambit_select'
                GambitSelectArg = Get-StringField -Fields $fields -Key 'gambit_select_arg'
                GambitResolvedId = Get-StringField -Fields $fields -Key 'gambit_resolved_id'
                GambitTargetTargId = Get-StringField -Fields $fields -Key 'gambit_target_targid'
                TpSkillSkipReason = Get-StringField -Fields $fields -Key 'tp_skill_skip_reason'
                TpSkillSkipReasonName = Get-StringField -Fields $fields -Key 'tp_skill_skip_reason_name'
                TpSkillSkipId = Get-StringField -Fields $fields -Key 'tp_skill_skip_id'
                TpSkillSkipTargetTargId = Get-StringField -Fields $fields -Key 'tp_skill_skip_target_targid'
                CurrentBattleTarget = Get-StringField -Fields $fields -Key 'current_battle_target_name'
                CurrentBattleTargetTargId = Get-StringField -Fields $fields -Key 'current_battle_target_targid'
                PacketTarget = Get-StringField -Fields $fields -Key 'packet_target_name'
                PacketTargetObjtype = Get-StringField -Fields $fields -Key 'packet_target_objtype'
                ResultResolutionName = Get-StringField -Fields $fields -Key 'result_resolution_name'
                TargetCount = Get-IntOrNull -Fields $fields -Key 'target_count'
                ResultCount = Get-IntOrNull -Fields $fields -Key 'result_count'
                DistanceToCurrentTarget = Get-DoubleOrNull -Fields $fields -Key 'distance_to_current_target'
                DistanceToPrimaryTarget = Get-DoubleOrNull -Fields $fields -Key 'distance_to_primary_target'
                DistanceToMaster = Get-DoubleOrNull -Fields $fields -Key 'distance_to_master'
                DistanceToPacketTarget = Get-DoubleOrNull -Fields $fields -Key 'distance_to_packet_target'
                RoleEnmityAction = Get-StringField -Fields $fields -Key 'role_enmity_action_name'
                TrustStatuses = Get-StringField -Fields $fields -Key 'trust_statuses'
                MasterStatuses = Get-StringField -Fields $fields -Key 'master_statuses'
                TargetStatuses = Get-StringField -Fields $fields -Key 'target_statuses'
            }
        }
    }
}

function Get-EffectNames {
    param([string]$StatusText)

    if ([string]::IsNullOrWhiteSpace($StatusText) -or $StatusText -eq 'none') {
        return @()
    }

    return @(
        $StatusText -split ';' |
            Where-Object { $_ -and $_ -ne 'none' } |
            ForEach-Object { ($_ -split ':', 2)[0] } |
            Where-Object { $_ }
    )
}

function Get-EffectRemaining {
    param(
        [string]$StatusText,
        [string]$EffectName
    )

    $entry = Get-EffectEntry -StatusText $StatusText -EffectName $EffectName
    if ($null -ne $entry) {
        return $entry.Remaining
    }

    return $null
}

function Get-EffectEntry {
    param(
        [string]$StatusText,
        [string]$EffectName
    )

    if ([string]::IsNullOrWhiteSpace($StatusText) -or $StatusText -eq 'none') {
        return $null
    }

    foreach ($entry in ($StatusText -split ';')) {
        $parts = $entry -split ':'
        if ($parts.Count -eq 0 -or $parts[0] -ne $EffectName) {
            continue
        }

        $remaining = 0
        $duration = 0
        foreach ($part in $parts) {
            if ($part -match '^rem=(-?\d+)$') {
                $remaining = [int]$matches[1]
            } elseif ($part -match '^dur=(-?\d+)$') {
                $duration = [int]$matches[1]
            }
        }

        return [pscustomobject]@{
            Effect = $EffectName
            Remaining = $remaining
            Duration = $duration
        }
    }

    return $null
}

function Format-IssueContext {
    param([object[]]$Rows)

    $contexts = @(
        $Rows |
            Select-Object -First 3 |
            ForEach-Object {
                $current = if ([string]::IsNullOrWhiteSpace($_.CurrentBattleTarget)) { 'none' } else { $_.CurrentBattleTarget }
                $currentTargId = if ([string]::IsNullOrWhiteSpace($_.CurrentBattleTargetTargId)) { '0' } else { $_.CurrentBattleTargetTargId }
                $gambitTarget = if ([string]::IsNullOrWhiteSpace($_.GambitTargetTargId)) { '0' } else { $_.GambitTargetTargId }
                $resolved = if ([string]::IsNullOrWhiteSpace($_.GambitResolvedId)) { '0' } else { $_.GambitResolvedId }
                $selectArg = if ([string]::IsNullOrWhiteSpace($_.GambitSelectArg)) { '0' } else { $_.GambitSelectArg }

                "current=$current#$currentTargId;gambitTarget#$gambitTarget;resolved=$resolved;selectArg=$selectArg"
            }
    )

    if ($contexts.Count -eq 0) {
        return ''
    }

    return ($contexts -join '<br>')
}

function Get-RefreshWindowSeconds {
    param([int]$Duration)

    if ($Duration -le 0) {
        return 0
    }

    if ($Duration -le 60) {
        return 5
    }

    if ($Duration -le 180) {
        return 15
    }

    if ($Duration -le 600) {
        return 30
    }

    return 60
}

function Get-DistanceBucket {
    param($Distance)

    if ($null -eq $Distance) {
        return 'unknown'
    }

    if ($Distance -lt 10) {
        return '<10'
    }

    if ($Distance -lt 20) {
        return '10-20'
    }

    if ($Distance -lt 30) {
        return '20-30'
    }

    if ($Distance -lt 50) {
        return '30-50'
    }

    return '50+'
}

function Get-MaxDistance {
    param([object[]]$Rows)

    $distances = @()
    foreach ($row in $Rows) {
        if ($null -ne $row.DistanceToCurrentTarget) {
            $distances += $row.DistanceToCurrentTarget
        }

        if ($null -ne $row.DistanceToPacketTarget) {
            $distances += $row.DistanceToPacketTarget
        }
    }

    if ($distances.Count -eq 0) {
        return ''
    }

    return [Math]::Round((($distances | Measure-Object -Maximum).Maximum), 2)
}

function Format-StatusText {
    param([string]$StatusText)

    if ([string]::IsNullOrWhiteSpace($StatusText) -or $StatusText -eq 'none') {
        return 'none'
    }

    $entries = @(
        $StatusText -split ';' |
            Where-Object { $_ -and $_ -ne 'none' } |
            Select-Object -First 18
    )

    if ($entries.Count -eq 0) {
        return 'none'
    }

    $summary = ($entries -join '<br>')
    if (($StatusText -split ';').Count -gt $entries.Count) {
        $summary += '<br>...'
    }

    return $summary
}

function Get-SpellEffectName {
    param([string]$SpellName)

    switch -Regex ($SpellName) {
        '^protect' { return 'protect' }
        '^shell' { return 'shell' }
        '^haste' { return 'haste' }
        '^refresh' { return 'refresh' }
        '^regen' { return 'regen' }
        '^phalanx' { return 'phalanx' }
        '^reprisal' { return 'reprisal' }
        '^enlight' { return 'enlight' }
        '^aquaveil' { return 'aquaveil' }
        '^stoneskin' { return 'stoneskin' }
        '^blink' { return 'blink' }
        '^reraise' { return 'reraise' }
        '^auspice' { return 'auspice' }
        '^boost-mnd' { return 'mnd_boost' }
        '^dia' { return 'dia' }
        '^slow' { return 'slow' }
        '^paralyze' { return 'paralysis' }
        '^addle' { return 'addle' }
        '^distract' { return 'evasion_down' }
        '^frazzle' { return 'magic_evasion_down' }
        '^gravity' { return 'weight' }
        '^bind' { return 'bind' }
        '^flash' { return 'flash' }
        '^carnage_elegy|elegy' { return 'elegy' }
        '^sleep|^repose' { return 'sleep_i' }
        default { return $null }
    }
}

function Normalize-TrustName {
    param([string]$Name)
    return ($Name -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
}

$rows = foreach ($script in $trustScripts) {
    $base = [IO.Path]::GetFileNameWithoutExtension($script.Name)
    $normalized = Normalize-TrustName $base
    [pscustomobject]@{
        Script = $script.Name
        Profile = if ($profileKeys -contains $normalized) { 'explicit' } else { 'generated-audit' }
        ActiveInLatestLog = if ($activeTrusts | Where-Object { (Normalize-TrustName $_) -eq $normalized }) { 'yes' } else { 'no' }
    }
}

$spellSqlText = @(
    if (Test-Path -LiteralPath $baseSpellSqlPath) { Get-Content -LiteralPath $baseSpellSqlPath -Raw }
    if (Test-Path -LiteralPath $customSqlPath) { Get-Content -LiteralPath $customSqlPath -Raw }
) -join "`n"

$skillSqlText = @(
    if (Test-Path -LiteralPath $baseSkillSqlPath) { Get-Content -LiteralPath $baseSkillSqlPath -Raw }
    if (Test-Path -LiteralPath $customSqlPath) { Get-Content -LiteralPath $customSqlPath -Raw }
) -join "`n"

$spellPairs = [System.Collections.Generic.HashSet[string]]::new()
[regex]::Matches($spellSqlText, "\(\s*'[^']*'\s*,\s*(\d+)\s*,\s*(\d+)\s*,") | ForEach-Object {
    [void]$spellPairs.Add("$($_.Groups[1].Value):$($_.Groups[2].Value)")
}

$skillPairs = [System.Collections.Generic.HashSet[string]]::new()
[regex]::Matches($skillSqlText, "\(\s*'[^']*'\s*,\s*(\d+)\s*,\s*(\d+)\s*\)") | ForEach-Object {
    [void]$skillPairs.Add("$($_.Groups[1].Value):$($_.Groups[2].Value)")
}

$requiredSpellRows = @(
    @{ Trust = 'Yoran-Oran UC'; List = 393; Id = 54; Name = 'Stoneskin' },
    @{ Trust = 'Sylvie UC'; List = 394; Id = 143; Name = 'Erase' },
    @{ Trust = 'Koru-Moru'; List = 364; Id = 58; Name = 'Paralyze' },
    @{ Trust = 'Koru-Moru'; List = 364; Id = 80; Name = 'Paralyze II' },
    @{ Trust = 'Koru-Moru'; List = 364; Id = 216; Name = 'Gravity' },
    @{ Trust = 'Koru-Moru'; List = 364; Id = 217; Name = 'Gravity II' },
    @{ Trust = 'Koru-Moru'; List = 364; Id = 253; Name = 'Sleep' },
    @{ Trust = 'Koru-Moru'; List = 364; Id = 258; Name = 'Bind' },
    @{ Trust = 'Koru-Moru'; List = 364; Id = 259; Name = 'Sleep II' },
    @{ Trust = 'Koru-Moru'; List = 364; Id = 286; Name = 'Addle' },
    @{ Trust = 'Koru-Moru'; List = 364; Id = 843; Name = 'Frazzle' },
    @{ Trust = 'Koru-Moru'; List = 364; Id = 844; Name = 'Frazzle II' },
    @{ Trust = 'Joachim'; List = 323; Id = 462; Name = 'Magic Finale' },
    @{ Trust = 'Matsui-P'; List = 435; Id = 338; Name = 'Utsusemi: Ichi' },
    @{ Trust = 'Matsui-P'; List = 435; Id = 339; Name = 'Utsusemi: Ni' },
    @{ Trust = 'Matsui-P'; List = 435; Id = 341; Name = 'Jubaku: Ichi' },
    @{ Trust = 'Matsui-P'; List = 435; Id = 342; Name = 'Jubaku: Ni' },
    @{ Trust = 'Matsui-P'; List = 435; Id = 344; Name = 'Hojo: Ichi' },
    @{ Trust = 'Matsui-P'; List = 435; Id = 345; Name = 'Hojo: Ni' },
    @{ Trust = 'Matsui-P'; List = 435; Id = 347; Name = 'Kurayami: Ichi' },
    @{ Trust = 'Matsui-P'; List = 435; Id = 348; Name = 'Kurayami: Ni' },
    @{ Trust = 'Matsui-P'; List = 435; Id = 350; Name = 'Dokumori: Ichi' },
    @{ Trust = 'Matsui-P'; List = 435; Id = 351; Name = 'Dokumori: Ni' }
)

$requiredSkillRows = @(
    @{ Trust = 'Matsui-P'; List = 1148; Id = 128; Name = 'Blade: Rin' },
    @{ Trust = 'Matsui-P'; List = 1148; Id = 129; Name = 'Blade: Retsu' },
    @{ Trust = 'Matsui-P'; List = 1148; Id = 133; Name = 'Blade: Ei' },
    @{ Trust = 'Matsui-P'; List = 1148; Id = 134; Name = 'Blade: Jin' },
    @{ Trust = 'Matsui-P'; List = 1148; Id = 136; Name = 'Blade: Ku' },
    @{ Trust = 'Matsui-P'; List = 1148; Id = 138; Name = 'Blade: Kamu' },
    @{ Trust = 'Matsui-P'; List = 1148; Id = 141; Name = 'Blade: Shun' },
    @{ Trust = 'Lilisette II'; List = 1128; Id = 23; Name = 'Dancing Edge' },
    @{ Trust = 'Lilisette II'; List = 1128; Id = 25; Name = 'Evisceration' },
    @{ Trust = 'Lilisette II'; List = 1128; Id = 29; Name = 'Pyrrhic Kleos' },
    @{ Trust = 'Lilisette II'; List = 1128; Id = 30; Name = 'Aeolian Edge' },
    @{ Trust = 'Lilisette II'; List = 1128; Id = 31; Name = "Rudra's Storm" },
    @{ Trust = 'Lilisette II'; List = 1128; Id = 224; Name = 'Exenterator' },
    @{ Trust = "Selh'teus"; List = 1094; Id = 1508; Name = 'Luminous Lance' },
    @{ Trust = "Selh'teus"; List = 1094; Id = 1509; Name = 'Rejuvenation' },
    @{ Trust = "Selh'teus"; List = 1094; Id = 1510; Name = 'Revelation' }
)

function Get-RowStatus {
    param(
        [System.Collections.Generic.HashSet[string]]$Set,
        [int]$ListId,
        [int]$ValueId
    )

    if ($Set.Contains("${ListId}:${ValueId}")) {
        return 'ok'
    }

    return 'missing'
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Mochirii Trust Parity Audit')
$lines.Add('')
$lines.Add("- Generated: $(Get-Date -Format s)")
$lines.Add("- Trust scripts: $($trustScripts.Count)")
$lines.Add("- Explicit profile keys: $($profileKeys.Count)")
$lines.Add("- Generated audit profile keys: $generatedProfileCount")
$lines.Add("- Latest log: $logPath")
$lines.Add("- Active Trusts in latest log: $($activeTrusts.Count)")
$lines.Add('')
$lines.Add('## Active Trusts')
if ($activeTrusts.Count -eq 0) {
    $lines.Add('- None found in latest live log.')
} else {
    foreach ($trust in $activeTrusts) {
        $lines.Add("- $trust")
    }
}
$lines.Add('')
$lines.Add('## Roster Coverage')
$lines.Add('| Trust Script | Profile | Active In Latest Log |')
$lines.Add('| --- | --- | --- |')
foreach ($row in $rows) {
    $lines.Add("| $($row.Script) | $($row.Profile) | $($row.ActiveInLatestLog) |")
}
$lines.Add('')
$lines.Add('## Current Alliance Static Preconditions')
$lines.Add('| Type | Trust | List | ID | Name | Status |')
$lines.Add('| --- | --- | ---: | ---: | --- | --- |')
foreach ($row in $requiredSpellRows) {
    $lines.Add("| spell | $($row.Trust) | $($row.List) | $($row.Id) | $($row.Name) | $(Get-RowStatus -Set $spellPairs -ListId $row.List -ValueId $row.Id) |")
}

foreach ($row in $requiredSkillRows) {
    $lines.Add("| skill | $($row.Trust) | $($row.List) | $($row.Id) | $($row.Name) | $(Get-RowStatus -Set $skillPairs -ListId $row.List -ValueId $row.Id) |")
}
$lines.Add('')
$lines.Add('## Latest Log Summary')
if ($parsedLogRows.Count -eq 0) {
    $lines.Add('- No Trust action rows found in the latest live log.')
} else {
    $lines.Add('| Trust | Rows | Top Events | Last HP% | Last MP% | Last Target | Last Rest | Last Rest Block |')
    $lines.Add('| --- | ---: | --- | ---: | ---: | --- | --- | --- |')
    foreach ($group in ($parsedLogRows | Group-Object Trust | Sort-Object Name)) {
        $last = $group.Group | Select-Object -Last 1
        $topEvents = ($group.Group |
            Group-Object Event |
            Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false } |
            Select-Object -First 4 |
            ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '

        $lines.Add("| $($group.Name) | $($group.Count) | $topEvents | $($last.Hpp) | $($last.Mpp) | $($last.Target) | $($last.RestMode) | $($last.RestBlock) |")
    }

    $unresolvedRows = $parsedLogRows | Where-Object {
        $_.SpellName -match '^spell_\d+$' -or
        $_.SkillName -match '^skill_\d+$' -or
        $_.MessageName -eq 'msg_unknown'
    }

    $lines.Add('')
    $lines.Add('## Unresolved Log Names')
    if ($unresolvedRows.Count -eq 0) {
        $lines.Add('- None found.')
    } else {
        $lines.Add("| Field | Value | Count | Trusts |")
        $lines.Add("| --- | --- | ---: | --- |")

        $unresolvedItems = @()
        $unresolvedItems += $parsedLogRows |
            Where-Object { $_.SpellName -match '^spell_\d+$' } |
            ForEach-Object { [pscustomobject]@{ Field = 'spell_name'; Value = $_.SpellName; Trust = $_.Trust } }
        $unresolvedItems += $parsedLogRows |
            Where-Object { $_.SkillName -match '^skill_\d+$' } |
            ForEach-Object { [pscustomobject]@{ Field = 'skill_name'; Value = $_.SkillName; Trust = $_.Trust } }
        $unresolvedItems += $parsedLogRows |
            Where-Object { $_.MessageName -eq 'msg_unknown' } |
            ForEach-Object { [pscustomobject]@{ Field = 'message_name'; Value = $_.MessageName; Trust = $_.Trust } }

        foreach ($group in ($unresolvedItems | Group-Object Field, Value | Sort-Object Name)) {
            $parts = $group.Name -split ', ', 2
            $trusts = ($group.Group | Select-Object -ExpandProperty Trust -Unique | Sort-Object) -join ', '
            $lines.Add("| $($parts[0]) | $($parts[1]) | $($group.Count) | $trusts |")
        }
    }

    $lines.Add('')
    $lines.Add('## Runtime Action Issues')
    $issueRows = $parsedLogRows | Where-Object {
        $_.Event -match 'invalid|interrupt|out_of_range|too_far|cannot' -or
        $_.Source -match 'invalid|interrupt|out_of_range|too_far|cannot' -or
        $_.MessageName -match 'invalid|interrupt|out_of_range|too_far|cannot'
    }

    if ($issueRows.Count -eq 0) {
        $lines.Add('- None found in latest log rows.')
    } else {
        $lines.Add('| Trust | Event | Source | Action | Target | Context | Max Distance | Count |')
        $lines.Add('| --- | --- | --- | --- | --- | --- | ---: | ---: |')
        foreach ($group in ($issueRows | Group-Object Trust, Event, Source, ActionName, Target | Sort-Object Count -Descending | Select-Object -First 60)) {
            $parts = $group.Name -split ', ', 5
            $lines.Add("| $($parts[0]) | $($parts[1]) | $($parts[2]) | $($parts[3]) | $($parts[4]) | $(Format-IssueContext -Rows $group.Group) | $(Get-MaxDistance -Rows $group.Group) | $($group.Count) |")
        }
    }

    $lines.Add('')
    $lines.Add('## TP Skill Guard Skips')
    $tpSkipRows = $parsedLogRows | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.TpSkillSkipReasonName) -and
        $_.TpSkillSkipReasonName -ne 'none'
    }

    if ($tpSkipRows.Count -eq 0) {
        $lines.Add('- None found in latest log rows.')
    } else {
        $lines.Add('| Trust | Reason | Skill ID | Target TargID | Current Target | Count |')
        $lines.Add('| --- | --- | ---: | ---: | --- | ---: |')
        foreach ($group in ($tpSkipRows | Group-Object Trust, TpSkillSkipReasonName, TpSkillSkipId, TpSkillSkipTargetTargId, CurrentBattleTarget | Sort-Object Count -Descending | Select-Object -First 60)) {
            $parts = $group.Name -split ', ', 5
            $lines.Add("| $($parts[0]) | $($parts[1]) | $($parts[2]) | $($parts[3]) | $($parts[4]) | $($group.Count) |")
        }
    }

    $lines.Add('')
    $lines.Add('## Distance Diagnostics')
    $distanceItems = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $parsedLogRows) {
        if ($null -ne $row.DistanceToCurrentTarget -and $row.DistanceToCurrentTarget -ge 20) {
            $distanceItems.Add([pscustomobject]@{
                Trust = $row.Trust
                Event = $row.Event
                Target = $row.CurrentBattleTarget
                DistanceField = 'current'
                Bucket = Get-DistanceBucket $row.DistanceToCurrentTarget
                Action = $row.ActionName
            })
        }

        if ($null -ne $row.DistanceToPacketTarget -and $row.DistanceToPacketTarget -ge 20) {
            $distanceItems.Add([pscustomobject]@{
                Trust = $row.Trust
                Event = $row.Event
                Target = $row.PacketTarget
                DistanceField = 'packet'
                Bucket = Get-DistanceBucket $row.DistanceToPacketTarget
                Action = $row.ActionName
            })
        }
    }

    if ($distanceItems.Count -eq 0) {
        $lines.Add('- No action rows at 20+ yalms from current or packet target.')
    } else {
        $lines.Add('| Trust | Event | Action | Target | Distance Field | Bucket | Count |')
        $lines.Add('| --- | --- | --- | --- | --- | --- | ---: |')
        foreach ($group in ($distanceItems | Group-Object Trust, Event, Action, Target, DistanceField, Bucket | Sort-Object Count -Descending | Select-Object -First 60)) {
            $parts = $group.Name -split ', ', 6
            $lines.Add("| $($parts[0]) | $($parts[1]) | $($parts[2]) | $($parts[3]) | $($parts[4]) | $($parts[5]) | $($group.Count) |")
        }
    }

    $lines.Add('')
    $lines.Add('## Role Enmity Decisions')
    $roleRows = $parsedLogRows | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.RoleEnmityAction) -and
        $_.RoleEnmityAction -ne 'none'
    }

    if ($roleRows.Count -eq 0) {
        $lines.Add('- No role-enmity decisions found in latest log rows.')
    } else {
        $lines.Add('| Action | Trusts | Rows |')
        $lines.Add('| --- | --- | ---: |')
        foreach ($group in ($roleRows | Group-Object RoleEnmityAction | Sort-Object Count -Descending)) {
            $trusts = ($group.Group | Select-Object -ExpandProperty Trust -Unique | Sort-Object) -join ', '
            $lines.Add("| $($group.Name) | $trusts | $($group.Count) |")
        }
    }

    $lines.Add('')
    $lines.Add('## Alliance Support Scope')
    $supportRows = $parsedLogRows | Where-Object {
        ($null -ne $_.TargetCount -and $_.TargetCount -gt 1) -or
        ($null -ne $_.ResultCount -and $_.ResultCount -gt 1)
    }

    if ($supportRows.Count -eq 0) {
        $lines.Add('- No multi-target action packets/results found.')
    } else {
        $lines.Add('| Trust | Source | Category | Action | Max Targets | Max Results | Rows With Fewer Results Than Targets | Count |')
        $lines.Add('| --- | --- | --- | --- | ---: | ---: | ---: | ---: |')
        foreach ($group in ($supportRows | Group-Object Trust, Source, ActionCategoryName, ActionName | Sort-Object Count -Descending | Select-Object -First 60)) {
            $parts = $group.Name -split ', ', 4
            $targetCounts = @($group.Group | Where-Object { $null -ne $_.TargetCount } | Select-Object -ExpandProperty TargetCount)
            $resultCounts = @($group.Group | Where-Object { $null -ne $_.ResultCount } | Select-Object -ExpandProperty ResultCount)
            $maxTargets = if ($targetCounts.Count -gt 0) { ($targetCounts | Measure-Object -Maximum).Maximum } else { '' }
            $maxResults = if ($resultCounts.Count -gt 0) { ($resultCounts | Measure-Object -Maximum).Maximum } else { '' }
            $missed = @($group.Group | Where-Object {
                $null -ne $_.TargetCount -and
                $null -ne $_.ResultCount -and
                $_.ResultCount -lt $_.TargetCount
            }).Count
            $lines.Add("| $($parts[0]) | $($parts[1]) | $($parts[2]) | $($parts[3]) | $maxTargets | $maxResults | $missed | $($group.Count) |")
        }
    }

    $lines.Add('')
    $lines.Add('## Active Effect Coverage')
    $effectItems = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $parsedLogRows) {
        foreach ($effectName in (Get-EffectNames $row.TrustStatuses)) {
            $effectItems.Add([pscustomobject]@{ Scope = 'trust'; Effect = $effectName; Trust = $row.Trust })
        }

        foreach ($effectName in (Get-EffectNames $row.MasterStatuses)) {
            $effectItems.Add([pscustomobject]@{ Scope = 'master'; Effect = $effectName; Trust = $row.Trust })
        }

        foreach ($effectName in (Get-EffectNames $row.TargetStatuses)) {
            $effectItems.Add([pscustomobject]@{ Scope = 'target'; Effect = $effectName; Trust = $row.Trust })
        }
    }

    if ($effectItems.Count -eq 0) {
        $lines.Add('- No tracked active effects found in latest log rows.')
    } else {
        $lines.Add('| Scope | Effect | Rows | Trusts Reporting |')
        $lines.Add('| --- | --- | ---: | --- |')
        foreach ($group in ($effectItems | Group-Object Scope, Effect | Sort-Object Count -Descending | Select-Object -First 40)) {
            $parts = $group.Name -split ', ', 2
            $trusts = ($group.Group | Select-Object -ExpandProperty Trust -Unique | Sort-Object) -join ', '
            $lines.Add("| $($parts[0]) | $($parts[1]) | $($group.Count) | $trusts |")
        }
    }

    $lines.Add('')
    $lines.Add('## Latest Active Effects By Entity')
    $lines.Add('| Scope | Entity | Latest Effects |')
    $lines.Add('| --- | --- | --- |')

    $latestMasterRow = $parsedLogRows |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.MasterStatuses) -and $_.MasterStatuses -ne 'none' } |
        Select-Object -Last 1
    if ($null -ne $latestMasterRow) {
        $lines.Add("| master | $Player | $(Format-StatusText $latestMasterRow.MasterStatuses) |")
    } else {
        $lines.Add("| master | $Player | none |")
    }

    foreach ($group in ($parsedLogRows | Group-Object Trust | Sort-Object Name)) {
        $latestTrustRow = $group.Group |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.TrustStatuses) } |
            Select-Object -Last 1
        if ($null -ne $latestTrustRow) {
            $lines.Add("| trust | $($group.Name) | $(Format-StatusText $latestTrustRow.TrustStatuses) |")
        }
    }

    $targetStatusRows = $parsedLogRows |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.Target) -and
            $_.Target -ne 'none' -and
            -not [string]::IsNullOrWhiteSpace($_.TargetStatuses)
        } |
        Group-Object Target |
        Sort-Object Name

    foreach ($group in $targetStatusRows) {
        $latestTargetRow = $group.Group | Select-Object -Last 1
        $lines.Add("| target | $($group.Name) | $(Format-StatusText $latestTargetRow.TargetStatuses) |")
    }

    $lines.Add('')
    $lines.Add('## Potential Early Buff/Debuff Refreshes')
    $earlyRefreshRows = [System.Collections.Generic.List[object]]::new()
    foreach ($row in ($parsedLogRows | Where-Object { $_.Event -eq 'magic_start' -and $_.SpellName })) {
        $effectName = Get-SpellEffectName $row.SpellName
        if ($null -eq $effectName) {
            continue
        }

        $effectEntry = Get-EffectEntry -StatusText $row.TargetStatuses -EffectName $effectName
        if ($null -eq $effectEntry) {
            continue
        }

        $refreshWindow = Get-RefreshWindowSeconds -Duration $effectEntry.Duration
        if ($effectEntry.Remaining -gt $refreshWindow) {
            $earlyRefreshRows.Add([pscustomobject]@{
                Trust = $row.Trust
                Spell = $row.SpellName
                Target = $row.Target
                Effect = $effectName
                Remaining = $effectEntry.Remaining
                Duration = $effectEntry.Duration
                RefreshWindow = $refreshWindow
            })
        }
    }

    if ($earlyRefreshRows.Count -eq 0) {
        $lines.Add('- None found above the duration-based refresh windows.')
    } else {
        $lines.Add('| Trust | Spell | Target | Effect | Remaining Seconds | Duration Seconds | Refresh Window Seconds | Count |')
        $lines.Add('| --- | --- | --- | --- | ---: | ---: | ---: | ---: |')
        foreach ($group in ($earlyRefreshRows | Group-Object Trust, Spell, Target, Effect, Remaining, Duration, RefreshWindow | Sort-Object Count -Descending | Select-Object -First 40)) {
            $parts = $group.Name -split ', ', 7
            $lines.Add("| $($parts[0]) | $($parts[1]) | $($parts[2]) | $($parts[3]) | $($parts[4]) | $($parts[5]) | $($parts[6]) | $($group.Count) |")
        }
    }
}
$lines.Add('')
$lines.Add('## Interpretation')
$lines.Add('- explicit: the Trust has a Mochirii role/profile row for audit or behavior work.')
$lines.Add('- generated-audit: the Trust script has a generated placeholder profile so roster-wide audits include it while detailed source-backed parity is still pending.')
$lines.Add('- Active Trusts should be upgraded before inactive roster entries because their logs provide evidence.')

Set-Content -LiteralPath $reportPath -Value $lines -Encoding UTF8
Write-Output $reportPath
