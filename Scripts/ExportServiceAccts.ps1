# Scans windows servers in a domain and exports any services running under service accounts
# Uses the current domain as the target
#
$maxThreads = 10
$currentDomain = $env:USERDOMAIN.ToUpper()
$ReportFile = ".\" + $currentDOmain + "_Accounts.csv"
$ErrorFile = ".\" + $currentDOmain + "_Issues.csv"
$serviceAccounts = @{}
[string[]]$warnings = @() 


$readServiceAccounts = {

# Get list services from computer 
    param( $hostname )
    if ( Test-Connection -ComputerName $hostname -Count 3 -Quiet ){
        try {
            $serviceList = @( Get-WmiObject -Class Win32_Service -ComputerName $hostname -Property Name,StartName,SystemName -ErrorAction Stop )
            $serviceList
        }
        catch{
            "Failed to retrieve data from $hostname : $($_.toString())"
        }
    }
    else{
        "$hostname is unreachable"
    }        
}



function processCompletedJobs(){
    # reads service list from completed jobs,updates $serviceAccount table and removes completed job
            $jobs = Get-Job -State Completed
        foreach( $job in $jobs ) {
    
            $data = Receive-Job $job 
            Remove-Job $job 
            
            if ( $data.GetType() -eq [Object[]] ){
            try
            {
                $serviceList = $data | Where-Object { $_.StartName.toUpper().StartsWith( $currentDomain )}
                foreach( $service in $serviceList ){
                    $account = $service.StartName
                    $occurance = "`"$($service.Name)`" service on server $($service.SystemName)" 
                    if ( $script:serviceAccounts.Contains( $account ) ){
                        $script:serviceAccounts.Item($account) += $occurance
                    }
                    else {
                        $script:serviceAccounts.Add( $account, @( $occurance ) ) 
                    }
                }
                }
                catch
                {"...."}
            }
            elseif ( $data.GetType() -eq [String] ) {
                $script:warnings += $data
                Write-warning $data
            }
        }
    }


Import-Module ActiveDirectory

# read all enabled computer accounts from current domain
Write-Progress -Activity "Retrieving server list from domain" -Status "Processing..." -PercentComplete 0 
$serverList = Get-ADComputer -Filter {OperatingSystem -like "Windows Server*"} -Properties DNSHostName, cn | Where-Object { $_.enabled } 


# start discovery for each server in the list
$count_servers = 0
foreach( $server in $serverList ){
    Start-Job -ScriptBlock $readServiceAccounts -Name "read_$($server.cn)" -ArgumentList $server.dnshostname | Out-Null
    ++$count_servers
    Write-Progress -Activity "Retrieving data from servers" -Status "Processing..." -PercentComplete ( $count_servers * 100 / $serverList.Count )
    while ( ( Get-Job -State Running).count -ge $maxThreads ) { Start-Sleep -Seconds 3 }
    processCompletedJobs
}

# process remaining jobs 
Write-Progress -Activity "Retrieving data from servers" -Status "Waiting for background jobs to complete..." -PercentComplete 100
Wait-Job -State Running -Timeout 30  | Out-Null
Get-Job -State Running | Stop-Job
processCompletedJobs


# prepare data table for report
Write-Progress -Activity "Generating report" -Status "Please wait..." -PercentComplete 0
$accountTable = @()
foreach( $serviceAccount in $serviceAccounts.Keys )  {
    foreach( $occurance in $serviceAccounts.item($serviceAccount)  ){
        $row = new-object psobject
        Add-Member -InputObject $row -MemberType NoteProperty -Name "Service Account" -Value $serviceAccount
        Add-Member -InputObject $row -MemberType NoteProperty -Name "Process/Service and host server" -Value $occurance
        $accountTable  += $row
    }
}


# export discovery results to CSV with summary as last row
$Summary =  "Total Servers processed is " + $($serverList.count).ToString() + ". Service accounts discovered is " + $($serviceAccounts.count).ToString()
$row = new-object psobject
Add-Member -InputObject $row -MemberType NoteProperty -Name "Service Account" -Value $Summary
$accountTable  += $row
Write-Progress -Activity "Exporting Service account data" -Status "Please wait..." -Completed
$accountTable | export-csv $ReportFile -NoTypeInformation


# export error data to CSV
$errors = @()
    Foreach ($er in $warnings)  {
        $row1 = new-object psobject
        Add-Member -InputObject $row1 -MemberType NoteProperty -Name "Errors" -Value $er
        $errors += $row1
    }
Write-Progress -Activity "Exporting errors" -Status "Please wait..." -Completed
$errors | export-csv .\$ErrorFile -NoTypeInformation


