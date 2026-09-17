#!/usr/bin/env python3
import re
import sys
import yaml
import os
import argparse

def parse_checksums(content, base_url, apcm_version_from_path):
    artifacts = {}
    versions = {"apcm_version": apcm_version_from_path}

    # regex for sha256sum format: hash *./path/to/file
    pattern = re.compile(r'^([a-fA-F0-9]{64})\s+\*?\./(.*)$')

    for line in content.splitlines():
        match = pattern.match(line.strip())
        if not match:
            continue

        checksum, filepath = match.groups()
        filename = os.path.basename(filepath)

        # Component Mapping Logic
        key = None
        if "payara" in filename:
            key = "payara"
            v_match = re.search(r'apcm-payara-bundle-(.*)-payara-bundle\.zip', filename)
            if v_match: versions['payara_bundle_version'] = v_match.group(1)

        elif "keycloak" in filename:
            if "RedHat" in filename:
                key = "keycloak_rh"
            else:
                key = "keycloak_standard"
            v_match = re.search(r'apcm-keycloak-bundle-(.*)-Keycloak', filename)
            if v_match: versions['keycloak_bundle_version'] = v_match.group(1)

        elif "nginx" in filename:
            key = "nginx"
            v_match = re.search(r'apcm-nginx-bundle-(.*)-nginx-bundle\.zip', filename)
            if v_match: versions['nginx_bundle_version'] = v_match.group(1)

        elif "zulu" in filename:
            # Determine if it's front or back JDK
            if "jdk/front/" in filepath:
                jdk_type = "front_"
            elif "jdk/back/" in filepath:
                jdk_type = "back_"
            else:
                jdk_type = ""

            if "linux" in filename:
                key = f"jdk_{jdk_type}linux"
            elif "win" in filename:
                key = f"jdk_{jdk_type}windows"

        elif "adg-server" in filename:
            key = "adg_server"
            v_match = re.search(r'apcm-adg-server-war-(.*)\.war', filename)
            if v_match and (not versions.get("apcm_version") or versions.get("apcm_version") == "REPLACE_ME"):
                versions['apcm_version'] = v_match.group(1)

        elif "apcm-server" in filename:
            key = "apcm_server"

        elif "explorer-ear" in filename:
            key = "explorer_ear"

        elif "rest-api" in filename:
            key = "rest_api"

        elif "otap-server" in filename:
            key = "otap_server"

        if key:
            # Use POSIX-style join for URLs regardless of OS
            url = base_url.rstrip('/') + '/' + filepath.lstrip('./')
            artifacts[key] = {
                "name": filename,
                "url": url,
                "checksum": f"sha256:{checksum}"
            }

    return versions, artifacts

def main():
    parser = argparse.ArgumentParser(description="Generate release variables from a checksum file.")
    parser.add_argument("checksum_file", nargs="?", help="Path to the checksum file. If not provided, reads from stdin.")
    parser.add_argument("--base-url", help="Base URL or path for artifacts. Defaults to the directory of the checksum file.")

    args = parser.parse_args()

    apcm_version_from_path = "REPLACE_ME"
    base_url = args.base_url

    if args.checksum_file:
        if not os.path.exists(args.checksum_file):
            print(f"Error: File {args.checksum_file} not found.")
            sys.exit(1)

        # Try to extract version from path like /opt/SOURCES/ADR-3.1.1/checksums
        abs_path = os.path.abspath(args.checksum_file)
        path_parts = abs_path.split(os.sep)
        for part in path_parts:
            if "ADR-" in part:
                apcm_version_from_path = part.replace("ADR-", "")
                break

        if not base_url:
            base_url = os.path.dirname(abs_path)

        with open(args.checksum_file, 'r') as f:
            content = f.read()
    else:
        if sys.stdin.isatty():
            parser.print_help()
            sys.exit(1)
        content = sys.stdin.read()
        if not base_url:
            base_url = "/opt/SOURCES/ADR-REPLACE_ME"

    versions, artifacts = parse_checksums(content, base_url, apcm_version_from_path)

    output = {
        "apcm_version": versions.get("apcm_version", "REPLACE_ME"),
        "payara_bundle_version": versions.get("payara_bundle_version", "REPLACE_ME"),
        "keycloak_bundle_version": versions.get("keycloak_bundle_version", "REPLACE_ME"),
        "nginx_bundle_version": versions.get("nginx_bundle_version", "REPLACE_ME"),
        "keycloak_flavor": "rh",
        "mongodb_version": "8.0.16",
        "artifacts": artifacts
    }

    print(yaml.dump(output, sort_keys=False, default_flow_style=False))

if __name__ == "__main__":
    main()
