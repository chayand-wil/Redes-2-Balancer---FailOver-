#!/bin/bash
# ==========================================================
# Script de Monitoreo y Failover (check_link.sh)
# Ejecutar con: sudo nohup ./check_link.sh &
# ==========================================================

# Configuración de ISPs
GW1="11.11.11.1"         # Gateway ISP1
GW2="11.11.12.1"         # Gateway ISP2
IFACE1="eno1"            # Interfaz ISP1
IFACE2="enx00e04c36035e" # Interfaz ISP2
SOURCE_IP_1="11.11.11.2" # IP local ISP1
SOURCE_IP_2="11.11.12.2" # IP local ISP2
HOST1="8.8.8.8"          # IP de prueba ISP1
HOST2="1.1.1.1"          # IP de prueba ISP2
TABLE1="ISP1_TABLES"
TABLE2="ISP2_TABLES"
MARK1="1"
MARK2="2"

# Estado inicial (0 = up, 1 = down)
ISP1_STATUS=0
ISP2_STATUS=0

# Archivo de log
LOGFILE="/var/log/failover.log"
echo "=== $(date): Iniciando monitoreo de Failover ===" | tee -a $LOGFILE

# Función para verificar conectividad y actualizar reglas de ruteo
check_link() {
    local SOURCE_IP=$1
    local HOST=$2
    local TABLE=$3
    local MARK=$4
    local GW=$5
    local IFACE=$6

    ping -c 3 -W 2 -I ${SOURCE_IP} ${HOST} > /dev/null 2>&1
    STATUS=$?

    if [ "$TABLE" = "$TABLE1" ]; then
        ISP1_STATUS=$STATUS
    elif [ "$TABLE" = "$TABLE2" ]; then
        ISP2_STATUS=$STATUS
    fi

    if [ $STATUS -eq 0 ]; then
        # Enlace activo → asegurar regla
        if ! ip rule show | grep -q "fwmark ${MARK} lookup ${TABLE}"; then
            echo "$(date): ${TABLE} (${IFACE}) recuperado. Restableciendo regla." | tee -a $LOGFILE
            ip rule add fwmark ${MARK} table ${TABLE}
        fi
    else
        # Enlace caído → eliminar regla
        if ip rule show | grep -q "fwmark ${MARK} lookup ${TABLE}"; then
            echo "$(date): ${TABLE} (${IFACE}) caído. Eliminando regla de ruteo." | tee -a $LOGFILE
            ip rule del fwmark ${MARK} table ${TABLE}
        fi
    fi
}

# Función para manejar la ruta por defecto global
manage_default_route() {
    CURRENT_GW=$(ip route show default | grep -oP '(?<=via )[0-9.]+')

    if [ $ISP2_STATUS -ne 0 ] && [ $ISP1_STATUS -eq 0 ]; then
        # ISP2 (principal) caído → cambiar a ISP1
        if [ "$CURRENT_GW" != "$GW1" ]; then
            echo "$(date): FAILOVER → ISP2 caído. Cambiando default route a ISP1 (${GW1})." | tee -a $LOGFILE
            ip route del default || true
            ip route add default via $GW1 dev $IFACE1 metric 100
        fi
    elif [ $ISP1_STATUS -ne 0 ] && [ $ISP2_STATUS -eq 0 ]; then
        # ISP1 caído → mantener ISP2 como principal
        if [ "$CURRENT_GW" != "$GW2" ]; then
            echo "$(date): RECUPERACIÓN → ISP2 activo. Restaurando default route (${GW2})." | tee -a $LOGFILE
            ip route del default || true
            ip route add default via $GW2 dev $IFACE2 metric 100
        fi
    fi
}

# Bucle principal
while true; do
    check_link $SOURCE_IP_1 $HOST1 $TABLE1 $MARK1 $GW1 $IFACE1
    check_link $SOURCE_IP_2 $HOST2 $TABLE2 $MARK2 $GW2 $IFACE2
    manage_default_route
    sleep 5
done
