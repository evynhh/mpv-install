function Check-PowershellVersion {
    $version = $PSVersionTable.PSVersion.Major
    Write-Host "Checking Windows PowerShell version -- $version" -ForegroundColor Green
    if ($version -le 2)
    {
        Write-Host "PowerShell version $version is unsupported. Upgrade your PowerShell." -ForegroundColor Red
        throw
    }
}

function Check-Youtubedl {
    $youtubedl = (Get-Location).Path + "\youtube-dl.exe"
    $is_exist = Test-Path $youtubedl
    return $is_exist
}

function Check-Mpv {
    $mpv = (Get-Location).Path + "\mpv.exe"
    $is_exist = Test-Path $mpv
    return $is_exist
}

function Download-Mpv ($filename) {
    Write-Host "Downloading" $filename -ForegroundColor Green
    $global:progressPreference = 'Continue'
    $link = "https://download.sourceforge.net/mpv-player-windows/" + $filename
    Invoke-WebRequest -Uri $link -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox -OutFile $filename
}

function Download-Youtubedl ($version) {
    Write-Host "Downloading youtube-dl ($version)" -ForegroundColor Green
    $global:progressPreference = 'Continue'
    $link = "https://yt-dl.org/downloads/" + $version + "/youtube-dl.exe"
    Invoke-WebRequest -Uri $link -UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox -OutFile "youtube-dl.exe"
}

function Extract-Mpv ($file) {
    $7za = (Get-Location).Path + "\7z\7z.exe"
    Write-Host "Extracting" $file -ForegroundColor Green
    & $7za x -y $file
}

function Get-Latest-Mpv($Arch) {
    $i686_link = "https://sourceforge.net/projects/mpv-player-windows/rss?path=/32bit"
    $x86_64_link = "https://sourceforge.net/projects/mpv-player-windows/rss?path=/64bit"
    $link = ''
    switch ($Arch)
    {
        i686 { $link = $i686_link}
        x86_64 { $link = $x86_64_link }
    }
    Write-Host "Fetching RSS feed for mpv" -ForegroundColor Green
    $result = [xml](New-Object System.Net.WebClient).DownloadString($link)
    $latest = $result.rss.channel.item.link[0]
    $filename = $latest.split("/")[-2]
    return [System.Uri]::UnescapeDataString($filename)
}

function Get-Latest-Youtubedl {
    $link = "https://yt-dl.org/downloads/latest/youtube-dl.exe"
    $global:progressPreference = 'silentlyContinue'
    $resp = Invoke-WebRequest $link -MaximumRedirection 0 -ErrorAction Ignore -UseBasicParsing
    $redirect_link = $resp.Headers.Location
    $version = $redirect_link.split("/")[4]
    return $version
}

function Get-Arch {
    # Reference: http://superuser.com/a/891443
    $FilePath = [System.IO.Path]::Combine((Get-Location).Path, 'mpv.exe')
    [int32]$MACHINE_OFFSET = 4
    [int32]$PE_POINTER_OFFSET = 60

    [byte[]]$data = New-Object -TypeName System.Byte[] -ArgumentList 4096
    $stream = New-Object -TypeName System.IO.FileStream -ArgumentList ($FilePath, 'Open', 'Read')
    $stream.Read($data, 0, 4096) | Out-Null

    # DOS header is 64 bytes, last element, long (4 bytes) is the address of the PE header
    [int32]$PE_HEADER_ADDR = [System.BitConverter]::ToInt32($data, $PE_POINTER_OFFSET)
    [int32]$machineUint = [System.BitConverter]::ToUInt16($data, $PE_HEADER_ADDR + $MACHINE_OFFSET)

    $result = "" | select FilePath, FileType
    $result.FilePath = $FilePath

    switch ($machineUint)
    {
        0      { $result.FileType = 'Native' }
        0x014c { $result.FileType = 'i686' } # 32bit
        0x0200 { $result.FileType = 'Itanium' }
        0x8664 { $result.FileType = 'x86_64' } # 64bit
    }

    $result
}

function ExtractGitFromFile {
    $stripped = .\mpv --no-config | select-string "mpv" | select-object -First 1
    $pattern = "-g([a-z0-9-]{7})"
    $bool = $stripped -match $pattern
    return $matches[1]
}

function ExtractGitFromURL($filename) {
    $pattern = "-git-([a-z0-9-]{7})"
    $bool = $filename -match $pattern
    return $matches[1]
}

