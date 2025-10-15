#!/bin/bash

# ====================================================================
# CONFIGURACIÓN DE RED ESTÁTICA PARA EL BALANCEADOR DE CARGA
# ====================================================================

echo "Iniciando configuración de red estática para el Balanceador de Carga..."

# 1. Variables de Interfaces y Direcciones (Basado en el Diagrama)
WAN_ISP1="eno1"   # Conexión al Firewall (Enlace 1: 11.11.11.0/30)
WAN_ISP2="enx00e04c36035e"   # Conexión al Firewall (Enlace 2: 11.11.12.0/30)
LAN_PROXY="enx00e04c360357"  # Conexión al Proxy (Red: 172.16.3.0/30)

# -------------------------------------------------------------------

# 2. CONFIGURACIÓN DE /etc/network/interfaces (3 interfaces estáticas)
# Se utiliza 'tee' para escribir en el archivo con permisos de sudo.

echo "Creando archivo /etc/network/interfaces con 3 IPs estáticas..."
cat << EOL | sudo tee /etc/network/interfaces > /dev/null
# Loopback
auto lo
iface lo inet loopback

# -----------------------------------------------
# WAN INTERFACES (Conexión al Firewall/Gateways)
# -----------------------------------------------

# WAN 1 (Conexión al 11.11.11.1/30 del Firewall)
auto $WAN_ISP1
iface $WAN_ISP1 inet static
    address 11.11.11.2/30
    # No se define gateway aquí; se hará con ip route en load_balancer.sh

# WAN 2 (Conexión al 11.11.12.1/30 del Firewall)
auto $WAN_ISP2
iface $WAN_ISP2 inet static
    address 11.11.12.2/30
    # No se define gateway aquí; se hará con ip route en load_balancer.sh

# -----------------------------------------------
# LAN INTERFACE (Conexión al Proxy)
# -----------------------------------------------

# LAN (Conexión al 172.16.3.1/30 del Proxy)
auto $LAN_PROXY
iface $LAN_PROXY inet static
    address 172.16.3.2/30

EOL
echo "Configuración de interfaces completada."

# 3. CONFIGURACIÓN DE DNS EN /etc/resolv.conf
# Aunque el Balanceador usa las IPs del Firewall como GW, es buena práctica tener DNS
echo "Configurando DNS (8.8.8.8, 8.8.4.4)..."
cat << EOL | sudo tee /etc/resolv.conf > /dev/null
nameserver 8.8.8.8
nameserver 8.8.4.4
EOL

# 4. APLICAR CAMBIOS
echo "Reiniciando el servicio de red para aplicar las IPs..."
# Aplicar la configuración sin necesidad de reiniciar
sudo systemctl restart networking.service

echo "Verificando interfaces activas:"
ip addr show

echo "==========================================================="
echo "¡Configuración de red estática del Balanceador lista!"
echo "Siguiente paso: Ejecutar el script 'load_balancer.sh'."
echo "==========================================================="
