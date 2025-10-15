#!/bin/bash

# ==========================================================
# Script de Configuración de Balanceo de Carga (balancer.sh)
# DEBE EJECUTARSE CON: sudo ./balancer.sh
# ==========================================================
# Detener el script inmediatamente si un comando falla
set -e

# Asegúrate de que las tablas 101 (ISP1_TABLES) y 102 (ISP2_TABLES) estén en /etc/iproute2/rt_tables.

echo -e "\n--- 1. Habilitando IP Forwarding y Limpiando Reglas ---"

# Habilitar IP Forwarding (Persistente y Temporal)
echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf > /dev/null
sysctl -p && echo "IP Forwarding habilitado." || { echo "FALLO al habilitar IP Forwarding."; exit 1; }

# Limpiar Cadenas (Filter, NAT, Mangle)
iptables -F && echo "Cadena filter limpiada."
iptables -t nat -F && echo "Cadena nat limpiada."
iptables -t mangle -F && echo "Cadena mangle limpiada."
iptables -X && echo "Cadenas de usuario eliminadas."



echo -e "\n--- 2. Configurando Rutas Estáticas y Tablas Personalizadas (101, 102) ---"

# Limpieza de reglas IP Rule previas
echo "Limpiando reglas IP Rule previas..."

ip route flush table ISP1_TABLES
ip route flush table ISP2_TABLES

ip rule add pref 102 table ISP2_TABLES
ip rule add pref 101 table ISP1_TABLES




     #ip rule del fwmark 1 table ISP1_TABLES 2>/dev/null || true
     #ip rule del fwmark 2 table ISP2_TABLES 2>/dev/null || true
echo "Limpieza de reglas IP Rule finalizada."

# Tabla ISP1 (Interfaces eno1)
ip route add 11.11.11.0/30 dev eno1 src 11.11.11.2 table ISP1_TABLES && echo "Ruta de red local 11.11.11.0/30 estableci>
ip route add default via 11.11.11.1 dev eno1 table ISP1_TABLES && echo "Ruta por defecto 11.11.11.1/eno1 (Tabla ISP1_TABLES) establecida."

# Tabla ISP2 (Interfaces enx00e04c36035e)
ip route add 11.11.12.0/30 dev enx00e04c36035e src 11.11.12.2 table ISP2_TABLES && echo "Ruta de red local 11.11.12.0/3>
ip route add default via 11.11.12.1 dev enx00e04c36035e table ISP2_TABLES && echo "Ruta por defecto 11.11.12.1/enx00e04c36035e (Tabla ISP2_TABLES) establecida."

# Ruta para la red interna (172.16.3.0/30) en la tabla principal
ip route add 172.16.3.0/30 dev enx00e04c360357 src 172.16.3.2 && echo "Ruta de red LAN (172.16.3.0/30) establecida."

# **RUTA POR DEFECTO DE LA TABLA MAIN (ISP2 por defecto, el 'catch-all'):**
# Esta será manipulada por check_link.sh para el failover.
ip route add default via 11.11.12.1 dev enx00e04c36035e metric 100 && echo "Ruta por defecto (main/ISP2) establecida."



echo -e "\n--- 3. Configurando NAT (MASQUERADE) ---"

# NAT para ISP1 (eno1)
iptables -t nat -A POSTROUTING -o eno1 -j MASQUERADE && echo "NAT MASQUERADE para eno1 (ISP1) establecida."

# NAT para ISP2 (enx00e04c36035e)
iptables -t nat -A POSTROUTING -o enx00e04c36035e -j MASQUERADE && echo "NAT MASQUERADE para enx00e04c36035e (ISP2) establecida."



echo -e "\n--- 4. Configurando Marcado de Tráfico (fwmark) en la cadena MANGLE ---"

# ISP1: Tráfico http y https (puertos 80, 443) -> Marca 1
iptables -t mangle -A PREROUTING -i enx00e04c360357 -p tcp -m multiport --dports 80,443 -j MARK --set-mark 1 && echo "Regla: HTTP/S (443, 80) -> Marca 1 (ISP1)."

# Cliente 192.168.1.2 SSH (puerto 22) -> Marca 2
# Nota: La IP 192.168.1.2 es de ejemplo. Asume que está en la red 172.16.3.0/30.
iptables -t mangle -A PREROUTING -i enx00e04c360357 -s 172.16.3.2 -p tcp --dport 22 -j MARK --set-mark 2 && echo "Regla: Cliente 192.168.1.2 SSH (22) -> Marca 2 (ISP2)."

# Evitar remarcar paquetes ya marcados y continuar
iptables -t mangle -A PREROUTING -i enx00e04c360357 -m mark ! --mark 0 -j ACCEPT && echo "Regla: Paquetes ya marcados son aceptados."

# ISP2: Resto del tráfico por defecto -> Marca 2 (Asume ISP2 como la ruta principal)
iptables -t mangle -A PREROUTING -i enx00e04c360357 -j MARK --set-mark 2 && echo "Regla: Tráfico restante -> Marca 2 (ISP2 por defecto)."

---

echo -e "\n--- 5. Configurando Reglas de Policy Routing (Basadas en fwmark) ---"

# Regla: Si el paquete tiene Marca 1 (ISP1), usa la tabla ISP1_TABLES
ip rule add fwmark 1 table ISP1_TABLES && echo "IP Rule de fwmark 1 (ISP1) establecida."

# Regla: Si el paquete tiene Marca 2 (ISP2), usa la tabla ISP2_TABLES
ip rule add fwmark 2 table ISP2_TABLES && echo "IP Rule de fwmark 2 (ISP2) establecida."

---

echo -e "\n--- 6. Guardando Configuración y Finalizando ---"

# Guardar reglas de iptables (Asegúrate de tener el paquete 'netfilter-persistent' o similar instalado)
iptables-save > /etc/iptables/rules.v4 && echo "Reglas IPv4 guardadas."
# ip6tables-save > /etc/iptables/rules.v6 && echo "Reglas IPv6 guardadas." # Descomentar si usas IPv6

echo -e "\n=========================================================="
echo "CONFIGURACIÓN BASE DEL BALANCEADOR TERMINADA CON ÉXITO."
echo "¡INICIE EL SCRIPT DE MONITOREO (check_link.sh) PARA EL FAILOVER!"
echo "=========================================================="
