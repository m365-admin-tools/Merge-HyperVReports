<#
.SYNOPSIS
    Merge-HyperVReports.ps1 - Merges multiple HyperV-Inventory HTML reports into one tabbed file.

.DESCRIPTION
    Takes 2 or more HTML files from HyperV-Inventory.ps1 (one per host) and combines them into
    a single self-contained HTML with an outer HOST tab bar plus the original inner data-section
    tabs (vInfo, vDisk, vNetwork, etc.) preserved and fully functional per host.

    All element IDs, sortTable and data-table references are namespaced per host so sort,
    filter, and tab state are fully independent across host panels.

.PARAMETER InputFiles
    Explicit list of HTML report paths to merge.
    Example: -InputFiles ".\HV01.html",".\HV02.html",".\HV03.html"

.PARAMETER ReportFolder
    Auto-scan this folder for HyperV-Inventory*.html files.
    Ignored when InputFiles is provided.
    Defaults to the current directory if neither parameter is specified.

.PARAMETER OutputPath
    Destination folder for the merged report. Defaults to the current directory.

.PARAMETER CustomerName
    Customer/site label shown in the merged report header.

.EXAMPLE
    .\Merge-HyperVReports.ps1 -InputFiles ".\HV01.html",".\HV02.html",".\HV03.html"

.EXAMPLE
    .\Merge-HyperVReports.ps1 -ReportFolder C:\Reports -CustomerName "Contoso Ltd"

.EXAMPLE
    .\Merge-HyperVReports.ps1

.NOTES
    No external modules required. PowerShell 5.1 or later.
    Run from the folder containing your per-host HTML files for simplest usage.
#>

[CmdletBinding()]
param(
    [string[]] $InputFiles,
    [string]   $ReportFolder,
    [string]   $OutputPath   = (Get-Location).Path,
    [string]   $CustomerName = 'Customer Name'
)

$ErrorActionPreference = 'Continue'

#region -- Resolve file list -----------------------------------------------

if ($InputFiles -and $InputFiles.Count -gt 0) {
    $files = $InputFiles
} elseif ($ReportFolder) {
    $files = @(Get-ChildItem -Path $ReportFolder -Filter 'HyperV-Inventory*.html' -File |
               Sort-Object Name | Select-Object -ExpandProperty FullName)
} else {
    $files = @(Get-ChildItem -Path (Get-Location).Path -Filter 'HyperV-Inventory*.html' -File |
               Sort-Object Name | Select-Object -ExpandProperty FullName)
}

if (-not $files -or $files.Count -eq 0) {
    Write-Error 'No HTML report files found. Use -InputFiles or -ReportFolder to specify the reports.'
    exit 1
}

Write-Host ''
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host '  Merge-HyperVReports.ps1' -ForegroundColor Cyan
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host "  Files to merge: $($files.Count)" -ForegroundColor White
$files | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
Write-Host ''

#endregion

#region -- Parse each HTML file --------------------------------------------

$hostBlocks = [System.Collections.Generic.List[PSObject]]::new()
$sharedCss  = $null
$hIdx       = 0

