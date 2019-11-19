function Get-StoredCredential($ComputerName) {
  $ComputerName = $ComputerName -replace "::", "_"
  Import-Clixml -Path "secrets/$ComputerName.clixml"
}

function Host {
  param(
    [Parameter(Mandatory, Position = 1)]
    [string] $ComputerName,
    [Parameter(Mandatory, Position = 2)]
    [scriptblock]$ScriptBlock
  )
  Write-Verbose "Host '$ComputerName'"
  Write-Verbose "ScriptBlock: '$($ScriptBlock.ToString())'"
  Describe "Host '$ComputerName'" {
    $global:t_ica = @{
      ComputerName = $ComputerName
      Credential   = Get-StoredCredential $ComputerName
    }
    $ScriptBlock.Invoke()
  }
}

function Services {
  param(
    [Parameter(Mandatory, Position = 1)]
    [scriptblock]$Services
  )
  $serviceNames = $Services -split " " | ForEach-Object { 
    $v = $_.Trim(); if ( $v) { $v }
  }
  $serviceNames | Foreach-Object { 
    Write-Verbose "check service $_ " 
    It "has service '$_' installed and running" {
      $s = Invoke-Command @global:t_ica -ScriptBlock {
        param($svc)
        Get-Service -Name $svc
      } -ArgumentList $_
      $s | Should -Not -BeNullOrEmpty
      $s.Status | Should -Be "Running"
    }
  }
}

function Chocolatey {
  param(
    [Parameter(Mandatory, Position = 1)]
    [scriptblock]$Packages
  )
  $pkgs = $Packages -split " " | ForEach-Object {
    $v = $_.Trim(); if ( $v) { $v }
  }
  
  It "has no packages in lib-bad" {
    Invoke-Command @global:t_ica -ScriptBlock {
      (Get-ChildItem "C:\ProgramData\chocolatey\lib-bad").Count
    } | Should -Be 0
  }
  $allPkgs = Invoke-Command @t_ica -ScriptBlock {
    (Get-ChildItem "C:\ProgramData\chocolatey\lib").Name
  }
  $pkgs | Foreach-Object {
    Write-Verbose "check choco pkg $_ "
    It "has chocolatey package '$_' installed" {
      $_ | Should -BeIn $allPkgs
    }
  }
}