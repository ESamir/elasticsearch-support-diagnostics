<#
.SYNOPSIS
    Collects diagnostic information from your elasticsearch cluster.
.DESCRIPTION
    This script is used to gather diagnotistic information for elasticsearch support.  In order to gather the elasticsearch config and logs you must run this on a node within your elasticsearch cluster.
.PARAMETER H
    Elasticsearch hostname:port (defaults to localhost:9200)
.PARAMETER n
    On a host with multiple nodes, specify the node name to gather data for. Value should match node.name as defined in elasticsearch.yml
.PARAMETER o
    Script output directory (optional, defaults to ./support-diagnostics.[timestamp].[hostname])
.PARAMETER nc
    Disable compression (optional)
#>

Param(
    [string]$H,
    [string]$n,
    [string]$o,
    [switch]$nc
)

# Set defaults
$esHostPort = 'localhost:9200'
$timestamp = Get-Date -format yyyyMMdd-HHmmss
$outputDir = $o
$targetNode = '_local'

If ($H) {
    $esHostPort = $H
}

If ($n) {
    $targetNode = $n
}

# Cannot be defaulted without the target node being set
If (! $o) {
    $hostName = [System.Net.Dns]::GetHostName()
    $outputDir = 'support-diagnostics.'+$hostName+'.'+$targetNode+'.'+$timestamp
}

$esHost = 'http://' + $esHostPort + '/'

New-Item $outputDir -Type directory | Out-Null
If (!(Test-Path $outputDir)) {
    Write-Host Cannot write output file.
    Exit
}

Write-Host 'Getting your configuration from the elasticsearch API'

$connectionTest = Invoke-WebRequest $esHost
If ($connectionTest.StatusCode -ne 200) {
    Write-Host Error connecting to $esHost
    Exit
}

