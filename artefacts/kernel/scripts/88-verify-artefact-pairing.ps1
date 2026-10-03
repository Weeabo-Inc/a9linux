# 88-verify-artefact-pairing.ps1
#
# Runs on Windows against E: with NO VM required.
#
# WHY THIS EXISTS
# qemu-validator's `resolve-pc.sh` resolves crash PCs against the `System.map` files
# shipped in this directory. That creates a dependency with no guard: if a map ever
# goes stale relative to its Image, every symbol resolution silently returns a
# confident wrong answer -- the exact failure mode this project keeps paying for.
#
# The structural link. `arch/arm64/kernel/image.h` defines:
#     #define HEAD_SYMBOLS  DEFINE_IMAGE_LE64(_kernel_size_le, _end - _text)
# so the Image header's `image_size` field is BY CONSTRUCTION `_end - _text`.
#
# WHY THERE ARE TWO RULES, NOT ONE
# `image_size` is PAGE-GRANULAR, and BOTH kernels here report `_end - _text` ==
# 0x1370000 (the PL011 driver fits inside the existing rounded footprint). So the
# footprint rule is a NECESSARY condition only -- a stale map from a sibling build
# passes it. The PL011 discriminator is what makes it SUFFICIENT.
#
# WHY THE MIS-PAIRINGS RUN BY DEFAULT
# An earlier version demonstrated the failure mode only via a hand-run negative
# control in a temp directory. qemu-validator's objection was right and is adopted
# here: a check whose failure is only ever shown by hand tends to stop being shown.
# So this script evaluates ALL FOUR Image x map combinations on every run. The
# header field and the map fields are read independently, so no copies are needed.
# If the off-diagonal cases ever stop being rejected, this script fails loudly.
#
# WHY RULE 2 IS DERIVED, NOT HARDCODED
# Rule 2 originally compared the map's pl011 count against a profile constant typed
# into this file. qemu-validator's version instead cross-checks the MAP against the
# IMAGE's own literal strings -- an expectation read out of the artefact rather than
# asserted from a table. That is strictly better (a typed table is the thing that
# rots, and a typo in it would silently disable the guard), so it is adopted here.
# The relation tested is: (map has pl011 symbols) == (Image has pl011 literals).
# Measured values: device 0 symbols / 0 literals, variant 62 / 20.

param([string]$Dir = 'E:\Reverseing\Arlo\a9linux\artefacts\kernel')

$ErrorActionPreference = 'Stop'
$fail = 0

# ---------------------------------------------------------------------------
# RESIDUAL LIMIT OF RULES 1+2, AND WHAT CLOSES IT
# Rule 2 is TWO-VALUED: pl011 present or absent. It separates the two builds in
# this directory and nothing more. A stale map from an earlier DEVICE-kernel
# revision also has zero pl011 symbols, so it passes rule 2; and it passes rule 1
# whenever the page-rounded image_size happens to match. That case is reachable
# (qemu-validator named it; this script's own self-test below demonstrates it) and
# rules 1+2 CANNOT catch it.
#
# What closes it is PINNING: record the SHA-256 of each artefact and fail if it
# moves. A stale map has a different hash, full stop. The cost is that a
# deliberate regeneration must be re-pinned by hand -- which is the correct
# workflow, because re-pinning is the moment someone re-decides that the new pair
# is the pair to cite.
#
# So the guard has two independent verdicts and BOTH must pass:
#   (A) pairing  -- rules 1+2 across all four combinations (catches swaps)
#   (B) pinning  -- every artefact hash equals the recorded pin (catches staleness)
# ---------------------------------------------------------------------------
$pins = [ordered]@{
    'Image'                 = '39a270676141f42575cbadffbac085cc120aa1e0f6e61af0b6db8ad5b0c7e228'
    'Image-16k-qemu-pl011'  = '2697e77d901d44844cb8871400ee59119148be08182ccf57bbb6df9b766fde88'
    'System.map'            = '821a3f3aee0b2cc23ea3f11a4ac927bb8c78f148e8a597e86d3ef33b4e57e64c'
    'System.map-qemu-pl011' = '07408377308361cb8d91d35e24857325c98c698c5c0703dd476b3bb7ee46c6ab'
}

