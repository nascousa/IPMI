##############################################################################################
# IPMI Fan Controller
# Nate Scott
# v1.00
# BIOS Version <= v3.30.30.30
##############################################################################################

$server = "<YOUR SERVER IPv4 ADDRESS>"
$user = "<YOUR DELL SERVER IDRAC USERNAME>"
$pass = "<YOUR DELL SERVER IDRAC PASSWORD>"

Function SetFanControl($mode)
{
    if($mode -eq $true)
    {
        # enable
        Write-Host "Fan Control: Enabled`n" -ForegroundColor Green
        $cmd = ("ipmitool -I lanplus -H $server -U $user -P $pass raw 0x30 0x30 0x01 0x00")
    }else{
        # disable
        Write-Host "Fan Control: Disabled`n" -ForegroundColor Red
        $cmd = ("ipmitool -I lanplus -H $server -U $user -P $pass raw 0x30 0x30 0x01 0x01")
    }

    # Write-Host "IPMI CMD: $cmd`n"
    Invoke-Expression -Command $cmd
}

Function ChangeFanSpeed($speed, $color)
{
    Write-Host "Fan Speed: $speed%" -ForegroundColor $color
    switch($speed)
    {
        {1..10 -contains $_}{$speed='0A'}
        {11..15 -contains $_}{$speed='0F'}
        {16..20 -contains $_}{$speed='14'}
        {21..25 -contains $_}{$speed='19'}
        {26..30 -contains $_}{$speed='1E'}
        {31..35 -contains $_}{$speed='23'}
        {36..40 -contains $_}{$speed='28'}
        {41..45 -contains $_}{$speed='2d'}
        {46..50 -contains $_}{$speed='32'}
        {51..55 -contains $_}{$speed='34'}
        {56..60 -contains $_}{$speed='3C'}
        {61..65 -contains $_}{$speed='41'}
        {66..70 -contains $_}{$speed='46'}
        {71..75 -contains $_}{$speed='4B'}
        {76..80 -contains $_}{$speed='50'}
        {81..85 -contains $_}{$speed='55'}
        {86..90 -contains $_}{$speed='5A'}
        {91..95 -contains $_}{$speed='5F'}
        {96..100 -contains $_}{$speed='64'}
    }
    $cmd = ("ipmitool -I lanplus -H $server -U $user -P $pass raw 0x30 0x30 0x02 0xff 0x$speed")
    # Write-Host "IPMI CMD: $cmd`n"
    Invoke-Expression -Command $cmd
}

Function CheckServerHealth()
{
    $cmd = ("ipmitool -I lanplus -H $server -U $user -P $pass sdr elist")
    $res = Invoke-Expression -Command $cmd

    $cpuInletTemp = $($res | findstr '04h').Split('|')[4].Split(' ')[1].Trim()
    if($cpuInletTemp -ne 'no')
    {
        $cpuInletTempF = [double]$cpuInletTemp * 1.8 + 32
        Write-Host "CPU Inlet Temperature: $cpuInletTemp`C / $cpuInletTempF`F" -ForegroundColor White
    }

    $cpuExhaustTemp = $($res | findstr '01h').Split('|')[4].Split(' ')[1].Trim()
    if($cpuExhaustTemp -ne 'no')
    {
        $cpuExhaustTempF = [double]$cpuExhaustTemp * 1.8 + 32
        Write-Host "CPU Exhaust Temperature: $cpuExhaustTemp`C / $cpuExhaustTempF`F" -ForegroundColor White
    }
    
    $cpu1temp = $($res | findstr '09h').Split('|')[4].Split(' ')[1].Trim()
    if($cpu1temp -ne 'no')
    {
        $cpu2temp = $($res | findstr '06h').Split('|')[4].Split(' ')[1].Trim()
        $cpu3temp = $($res | findstr '07h').Split('|')[4].Split(' ')[1].Trim()
        $cpu4temp = $($res | findstr '08h').Split('|')[4].Split(' ')[1].Trim()
        
        $cpuMaxTemp = [double]$cpu1temp, [double]$cpu2temp, [double]$cpu3temp, [double]$cpu4temp
        $cpuMaxTemp = ($cpuMaxTemp | Measure-Object -Maximum).Maximum
        $cpuMaxTempF = [double]$cpuMaxTemp * 1.8 + 32

        $cpuAvgTemp = ([double]$cpu1temp + [double]$cpu2temp + [double]$cpu3temp + [double]$cpu4temp) / 4
        $cpuAvgTempF = [double]$cpuAvgTemp * 1.8 + 32

        Write-Host "CPU Core Temperature: Max[ $cpuMaxTemp`C / $cpuMaxTempF`F ] | Avg[ $cpuAvgTemp`C / $cpuAvgTempF`F ] | [ $cpu1temp`C | $cpu2temp`C | $cpu3temp`C | $cpu4temp`C ]" -ForegroundColor White
    }

    $fan1 = $($res | findstr '30h').Split('|')[4].Split(' ')[1].Trim()
    if($fan1 -ne 'no')
    {
        $fan2 = $($res | findstr '31h').Split('|')[4].Split(' ')[1].Trim()
        $fan3 = $($res | findstr '32h').Split('|')[4].Split(' ')[1].Trim()
        $fan4 = $($res | findstr '33h').Split('|')[4].Split(' ')[1].Trim()
        $fan5 = $($res | findstr '34h').Split('|')[4].Split(' ')[1].Trim()
        $fan6 = $($res | findstr '35h').Split('|')[4].Split(' ')[1].Trim()
        Write-Host "Fan Speed: [ $fan1 RPM | $fan2 RPM | $fan3 RPM | $fan4 RPM | $fan5 RPM | $fan6 RPM ]" -ForegroundColor White
    }

    $voltage1 = $($res | findstr '6Ch').Split('|')[4].Split(' ')[1].Trim()
    if($voltage1 -ne 'no')
    {
        $voltage2 = $($res | findstr '7Fh').Split('|')[4].Split(' ')[1].Trim()
        $voltage3 = $($res | findstr '7Ch').Split('|')[4].Split(' ')[1].Trim()
        $voltage4 = $($res | findstr '7Dh').Split('|')[4].Split(' ')[1].Trim()
        Write-Host "PSU Voltage: [ $voltage1 Volts | $voltage2 Volts | $voltage3 Volts | $voltage4 Volts ]" -ForegroundColor White
    }

    $pwr = $($res | findstr '77h').Split('|')[4].Split(' ')[1].Trim()
    Write-Host "Power Consumption: $pwr Watts`n" -ForegroundColor White

    return $cpuMaxTemp
}

