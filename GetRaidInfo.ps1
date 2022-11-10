[CmdletBinding()]
param (
    [Parameter(ParameterSetName='RSTeBranch' , Mandatory=$true)] [switch] $RSTe,
    [Parameter(ParameterSetName='StorCLIBranch' , Mandatory=$true)] [switch] $StorCLI,
    [Parameter(ParameterSetName='SoftRAIDBranch' , Mandatory=$true)] [switch] $SoftRAID,
    [Parameter(ParameterSetName='SoftRAIDBranch' , Mandatory=$true)] [char] $DriveLetter,
    
    [parameter(ParameterSetName='RSTeBranch' , Mandatory=$true , ValueFromPipeline=$true)] 
        [parameter(ParameterSetName='StorCLIBranch' , Mandatory=$true , ValueFromPipeline=$true)] 
        [AllowEmptyString()] [string] $sFromStdIn  
); 

Begin {
    # Executes once before first item in pipeline is processed
    Class CRAIDInfo {
        [long] $Size; 
        [bool] $State; 
        [string] $SizeHuman; 

        CRAIDInfo(){
            $this.SizeHuman = "UNKNOWN"; 
            $this.Size = 0 ; 
            $this.State = $null ; 
        }

        [long] SetSize ([long] $in){
            $local:Suffix="";
#            $local:lIn = $in;  

            $this.Size = $in;

            if ($in -ge 1024){ $in = $in -shr 10; $local:Suffix = 'KB'; }
            if ($in -ge 1024){ $in = $in -shr 10; $local:Suffix = 'MB'; }
            if ($in -ge 1024){ $in = $in -shr 10; $local:Suffix = 'GB'; }
            if ($in -ge 1024){ $in = $in -shr 10; $local:Suffix = 'TB'; }

            $this.SizeHuman = ('{0} {1}' -f $in, $local:Suffix); 

            return $this.Size ;
        }

        [string] SetSizeHuman([string] $in) {
            if ($in -match '^([0-9.]+)\s*(\w*).*$') {
                $multiplies = 1 ; 
                $this.SizeHuman = ('{0} {1}' -f $Matches[1], $Matches[2]); 
                switch ( $Matches[2] ) {
                    'TB' { $multiplies = 1024 * 1024 * 1024 * 1024 }
                    'GB' { $multiplies = 1024 * 1024 * 1024 }
                    'MB' { $multiplies = 1024 * 1024 }
                    'KB' { $multiplies = 1024 }
                    Default { $multiplies = 1 }
                }
                $this.Size = $multiplies * [System.Convert]::ToDecimal(($Matches[1]).Replace('.', ',')) ; 
            } else {
                $this.Size = 0 ; 
                $this.SizeHuman = "UNKNOWN" ; 
            }
            return $this.SizeHuman ; 
        }
        [bool] SetState([string] $in){
            switch ( $in ) {
                'Healthy' { $this.State = $true ; }
                'Optimal' { $this.State = $true ; }
                'Normal'  { $this.State = $true ; }
                'Optl'    { $this.State = $true ; }
                'Onln'    { $this.State = $true ; }
                Default { $this.State = $false ; }
            }
            return $this.State ; 
        }
    } ; 

    Class CRAIDDiskInfo : CRAIDInfo {
        [string] $ID; 
        [string] $Type; 
        [string] $Model;
        [string] $SerialNumber; 

        CRAIDDiskInfo([string] $sID=""){
            $this.ID = $sID; 
            $this.Type = ""; 
            $this.Model = ""; 
            $this.SerialNumber = "";             
        }
    } ; 

    Class CRAIDVolumeInfo : CRAIDInfo {
        [string] $Name; 
        [int] $RaidLevel; 
        [System.Collections.ArrayList] $RAIDDiskInfo; 

        CRAIDVolumeInfo(){
            $this.Name = ""; 
            $this.RaidLevel = 0; 
            $this.RAIDDiskInfo = New-Object System.Collections.ArrayList($null) ;
        }
    }; 

    [bool] $fVolPart = $false; 
    [bool] $fDiskPart = $false; 
    [System.Collections.ArrayList] $RAIDVolumeInfo = New-Object System.Collections.ArrayList($null); 
    [string] $InData = ""; 
}

Process {
    $InData += "$_`n"; 
}

