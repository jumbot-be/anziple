@echo off
echo Setting up Windows prerequisites for Ansible managed node...

:: Check for Administrative privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Administrative permissions confirmed.
) else (
    echo Please run this script as Administrator.
    pause
    exit /B 1
)

:: Check for Git
where git >nul 2>&1
if %errorLevel% == 0 (
    echo Git is already installed.
) else (
    echo Git not found. It will be installed by the Ansible 'common' role using Chocolatey.
)

:: Enable WinRM for Ansible
echo Enabling WinRM...
powershell.exe -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $url = 'https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1'; $file = \"$env:temp\ConfigureRemotingForAnsible.ps1\"; (New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file); powershell.exe -ExecutionPolicy Raw -File $file"

echo Windows setup complete.
pause
