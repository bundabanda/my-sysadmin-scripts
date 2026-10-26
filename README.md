# my-sysadmin-scripts

Проект Bash, Git и Docker.
- `script.sh` — Bash-скрипт мониторинга ресурсов.
- `Dockerfile` — инструкция сборки Docker-образа.
- `bootstrap.sh` — автоматизация подготовки Docker, учебного RAID 1 и LVM.
- `storage-lab.md` — описание лабораторной работы с хранилищем.
- `sample_output.txt` — пример вывода скрипта.

Запуск скрипта

```bash
chmod +x script.sh
./script.sh

Часть 2: Nginx, HTTPS и systemd

Контейнер `my-app` запускает HTTP-сервер на порту 8080.
Nginx перенаправляет HTTP на HTTPS.

Используется самоподписанный сертификат.

Проверка

```bash
sudo nginx -t
curl -kI https://127.0.0.1/
sudo systemctl status my-app --no-pager
sudo journalctl -u my-app -n 50 --no-pager
sudo tail -n 30 /var/log/nginx/access.log
