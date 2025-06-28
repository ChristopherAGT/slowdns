#!/usr/bin/env bash

# Variables globales
GITHUB_USER="ChristopherAGT"
GITHUB_REPO="slowdns"
RELEASE_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/latest/download"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="slowdns"
CONFIG_DIR="/etc/slowdns"
CONFIG_FILE="$CONFIG_DIR/config.conf"
LOG_FILE="/var/log/slowdns.log"

# Colores para estética
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sin color

# Crear carpeta config si no existe
mkdir -p "$CONFIG_DIR"

# Detectar arquitectura
detect_arch() {
  local arch
  arch=$(uname -m)
  case $arch in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    armv7l|armv6l) echo "armv7" ;;
    *) echo "amd64" ;; # default
  esac
}

# Descargar binarios y clave pública
download_binaries() {
  local arch server_bin client_bin pubkey url
  arch=$(detect_arch)
  echo -e "${CYAN}Descargando binarios para arquitectura: $arch${NC}"

  server_bin="dnstt-server-$arch"
  client_bin="dnstt-client-$arch"
  pubkey="server.pub"

  for bin in "$server_bin" "$client_bin" "$pubkey"; do
    url="$RELEASE_URL/$bin"
    echo -n "Descargando $bin... "
    if wget -q --show-progress -O "$INSTALL_DIR/$bin" "$url"; then
      chmod +x "$INSTALL_DIR/$bin"
      echo -e "${GREEN}OK${NC}"
    else
      echo -e "${RED}ERROR${NC}"
      exit 1
    fi
  done
}

# Generar claves si no existen o preguntar para regenerar
generate_keys() {
  local server_bin
  server_bin="$INSTALL_DIR/dnstt-server-$(detect_arch)"

  echo -e "${CYAN}Verificando claves existentes...${NC}"
  if [[ -f "$INSTALL_DIR/server.key" && -f "$INSTALL_DIR/server.pub" ]]; then
    echo "Claves encontradas."
    read -rp "¿Generar un nuevo par de claves? (s/n): " opt
    if [[ "$opt" =~ ^[Ss]$ ]]; then
      "$server_bin" -gen-key -privkey-file "$INSTALL_DIR/server.key" -pubkey-file "$INSTALL_DIR/server.pub"
      echo -e "${GREEN}Claves generadas correctamente.${NC}"
    else
      echo "Usando claves actuales."
    fi
  else
    echo "No se encontraron claves, generando nuevas..."
    "$server_bin" -gen-key -privkey-file "$INSTALL_DIR/server.key" -pubkey-file "$INSTALL_DIR/server.pub"
    echo -e "${GREEN}Claves generadas correctamente.${NC}"
  fi
  chmod 600 "$INSTALL_DIR/server.key"
}

# Guardar configuración en archivo
save_config() {
  cat > "$CONFIG_FILE" << EOF
NS_DOMAIN=$ns_domain
TRAFFIC_PORT=$trafic_port
SERVICE_PORT=5300
REDIRECT_PORT=53
EOF
}

# Leer configuración desde archivo
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
  else
    ns_domain=""
    trafic_port=""
  fi
}

# Crear servicio systemd
create_service() {
  local server_bin
  server_bin="$INSTALL_DIR/dnstt-server-$(detect_arch)"

  cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=SlowDNS (dnstt) service
After=network.target

[Service]
ExecStart=$server_bin -udp :5300 -privkey-file $INSTALL_DIR/server.key -pubkey-file $INSTALL_DIR/server.pub -ns $ns_domain -redir 53:$trafic_port
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable $SERVICE_NAME
  systemctl start $SERVICE_NAME
}

# Mostrar estado del servicio
service_status() {
  systemctl status $SERVICE_NAME --no-pager
  echo
  read -rp "Presione Enter para continuar..."
}

# Reiniciar servicio
service_restart() {
  systemctl restart $SERVICE_NAME
  echo -e "${GREEN}Servicio reiniciado.${NC}"
  sleep 1
}

# Iniciar/parar servicio
service_toggle() {
  if systemctl is-active --quiet $SERVICE_NAME; then
    systemctl stop $SERVICE_NAME
    echo -e "${YELLOW}Servicio detenido.${NC}"
  else
    systemctl start $SERVICE_NAME
    echo -e "${GREEN}Servicio iniciado.${NC}"
  fi
  sleep 1
}

# Mostrar logs
show_logs() {
  less +F "$LOG_FILE"
}

# Mostrar logs en tiempo real
show_logs_realtime() {
  tail -f "$LOG_FILE"
}

# Reconfigurar SlowDNS (dominio y puerto)
reconfigure() {
  read -rp "Nuevo dominio NS: " ns_domain
  read -rp "Puerto de tráfico: " trafic_port
  save_config
  service_restart
  echo -e "${GREEN}Configuración actualizada.${NC}"
  sleep 1
}

# Mostrar claves
show_keys() {
  echo -e "${CYAN}Clave pública (server.pub):${NC}"
  cat "$INSTALL_DIR/server.pub"
  echo
  echo -e "${CYAN}Clave privada (server.key):${NC}"
  ls -lh "$INSTALL_DIR/server.key"
  echo "(Se recomienda no mostrar la clave privada)"
  read -rp "Presione Enter para continuar..."
}

# Generar nuevo par de claves
generate_new_keys() {
  local server_bin
  server_bin="$INSTALL_DIR/dnstt-server-$(detect_arch)"
  "$server_bin" -gen-key -privkey-file "$INSTALL_DIR/server.key" -pubkey-file "$INSTALL_DIR/server.pub"
  chmod 600 "$INSTALL_DIR/server.key"
  echo -e "${GREEN}Nuevo par de claves generado.${NC}"
  sleep 1
}

