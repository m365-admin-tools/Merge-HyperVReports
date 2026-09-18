# Merge-HyperVReports
Merge Hyper-V Inventory Reports (PowerShell)

Combines several per-host HTML reports from [HyperV-Inventory.ps1](https://github.com/m365admintools/hyperv-inventory-report) into one self-contained file with a host tab bar across the top. Each host keeps its own dashboard and its own vInfo, vDisk, vNetwork, vSnapshot, vHost, vSwitch, vReplication, and vIntegration tabs, and they work independently.

# This one makes the Hyper-V reporting script even more powerful. It will take all your out puts form different Hyper-V servers and combine them into one report.

Visit https://m365admintools.com for more information and IT engineering tools

Sort a column on one host, filter a table on another, and neither affects the other. Every element ID, sort call, and table reference is namespaced per host during the merge.

The result is one attachment to send a client instead of six.

<!-- Add a screenshot showing the host tab bar with a report open here, then uncomment:
![Combined report](docs/images/combined-report.png)
-->

## Requirements

| Item | Requirement |
|---|---|
| PowerShell | 5.1 or later |
| Modules | None |
| Input | Two or more HTML files produced by `HyperV-Inventory.ps1` |

No Hyper-V access is needed. This script reads HTML files and writes an HTML file, so it can run on any workstation after the reports have been collected.

## Quick start

```powershell
# Merge every HyperV-Inventory*.html in the current folder
.\Merge-HyperVReports.ps1

# Name the files explicitly
.\Merge-HyperVReports.ps1 -InputFiles ".\HV01.html",".\HV02.html",".\HV03.html"

# Scan a folder and label the report for the client
.\Merge-HyperVReports.ps1 -ReportFolder C:\Reports -CustomerName "Contoso Ltd"
```

The simplest workflow is to run `HyperV-Inventory.ps1` once per host, drop the HTML files into one folder, then run this script from that folder with no parameters.

If the script is blocked on first run:

```powershell
Unblock-File .\Merge-HyperVReports.ps1
```

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-InputFiles` | string[] | None | Explicit list of report paths to merge. Takes precedence over `-ReportFolder` |
| `-ReportFolder` | string | None | Folder to scan for `HyperV-Inventory*.html`. Ignored when `-InputFiles` is supplied |
| `-OutputPath` | string | Current directory | Destination folder for the merged file. Created if it does not exist |
| `-CustomerName` | string | `Customer Name` | Label shown in the merged report header as "Prepared for" |

With neither `-InputFiles` nor `-ReportFolder`, the script scans the current directory. Files found by scanning are merged in filename order, which is worth knowing if you want the host tabs in a particular sequence: name the files so they sort the way you want, or list them explicitly with `-InputFiles`.

## Output

```
HyperV-Combined_20260917_142233.html
```

Self-contained, with the CSS and JavaScript inline and no external dependencies. It can be emailed as a single attachment, attached to a ticket, or opened from a USB drive.

The header carries the customer name and generation time. The footer lists every host included and notes that the file was merged, so a reader a year later knows what they are looking at.

## How the host label is chosen

The script reads the hostname from the "Host(s):" line in each report header. If that line cannot be found, it falls back to the filename with the `HyperV-Inventory_` prefix removed. Rename a file before merging if you want a different tab label and the header line is missing.

## Limitations

- **One host per input file works best.** A report produced by running the inventory against several hosts at once contains all of them in a single file, and the merge treats it as one tab with one label. Collect one report per host if you want one tab per host.
- **Data is not aggregated.** Each host panel keeps its own dashboard and its own numbers. There is no combined total across hosts. If you need estate-wide totals, run `HyperV-Inventory.ps1` once with every host in `-ComputerName` and use the Excel output instead.
- **The parser depends on the inventory report's structure.** Sections are located by regular expression against the HTML that `HyperV-Inventory.ps1` produces. If that script's markup changes, update the patterns here to match. The two are versioned together for this reason.
- **Styling comes from the first file only.** The reports are expected to share identical CSS. Mixing files from two different versions of the inventory script can produce a report where later hosts are styled by the first file's stylesheet.
- **Duplicate labels are not detected.** Merging two reports from the same host produces two tabs with the same name.

## Troubleshooting

**`No HTML report files found. Use -InputFiles or -ReportFolder to specify the reports.`**

The folder contains no files matching `HyperV-Inventory*.html`. Either the reports were renamed, or the script is running in the wrong directory. Use `-InputFiles` to name them directly.

**`No valid report files could be parsed.`**

Files were found but none contained the expected structure. Confirm they came from `HyperV-Inventory.ps1` rather than another tool, and that they are complete rather than truncated.

**`Could not extract CSS from this file.`**

The first file had no `<style>` block. The merge continues but the output will be unstyled. Put a known-good report first in the list.

**A host tab is labelled with a filename instead of a hostname**

The "Host(s):" line was missing from that report's header. The filename fallback was used. Rename the file to the hostname before merging.

**Sort or filter on one host affects another**

This should not happen, since IDs are namespaced during the merge. If it does, the input files came from a version of the inventory script whose ID naming differs from what the namespacing patterns expect. Report it as an issue with the version of the inventory script that produced the files.

## Related

- [HyperV-Inventory.ps1](https://github.com/m365admintools/hyperv-inventory-report), which produces the reports this script merges
- Free Microsoft 365, Active Directory, and Veeam tools at [m365admintools.com](https://m365admintools.com)

## Author

Charles Arconi, [m365admintools.com](https://m365admintools.com)

## License

MIT. See [LICENSE](LICENSE).