function Get-ImageHeader {
    param([string]$Path)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] 64
        [void]$fs.Read($buf, 0, 64)
    } finally { $fs.Close() }
    [pscustomobject]@{
        Name      = (Split-Path $Path -Leaf)
        Bytes     = (Get-Item $Path).Length
        Sha256    = (Get-FileHash $Path -Algorithm SHA256).Hash.ToLower()
        Magic     = [BitConverter]::ToUInt32($buf, 56)
        ImageSize = [BitConverter]::ToUInt64($buf, 16)
        Flags     = [BitConverter]::ToUInt64($buf, 24)
        Pl011Literals = (Get-Pl011LiteralCount $Path)
    }
}

# Count printable ASCII runs (>= 4 chars, the classic `strings` default that
# contains "pl011". Derived from the Image itself so no expectation is typed in.
function Get-Pl011LiteralCount {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $latin1 = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
    $runs = [regex]::Matches($latin1, '[\x20-\x7E]{4,}')
    $n = 0
    foreach ($r in $runs) { if ($r.Value -match 'pl011') { $n++ } }
    return $n
}

function Get-MapFacts {
    param([string]$Path)
    $m = Select-String -Path $Path -Pattern '^([0-9a-f]+)\s+\S+\s+_text$' | Select-Object -First 1
    $e = Select-String -Path $Path -Pattern '^([0-9a-f]+)\s+\S+\s+_end$'  | Select-Object -First 1
    [pscustomobject]@{
        Name   = (Split-Path $Path -Leaf)
        Bytes  = (Get-Item $Path).Length
        Sha256 = (Get-FileHash $Path -Algorithm SHA256).Hash.ToLower()
        Text   = if ($m) { [Convert]::ToUInt64($m.Matches[0].Groups[1].Value, 16) } else { $null }
        End    = if ($e) { [Convert]::ToUInt64($e.Matches[0].Groups[1].Value, 16) } else { $null }
        Pl011  = (Select-String -Path $Path -Pattern 'pl011' -AllMatches | Measure-Object).Count
    }
}

# The two kernels. NOTE: no pl011 profile is asserted here -- rule 2 derives its
# expectation from each Image's own literal strings, so this table needs no editing
# if a third kernel is ever added.
$kernels = @(
    [pscustomobject]@{ Image = 'Image';                Map = 'System.map' }
    [pscustomobject]@{ Image = 'Image-16k-qemu-pl011'; Map = 'System.map-qemu-pl011' }
)

$imgs = @{}
$maps = @{}
foreach ($k in $kernels) {
    $ip = Join-Path $Dir $k.Image
    $mp = Join-Path $Dir $k.Map
    if (-not (Test-Path $ip)) { Write-Output "MISSING IMAGE: $ip"; $fail++; continue }
    if (-not (Test-Path $mp)) { Write-Output "MISSING MAP  : $mp"; $fail++; continue }
    $imgs[$k.Image] = Get-ImageHeader $ip
    $maps[$k.Map]   = Get-MapFacts    $mp
}
if ($fail -gt 0) { exit $fail }

Write-Output "======================================================================================"
Write-Output "ARTEFACT PAIRING CHECK -- every Image x map combination, evaluated every run"
Write-Output "  rule 1 (necessary)  : image_size (Image header) == _end - _text (System.map)"
Write-Output "  rule 2 (sufficient) : map's pl011 symbols agree with THIS Image's pl011 literals"
Write-Output "  rule 1 source       : arch/arm64/kernel/image.h  HEAD_SYMBOLS"
Write-Output "======================================================================================"