foreach ($f in $files) {

    if (-not (Test-Path $f)) {
        Write-Warning "File not found - skipping: $f"
        continue
    }

    Write-Host "  [Parsing] $([System.IO.Path]::GetFileName($f))" -ForegroundColor Yellow
    $raw = Get-Content -Path $f -Raw -Encoding UTF8

    # CSS - grab once from the first file (identical across all reports)
    if ($null -eq $sharedCss) {
        $cssM = [regex]::Match($raw, '(?s)<style>(.*?)</style>')
        if ($cssM.Success) {
            $sharedCss = $cssM.Groups[1].Value
            Write-Host '    CSS extracted' -ForegroundColor DarkGray
        } else {
            Write-Warning '    Could not extract CSS from this file.'
        }
    }

    # Hostname from header paragraph
    # Header reads: "Generated: ... | Host(s): HV01 &nbsp;|&nbsp; ..."
    $hostM = [regex]::Match($raw, 'Host\(s\):\s*([^<&]+?)(?:\s*&nbsp;|</p>)')
    if ($hostM.Success) {
        $hostLabel = $hostM.Groups[1].Value.Trim()
    } else {
        $hostLabel = [System.IO.Path]::GetFileNameWithoutExtension($f) -replace '^HyperV-Inventory_', ''
    }

    # Dashboard + state-bar (everything between </header> and the inner <nav>)
    $metaM = [regex]::Match($raw, '(?s)</header>\s*(.*?)\s*<nav\s+class="tab-nav">')
    $metaBlock = if ($metaM.Success) { $metaM.Groups[1].Value.Trim() } else { '' }

    # Inner nav buttons
    $navM = [regex]::Match($raw, '(?s)<nav\s+class="tab-nav">(.*?)</nav>')
    $innerNav = if ($navM.Success) { $navM.Groups[1].Value.Trim() } else { '' }

    # Section blocks
    $sectionMatches = [regex]::Matches($raw, '(?s)<section[^>]*>.*?</section>')
    $sections = @($sectionMatches | ForEach-Object { $_.Value })

    # Namespace IDs and function calls for this host index.
    # Pattern: tab-vInfo  -> tab-h0-vInfo  (or h1, h2 etc.)
    $prefix = 'h' + $hIdx + '-'

    $innerNav = $innerNav -replace 'showTab\("tab-', ('showSec("tab-' + $prefix)

    $namespacedSections = $sections | ForEach-Object {
        $s = $_
        $s = $s -replace "id='tab-",         ("id='tab-"         + $prefix)
        $s = $s -replace "id='tbl-",         ("id='tbl-"         + $prefix)
        $s = $s -replace 'sortTable\("tbl-', ('sortTable("tbl-'   + $prefix)
        $s = $s -replace "data-table='tbl-", ("data-table='tbl-"  + $prefix)
        $s
    }

    $hostBlocks.Add([PSCustomObject]@{
        Index     = $hIdx
        Label     = $hostLabel
        MetaBlock = $metaBlock
        InnerNav  = $innerNav
        Sections  = $namespacedSections
    })

    Write-Host "    Label    : $hostLabel" -ForegroundColor Green
    Write-Host "    Sections : $($namespacedSections.Count)" -ForegroundColor Green
    $hIdx++
}

if ($hostBlocks.Count -eq 0) {
    Write-Error 'No valid report files could be parsed.'
    exit 1
}

#endregion

#region -- Build combined HTML ---------------------------------------------

Write-Host ''
Write-Host '  Building combined report...' -ForegroundColor Cyan

$generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$hostNames   = ($hostBlocks | ForEach-Object { $_.Label }) -join ', '

# Outer host tab buttons
$hostTabBtns = @()
foreach ($hb in $hostBlocks) {
    $active    = if ($hb.Index -eq 0) { ' active' } else { '' }
    $safeLabel = $hb.Label -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
    $hostTabBtns += "<button class='host-tab-btn$active' onclick='showHost($($hb.Index),this)'>$safeLabel</button>"
}

# Per-host content panels.
# Using array+join instead of a here-string inside a script block to avoid
# the PowerShell requirement that "@ must be at column 0.
$hostPanels = @()
foreach ($hb in $hostBlocks) {
    $vis      = if ($hb.Index -eq 0) { '' } else { ' style="display:none"' }
    $sectHtml = $hb.Sections -join "`n"
    $parts = @(
        "<div class=""host-panel"" id=""hp-$($hb.Index)""$vis>",
        $hb.MetaBlock,
        '<nav class="tab-nav">',
        "  $($hb.InnerNav)",
        '</nav>',
        $sectHtml,
        '</div>'
    )
    $hostPanels += $parts -join "`n"
}

if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath | Out-Null }
$outFile = Join-Path $OutputPath ('HyperV-Combined_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.html')

$hostTabBtnsHtml = $hostTabBtns -join "`n  "
$hostPanelsHtml  = $hostPanels  -join "`n"

$combinedHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Hyper-V Combined Inventory - $generatedAt</title>
<style>
$sharedCss

