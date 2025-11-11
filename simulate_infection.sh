#!/usr/bin/env bash
# simulate_infection.sh - Simula infección USB: crea accesos directos .lnk y oculta archivos originales
# Uso: sudo ./simulate_infection.sh /punto/de/montaje

set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  echo "Uso: $0 /ruta/al/directorio"
  exit 1
fi

if ! command -v fatattr >/dev/null 2>&1; then
  echo "Instalando 'fatattr'..."
  sudo apt update && sudo apt install -y fatattr
fi

echo "=== Simulador de infección USB ==="
echo "Directorio objetivo: $TARGET"
echo "Creando archivos .lnk y ocultando originales..."
echo

# Recorre todos los archivos y carpetas (excepto los .lnk ya existentes)
find "$TARGET" -mindepth 1 -print0 | while IFS= read -r -d '' item; do
  # Saltar si ya es un .lnk
  [[ "$item" == *.lnk ]] && continue

  dir=$(dirname "$item")
  base=$(basename "$item")
  link="$dir/${base}.lnk"

  # Crear archivo .lnk vacío (simulado)
  touch "$link"

  # Aplicar atributos oculto y sistema a original
  if sudo fatattr +h +s "$item" 2>/dev/null; then
    echo "[OK] Oculto: $item"
  else
    echo "[WARN] No se pudo ocultar: $item"
  fi

  echo "[CREADO] $link"
done

echo
echo "Simulación completada."
echo "Archivos originales ocultos (+h +s) y duplicados .lnk creados."

