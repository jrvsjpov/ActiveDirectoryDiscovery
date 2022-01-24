# Get admin groups membership from the current domain. Note if running in a child domain
# you will get a failure for the enterprise admin group.
function Get-ADNestedGroupMembers {
    [cmdletbinding()]
    param ( [String] $Group )            
    Import-Module ActiveDirectory
    $Members = Get-ADGroupMember -Identity $Group -Recursive
    $members
    }
  
# Main
  $TargetGroups = "Domain Admins","Enterprise Admins","Administrators"
  $CurrentDomain = $env:USERDOMAIN.ToUpper()
  $ReportFile = ".\" + $currentDOmain + "_Adm_Report.csv"
  
  foreach ($x in $TargetGroups) {
      try   {
            $ADGroup = $x
            Get-ADGroup $ADGroup | Select-Object Name
            $ReportFile = ".\" + $currentDomain + "_" + $ADGroup +"_Report.csv"
            Get-ADNestedGroupMembers $x | Select-Object Name,DistinguishedName,objectclass |
            Export-CSV $ReportFile -NoTypeInformation -Encoding UTF8
            }
            catch
            {
            $ADGroup + " group doesn't exist"
            }
  }