Function KillHighCPU()
{
    # Get all cores, which includes virtual cores from hyperthreading
    $cores = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors

    # Get all process with there ID's excluding process you can't stop
    $processes = ((Get-Counter "\Process(*)\ID Process").CounterSamples).Where({$_.InstanceName -notin "idle","_total","system"})
    
    # Get cpu time for all process
    $cputime = $processes.Path.Replace("id process", "% Processor Time") | Get-Counter | Select-Object -ExpandProperty CounterSamples

    #Get the process with above 14% utilistaion
    $highUsage = $cputime.Where({[Math]::round($_.CookedValue / $cores,2) -gt 14})

    # For each high usage process, grab it's process ID from the processes list, by matching on the relevant part of the path
    $highUsage |%{
        $path = $_.Path
        $id = $processes.Where({$_.Path -like "*$($path.Split('(')[1].Split(')')[0])*"}) | Select-Object -ExpandProperty CookedValue
        # Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

Function Run()
{
    [System.Console]::Clear()
    # Invoke-Expression -Command "ipmitool -I lanplus -H $server -U $user -P $pass chassis power on"

    SetFanControl $true

    While($true)
    {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        Write-Host "Dell PowerEdge Server [R930] - $timestamp" -ForegroundColor Yellow

        $cpuAvgTemp = CheckServerHealth

        # E7-8890v4 Max CPU temperature is Tcase(79c)
        # https://www.intel.com/content/www/us/en/products/sku/93790/intel-xeon-processor-e78890-v4-60m-cache-2-20-ghz/specifications.html
        switch([int]$cpuAvgTemp)
        {
            {1..33 -contains $_}{ChangeFanSpeed 10 Cyan}
            {34..37 -contains $_}{ChangeFanSpeed 15 Cyan}
            {38..40 -contains $_}{ChangeFanSpeed 20 Cyan}
            {41..43 -contains $_}{ChangeFanSpeed 25 Cyan}
            {44..46 -contains $_}{ChangeFanSpeed 30 Green}
            {47..49 -contains $_}{ChangeFanSpeed 35 Green}
            {50..52 -contains $_}{ChangeFanSpeed 40 Green}
            {53..54 -contains $_}{ChangeFanSpeed 45 Green}
            {55..56 -contains $_}{ChangeFanSpeed 55 Green}
            {57..58 -contains $_}{ChangeFanSpeed 60 Yellow}
            {59..60 -contains $_}{ChangeFanSpeed 65 Yellow}
            {61..62 -contains $_}{ChangeFanSpeed 70 Yellow}
            {63..64 -contains $_}{ChangeFanSpeed 75 Yellow}
            {65..66 -contains $_}{ChangeFanSpeed 80 Red}
            {67..68 -contains $_}{ChangeFanSpeed 85 Red}
            {69..70 -contains $_}{ChangeFanSpeed 90 Red}
            {71..72 -contains $_}{ChangeFanSpeed 95 Purple}
            {73..74 -contains $_}{ChangeFanSpeed 100 Purple}
            {75..999 -contains $_}{
                Write-Host "!!! TOO HOT !!! Server shutting down...`n" -ForegroundColor Purple
                Invoke-Expression -Command "ipmitool -I lanplus -H $server -U $user -P $pass chassis power off"
            }
        }

        Write-Host "------------------------------------------------------------------------------------------`n"  -ForegroundColor White
    }
}

Run
