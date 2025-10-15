#!/bin/bash

# ==========================================================
# Script de Monitoreo y Failover (check_link.sh)
# DEBE EJECUTARSE CON: sudo nohup ./check_link.sh &
# ==========================================================

# IPs de Gateway
GW1=11.11.11.1 # Gateway ISP1
GW2=11.11.12.1 # Gateway ISP2

# Interfaces
IFACE1=eno1
IFACE2=enx00e04c36035e

# IPs de Origen (IP del Balanceador de Carga en cada enlace)
SOURCE_IP_1=11.11.11.2
HOST1=8.8.8.8 # Host externo para prueba ISP1

SOURCE_IP_2=11.11.12.2
HOST2=1.1.1.1 # Host externo para prueba ISP2

# Nombres de las tablas de ruteo
TABLE1=ISP1_TABLES
TABLE2=ISP2_TABLES

# Marcas de Firewall
MARK1=1
MARK2=2

# La tabla principal ('main') usa ISP2 por defecto (el que tiene la marca 2)
# La ruta de ISP1 será la ruta de respaldo para el 'catch-all' (tráfico que caiga de la marca 2)

# Función de chequeo
check_link() {
    # $1: SOURCE_IP, $2: HOST, $3: TABLE_NAME, $4: MARK, $5: LINK_GW, $6: LINK_IFACE
    SOURCE_IP=$1
    HOST=$2
    TABLE=$3
    MARK=$4
    LINK_GW=$5
    LINK_IFACE=$6

    # 1. Probar conectividad A TRAVÉS DE LA INTERFAZ/IP DEL BALANCEADOR
    ping -c 3 -W 2 -I ${SOURCE_IP} ${HOST} > /dev/null 2>&1
    STATUS=$?

    if [ $STATUS -eq 0 ]; then
        # 2. Enlace Arriba: Asegurar que la regla de ruteo esté presente
        if ! ip rule show | grep -q "fwmark ${MARK} lookup ${TABLE}"; then
            echo "$(date): Enlace ${TABLE} (${SOURCE_IP}) recuperado. Restableciendo regla."
            ip rule add fwmark ${MARK} table ${TABLE}
        fi

        # **LÓGICA CRÍTICA DE RECUPERACIÓN (Solo para el enlace por defecto/ISP2)**
        if [ "$TABLE" == "$TABLE2" ] && ! ip route show default | grep -q "${GW2}"; then
            # Si ISP2 sube, aseguramos que la ruta por defecto vuelva a ser ISP2
            echo "$(date): ISP2 recuperado. Cambiando ruta por defecto (main) a ISP2."
            ip route del default via ${GW1} dev ${IFACE1} > /dev/null 2>&1
            ip route add default via ${GW2} dev ${IFACE2} metric 100
        fi
    else
        # 3. Enlace Abajo: Eliminar la regla de ruteo
        if ip rule show | grep -q "fwmark ${MARK} lookup ${TABLE}"; then
            echo "$(date): Enlace ${TABLE} (${SOURCE_IP}) caído. Eliminando regla de ruteo."
            ip rule del fwmark ${MARK} table ${TABLE}

            # **LÓGICA CRÍTICA DE FAILOVER (Solo para el enlace por defecto/ISP2)**
            if [ "$TABLE" == "$TABLE2" ]; then
                # Si ISP2 (el por defecto) cae, el tráfico sin marca 1 que caía aquí (marca 2)
                # ahora caerá en la tabla main. Debemos asegurarnos de que main apunte a ISP1.
                echo "$(date): ISP2 (DEFAULT) caído. Cambiando ruta por defecto (main) a ISP1."
                ip route del default via ${GW2} dev ${IFACE2} > /dev/null 2>&1
                ip route add default via ${GW1} dev ${IFACE1} metric 100
            fi
        fi
    fi
}

# Bucle principal de monitoreo
echo "Iniciando monitoreo de Failover..."
while true; do
    # Chequeo para ISP1
    check_link $SOURCE_IP_1 $HOST1 $TABLE1 $MARK1 $GW1 $IFACE1

    # Chequeo para ISP2 (el enlace principal/por defecto)
    check_link $SOURCE_IP_2 $HOST2 $TABLE2 $MARK2 $GW2 $IFACE2

    sleep 5 # Esperar 5 segundos antes de la siguiente verificación
done