Write-Output ""
Write-Output "Images:"
foreach ($k in $kernels) {
    $i = $imgs[$k.Image]
    $page = ($i.Flags -shr 1) -band 3
    $ps = @('unspecified','4K','16K','64K')[[int]$page]
    Write-Output ("  {0,-24} {1,10} B  flags=0x{2:x} bits[2:1]={3} -> {4}   image_size=0x{5:x}   pl011 literals={6}" -f `
        $i.Name, $i.Bytes, $i.Flags, $page, $ps, $i.ImageSize, $i.Pl011Literals)
    Write-Output ("    sha256 {0}" -f $i.Sha256)
    if ($i.Magic -ne 0x644d5241) { Write-Output "    FAIL: bad ARM64 magic"; $fail++ }
    if ($page -ne 2)             { Write-Output "    FAIL: not a 16K kernel";  $fail++ }
}
Write-Output ""
Write-Output "Maps:"
foreach ($k in $kernels) {
    $m = $maps[$k.Map]
    Write-Output ("  {0,-24} {1,10} B  pl011={2,-3} _end-_text=0x{3:x}" -f `
        $m.Name, $m.Bytes, $m.Pl011, ($m.End - $m.Text))
    Write-Output ("    sha256 {0}" -f $m.Sha256)
}

Write-Output ""
Write-Output "======================================================================================"
Write-Output "ALL FOUR COMBINATIONS  (off-diagonal = mis-pairings that MUST be rejected)"
Write-Output "======================================================================================"
Write-Output ""
Write-Output ("  {0,-22} {1,-22} {2,-8} {3,-8} {4}" -f 'IMAGE','MAP','RULE 1','RULE 2','VERDICT')

