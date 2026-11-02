# Builds amberscript-<version>.vsix from this folder without npm or vsce (a .vsix is a zip with a manifest).
# Usage: powershell -ExecutionPolicy Bypass -File build.ps1 [-Install]
param([switch]$Install)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$package = Get-Content (Join-Path $root 'package.json') -Raw | ConvertFrom-Json
$id = $package.name
$version = $package.version
$publisher = $package.publisher
$out = Join-Path $root 'out'
$vsix = Join-Path $out "$id-$version.vsix"

New-Item -ItemType Directory -Force $out | Out-Null

if (Test-Path $vsix) { Remove-Item $vsix }

$files = @(
	'package.json',
	'language-configuration.json',
	'syntaxes/amberscript.tmLanguage.json',
	'snippets/amberscript.json',
	'README.md'
)

$description = [System.Security.SecurityElement]::Escape($package.description)
$categories = ($package.categories -join ',')
$tags = ($package.keywords -join ',')

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
	<Metadata>
		<Identity Language="en-US" Id="$id" Version="$version" Publisher="$publisher" />
		<DisplayName>$($package.displayName)</DisplayName>
		<Description xml:space="preserve">$description</Description>
		<Tags>$tags</Tags>
		<Categories>$categories</Categories>
		<GalleryFlags>Public</GalleryFlags>
		<Properties>
			<Property Id="Microsoft.VisualStudio.Code.Engine" Value="$($package.engines.vscode)" />
			<Property Id="Microsoft.VisualStudio.Code.ExtensionDependencies" Value="" />
			<Property Id="Microsoft.VisualStudio.Code.ExtensionPack" Value="" />
			<Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="workspace" />
			<Property Id="Microsoft.VisualStudio.Code.LocalizedLanguages" Value="" />
		</Properties>
	</Metadata>
	<Installation>
		<InstallationTarget Id="Microsoft.VisualStudio.Code" />
	</Installation>
	<Dependencies />
	<Assets>
		<Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
		<Asset Type="Microsoft.VisualStudio.Services.Content.Details" Path="extension/README.md" Addressable="true" />
	</Assets>
</PackageManifest>
"@

$contentTypes = @"
<?xml version="1.0" encoding="utf-8"?>
<Types>
	<Default Extension=".json" ContentType="application/json" />
	<Default Extension=".md" ContentType="text/markdown" />
	<Default Extension=".vsixmanifest" ContentType="text/xml" />
</Types>
"@

$utf8 = New-Object System.Text.UTF8Encoding($false)
$zip = [System.IO.Compression.ZipFile]::Open($vsix, 'Create')

try
{
	function Add-Text($name, $text)
	{
		$entry = $zip.CreateEntry($name)
		$stream = $entry.Open()
		$bytes = $utf8.GetBytes($text)
		$stream.Write($bytes, 0, $bytes.Length)
		$stream.Dispose()
	}

	Add-Text '[Content_Types].xml' $contentTypes
	Add-Text 'extension.vsixmanifest' $manifest

	foreach ($file in $files)
	{
		# entries need forward slashes
		$entry = $zip.CreateEntry("extension/$file")
		$stream = $entry.Open()
		$bytes = [System.IO.File]::ReadAllBytes((Join-Path $root $file))
		$stream.Write($bytes, 0, $bytes.Length)
		$stream.Dispose()
	}
}
finally
{
	$zip.Dispose()
}

Write-Host "Built $vsix"

if ($Install)
{
	$code = (Get-Command code -ErrorAction SilentlyContinue).Source

	if (-not $code)
	{
		Write-Error "The 'code' command was not found. Install the extension with: code --install-extension `"$vsix`""
	}

	& $code --install-extension $vsix --force
}
