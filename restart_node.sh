#!/bin/bash

echo "🔄 Перезапускаю ноду..."
docker restart infera-node

echo "⏳ Жду 10 секунд для полного запуска..."
sleep 10

echo "🔍 Проверяю статус..."
curl -s http://localhost:11025/node_details | jq

echo "✅ Нода перезапущена"
