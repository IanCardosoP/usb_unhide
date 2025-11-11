#!/usr/bin/env bash
# unhide_usb.sh - Limpia memorias USB FAT/exFAT: elimina .lnk, quita atributos ocultos y borra basura residual
# Autor: Ian Cardoso - 2025
# Versión: v2
# Documentación: Sharepoint/knowledge base/unhide_usb.pdf
#
# Uso: sudo ./unhide_usb.sh [OPTIONS] /punto/de/montaje
# Options:
#   -d, --dry-run       Simular operaciones sin hacer cambios
#   -n, --no-backup     Omitir creación de backup
#   -h, --help          Mostrar ayuda
#   -v, --verbose       Modo verboso

set -euo pipefail

# ============================================================================
# CONFIGURACIÓN GLOBAL
# ============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2"
readonly REQUIRED_TOOLS=("tar" "find" "fatattr")
readonly SUPPORTED_FILESYSTEMS=("vfat" "exfat" "msdos")
readonly BACKUP_DIR_NAME="USB-BACKUPS"

readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

# Variables globales configurables
DRY_RUN=false
CREATE_BACKUP=true
VERBOSE=false
MOUNT_POINT=""
USER_HOME=""
USB_NAME=""
LOG_FILE=""
BACKUP_PATH=""

# ============================================================================
# FUNCIONES DE UTILIDAD
# ============================================================================

log_to_file() {
    if [[ "$DRY_RUN" == false ]] && [[ -n "$LOG_FILE" ]]; then
        echo "$@" >> "$LOG_FILE"
    fi
}

print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${COLOR_RESET}"
}

log_info() {
    local msg="[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo "$msg"
    log_to_file "$msg"
}

log_success() {
    local msg="[OK] $*"
    print_color "$COLOR_GREEN" "$msg"
    log_to_file "$msg"
}

log_warning() {
    local msg="[AVISO] $*"
    print_color "$COLOR_YELLOW" "$msg"
    log_to_file "$msg"
}

log_error() {
    local msg="[ERROR] $*"
    print_color "$COLOR_RED" "$msg" >&2
    log_to_file "$msg"
}

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        local msg="[VERBOSE] $*"
        print_color "$COLOR_BLUE" "$msg"
        log_to_file "$msg"
    fi
}

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Verificar si el script se ejecuta como root
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "Este script debe ejecutarse con privilegios de root (sudo)" 2
    fi
}

# ============================================================================
# FUNCIONES DE VALIDACIÓN
# ============================================================================

validate_required_tools() {
    log_info "Verificando herramientas necesarias..."
    
    local missing_tools=()
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warning "Faltan herramientas: ${missing_tools[*]}"
        
        if [[ " ${missing_tools[*]} " =~ " fatattr " ]]; then
            log_info "Instalando fatattr..."
            apt-get update -qq && apt-get install -y fatattr || \
                error_exit "No se pudo instalar fatattr" 3
        else
            error_exit "Instala las herramientas faltantes: ${missing_tools[*]}" 3
        fi
    fi
    
    log_success "Todas las herramientas están disponibles"
}

validate_mount_point() {
    local mount="$1"
    
    if [[ -z "$mount" ]]; then
        error_exit "No se especificó punto de montaje" 4
    fi
    
    if [[ ! -d "$mount" ]]; then
        error_exit "El directorio '$mount' no existe" 4
    fi
    
    if [[ ! -r "$mount" ]] || [[ ! -w "$mount" ]]; then
        error_exit "No hay permisos de lectura/escritura en '$mount'" 4
    fi
}

validate_filesystem() {
    local mount="$1"
    local fstype
    
    log_info "Detectando tipo de sistema de archivos..."
    fstype=$(findmnt -n -o FSTYPE --target "$mount" 2>/dev/null || echo "unknown")
    
    log_info "Tipo detectado: $fstype"
    
    if [[ ! " ${SUPPORTED_FILESYSTEMS[*]} " =~ " ${fstype} " ]]; then
        error_exit "Filesystem '$fstype' no soportado. Solo se admiten: ${SUPPORTED_FILESYSTEMS[*]}" 5
    fi
    
    # Verificar opciones de montaje (solo informativo)
    local mount_opts
    mount_opts=$(findmnt -n -o OPTIONS --target "$mount" 2>/dev/null || echo "unknown")
    log_verbose "Opciones de montaje: $mount_opts"
    

    # (fatattr puede funcionar independientemente de permisos Unix)
    if [[ "$mount_opts" =~ ro ]]; then
        log_warning "La USB está montada como solo lectura"
        log_warning "Si hay problemas, remonta con: sudo mount -o remount,rw '$mount'"
    fi
    
    log_success "Filesystem compatible: $fstype"
}