End {    
    # Executes once after last pipeline object is processed
    if ($RSTe) {
        # Executes once for each pipeline object
        foreach ($swp in $InData.Split("`n")) {
            if ($swp -like '--VOLUME INFORMATION--') {
                $fVolPart = $true; 
                $fDiskPart = $false; 
                $curVolObj = [CRAIDVolumeInfo]::new(); 
                $RAIDVolumeInfo.Add($curVolObj) | Out-Null; 
            }
            elseif ($swp -like '--DISKS IN VOLUME:*') {
                $fVolPart = $false; 
                $fDiskPart = $true; 
            }
            elseif ($fVolPart) {
                if ($swp -match '^Name:\s*(.+)$') {
                    $curVolObj.Name = $Matches[1]; 
                }
                elseif ($swp -match '^Raid Level:\s*(\d+).*$') {
                    $curVolObj.RaidLevel = [System.Convert]::ToInt32( $Matches[1]); 
                }
                elseif ($swp -match '^Size:\s*(.*)$') {
                    $curVolObj.SetSizeHuman($Matches[1]) | Out-Null; 
                }
                elseif ($swp -match '^State:\s*(\w+).*$') {
                    $curVolObj.SetState($Matches[1]) | Out-Null; 
                }
            }
            elseif ($fDiskPart) {
                if ($swp -match '^ID:\s*([-\d]+).*$') {
                    $curDiskObj = [CRAIDDiskInfo]::new($Matches[1]); 
                    $curVolObj.RAIDDiskInfo.Add($curDiskObj) | Out-Null;
                }
                elseif ($swp -match '^Disk Type:\s*(\w+).*$') {
                    $curDiskObj.Type = $Matches[1]; 
                }
                elseif ($swp -match '^State:\s*(\w+).*$') {
                    $curDiskObj.SetState( $Matches[1] ) | Out-Null; 
                }
                elseif ($swp -match '^Size:\s*(.*)$') {
                    $curDiskObj.SetSizeHuman($Matches[1]) | Out-Null; 
                }
                elseif ($swp -match '^Serial Number:\s*(.*)$') {
                    $curDiskObj.SerialNumber = $Matches[1] ; 
                }
                elseif ($swp -match '^Model:\s*(.*)$') {
                    $curDiskObj.Model = $Matches[1] ; 
                }
            }
        }
    }
    elseif ($StorCLI) {
        #
        foreach ($ctrlJSON in ($InData | ConvertFrom-Json).Controllers) {
            $Volumes = (($ctrlJSON.'Response Data') | Get-Member | Select-Object -Property name | Where-Object -Property name -like '/c*/v*').name ; 
            $PDforVD = (($ctrlJSON.'Response Data') | Get-Member | Select-Object -Property name | Where-Object -Property name -like 'PDs for VD*').name ; 
            $VDprop = (($ctrlJSON.'Response Data') | Get-Member | Select-Object -Property name | Where-Object -Property name -like 'VD* Properties').name ; 
                
            foreach ($curVolume in $Volumes) {
                if ($curVolume -match '^/c\d+/v(\d+)') {
                    $curVolumeNum = $Matches[1]; 
                    $curPDforVD = ("PDs for VD {0}" -f $curVolumeNum); 
                    $curVDprop = ("VD{0} Properties" -f $curVolumeNum); 

                    $curVolObj = [CRAIDVolumeInfo]::new(); 
                    $RAIDVolumeInfo.Add($curVolObj) | Out-Null; 
                        
                    $curVolObj.Name = $ctrlJSON.'Response Data'."$curVolume".Name; 
                    $curVolObj.SetState($ctrlJSON.'Response Data'."$curVolume".State) | Out-Null; 

                    switch ($ctrlJSON.'Response Data'."$curVolume".TYPE) {
                        "RAID10" { $curVolObj.RaidLevel = 10 }
                        "RAID1" { $curVolObj.RaidLevel = 1 }
                        Default { $curVolObj.RaidLevel = 0 }
                    }
                    $curVolObj.SetSizeHuman($ctrlJSON.'Response Data'."$curVolume".Size) | Out-Null; 
                    foreach ($curPD in $ctrlJSON.'Response Data'."$curPDforVD") {
                        $curDiskObj = [CRAIDDiskInfo]::new($curPD."EID:Slt"); 
                        $curVolObj.RAIDDiskInfo.Add($curDiskObj) | Out-Null;
                        $curDiskObj.SetSizeHuman($curPD.Size) | Out-Null; 
                        $curDiskObj.SetState($curPD.State) | Out-Null; 
                        $curDiskObj.Model = $curPD.Model ; 
                        $curDiskObj.Type = ('{0}/{1}' -f $curPD.Med, $curPD.Intf) ; 
                        $curDiskObj.SerialNumber = "UNKNOWN" ; 
                    }
                }
            }
        }
    }
    elseif ($SoftRAID) {
        $curVolObj = [CRAIDVolumeInfo]::new(); 
        $RAIDVolumeInfo.Add($curVolObj) | Out-Null; 

        [Reflection.Assembly]::LoadWithPartialName("Microsoft.Storage.Vds") | Out-Null; 
        $VdsServiceLoader = New-Object Microsoft.Storage.Vds.ServiceLoader ; 
        $VdsService = $VdsServiceLoader.LoadService($null) ; 
        $VdsService.WaitForServiceReady(); 
        $vdsVolume = $VdsService.Providers  | ForEach-Object {$_.packs} | ForEach-Object {$_.volumes} | Where-Object -Property DriveLetter -Like $DriveLetter; 

        $curVolObj.Name = $vdsVolume[0].Label ; 
        $curVolObj.SetState($vdsVolume[0].Health) | Out-Null; 

        $curVolObj.SetSize($vdsVolume[0].Size) | Out-Null;

        switch ($vdsVolume[0].Type) {
            'Mirror' { $curVolObj.RaidLevel = 1; }
            'Simple' { $curVolObj.RaidLevel = 0; }
            Default { $curVolObj.RaidLevel = 0 }
        }
    }
 
    $RAIDVolumeInfo ; 
}