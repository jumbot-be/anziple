#!/bin/bash

# Cleanup script to remove Java configuration and installations on Linux

echo "Removing /etc/profile.d/java.sh..."
sudo rm -f /etc/profile.d/java.sh

echo "Removing JAVA_HOME from /etc/environment..."
sudo sed -i '/^JAVA_HOME=/d' /etc/environment

echo "Removing JAVA_HOME and Java PATH from /etc/bash.bashrc..."
sudo sed -i '/^export JAVA_HOME=/d' /etc/bash.bashrc
sudo sed -i '/^export PATH=.*zulu/d' /etc/bash.bashrc

echo "Removing extracted Zulu JDK from /opt/adr..."
sudo rm -rf /opt/adr/zulu*

echo "Removing temporary JDK archives from /tmp..."
sudo rm -f /tmp/zulu*.tar.gz

echo "Java configuration cleanup complete."

