#!/usr/bin/env bash

# VARIABLES
GITHUB_USER="ChristopherAGT"
GITHUB_REPO="slowdns"
RELEASE_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/latest/download"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="slowdns"

# Colores para estética
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # sin color

# Detectar arquitectura y mapear al nombre del binario
detect_arch(){
  arch=$(uname -m)
  case $arch in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    armv7l|armv6l) echo "armv7" ;;
    *) echo "amd64" ;; # default
  esac
}

download_binaries(){
  arch=$(detect_arch)
  echo -e "${CYAN}Descargando binarios para arquitectura: $arch${NC}"

  # Binarios a descargar
  server_bin="dnstt-server-$arch"
  client_bin="dnstt-client-$arch"

  for bin in "$server_bin" "$client_bin"; do
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

generate_keys(){
  echo -e "${CYAN}Verificando claves existentes...${NC}"
  if [[ -f "$INSTALL_DIR/server.key" && -f "$INSTALL_DIR/server.pub" ]]; then
    read -rp "Claves existentes encontradas. ¿Generar nuevas? (s/n): " opt
    if [[ "$opt" == "s" ]]; then
      "$INSTALL_DIR/dnstt-server-$(detect_arch)" -gen-key -privkey-file "$INSTALL_DIR/server.key" -pubkey-file "$INSTALL_DIR/server.pub"
      echo -e "${GREEN}Claves generadas correctamente.${NC}"
    else
      echo "Usando claves actuales."
    fi
  else
    echo "No se encontraron claves, generando nuevas..."
    "$INSTALL_DIR/dnstt-server-$(detect_arch)" -gen-key -privkey-file "$INSTALL_DIR/server.key" -pubkey-file "$INSTALL_DIR/server.pub"
    echo -e "${GREEN}Claves generadas correctamente.${NC}"
  fi
  chmod 600 "$INSTALL_DIR/server.key"
}

# Más funciones (menu, instalar servicio, configurar, etc.) irán aquí...

# EJEMPLO de uso (puedes expandir)
main(){
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
    0) echo "Cancelando..."; exit ;;
    *) echo "Opción inválida"; exit 1 ;;
  esac

  echo
  echo "Instalando dependencias..."
  apt update && apt install -y iptables

  download_binaries
  generate_keys

  # Aquí iría crear y habilitar el servicio systemd

  echo -e "${GREEN}Instalación completada con éxito!${NC}"
  read -rp ">> Presione Enter para continuar <<"
}

main
