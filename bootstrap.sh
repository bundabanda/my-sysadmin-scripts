#!/usr/bin/env bash
set -Eeuo pipefail

# Учебная автоматизация Docker, RAID 1 и LVM в Ubuntu VM.
# Все диски создаются как файлы в /mnt/raid-lab.
# Скрипт не должен форматировать уже существующие файловые системы.

readonly LAB_DIR="/mnt/raid-lab"
readonly DISK1="${LAB_DIR}/disk1.img"
readonly DISK2="${LAB_DIR}/disk2.img"
readonly DISK3="${LAB_DIR}/disk3.img"
readonly RAID_DEVICE="/dev/md0"
readonly RAID_MOUNT="/mnt/raid"
readonly VG_NAME="vg_data"
readonly LV_NAME="lv_logs"
readonly LV_DEVICE="/dev/${VG_NAME}/${LV_NAME}"
readonly LVM_MOUNT="/mnt/logs"

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

log() {
    printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    printf '\nОШИБКА: %s\n' "$*" >&2
    exit 1
}

trap 'die "Сбой в строке ${LINENO}. Проверь вывод команды выше."' ERR

if [[ "${EUID}" -ne 0 ]]; then
    die "Запусти скрипт через sudo: sudo ./bootstrap.sh"
fi

if [[ ! -f "${PROJECT_DIR}/script.sh" ]]; then
    die "Не найден ${PROJECT_DIR}/script.sh"
fi

if [[ ! -f "${PROJECT_DIR}/Dockerfile" ]]; then
    die "Не найден ${PROJECT_DIR}/Dockerfile"
fi

log "Шаг 1: установка необходимых пакетов"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y docker.io mdadm lvm2 e2fsprogs util-linux

log "Шаг 2: запуск Docker"
systemctl enable --now docker
docker --version

log "Шаг 3: подготовка файлов виртуальных дисков"
mkdir -p "${LAB_DIR}"

create_disk_file() {
    local file="$1"

    if [[ -e "${file}" ]]; then
        log "Файл уже существует, сохраняем его: ${file}"
    else
        log "Создаём виртуальный диск-файл: ${file}"
        dd if=/dev/zero of="${file}" bs=1M count=512 status=progress
    fi
}

create_disk_file "${DISK1}"
create_disk_file "${DISK2}"
create_disk_file "${DISK3}"

get_or_attach_loop() {
    local file="$1"
    local loop_device

    # Если файл уже подключён, используем существующее устройство.
    loop_device="$(losetup -j "${file}" | cut -d: -f1 | head -n1)"

    if [[ -n "${loop_device}" ]]; then
        printf '%s' "${loop_device}"
        return 0
    fi

    # Иначе подключаем файл к первому свободному loop-устройству.
    losetup -fP --show "${file}"
}

log "Шаг 4: подключение loop-устройств"
LOOP1="$(get_or_attach_loop "${DISK1}")"
LOOP2="$(get_or_attach_loop "${DISK2}")"
LOOP3="$(get_or_attach_loop "${DISK3}")"

printf 'Диск 1: %s\n' "${LOOP1}"
printf 'Диск 2: %s\n' "${LOOP2}"
printf 'Диск 3: %s\n' "${LOOP3}"

# Не допускаем случайного использования одного устройства для разных дисков.
if [[ "${LOOP1}" == "${LOOP2}" ||
      "${LOOP1}" == "${LOOP3}" ||
      "${LOOP2}" == "${LOOP3}" ]]; then
    die "Несколько файлов связаны с одним loop-устройством. Нужна ручная проверка."
fi

log "Шаг 5: создание RAID 1"

if [[ -b "${RAID_DEVICE}" ]]; then
    log "Устройство ${RAID_DEVICE} уже существует; не пересоздаём массив."
else
    # Проверяем, что на выбранных устройствах нет уже существующих метаданных.
    for device in "${LOOP1}" "${LOOP2}"; do
        if mdadm --examine "${device}" >/dev/null 2>&1; then
            die "На ${device} найдены метаданные RAID, но ${RAID_DEVICE} отсутствует. Нужна ручная проверка."
        fi
    done

    # Создание разрешено только для наших трёх файловых loop-устройств.
    yes | mdadm --create "${RAID_DEVICE}" \
        --level=1 \
        --raid-devices=2 \
        "${LOOP1}" "${LOOP2}"
fi

udevadm settle

if [[ ! -b "${RAID_DEVICE}" ]]; then
    die "RAID-устройство ${RAID_DEVICE} не появилось."
fi

# Форматируем только устройство без обнаруженной файловой системы.
if blkid "${RAID_DEVICE}" >/dev/null 2>&1; then
    log "На ${RAID_DEVICE} уже есть файловая система; форматирование пропускается."
else
    log "Создаём ext4 на ${RAID_DEVICE}"
    mkfs.ext4 "${RAID_DEVICE}"
fi

mkdir -p "${RAID_MOUNT}"

if ! mountpoint -q "${RAID_MOUNT}"; then
    mount "${RAID_DEVICE}" "${RAID_MOUNT}"
fi

log "Шаг 6: создание LVM"

# Инициализируем PV только если LVM ещё не распознаёт устройство.
if ! pvs --noheadings -o pv_name 2>/dev/null |
    awk '{$1=$1; print}' |
    grep -Fxq "${LOOP3}"; then

    # Не затираем неизвестные сигнатуры на устройстве.
    if wipefs -n "${LOOP3}" | grep -q .; then
        die "На ${LOOP3} уже есть сигнатуры. Автоматическая инициализация остановлена."
    fi

    pvcreate "${LOOP3}"
else
    log "Physical Volume на ${LOOP3} уже существует."
fi

if ! vgs --noheadings -o vg_name 2>/dev/null |
    awk '{$1=$1; print}' |
    grep -Fxq "${VG_NAME}"; then
    vgcreate "${VG_NAME}" "${LOOP3}"
else
    log "Volume Group ${VG_NAME} уже существует."
fi

if ! lvs --noheadings -o lv_name "${VG_NAME}" 2>/dev/null |
    awk '{$1=$1; print}' |
    grep -Fxq "${LV_NAME}"; then
    lvcreate -L 200M -n "${LV_NAME}" "${VG_NAME}"
else
    log "Logical Volume ${LV_NAME} уже существует."
fi

if [[ ! -b "${LV_DEVICE}" ]]; then
    die "Не найден логический том ${LV_DEVICE}"
fi

if blkid "${LV_DEVICE}" >/dev/null 2>&1; then
    log "На ${LV_DEVICE} уже есть файловая система; форматирование пропускается."
else
    log "Создаём ext4 на ${LV_DEVICE}"
    mkfs.ext4 "${LV_DEVICE}"
fi

mkdir -p "${LVM_MOUNT}"

if ! mountpoint -q "${LVM_MOUNT}"; then
    mount "${LV_DEVICE}" "${LVM_MOUNT}"
fi

log "Шаг 7: сборка Docker-образа"
docker build -t my-script "${PROJECT_DIR}"

log "Шаг 8: итоговая проверка"
printf '\n--- Docker images ---\n'
docker images

printf '\n--- RAID status ---\n'
cat /proc/mdstat
mdadm --detail "${RAID_DEVICE}"

printf '\n--- LVM ---\n'
pvs
vgs
lvs

printf '\n--- Mount points ---\n'
findmnt "${RAID_MOUNT}"
findmnt "${LVM_MOUNT}"

log "Готово: известные этапы Docker, RAID 1 и LVM выполнены."
log "nginx, TLS и systemd для приложения будут добавлены после сверки со второй частью задания."