# Cambiar puerto de tráfico
change_traffic_port() {
  read -rp "Nuevo puerto de tráfico: " trafic_port
  save_config
  service_restart
  echo -e "${GREEN}Puerto actualizado.${NC}"
  sleep 1
}

# Cambiar dominio NS
change_ns_domain() {
  read -rp "Nuevo dominio NS: " ns_domain
  save_config
  service_restart
  echo -e "${GREEN}Dominio actualizado.${NC}"
  sleep 1
}

# Reinstalar (borrar y correr instalador)
reinstall() {
  systemctl stop $SERVICE_NAME
  systemctl disable $SERVICE_NAME
  rm -f /etc/systemd/system/$SERVICE_NAME.service
  systemctl daemon-reload
  rm -rf "$CONFIG_DIR"
  rm -f "$INSTALL_DIR/dnstt-server-"* "$INSTALL_DIR/dnstt-client-"* "$INSTALL_DIR/server.key" "$INSTALL_DIR/server.pub"
  echo -e "${YELLOW}Archivos borrados.${NC}"
  echo "Ejecuta el script de instalación nuevamente."
  exit 0
}

# Desinstalar todo
uninstall() {
  read -rp "¿Seguro que quieres desinstalar SlowDNS? (s/n): " opt
  if [[ "$opt" =~ ^[Ss]$ ]]; then
    systemctl stop $SERVICE_NAME
    systemctl disable $SERVICE_NAME
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    systemctl daemon-reload
    rm -rf "$CONFIG_DIR"
    rm -f "$INSTALL_DIR/dnstt-server-"* "$INSTALL_DIR/dnstt-client-"* "$INSTALL_DIR/server.key" "$INSTALL_DIR/server.pub"
    echo -e "${RED}SlowDNS desinstalado.${NC}"
    exit 0
  fi
}

# Instalador inicial con menú para elegir dominio y puerto
installer() {
  clear
  echo "════════════════════════════════════════════════════════════"
  echo "                 INSTALADOR SLOWDNS (DNSTT)"
  echo "════════════════════════════════════════════════════════════"
  read -rp " Ingresa tu dominio NS: " ns_domain

  echo
  echo "  A qué protocolo se le permitirá el tráfico?"
  echo "------------------------------------------------------------"
  echo "  [1] sshd (22)"
  echo "  [0] Cancelar"
  echo "  [2] Ingresar puerto manualmente"
  echo "════════════════════════════════════════════════════════════"
  read -rp " Ingresa una opción: " option

  case $option in
    1) trafic_port=22 ;;
    2) read -rp "Ingresa puerto manual: " trafic_port ;;
    0) echo "Cancelando..."; exit 1 ;;
    *) echo "Opción inválida"; exit 1 ;;
  esac

  echo
  echo "Instalando dependencias..."
  apt update -y && apt install -y iptables wget

  download_binaries
  generate_keys
  save_config
  create_service

  echo -e "${GREEN}Instalación completada con éxito!${NC}"
  read -rp ">> Presione Enter para continuar <<"  
}

# Panel de administración
panel() {
  load_config
  while true; do
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "               ADMINISTRADOR DNSTT (SLOWDNS)"
    echo "════════════════════════════════════════════════════════════"
    echo " PORT: 5300"
    echo " REDIRECT: 53 > 5300"
    echo " TRAFFIC PORT: $trafic_port"
    echo " NS DOMAIN: $ns_domain"
    echo " CLAVE PUB: $(cat $INSTALL_DIR/server.pub 2>/dev/null || echo 'No disponible')"
    echo "════════════════════════════════════════════════════════════"
    echo "  [1] RECONFIGURAR SLOWDNS"
    echo "------------------------------------------------------------"
    echo "  [2] MIS CLAVES SLOWDNS"
    echo "  [3] GENERAR NUEVO PAR DE CLAVES"
    echo "  [4] PAR DE CLAVES PERSONALES (Copiar claves manualmente)"
    echo "------------------------------------------------------------"
    echo "  [5] MODIFICAR PUERTO DE TRÁFICO"
    echo "  [6] MODIFICAR DOMINIO NS"
    echo "------------------------------------------------------------"
    echo "  [7] ESTADO DEL SERVICIO"
    echo "  [8] REINICIAR SERVICIO"
    echo "  [9] INICIAR/PARAR SERVICIO"
    echo "------------------------------------------------------------"
    echo " [10] LOG SLOWDNS"
    echo " [11] LOG SLOWDNS EN TIEMPO REAL"
    echo "════════════════════════════════════════════════════════════"
    echo "  [0] Volver         [12] REINSTALAR        [13] DESINSTALAR"
    echo "════════════════════════════════════════════════════════════"
    read -rp " Ingresa una opción: " choice

    case $choice in
      0) break ;;
      1) reconfigure ;;
      2) show_keys ;;
      3) generate_new_keys ;;
      4) 
        echo "Para copiar claves manualmente, coloca server.key y server.pub en $INSTALL_DIR"
        read -rp "Presione Enter para continuar..."
        ;;
      5) change_traffic_port ;;
      6) change_ns_domain ;;
      7) service_status ;;
      8) service_restart ;;
      9) service_toggle ;;
      10) show_logs ;;
      11) show_logs_realtime ;;
      12) reinstall ;;
      13) uninstall ;;
      *) echo "Opción inválida."; sleep 1 ;;
    esac
  done
}

# Menú principal
main_menu() {
  while true; do
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "                  SLOWDNS INSTALADOR Y PANEL"
    echo "════════════════════════════════════════════════════════════"
    echo "  [1] Instalar SlowDNS (DNSTT)"
    echo "  [2] Abrir panel de administración"
    echo "  [0] Salir"
