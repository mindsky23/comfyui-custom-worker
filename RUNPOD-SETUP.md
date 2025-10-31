# Настройка RunPod Serverless

Инструкция по запуску volume-based подхода в RunPod Serverless.

## Структура Volume в RunPod

Убедитесь, что ваш Network Volume имеет следующую структуру:
```
/workspace/
├── ComfyUI/          # ComfyUI установка
│   ├── main.py
│   ├── custom_nodes/
│   └── ...
└── models/           # Модели (в корне workspace, НЕ внутри ComfyUI)
    ├── checkpoints/
    ├── clip/
    ├── loras/
    └── ...
```

## Шаг 1: Сборка Docker образа

### Локально

```bash
# Сборка образа
docker build -f Dockerfile.volume-based -t your-dockerhub-username/comfyui-runpod-worker:latest .

# Проверка образа локально (опционально)
docker run --rm -it --gpus all \
  -v "C:\comfyui:/workspace" \
  your-dockerhub-username/comfyui-runpod-worker:latest \
  echo "Image test OK"
```

### Загрузка в Docker Hub

```bash
# Войти в Docker Hub
docker login

# Загрузить образ
docker push your-dockerhub-username/comfyui-runpod-worker:latest
```

**Важно**: Замените `your-dockerhub-username` на ваш реальный username в Docker Hub.

## Шаг 2: Настройка в RunPod

### 2.1. Создание Network Volume (если еще нет)

1. Перейдите в [RunPod Network Volumes](https://www.runpod.io/console/user/storage)
2. Создайте новый Volume или используйте существующий
3. Убедитесь, что Volume содержит:
   - `/workspace/ComfyUI/` - установка ComfyUI
   - `/workspace/models/` - ваши модели

### 2.2. Создание Serverless Endpoint

1. Перейдите в [RunPod Serverless](https://www.runpod.io/console/serverless)
2. Нажмите **"New Endpoint"**
3. Заполните форму:

   **Template Configuration:**
   - **Container Image**: `your-dockerhub-username/comfyui-runpod-worker:latest`
   
   **Hardware Configuration:**
   - **GPU**: Выберите один из вариантов:
     - **RTX A4000** (16GB) - ваш текущий GPU, рекомендуется ✅
     - **RTX 3090** (24GB) - больше VRAM для больших моделей
     - **RTX 4090** (24GB) - самая быстрая для ComfyUI
     - **A6000** (48GB) - для очень больших моделей
   - **CUDA Version**: 
     - Базовый образ `hearmeman/comfyui-wan-template:v10` использует **CUDA 12.x**
     - В RunPod выберите **CUDA 12.1+** или **CUDA 12.6** (если доступно) ✅
     - Минимальная версия: **CUDA 11.8** (но лучше 12.x для совместимости)
     - 📖 Подробные рекомендации см. в **[GPU-CUDA-RECOMMENDATIONS.md](GPU-CUDA-RECOMMENDATIONS.md)**
   - **RAM**: согласно вашим потребностям (60GB для вашего случая)
   
   **Network Volume Configuration:**
   - **Volume**: Выберите ваш Network Volume
   - **Mount Path**: `/workspace`
   - Убедитесь, что Volume смонтирован в `/workspace`
   
   **Environment Variables (Optional):**
   ```
   PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:256
   MALLOC_ARENA_MAX=2
   REFRESH_WORKER=false
   ```
   
   **Advanced Settings:**
   - **Timeout**: установите достаточно большое значение (например, 3600 секунд = 1 час)
   - **Max Workers**: количество параллельных инстансов (обычно 1 достаточно)

4. Нажмите **"Deploy"**

## Шаг 3: Тестирование

### Через RunPod API

```bash
# Получите API ключ из RunPod Console
export RUNPOD_API_KEY="your-api-key"

# Создайте тестовый запрос
curl -X POST https://api.runpod.io/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -d '{
    "query": "mutation { podFindAndDeployOnDemand(input: { ... }) { ... } }"
  }'
```

### Через RunPod Python SDK

```python
import runpod

# Настройка API ключа
runpod.api_key = "your-api-key"

# Формат запроса для handler
job_input = {
    "workflow": {
        # Ваш workflow JSON
    }
}

# Отправка запроса
response = runpod.endpoint.submit("your-endpoint-id", job_input)
print(response)
```

## Шаг 4: Проверка логов

1. В RunPod Console перейдите к вашему Serverless Endpoint
2. Откройте вкладку **"Logs"**
3. Проверьте, что видите:
   - `worker-comfyui: ComfyUI found in /workspace/ComfyUI`
   - `worker-comfyui: Creating symlink /workspace/ComfyUI/models -> /workspace/models`
   - `worker-comfyui: ComfyUI API is reachable`
   - `worker-comfyui: Starting handler...`

## Важные моменты

### 1. Структура Volume

- ✅ ComfyUI должен быть в `/workspace/ComfyUI/`
- ✅ Модели должны быть в `/workspace/models/`
- ✅ Скрипт автоматически создаст симлинк и `extra_model_paths.yaml`

### 2. Timeout

Установите достаточно большой timeout в RunPod, так как:
- Первый запуск включает установку `sageattention` (может занять несколько минут)
- Запуск ComfyUI может занять время
- Генерация видео может занять 15-20 минут

Рекомендуемый timeout: **3600 секунд (1 час)** или больше.

### 3. Environment Variables

Опциональные переменные окружения для настройки:
- `REFRESH_WORKER=true` - контейнер завершается после каждого job (экономия ресурсов)
- `REFRESH_WORKER=false` - контейнер остается активным между job'ами (быстрее, но дороже)

### 4. Monitoring

Следите за:
- Логами в RunPod Console
- Использованием GPU
- Временем выполнения задач

## Troubleshooting

### Проблема: ComfyUI не находит модели

**Решение**: Проверьте логи на наличие сообщений о создании симлинка и `extra_model_paths.yaml`. Убедитесь, что Volume правильно смонтирован в `/workspace`.

### Проблема: Handler не запускается

**Решение**: Проверьте логи на наличие ошибок. Убедитесь, что ComfyUI успешно запустился и API доступен на `127.0.0.1:8188`.

### Проблема: Timeout

**Решение**: Увеличьте timeout в настройках Serverless Endpoint. Проверьте, не зависает ли установка `sageattention`.

## Пример запроса для тестирования

```json
{
  "input": {
    "workflow": {
      // Ваш workflow JSON из ComfyUI
      // Экспортируйте его через ComfyUI UI -> Save (API Format)
    }
  }
}
```

## Дополнительные ресурсы

- [RunPod Serverless Documentation](https://docs.runpod.io/serverless/)
- [RunPod Python SDK](https://github.com/runpod/runpod-python)
- [ComfyUI API Documentation](https://github.com/comfyanonymous/ComfyUI)