/* ==== Outer host tab bar ==== */
.host-tab-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 0;
  background: linear-gradient(135deg, #0d1f36, #1a3460);
  padding: 0 24px;
  border-bottom: 3px solid #2d6cb0;
}
.host-tab-btn {
  background: transparent;
  border: none;
  border-bottom: 3px solid transparent;
  margin-bottom: -3px;
  color: rgba(255,255,255,.6);
  padding: 13px 26px;
  cursor: pointer;
  font-size: 14px;
  font-weight: 600;
  font-family: inherit;
  letter-spacing: .3px;
  transition: all .15s;
}
.host-tab-btn:hover  { color: #fff; background: rgba(255,255,255,.08); }
.host-tab-btn.active { color: #fff; border-bottom-color: #5ab4ff; background: rgba(255,255,255,.12); }
.host-panel { display: block; }
footer {
  text-align: center;
  padding: 16px;
  color: #999;
  font-size: 11px;
  border-top: 1px solid #dde3ea;
  margin-top: 20px;
}
</style>
</head>
<body>

<header>
  <div>
    <h1>Hyper-V Combined Inventory Report</h1>
    <p>Generated: $generatedAt &nbsp;|&nbsp; $($hostBlocks.Count) host(s): $hostNames</p>
  </div>
  <div class="customer">Prepared for: $CustomerName</div>
</header>

<!-- Outer host switcher -->
<div class="host-tab-bar">
  $hostTabBtnsHtml
</div>

$hostPanelsHtml

<footer>
  Hyper-V Combined Inventory &nbsp;|&nbsp; $generatedAt &nbsp;|&nbsp;
  Hosts: $hostNames &nbsp;|&nbsp; Merged by Merge-HyperVReports.ps1
</footer>

<script>
// Switch between host panels
function showHost(idx, btn) {
  document.querySelectorAll('.host-panel').forEach(function(p) { p.style.display = 'none'; });
  document.querySelectorAll('.host-tab-btn').forEach(function(b) { b.classList.remove('active'); });
  var panel = document.getElementById('hp-' + idx);
  if (panel) { panel.style.display = ''; }
  if (btn) { btn.classList.add('active'); }
  // Auto-click the first inner section tab
  var firstInner = panel ? panel.querySelector('.tab-btn') : null;
  if (firstInner) { firstInner.click(); }
}

// Switch data-section tabs within a host panel
function showSec(id, btn) {
  var panel = btn ? btn.closest('.host-panel') : null;
  if (panel) {
    panel.querySelectorAll('section').forEach(function(s) { s.classList.remove('visible'); });
    panel.querySelectorAll('.tab-btn').forEach(function(b) { b.classList.remove('active'); });
  }
  var el = document.getElementById(id);
  if (el) { el.classList.add('visible'); }
  if (btn) { btn.classList.add('active'); }
}

// Column sort (unchanged from original)
function sortTable(tableId, colIdx) {
  var tbl = document.getElementById(tableId);
  if (!tbl) { return; }
  var rows = Array.from(tbl.querySelectorAll('tbody tr'));
  var asc  = (tbl.dataset.sortCol == colIdx && tbl.dataset.sortDir == 'asc') ? false : true;
  tbl.dataset.sortCol = colIdx;
  tbl.dataset.sortDir = asc ? 'asc' : 'desc';
  rows.sort(function(a, b) {
    var av = a.cells[colIdx] ? a.cells[colIdx].innerText : '';
    var bv = b.cells[colIdx] ? b.cells[colIdx].innerText : '';
    var an = parseFloat(av), bn = parseFloat(bv);
    if (!isNaN(an) && !isNaN(bn)) { return asc ? an - bn : bn - an; }
    return asc ? av.localeCompare(bv) : bv.localeCompare(av);
  });
  var tbody = tbl.querySelector('tbody');
  rows.forEach(function(r) { tbody.appendChild(r); });
}

// Per-table filter search (unchanged from original)
document.querySelectorAll('.search').forEach(function(inp) {
  inp.addEventListener('input', function() {
    var val = this.value.toLowerCase();
    var tbl = document.getElementById(this.dataset.table);
    if (!tbl) { return; }
    tbl.querySelectorAll('tbody tr').forEach(function(row) {
      row.style.display = row.innerText.toLowerCase().indexOf(val) !== -1 ? '' : 'none';
    });
  });
});

// Init: show first host and its first section
(function() {
  var firstHostBtn = document.querySelector('.host-tab-btn');
  if (firstHostBtn) { firstHostBtn.click(); }
})();
</script>
</body>
</html>
"@

$combinedHtml | Out-File -FilePath $outFile -Encoding UTF8 -Force

Write-Host ''
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host '  [Done] Combined report:' -ForegroundColor Green
Write-Host "  $outFile" -ForegroundColor White
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host ''

#endregion