$nodenameStatus = (Invoke-WebRequest ($esHost+'_nodes/'+$targetNode+'/settings?pretty')).RawContent | Select-String '"nodes" : { }'
If ($nodenameStatus) {
    Write-Host `n`nThe host and node name (\"$esHostPort\" and \"$targetNode\") does not appear to be connected to your cluster.  This script will continue, however without gathering the log files or elasticsearch.yml`n`n
}

# Get the ES version
$esVersion= (Invoke-RestMethod $esHost).version.number

$nodes = (Invoke-RestMethod ($esHost+'_nodes/'+$targetNode+'/settings?pretty')).nodes
$nodesPropertyName = $nodes.psobject.properties.name
$nodeSettings = $nodes.$nodesPropertyName.settings

If ($esVersion.StartsWith("0.9")) {
    $esHomePath = $nodeSettings."path.home"
    $esLogsPath = $nodeSettings."path.logs"
} Else {
    $esHomePath = $nodeSettings.path.home
    $esLogsPath = $nodeSettings.path.logs
}

Write-Host 'Getting config'
$esConfigPath = $esHomePath+'\config'
# Check if the config directory we found exists
If (!(Test-Path $esConfigPath)) {
    # Sometimes the API returns a relative path.  If so, try prepending the home directory
    $esConfigPath = $esHomePath+'\'+$esConfigPath
    If (!(Test-Path $esConfigPath)) {
        Write-Host `nCould not get your elasticsearch config.  Please add your elasticsearch config directory to the $outputDir'.zip' or to your ticket.`n`n
        $esConfigPath = ''
    }
}

If ($esConfigPath) {
    cp -r $esConfigPath $outputDir\config
}

Write-Host 'Getting logs'
If (!(Test-Path $esLogsPath)) {
    $esLogsPath = $esHomePath+'\'+$esLogsPath
    If (!(Test-Path $esLogsPath)) {
        Write-Host `nCould not get your elasticsearch logs.  Please add your logs directory to the $outputDir+'.zip' or to your ticket.`n`n
        $esLogsPath = ''
    }
}

If ($esLogsPath) {
    mkdir $outputDir\logs | Out-Null
    cp $esLogsPath\*.log $outputDir\logs\
}

# API calls that work with all versions
Write-Host 'Getting version'
Invoke-WebRequest $esHost -OutFile $outputDir/version.json

Write-Host "Getting _mapping"
Invoke-WebRequest $esHost'/_mapping?pretty' -OutFile $outputDir/mapping.json

Write-Host 'Getting _settings'
Invoke-WebRequest $esHost'/_settings?pretty' -OutFile $outputDir/settings.json

Write-Host 'Getting _cluster/settings'
Invoke-WebRequest $esHost'/_cluster/settings?pretty' -OutFile $outputDir/cluster_settings.json

Write-Host 'Getting _cluster/state'
Invoke-WebRequest $esHost'/_cluster/state?pretty' -OutFile $outputDir/cluster_state.json

Write-Host 'Getting _cluster/stats'
Invoke-WebRequest $esHost'/_cluster/stats?pretty&human' -OutFile $outputDir/cluster_stats.json

Write-Host 'Getting _cluster/health'
Invoke-WebRequest $esHost'/_cluster/health?pretty' -OutFile $outputDir/cluster_health.json

Write-Host 'Getting _cluster/pending_tasks'
Invoke-WebRequest $esHost'/_cluster/pending_tasks?pretty&human' -OutFile $outputDir/cluster_pending_tasks.json

Write-Host 'Getting _count'
Invoke-WebRequest $esHost'/_count?pretty' -OutFile $outputDir/count.json

Write-Host 'Getting nodes info'
Invoke-WebRequest $esHost'/_nodes/?all&pretty&human' -OutFile $outputDir/nodes.json

Write-Host 'Getting _nodes/hot_threads'
Invoke-WebRequest $esHost'/_nodes/hot_threads?threads=10' -OutFile $outputDir/nodes_hot_threads.txt

# API calls that only work with 0.90
If ($esVersion.StartsWith("0.9")) {
    Write-Host 'Getting _nodes/stats'
    Invoke-WebRequest $esHost'/_nodes/stats?all&pretty&human' -OutFile $outputDir/nodes_stats.json

    Write-Host 'Getting indices stats'
    Invoke-WebRequest $esHost'/_stats?all&pretty&human' -OutFile $outputDir/indices_stats.json
# API calls that only work with 1.0+
} Else {
    Write-Host 'Getting _nodes/stats'
    Invoke-WebRequest $esHost'/_nodes/stats?field=*&pretty&human' -OutFile $outputDir/nodes_stats.json

    Write-Host 'Getting indices stats'
    Invoke-WebRequest $esHost'/_stats?field=*&pretty&human' -OutFile $outputDir/indices_stats.json

    Write-Host 'Getting _cat/allocation'
    Invoke-WebRequest $esHost'/_cat/allocation?v' -OutFile $outputDir/allocation.txt

    Write-Host 'Getting _cat/plugins'
    Invoke-WebRequest $esHost'/_cat/plugins?v' -OutFile $outputDir/plugins.txt

    Write-Host 'Getting _cat/shards'
    Invoke-WebRequest $esHost'/_cat/shards?v' -OutFile $outputDir/cat_shards.txt

    # API calls that only work with 1.1+
    If (-Not $esVersion.StartsWith("1.0")) {
        Write-Host 'Getting _recovery'
        Invoke-WebRequest $esHost'/_recovery?detailed&pretty&human' -OutFile $outputDir/recovery.json
    # API calls that only work with 1.0
    } Else {
        Write-Host 'Getting _cat/recovery'
        Invoke-WebRequest $esHost'/_cat/recovery?v' -OutFile $outputDir/cat_recovery.txt
    }
}

Write-Host 'Running netstat'
netstat | Out-File $outputDir/netstat.txt

Write-Host 'Running top'
ps | sort -desc cpu | select -first 30 | Out-File $outputDir/top.txt

Write-Host 'Running ps'
Get-Process -Name *elasticsearch* | Out-File $outputDir/elasticsearch-process.txt

Write-Host 'Output complete.  Creating zip.'
Add-Type -Assembly System.IO.Compression.FileSystem
$compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
If ($nc) {
    $compressionLevel = [System.IO.Compression.CompressionLevel]::NoCompression
}
$zipFile = $outputDir+'.zip'
$source = $pwd.Path+'\'+$outputDir
$destination = $pwd.Path+'\'+$zipFile
If ($o) {
    $source = $outputDir
    $destination = $zipFile
}
[System.IO.Compression.ZipFile]::CreateFromDirectory($source, $destination, $compressionLevel, $false)

Write-Host `nDone.  Created $zipFile`n`n