test_fatattr() {
    log_info "Verificando funcionamiento de fatattr..."
    
    local test_file="$MOUNT_POINT/.test_fatattr_$$"
    
    if touch "$test_file" 2>/dev/null; then
        local attrs
        attrs=$(fatattr "$test_file" 2>&1)
        local status=$?
        
        if [[ $status -eq 0 ]]; then
            log_success "fatattr funciona correctamente"
            log_verbose "Atributos de prueba: $attrs"
        else
            log_warning "fatattr retornó error: $attrs"
            log_warning "Esto puede indicar un problema con el filesystem"
        fi
        
        rm -f "$test_file" 2>/dev/null
    else
        log_warning "No se pudo crear archivo de prueba en '$MOUNT_POINT'"
    fi
}

check_disk_space() {
    local mount="$1"
    local backup_dir="$2"
    
    log_verbose "Verificando espacio en disco..."
    
    local used_space
    used_space=$(du -sb "$mount" 2>/dev/null | awk '{print $1}')
    
    local available_space
    available_space=$(df -B1 "$backup_dir" 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [[ -z "$available_space" ]] || [[ "$available_space" -lt "$used_space" ]]; then
        log_warning "Espacio insuficiente para backup completo"
        read -p "¿Continuar sin backup? (y/N): " -n 1 -r </dev/tty
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error_exit "Operación cancelada por el usuario" 6
        fi
        CREATE_BACKUP=false
    fi
}

# ============================================================================
# FUNCIONES DE OPERACIONES
# ============================================================================

setup_environment() {
    USB_NAME=$(basename "$MOUNT_POINT")
    USER_HOME=$(eval echo "~${SUDO_USER:-$USER}")
    
    local backup_dir="$USER_HOME/$BACKUP_DIR_NAME"
    
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$backup_dir" || error_exit "No se pudo crear directorio de backups" 7
    fi
    
    LOG_FILE="$backup_dir/${USB_NAME}_$(date +%Y%m%d_%H%M%S).log"
    BACKUP_PATH="$backup_dir/${USB_NAME}_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    log_info "Directorio de backups: $backup_dir"
    log_info "Archivo de log: $LOG_FILE"
}

print_banner() {
    cat << EOF
================================================================================
    Reparador de USB Infectado v${SCRIPT_VERSION}
================================================================================
    Autor: Ian Cardoso - 2025
    Documentación: Sharepoint/knowledge base/unhide_usb.pdf
    
    ADVERTENCIA: Este programa NO limpia malware activo.
                 Ejecutar primero un antivirus (ej: clamtk)
    
    Punto de montaje: $MOUNT_POINT
    Modo: $([ "$DRY_RUN" == true ] && echo "DRY-RUN (simulación)" || echo "EJECUCIÓN REAL")
================================================================================

EOF
}

request_confirmation() {
    if [[ "$DRY_RUN" == false ]]; then
        read -p "¿Deseas continuar? (y/N): " -n 1 -r </dev/tty
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operación cancelada por el usuario"
            exit 0
        fi
    fi
}

create_backup() {
    if [[ "$CREATE_BACKUP" == false ]]; then
        log_warning "Omitiendo creación de backup"
        return 0
    fi
    
    log_info "Creando copia de seguridad..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] tar -czf '$BACKUP_PATH' -C '$MOUNT_POINT' ."
    else
        if tar -czf "$BACKUP_PATH" -C "$MOUNT_POINT" . 2>/dev/null; then
            log_success "Backup creado: $BACKUP_PATH"
        else
            log_warning "Falló la creación del backup, pero continuando..."
        fi
    fi
}

list_fat_attributes() {
    local title="$1"
    
    echo ""
    log_info "$title"
    echo "----------------------------------------------------------------------"
    log_to_file "----------------------------------------------------------------------"
    
    local count=0
    
    sudo find "$MOUNT_POINT" -print0 | while IFS= read -r -d '' file; do
        count=$((count + 1))
        
        # Progreso cada 100 items
        if [ $((count % 100)) -eq 0 ]; then
            log_info "Progreso: $count items analizados..."
        fi
        
        local attrs
        attrs=$(sudo fatattr "$file" 2>/dev/null || echo "N/A")
        
        # Mostrar solo si tiene atributos relevantes
        if [[ "$attrs" != "N/A" ]]; then
            echo "$attrs"
            log_to_file "$attrs"
        fi
    done
    
    log_info "Análisis de atributos completado"
    echo ""
}

remove_lnk_files() {
    log_info "Buscando y eliminando archivos .lnk sospechosos..."
    
    local lnk_files=()
    while IFS= read -r -d '' file; do
        lnk_files+=("$file")
    done < <(find "$MOUNT_POINT" -type f -iname '*.lnk' -print0)
    
    if [[ ${#lnk_files[@]} -eq 0 ]]; then
        log_info "No se encontraron archivos .lnk"
        return 0
    fi
    
    log_info "Encontrados ${#lnk_files[@]} archivos .lnk"
    
    for file in "${lnk_files[@]}"; do
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY-RUN] Eliminaría: $file"
        else
            if rm -f "$file" 2>/dev/null; then
                log_verbose "Eliminado: $file"
            else
                log_warning "No se pudo eliminar: $file"
            fi
        fi
    done
    
    log_success "Archivos .lnk procesados: ${#lnk_files[@]}"
}

normalize_permissions() {
    log_info "Normalizando permisos y propiedad..."
    
    local target_user="${SUDO_USER:-$USER}"
    local target_group
    target_group=$(id -gn "$target_user")
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] chown -R $target_user:$target_group '$MOUNT_POINT'"
        log_info "[DRY-RUN] chmod -R u+rwX,go+rX '$MOUNT_POINT'"
    else
        chown -R "$target_user:$target_group" "$MOUNT_POINT" 2>/dev/null || \
            log_warning "No se pudieron cambiar algunos permisos"
        chmod -R u+rwX,go+rX "$MOUNT_POINT" 2>/dev/null || \
            log_warning "No se pudieron cambiar algunos modos"
    fi
    
    log_success "Permisos normalizados"
}

restore_hidden_files() {
    log_info "Eliminando atributos 'hidden' y 'system'..."
    
    local restored_count=0
    local renamed_count=0
    
    sudo find "$MOUNT_POINT" -print0 | while IFS= read -r -d '' item; do
        
        if [[ "$DRY_RUN" == true ]]; then
            log_verbose "[DRY-RUN] fatattr -h -s '$item'"
            restored_count=$((restored_count + 1))
        else
            if sudo fatattr -h -s "$item" 2>/dev/null; then
                log_verbose "Atributos eliminados: $item"
                restored_count=$((restored_count + 1))
            fi
        fi
        
        # Renombrar archivos que empiezan con punto
        local base_name
        base_name=$(basename "$item")
        local dir_name
        dir_name=$(dirname "$item")
        
        if [[ "$base_name" == .* ]] && [[ "$base_name" != "." ]] && [[ "$base_name" != ".." ]]; then
            local new_name="${base_name#.}"
            local new_path="$dir_name/$new_name"
            
            if [[ ! -e "$new_path" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log_info "[DRY-RUN] Renombraría: $item → $new_path"
                    renamed_count=$((renamed_count + 1))
                else
                    if sudo mv "$item" "$new_path" 2>/dev/null; then
                        log_verbose "Renombrado: $base_name → $new_name"
                        renamed_count=$((renamed_count + 1))
                    else
                        log_warning "No se pudo renombrar: $item"
                    fi
                fi
            else
                log_warning "No se pudo renombrar '$base_name' porque '$new_name' ya existe"
            fi
        fi
    done
    
    log_success "Items con atributos modificados: $restored_count"
    log_success "Items renombrados: $renamed_count"
}

remove_trash_folders() {
    log_info "Eliminando carpetas de papelera (.Trash*)..."
    
    local trash_dirs=()
    while IFS= read -r -d '' dir; do
        trash_dirs+=("$dir")
    done < <(find "$MOUNT_POINT" -maxdepth 1 -type d -iname '.Trash*' -print0)
    
    if [[ ${#trash_dirs[@]} -eq 0 ]]; then
        log_info "No se encontraron carpetas de papelera"
        return 0
    fi
    
    for dir in "${trash_dirs[@]}"; do
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY-RUN] Eliminaría: $dir"
        else
            if rm -rf "$dir" 2>/dev/null; then
                log_verbose "Eliminado: $dir"
            else
                log_warning "No se pudo eliminar: $dir"
            fi
        fi
    done
    
    log_success "Carpetas de papelera procesadas: ${#trash_dirs[@]}"
}

generate_report() {
    cat << EOF

================================================================================
    RESUMEN FINAL
================================================================================
    Fecha de ejecución: $(date)
    Punto de montaje: $MOUNT_POINT
    Modo: $([ "$DRY_RUN" == true ] && echo "DRY-RUN" || echo "EJECUCIÓN REAL")
    
    Backup: $([ "$CREATE_BACKUP" == true ] && echo "$BACKUP_PATH" || echo "No creado")
    Log: $LOG_FILE
    
    Estado: ✓ COMPLETADO
================================================================================

La memoria USB ha sido procesada exitosamente.
Los archivos deberían estar visibles y sin atributos maliciosos.

IMPORTANTE: Escanear la USB con un antivirus antes de usarla en otros equipos.

================================================================================
EOF
}

# ============================================================================
# FUNCIONES DE AYUDA
# ============================================================================

show_usage() {
    cat << EOF
Uso: $SCRIPT_NAME [OPCIONES] /punto/de/montaje

Opciones:
  -d, --dry-run       Simular operaciones sin hacer cambios
  -n, --no-backup     Omitir creación de backup
  -v, --verbose       Mostrar información detallada
  -h, --help          Mostrar esta ayuda

Ejemplo:
  sudo $SCRIPT_NAME /media/user/USB
  sudo $SCRIPT_NAME --dry-run /media/user/USB
  sudo $SCRIPT_NAME -v -n /media/user/USB

EOF
}

# ============================================================================
# PARSEO DE ARGUMENTOS
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -n|--no-backup)
                CREATE_BACKUP=false
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                error_exit "Opción desconocida: $1" 1
                ;;
            *)
                if [[ -z "$MOUNT_POINT" ]]; then
                    MOUNT_POINT="$1"
                else
                    error_exit "Solo se permite un punto de montaje" 1
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$MOUNT_POINT" ]]; then
        show_usage
        error_exit "Falta especificar el punto de montaje" 1
    fi
}

# ============================================================================
# FUNCIÓN PRINCIPAL
# ============================================================================

main() {
    parse_arguments "$@"
    
    check_root_privileges
    validate_required_tools
    validate_mount_point "$MOUNT_POINT"
    validate_filesystem "$MOUNT_POINT"
    test_fatattr
    
    setup_environment
    
    if [[ "$CREATE_BACKUP" == true ]]; then
        check_disk_space "$MOUNT_POINT" "$(dirname "$BACKUP_PATH")"
    fi
    
    print_banner
    request_confirmation
    
    create_backup
    
    remove_lnk_files
    
    if [[ "$VERBOSE" == true ]]; then
        list_fat_attributes "Atributos FAT (antes de limpieza)"
    fi
    
    # IMPORTANTE: Normalizar permisos ANTES de modificar atributos FAT
    normalize_permissions
    
    restore_hidden_files
    
    if [[ "$VERBOSE" == true ]]; then
        list_fat_attributes "Atributos FAT (después de limpieza)"
    fi
    
    remove_trash_folders
    
    generate_report
    
    log_success "Proceso completado exitosamente"
}

# ============================================================================
# PUNTO DE ENTRADA
# ============================================================================

main "$@"
