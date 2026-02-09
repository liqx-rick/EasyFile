# Software Copyright Word Document Generation Script
# EasyFile V1.0.0

param(
    [switch]$GenerateFront,
    [switch]$GenerateBack
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$LibPath = Join-Path $ProjectRoot "lib"
$OutputDir = Join-Path $ProjectRoot "Copyright_Application_Documents"

$FrontFiles = @(
    @{Path="main.dart"}
    @{Path="app.dart"}
    @{Path="core\di\locator.dart"}
    @{Path="ui\widgets\quick_access_section.dart"}
    @{Path="presenter\quick_access_presenter.dart"}
)

$BackFiles = @(
    @{Path="core\services\recommendation_service.dart"}
    @{Path="core\services\duplicate_files_recommendation_engine.dart"}
    @{Path="data\models\recommendation_card.dart"}
    @{Path="ui\pages\recommend_aggregate_page.dart"}
)

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function New-WordDocument {
    param(
        [array]$FileList,
        [string]$OutputPath,
        [int]$StartPageNumber = 1,
        [string]$DocumentTitle
    )

    Write-ColorOutput "`nCreating Word document: $DocumentTitle" "Cyan"

    $Word = New-Object -ComObject Word.Application
    $Word.Visible = $false

    try {
        $Doc = $Word.Documents.Add()

        # Page setup
        $Doc.PageSetup.PaperSize = 7
        $Doc.PageSetup.TopMargin = $Word.CentimetersToPoints(2.5)
        $Doc.PageSetup.BottomMargin = $Word.CentimetersToPoints(2.5)
        $Doc.PageSetup.LeftMargin = $Word.CentimetersToPoints(2)
        $Doc.PageSetup.RightMargin = $Word.CentimetersToPoints(2)

        # Configure header
        $Section = $Doc.Sections.Item(1)
        $Header = $Section.Headers.Item(1)
        $HeaderRange = $Header.Range

        # Clear existing content
        $HeaderRange.Text = ""

        # Add left-aligned text (software name and version)
        $HeaderRange.Text = "EasyFile v1.0.0"
        $HeaderRange.Font.Name = "SimSun"
        $HeaderRange.Font.Size = 10.5
        $HeaderRange.ParagraphFormat.Alignment = 0  # Left align

        # Move to end and add tab
        $HeaderRange.Collapse(0)  # Move to end
        $HeaderRange.InsertAfter("`t`t`t`t`t`t")

        # Add page number at the end (right side)
        $HeaderRange.Collapse(0)
        $Field = $Header.Range.Fields.Add($HeaderRange, 33, $null, $false)  # 33 = wdFieldPage
        $Field.Result.Font.Name = "SimSun"
        $Field.Result.Font.Size = 10.5

        # Add separator line below header
        $HeaderRange = $Header.Range
        $HeaderRange.Collapse(0)
        $HeaderRange.InsertParagraphAfter()
        $HeaderRange.Borders.Item(3).LineStyle = 1  # 3 = wdBorderBottom, 1 = wdLineStyleSingle

        # Set starting page number
        $Section.Footers.Item(1).PageNumbers.StartingNumber = $StartPageNumber

        # Main document content
        $Range = $Doc.Range()
        $Range.Font.Name = "Consolas"
        $Range.Font.Size = 10
        $Range.ParagraphFormat.LineSpacingRule = 0
        $Range.ParagraphFormat.SpaceAfter = 0
        $Range.ParagraphFormat.SpaceBefore = 0

        $fileCount = 0
        $totalLines = 0

        foreach ($file in $FileList) {
            $fileCount++
            $filePath = Join-Path $LibPath $file.Path

            if (-not (Test-Path $filePath)) {
                Write-ColorOutput "  [!] File not found: $filePath" "Yellow"
                continue
            }

            $content = Get-Content $filePath -Encoding UTF8 -Raw
            $lines = Get-Content $filePath -Encoding UTF8
            $lineCount = $lines.Count
            $totalLines += $lineCount

            Write-ColorOutput "  [$fileCount] $($file.Path) - $lineCount lines" "Green"

            # Move to end of document
            $Range = $Doc.Range()
            $Range.Collapse(0)

            # Add file header with Chinese label
            $fileName = Split-Path $file.Path -Leaf
            $fileHeader = "$fileName"
            $Range.InsertAfter($fileHeader + [Environment]::NewLine)

            # Add code content
            $Range.Collapse(0)
            $Range.InsertAfter($content)

            # Add line breaks between files
            $Range.Collapse(0)
            $Range.InsertAfter([Environment]::NewLine + [Environment]::NewLine)

            # Apply formatting to entire document
            $Doc.Range().Font.Name = "Consolas"
            $Doc.Range().Font.Size = 10
        }

        Write-ColorOutput "`n  Total: $totalLines lines across $fileCount files" "Yellow"

        # Save document
        $Doc.SaveAs([ref]$OutputPath)
        $Doc.Close()

        $fileSize = (Get-Item $OutputPath).Length / 1KB
        Write-ColorOutput "  [OK] Document saved: $([Math]::Round($fileSize, 2)) KB" "Green"

    } catch {
        Write-ColorOutput "  [ERROR] $($_.Exception.Message)" "Red"
        throw
    } finally {
        $Word.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Word) | Out-Null
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
}

Write-ColorOutput @"

================================================================
   Software Copyright Word Document Generator
   EasyFile v1.0.0
================================================================

"@ "Cyan"

try {
    $Word = New-Object -ComObject Word.Application
    $Word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Word) | Out-Null
    Write-ColorOutput "[OK] Microsoft Word detected" "Green"
} catch {
    Write-ColorOutput "[ERROR] Microsoft Word is not installed" "Red"
    exit 1
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Default: generate both if no parameters specified
if (-not $GenerateFront -and -not $GenerateBack) {
    $GenerateFront = $true
    $GenerateBack = $true
}

if ($GenerateFront) {
    Write-ColorOutput "`n=== Generating Front 30 Pages ===" "Cyan"

    $frontOutputPath = Join-Path $OutputDir "Copyright_SourceCode_Front30.docx"

    try {
        New-WordDocument `
            -FileList $FrontFiles `
            -OutputPath $frontOutputPath `
            -StartPageNumber 1 `
            -DocumentTitle "Front 30 Pages"
    } catch {
        Write-ColorOutput "`n[ERROR] Failed to generate front document: $_" "Red"
    }
}

if ($GenerateBack) {
    Write-ColorOutput "`n=== Generating Back 30 Pages ===" "Cyan"

    $backOutputPath = Join-Path $OutputDir "Copyright_SourceCode_Back30.docx"

    try {
        New-WordDocument `
            -FileList $BackFiles `
            -OutputPath $backOutputPath `
            -StartPageNumber 31 `
            -DocumentTitle "Back 30 Pages"
    } catch {
        Write-ColorOutput "`n[ERROR] Failed to generate back document: $_" "Red"
    }
}

Write-ColorOutput @"

================================================================
   Generation Complete!
================================================================

Output Directory: $OutputDir

"@ "Green"

if ($GenerateFront -and (Test-Path (Join-Path $OutputDir "Copyright_SourceCode_Front30.docx"))) {
    $size = (Get-Item (Join-Path $OutputDir "Copyright_SourceCode_Front30.docx")).Length / 1KB
    Write-ColorOutput "  [DOC] Copyright_SourceCode_Front30.docx ($([Math]::Round($size, 2)) KB)" "Green"
}

if ($GenerateBack -and (Test-Path (Join-Path $OutputDir "Copyright_SourceCode_Back30.docx"))) {
    $size = (Get-Item (Join-Path $OutputDir "Copyright_SourceCode_Back30.docx")).Length / 1KB
    Write-ColorOutput "  [DOC] Copyright_SourceCode_Back30.docx ($([Math]::Round($size, 2)) KB)" "Green"
}

Write-ColorOutput @"

Next Steps:
  1. Open the Word documents to review
  2. Adjust formatting (line spacing, comments)
  3. Ensure front document = 30 pages
  4. Ensure back document = pages 31-60
  5. IMPORTANT: Rename files to Chinese names for submission

"@ "Yellow"

$openFolder = Read-Host "Open output directory? (Y/N)"
if ($openFolder -eq "Y" -or $openFolder -eq "y") {
    Invoke-Item $OutputDir
}