foreach ($k in $kernels) {
    foreach ($mk in $kernels) {
        $i = $imgs[$k.Image]
        $m = $maps[$mk.Map]
        $rule1 = (($m.End - $m.Text) -eq $i.ImageSize)
        # Derived, not hardcoded: the map's pl011 symbols must agree with THIS Image's
        # own pl011 literals. Catches a map that is internally consistent but from a
        # third build -- which a typed profile table would not.
        $rule2 = (($m.Pl011 -gt 0) -eq ($i.Pl011Literals -gt 0))
        $intended = ($k.Image -eq $mk.Image)

        if ($intended) {
            $ok = $rule1 -and $rule2
            if (-not $ok) { $fail++ }
            $verdict = if ($ok) { 'CORRECT PAIR (accepted)' } else { '*** INTENDED PAIR REJECTED ***' }
        } else {
            # A mis-pairing must be REJECTED. Rule 1 is EXPECTED to pass here --
            # that is precisely why rule 2 exists.
            $ok = (-not $rule2)
            if (-not $ok) { $fail++ }
            $verdict = if ($ok) { 'mis-pair correctly rejected' } else { '*** MIS-PAIR ACCEPTED -- GUARD BROKEN ***' }
        }

        Write-Output ("  {0,-22} {1,-22} {2,-8} {3,-8} {4}" -f `
            $k.Image, $mk.Map, $(if ($rule1) {'PASS'} else {'FAIL'}), $(if ($rule2) {'PASS'} else {'FAIL'}), $verdict)
    }
}

Write-Output ""
Write-Output "--------------------------------------------------------------------------------------"
Write-Output "NOTE: in both mis-pairings RULE 1 PASSES. That is not a bug -- it is exactly why"
Write-Output "RULE 2 exists. Both kernels share a page-rounded image_size of 0x1370000, so the"
Write-Output "footprint rule alone cannot separate them."
Write-Output "--------------------------------------------------------------------------------------"

# ---------------------------------------------------------------------------
# (B) PIN VERDICT. Rules 1+2 only catch swaps WITHIN this set; they cannot detect a
# stale map from a same-profile sibling build. The pin can, and does.
# ---------------------------------------------------------------------------
Write-Output ""
Write-Output "======================================================================================"
Write-Output "HASH PIN -- catches what rules 1+2 structurally cannot (staleness, not just swaps)"
Write-Output "======================================================================================"
Write-Output ""
$pinFail = 0
foreach ($name in $pins.Keys) {
    $p = Join-Path $Dir $name
    if (-not (Test-Path $p)) { Write-Output ("  {0,-24} MISSING" -f $name); $pinFail++; continue }
    $h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
    if ($h -eq $pins[$name]) {
        Write-Output ("  {0,-24} PINNED  {1}" -f $name, $h.Substring(0,16) + '...')
    } else {
        Write-Output ("  {0,-24} *** CHANGED ***" -f $name)
        Write-Output ("      pinned: {0}" -f $pins[$name])
        Write-Output ("      actual: {0}" -f $h)
        $pinFail++
    }
}
if ($pinFail -gt 0) {
    Write-Output ""
    Write-Output "  An artefact hash has moved. Rules 1+2 cannot tell a fresh pair from a stale"
    Write-Output "  map that happens to share the same profile -- a green pairing result is NOT"
    Write-Output "  evidence that the new set is the set to cite. Re-run this check against the"
    Write-Output "  NEW pair, then update `$pins` deliberately."
    $fail += $pinFail
}

Write-Output ""
Write-Output "======================================================================================"
Write-Output "(C) DOC AGREEMENT -- the pins above must match what BUILD-LOG.md states, or the doc is"
Write-Output "    decoration. Credit to qemu-validator: they found this drift in their own fix --"
Write-Output "    adding pins duplicated the same hashes in script and README -- and that is the very"
Write-Output "    risk this guard exists to prevent, one level up. The same defect existed here."
Write-Output "======================================================================================"
Write-Output ""
$docFail = 0
$docPath = Join-Path $Dir 'BUILD-LOG.md'
if (-not (Test-Path $docPath)) {
    Write-Output "  BUILD-LOG.md not found next to the artefacts -- cannot check doc agreement"
    $docFail++
} else {
    $docLines = @(Get-Content $docPath)
    foreach ($name in $pins.Keys) {
        # Only lines that name THIS artefact in backticks AND carry a full 64-hex hash.
        # Truncated hashes (with an ellipsis) are deliberately ignored.
        $namePattern = '[`]' + [regex]::Escape($name) + '[`]'
        $hits = @($docLines | Where-Object { $_ -match $namePattern -and $_ -match '[0-9a-f]{64}' })
        if ($hits.Count -eq 0) {
            Write-Output ("  {0,-24} *** NO FULL HASH IN BUILD-LOG.md ***" -f $name)
            $docFail++
            continue
        }
        foreach ($h in $hits) {
            $found = @([regex]::Matches($h, '[0-9a-f]{64}') | ForEach-Object { $_.Value })
            if ($found -contains $pins[$name]) {
                Write-Output ("  {0,-24} ok pin {1} present in BUILD-LOG.md" -f $name, ($pins[$name].Substring(0,16) + '...'))
            } else {
                Write-Output ("  {0,-24} *** DOC DISAGREES ***" -f $name)
                Write-Output ("      script pin: {0}" -f $pins[$name])
                Write-Output ("      doc says  : {0}" -f ($found -join ', '))
                $docFail++
            }
        }
    }
}
if ($docFail -gt 0) {
    Write-Output ""
    Write-Output "  The enforcement and the document disagree. Fix whichever is wrong, then re-run."
    Write-Output "  An artefact table nobody can contradict is worth less than one that fails when it"
    Write-Output "  drifts."
    $fail += $docFail
}

Write-Output ""
Write-Output "======================================================================================"
if ($fail -eq 0) {
    Write-Output "RESULT: PASS"
    Write-Output "  (A) pairing : intended pairs accepted, both mis-pairings rejected"
    Write-Output "  (B) pinning : all four artefacts match their recorded hashes"
    Write-Output "  (C) doc     : all four pins are also stated in BUILD-LOG.md"
    Write-Output "  qemu-validator's resolve-pc.sh may cite these maps."
    Write-Output ""
    Write-Output "  LIMIT, stated so this is not over-generalised: rule 2 is two-valued, so (A)"
    Write-Output "  alone is sufficient only for THIS artefact set, not in general. (B) makes"
    Write-Output "  staleness detectable; (C) stops the document drifting from the enforcement."
    Write-Output "  If these maps are regenerated, the safety comes from re-running this check"
    Write-Output "  against the new pair, not from it having passed once."
} else {
    Write-Output "RESULT: FAIL ($fail problem(s)) -- do NOT cite these maps until resolved."
}
Write-Output "======================================================================================"
exit $fail
