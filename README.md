
# creating a custom DSL with PowerShell and Pester for your infrastructure tests

## why pester

=> because we already do use PowerShell to setup our hosts, drive our build-pipelines, gather statistics, rule the world, ...

## minimal example

Have some `Describe` blocks with some `It` checks inside.

```PowerShell
Describe "basic" {
  It "works" {
    1 | Should -be 1
  }
  It "fails" {
    1 | Should -be 2
  }
}
```

```PowerShell
Invoke-Pester $testFilePath
```

## testing infra with Pester

Does this provide any value?

```PowerShell
$ComputerName = "something"

Describe "host '$ComputerName'" {
  It "is reachable via Test-NetConnection" {
    (Test-NetConnection $ComputerName).PingSucceeded | Should -be $true
  }
  It "WSMan is up and running" {
    Test-WSMan $ComputerName | Should -Not -BeNullOrEmpty
  }
}
```

How about this?

```PowerShell
Describe "host '$ComputerName'" {
  It "has no failed Chocolatey installs" {
    Invoke-Command -ComputerName $ComputerName -Credential $creds -ScriptBlock {
      Get-ChildItem "C:\ProgramData\chocolatey\lib-bad"
    } | Should -BeNullOrEmpty
  }
}
```

Notice we need (probably) to pass some `-Credential` object!

We probably have more than one sever/host ...

```PowerShell
$ComputerNames = @("localhost", "127.0.0.1", "::1")

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
```

Checking for broken Chocolatey packages sure is nice, but what about service status?

```PowerShell
$ComputerNames = @("localhost", "127.0.0.1", "::1")
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
```

By now this is getting messy to look at, we can do better with DSL!

how about something like this, what is the intend of this code?

```PowerShell
Host "localhost" {
  Services { WinRM }
  Chocolatey { Firefox notepadplusplus }
}
Host "ServerX" {
  Services { IISManager ChocolateyAgent }
  Chocolatey { Firefox }
}
Host "ServerY" {
  Services { IISManager }
  Chocolatey { Firefox }
}
```

Let's see how this is possible, focusing on the 'inner' bits, as "Host" is basically equivalent to a "Describe" block.

```PowerShell
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
```

With the following "DSL-helpers", we can now create Pester test definitions like this:

```PowerShell
Describe "some basic DSL goodies on localhost" {
  Services { WinRM WSearch }
  Chocolatey { Firefox notepadplusplus powershell }
}
```

Yet, what we actually want to do is:

```PowerShell
Host "ServerX" {
  Services { IISManager ChocolateyAgent }
  Chocolatey { Waterfox }
}
Host "ServerY" {
  Services { IISManager }
  Chocolatey { Firefox }
}
```
