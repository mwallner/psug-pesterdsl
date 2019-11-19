$mytestname = Join-Path $PSScriptRoot "mytest.Test.ps1"

# NOTE: this needs to be in context of the generated tests!
function Get-StoredCredential($ComputerName) {
  $ComputerName = $ComputerName -replace "::", "_"
  Import-Clixml -Path "secrets/$ComputerName.clixml"
}
# $(Get-Credential) | Export-Clixml "$ComputerName.clixml"


## basic example
{
  $test = {

    Describe "basic" {
      It "works" {
        1 | Should -be 1
      }
      It "fails" {
        1 | Should -be 2
      }
    }

  }

  $test.ToString() | Out-File $mytestname
  Invoke-Pester $mytestname
}
 
## testing network connectivity
{
  $test = {
    $ErrorActionPreference = "Stop"
    $ComputerName = "localhost"

    Describe "host '$ComputerName'" {
      It "is reachable via Test-NetConnection" {
        (Test-NetConnection $ComputerName).PingSucceeded | Should -be $true
      }
      It "WSMan is up and running" {
        Test-WSMan $ComputerName | Should -Not -BeNullOrEmpty
      }
    }
  }

  $test.ToString() | Out-File $mytestname
  Invoke-Pester $mytestname
}

## checking for broken package installs
{
  $test = {
    $ErrorActionPreference = "Stop"
    $ComputerName = "localhost"
    $creds = Get-StoredCredential $ComputerName
      
    Describe "host '$ComputerName'" {
      It "has no failed Chocolatey installs" {
        Invoke-Command -ComputerName $ComputerName -Credential $creds -ScriptBlock {
          Get-ChildItem "C:\ProgramData\chocolatey\lib-bad"
        } | Should -BeNullOrEmpty
      }
    }
  }

  $test.ToString() | Out-File $mytestname
  Invoke-Pester $mytestname
}



## checking for broken package installs
{
  $test = {
    $ErrorActionPreference = "Stop"
    $ComputerNames = @("localhost")

    foreach ($c in $ComputerNames) {
      $creds = Get-StoredCredential $c
      Describe "host '$c'" {
        It "has no failed Chocolatey installs" {
          Invoke-Command -ComputerName $c -Credential $creds -ScriptBlock {
            Get-ChildItem "C:\ProgramData\chocolatey\lib-bad"
          } | Should -BeNullOrEmpty
        }
      }
    }
  }

  $test.ToString() | Out-File $mytestname
  Invoke-Pester $mytestname
}


## checking if some service(s) are running
{
  $test = {
    $ErrorActionPreference = "Stop"
    $ComputerNames = @("localhost")
    $Services = @("WinRm")

    foreach ($c in $ComputerNames) {
      $creds = Get-StoredCredential $c
      Describe "host '$c'" {
        foreach ($s in $Services) {
          It "has service '$s' installed and running" {
            Invoke-Command -ComputerName $c -Credential $creds -ScriptBlock {
              param($s)
              (Get-Service $s).Status
            } -ArgumentList $s | Should -Be "Running"
          }
        }
      }
    }
  }

  $test.ToString() | Out-File $mytestname
  Invoke-Pester $mytestname
}

## DSL - draft #1
{
  $test = {
    function Services {
      param(
        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$Services
      )
      $serviceNames = $Services -split " " | ForEach-Object { if ($_) { $_ } }
      $serviceNames | Foreach-Object { 
        Write-Verbose "check service $_ " 
        It "has service '$_' installed and running" {
          $s = (Get-Service -Name $_)
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
      $pkgs = $Packages -split " " | ForEach-Object { if ($_) { $_ } }
      
      It "has no packages in lib-bad" {
        (Get-ChildItem "C:\ProgramData\chocolatey\lib-bad").Count | Should -Be 0
      }
      $allPkgs = (choco list -lo -r) | ForEach-Object { $_.Split("|")[0] }
      $pkgs | Foreach-Object { 
        Write-Verbose "check choco pkg $_ "
        It "has chocolatey package '$_' installed" {
          $allPkgs | Should -Contain $_
        }
      }
    }

    Describe "some basic DSL goodies on localhost" {
      Services { WinRM WSearch }
      Chocolatey { Firefox notepadplusplus } 
    }
  }

  $test.ToString() | Out-File $mytestname
  Invoke-Pester $mytestname
}

## DSL - draft #2 (introducing remote checks with 'Host')
{
  $test = {
    # host creates a "decribe" section / scriptblock for a host
    # nested Scriptblock will be evaluated before describe section is returned
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
      $serviceNames = $Services -split " " | ForEach-Object { if ($_) { $_ } }
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
      $pkgs = $Packages -split " " | ForEach-Object { if ($_) { $_ } }
      
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

    Host "localhost" {
      Services { WinRM WSearch }
      Chocolatey { FiraCode vscode gnuwin32-coreutils.install notepadplusplus }
    }
    Host "ServerX" {
      Services { IISManager ChocolateyAgent }
      Chocolatey { Firefox }
    }
    Host "ServerY" {
      Services { IISManager }
      Chocolatey { Firefox }
    }
  }
  
  $test.ToString() | Out-File $mytestname
  Invoke-Pester $mytestname
}

## DSL - adding groups / categories

## rubbing a little CI on the mix
