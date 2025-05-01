#!/bin/bash

# --------------------------- FUNCIONALIDAD ---------------------------------
# SCRIPT QUE:
# 1. Si detecta Fail2Ban instalado, recomienda usar el panel Plesk
# 2. Si no tiene Fail2Ban, bloquea IPs con iptables/ipset usando BLACKLIST_SYS4NET
# ---------------------------------------------------------------------------

# COLORES PARA MENSAJES
RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
CYAN='\e[1;36m'
NC='\e[0m' # No Color

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verificar si es servidor Plesk
if [ ! -f /usr/local/psa/version ] && [ ! -f /usr/sbin/plesk ]; then
    echo -e "${RED}ERROR: Este servidor no tiene Plesk instalado.${NC}"
    exit 1
fi

# Verificar si Fail2Ban está instalado y activo
if command_exists fail2ban-client && systemctl is-active --quiet fail2ban; then
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "${YELLOW}SE HA DETECTADO FAIL2BAN INSTALADO EN EL SISTEMA${NC}"
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "\n${CYAN}Recomendación:${NC}"
    echo -e "Por favor, bloquee las IPs manualmente a través del panel de Plesk:"
    echo -e "1. Acceda al panel Plesk (https://[su-servidor]:8443)"
    echo -e "2. Vaya a 'Herramientas y Configuración' > 'Firewall'"
    echo -e "3. Añada las IPs desde el archivo /root/bloqueo_ips.txt"
    echo -e "\n${YELLOW}El script no bloqueará IPs automáticamente para evitar conflictos con Fail2Ban.${NC}"
    exit 0
fi

# Si llegamos aquí, no hay Fail2Ban - proceder con iptables
echo -e "${GREEN}Fail2Ban no detectado, procediendo con bloqueo via iptables/ipset...${NC}"

# Descargar lista de IPs
echo -e "${CYAN}Descargando lista de IPs a bloquear...${NC}"
wget -q -O /root/bloqueo_ips.txt http://212.227.163.77/list/bloqueo_ips.txt
if [ $? -ne 0 ]; then
    echo -e "${RED}Error al descargar el archivo de IPs${NC}"
    exit 1
fi

# Configurar ipset
IPSET_NAME="BLACKLIST_SYS4NET"

# Crear ipset si no existe
if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
    ipset create "$IPSET_NAME" hash:net
    echo -e "${GREEN}Conjunto ipset $IPSET_NAME creado.${NC}"
fi

# Añadir regla iptables si no existe
if ! iptables -C INPUT -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
    iptables -I INPUT -m set --match-set "$IPSET_NAME" src -j DROP
    echo -e "${GREEN}Regla iptables añadida para el conjunto $IPSET_NAME.${NC}"
fi

# Procesar cada IP
TOTAL=0
BLOQUEADAS=0
YA_BLOQUEADAS=0

echo -e "${CYAN}Procesando IPs...${NC}"

while read -r ip; do
    # Validar formato IP
    if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}IP no válida: $ip - omitiendo${NC}"
        continue
    fi

    ((TOTAL++))
    
    if ! ipset test "$IPSET_NAME" "$ip" 2>/dev/null; then
        ipset add "$IPSET_NAME" "$ip"
        echo -e "${GREEN}Bloqueada: $ip${NC}"
        ((BLOQUEADAS++))
    else
        echo -e "${YELLOW}Ya bloqueada: $ip${NC}"
        ((YA_BLOQUEADAS++))
    fi
done < /root/bloqueo_ips.txt

# Guardar reglas persistentemente
if command_exists iptables-save; then
    iptables-save > /etc/sysconfig/iptables
    echo -e "${GREEN}Reglas iptables guardadas persistentemente.${NC}"
fi

# Mostrar resumen
echo -e "\n${CYAN}==== RESUMEN ====${NC}"
echo -e "IPs procesadas: ${TOTAL}"
echo -e "IPs nuevas bloqueadas: ${BLOQUEADAS}"
echo -e "IPs ya bloqueadas: ${YA_BLOQUEADAS}"
echo -e "${GREEN}Proceso completado.${NC}"
