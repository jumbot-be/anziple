Note: always use Git Bash/ MinGW64 (for .sh) or CMD as Admin (for .bat)

Prerequisites:
0. On Linux the default install (unzip) directory for bundle is /opt/adr2 (C:\adr2\ on Windows). Navigate to this directory and enter the just-extracted "nginx" dir.
1. Create or edit your profile (called [PROFILE-NAME]) and place it profiles/[PROFILE-NAME]
2. Launch <prepare-config.sh> [PROFILE-NAME] to filter the resources from resources/ to generated/

Install NGINX on WINDOWS:
    8.1 In GitBash - Launch <nginx-1--setup-windows.sh> to install and configure NGINX
        An Nginx distribution will be installed.

    8.x If applicable: replace certificates from nginx/certs with production one. Eventually modify ampacimon.conf accordingly.
        or use <nginx-X--create-selfsigned-windows.sh> to provision test certificates in your nginx installation

    8.2 in CMD Launch <nginx-2--install-service.bat> to create or recreate nginx (ADR Proxy-nginx) service
        If install and start are successfull then it should be correctly. Check console output and nginx/logs if any issue.
    
Configure NGINX on LINUX:
    8.1 Launch <nginx-1--setup-linux.sh> to configure NGINX ampacimon virtual host.
        NO Nginx distribution will be installed. It is required to install it manually with APT or similar.

    8.x If applicable: replace certificates from /etc/nginx/certs with production one. Eventually modify ampacimon.conf accordingly.
        or use <nginx-X--create-selfsigned-linux.sh> to provision test certificates in your nginx installation

    8.2 Restart your nginx service.
    
