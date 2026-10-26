RAID 1 и LVM
RAID 1
- Два виртуальных диска созданы из файлов disk1.img и disk2.img.
- RAID-массив: /dev/md0.
- Файловая система: ext4.
- Точка монтирования: /mnt/raid.

LVM
- Виртуальный диск disk3.img.
- Physical Volume: loop-устройство, disk3.img.
- Volume Group vg_data.
- Logical Volume lv_logs.
- Размер логического тома 200M.
- Файловая система ext4.
- Точка монтирования /mnt/logs.
