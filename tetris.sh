#!/bin/bash

download_node() {
  echo "Начинаю установку ноды через Docker..."

  # Правильная установка Docker
  echo "Установка Docker..."
  sudo apt-get remove docker docker-engine docker.io containerd runc || true
  sudo apt-get update
  sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    wget \
    jq
  
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Загрузка файла infera
  wget -O infera "https://drive.google.com/uc?id=1VSeI8cXojdh78H557SQJ9LfnnaS96DT-&export=download&confirm=yes"
  chmod +x infera

  # Создание Dockerfile
  cat <<EOF > Dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \
    curl git nano make gcc build-essential jq screen \
    ca-certificates gcc unzip lz4 wget bison software-properties-common \
    && apt-get clean
COPY infera /usr/local/bin/infera
RUN chmod +x /usr/local/bin/infera
CMD ["infera"]
EOF

  # Сборка Docker-образа
  docker build -t infera-node .

  # Запуск контейнера с параметром network=host
  docker run -d --name infera-node --network="host" --restart unless-stopped infera-node

  echo "Нода успешно установлена и запущена в контейнере Docker!"
}

check_points() {
  total_points=$(curl -s http://localhost:11025/points | jq)
  echo -e "У вас столько поинтов: $total_points"
}

watch_secrets() {
  curl -s http://localhost:11025/node_details | jq
}

check_logs() {
  docker logs --tail 100 infera-node
}

restart_node() {
  echo "Перезагружаю ноду..."
  docker restart infera-node
  echo "Нода была успешно перезагружена."
}

setup_auto_restart() {
  echo "Настраиваю автоматический перезапуск ноды каждые 2 часа..."
  (crontab -l 2>/dev/null; echo "0 */2 * * * docker restart infera-node >> /root/node_restart.log 2>&1") | crontab -
  echo "✅ Автоматический перезапуск настроен!"
  echo "🕐 Нода будет перезапускаться каждые 2 часа"
  echo "📝 Логи перезапуска сохраняются в /root/node_restart.log"
}

disable_auto_restart() {
  echo "Отключаю автоматический перезапуск..."
  crontab -l | grep -v "docker restart infera-node" | crontab -
  echo "✅ Автоматический перезапуск отключен"
}

link_and_downgrade() {
  echo "🔄 План действий:"
  echo "1. Сохраним текущие рабочие ключи"
  echo "2. Обновимся до новой версии и используем те же ключи"
  echo "3. Привяжем ноду к аккаунту"
  echo "4. Вернемся на старую версию с теми же ключами"
  echo -e "\n"
  
  read -p "Продолжить? (y/n): " confirm
  if [[ "$confirm" != "y" ]]; then
    echo "Операция отменена"
    return
  fi

  # Шаг 1: Сохраняем текущие рабочие ключи
  echo "📦 Сохраняем текущие ключи..."
  rm -rf node_backup
  mkdir -p node_backup
  docker cp infera-node:/root/.local/share/node_info/. node_backup/
  
  echo "📋 Проверьте текущие ключи:"
  cat node_backup/node_file.txt
  read -p "Ключи верные? (y/n): " confirm_keys
  if [[ "$confirm_keys" != "y" ]]; then
    echo "❌ Отмена операции"
    rm -rf node_backup
    return 1
  fi

  # Шаг 2: Обновляем до новой версии с теми же ключами
  echo "🔄 Обновляем до новой версии..."
  docker stop infera-node
  docker rm infera-node
  docker rmi infera-node
  
  wget -O infera_node https://inferabuilds.s3.us-east-1.amazonaws.com/0.0.3_infera_build_linux
  chmod +x infera_node
  
  # Создаем Dockerfile для новой версии с сохраненными ключами
  cat <<EOF > Dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \
    curl git nano make gcc build-essential jq screen \
    ca-certificates gcc unzip lz4 wget bison software-properties-common \
    && apt-get clean

RUN mkdir -p /root/.local/share/node_info
COPY node_backup/. /root/.local/share/node_info/
COPY infera_node /usr/local/bin/infera_node
RUN chmod +x /usr/local/bin/infera_node
CMD ["infera_node"]
EOF

  docker build -t infera-node .
  docker run -d --name infera-node --network="host" --restart unless-stopped infera-node
  
  echo "⏳ Ждем запуска ноды..."
  sleep 15
  
  # Шаг 3: Привязываем ноду
  echo "🔗 Привязка ноды к аккаунту"
  echo "------------------------"
  echo "1. Убедитесь, что у вас есть аккаунт на https://infera.org"
  echo "2. Скопируйте ваш Account ID из личного кабинета"
  echo "3. Нажмите кнопку 'Link CLI node' на сайте"
  echo -e "\n"
  
  read -p "Вставьте полную команду для привязки ноды: " link_command
  
  echo "🔄 Выполняю привязку ноды..."
  eval "$link_command"
  
  echo -e "\n🔍 Проверяю статус привязки..."
  sleep 5
  curl -s http://localhost:11025/node_details | jq
  
  # Шаг 4: Возвращаемся на старую версию с теми же ключами
  echo "🔄 Возвращаемся на старую версию..."
  docker stop infera-node
  docker rm infera-node
  docker rmi infera-node
  
  wget -O infera "https://drive.google.com/uc?id=1VSeI8cXojdh78H557SQJ9LfnnaS96DT-&export=download&confirm=yes"
  chmod +x infera
  
  cat > Dockerfile << EOF
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \
    curl git nano make gcc build-essential jq screen \
    ca-certificates gcc unzip lz4 wget bison software-properties-common \
    && apt-get clean

RUN mkdir -p /root/.local/share/node_info
COPY node_backup/. /root/.local/share/node_info/
COPY infera /usr/local/bin/infera
RUN chmod +x /usr/local/bin/infera

CMD ["infera"]
EOF

  docker build -t infera-node .
  docker run -d \
    --name infera-node \
    --network="host" \
    --restart unless-stopped \
    infera-node
  
  echo "✅ Процесс завершен!"
  echo "⏳ Ждем запуска..."
  sleep 15
  
  echo -e "\n🔍 Проверяем статус:"
  curl -s http://localhost:11025/node_details | jq
  
  rm -rf node_backup
}

update_node() {
  echo "Начинаю обновление ноды..."
  docker stop infera-node && docker rm infera-node
  docker rmi infera-node
  download_node
}

delete_node() {
  read -p "Вы уверены, что хотите удалить ноду? (нажмите y для продолжения): " confirm
  if [[ "$confirm" == "y" ]]; then
    echo "Удаляю ноду..."
    docker stop infera-node && docker rm infera-node
    docker rmi infera-node
    rm -f infera Dockerfile
    echo "Нода успешно удалена."
  else
    echo "Операция отменена."
  fi
}

check_auto_restart() {
  if crontab -l | grep -q "docker restart infera-node"; then
    echo "✅ Автоперезапуск активен"
    echo "🕐 Текущее расписание:"
    crontab -l | grep "docker restart infera-node"
    
    current_minute=$(date +%M)
    minutes_left=$((120 - (current_minute % 120)))
    hours_left=$((minutes_left / 60))
    mins_left=$((minutes_left % 60))
    
    echo "⏳ Следующий перезапуск через: ${hours_left}ч ${mins_left}мин"
  else
    echo "❌ Автоперезапуск не активен"
  fi
}

exit_from_script() {
  exit 0
}

while true; do
  echo -e "\n\nМеню:"
  echo "1. 🌱 Установить ноду"
  echo "2. 📊 Проверить сколько поинтов"
  echo "3. 📂 Посмотреть данные"
  echo "4. 🕸️ Посмотреть логи"
  echo "5. 🍴 Перезагрузить ноду"
  echo "6. 🔄 Обновить ноду"
  echo "7. ❌ Удалить ноду"
  echo "8. ⏰ Включить авто-перезапуск (каждые 2 часа)"
  echo "9. 🚫 Отключить авто-перезапуск"
  echo "10. 📋 Проверить статус авто-перезапуска"
  echo "11. 🔗 Привязать ID и вернуться на старую версию"
  echo "12. 🚪 Выйти из скрипта"
  
  read -p "Выберите пункт меню: " choice

  case $choice in
    1)
      download_node
      ;;
    2)
      check_points
      ;;
    3)
      watch_secrets
      ;;
    4)
      check_logs
      ;;
    5)
      restart_node
      ;;
    6)
      update_node
      ;;
    7)
      delete_node
      ;;
    8)
      setup_auto_restart
      ;;
    9)
      disable_auto_restart
      ;;
    10)
      check_auto_restart
      ;;
    11)
      link_and_downgrade
      ;;
    12)
      exit_from_script
      ;;
    *)
      echo "Неверный пункт. Пожалуйста, выберите правильную цифру в меню."
      ;;
  esac
done
