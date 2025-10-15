iptables -t nat -A POSTROUTING -o eno1 -j MASQUERADE
iptables -t nat -A POSTROUTING -o enx00e04c36035e -j MASQUERADE


#ip route add 11.11.11.0/30 dev eno1 src 11.11.11.2 table ISP1_TABLES
#ip route add default via 11.11.11.1 dev eno1 table ISP1_TABLES

#ip route add 11.11.12.0/30 dev enx00e04c36035e src 11.11.12.2 table ISP2_TABLES
#ip route add default via 11.11.12.1 dev enx00e04c36035e table ISP2_TABLES