function ExtractDateFromFile {
    $date = (Get-Item ./mpv.exe).LastWriteTimeUtc
    $day = $date.Day.ToString("00")
    $month = $date.Month.ToString("00")
    $year = $date.Year.ToString("0000")
    return "$year$month$day"
}

function ExtractDateFromURL($filename) {
    $pattern = "mpv-[xi864_]*-([0-9]{8})-git-([a-z0-9-]{7})"
    $bool = $filename -match $pattern
    return $matches[1]
}

function Test-Admin
{
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Upgrade-Mpv {
    $need_download = $false
    $remoteName = ""
    $arch = ""

    if (Check-Mpv) {
        $arch = (Get-Arch).FileType
        $remoteName = Get-Latest-Mpv $arch
        $localgit = ExtractGitFromFile
        $localdate = ExtractDateFromFile
        $remotegit = ExtractGitFromURL $remoteName
        $remotedate = ExtractDateFromURL $remoteName
        if ($localgit -match $remotegit)
        {
            if ($localdate -match $remotedate)
            {
                Write-Host "You are already using latest mpv build -- $remoteName" -ForegroundColor Green
                $need_download = $false
            }
            else {
                Write-Host "Newer mpv build available" -ForegroundColor Green
                $need_download = $true
            }
        }
        else {
            Write-Host "Newer mpv build available" -ForegroundColor Green
            $need_download = $true
        }
    }
    else {
        Write-Host "mpv doesn't exist. " -ForegroundColor Green -NoNewline
		$result = Read-KeyOrTimeout "Downloading mpv.." "Y"
        Write-Host ""

        if ($result -eq "Y") {
            $need_download = $true
            if (Test-Path (Join-Path $env:windir "SysWow64")) {
                Write-Host "Detecting System Type is 64-bit" -ForegroundColor Green
                $arch = "x86_64"
            }
            else {
                Write-Host "Detecting System Type is 32-bit" -ForegroundColor Green
                $arch = "i686"
            }
            $remoteName = Get-Latest-Mpv $arch
        }
        else {
            $need_download = $false
        }
    }

    if ($need_download) {
        Download-Mpv $remoteName
        Extract-Mpv $remoteName
    }
}

function Upgrade-Youtubedl {
    $need_download = $false
    $latest_release = Get-Latest-Youtubedl

    if (Check-Youtubedl) {
        if ((.\youtube-dl --version) -match ($latest_release)) {
            Write-Host "You are already using latest youtube-dl -- $latest_release" -ForegroundColor Green
            $need_download = $false
        }
        else {
            Write-Host "Newer youtube-dl build available" -ForegroundColor Green
            $need_download = $true
        }
    }
    else {
        Write-Host "youtube-dl doesn't exist. " -ForegroundColor Green -NoNewline
        $result = Read-KeyOrTimeout "" "Y"
        Write-Host ""

        if ($result -eq 'Y') {
            $need_download = $true
        }
        else {
            $need_download = $false
        }
    }

    if ($need_download) {
        Download-Youtubedl $latest_release
    }
}
function Cleanup {
	Remove-Item mpv-*.7z
	Remove-Item -Recurse -Force 7z
	Remove-Item -Recurse -Force installer
}

function Read-KeyOrTimeout ($prompt, $key){
    $seconds = 0
    $startTime = Get-Date
    $timeOut = New-TimeSpan -Seconds $seconds

    while (-not [System.Console]::KeyAvailable) {
        $currentTime = Get-Date
        if ($currentTime -gt $startTime + $timeOut) {
            Break
        }
    }
    if ([System.Console]::KeyAvailable) {
        $response = [System.Console]::ReadKey($true).Key
    }
    else {
        $response = $key
    }
    return $response.ToString()
}

#
# Main script entry point
#
if (Test-Admin) {
    Write-Host "Running script with administrator privileges" -ForegroundColor Yellow
}
else {
    Write-Host "Running script without administrator privileges" -ForegroundColor Red
}

try {
    Check-PowershellVersion
    # Sourceforge only support TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Upgrade-Mpv
    Upgrade-Youtubedl
    Write-Host "Operation completed." -ForegroundColor Magenta
	Write-Host "You now have to set the path for mpv. Add '%appdata%\mpv' to your path, use your preferred search engine to figure out how to do so." -ForegroundColor Red
	Cleanup
}
catch [System.Exception] {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
