# Решение проблем

## Ошибка: "CUDA driver initialization failed, you might not have a CUDA gpu"

### Признаки:
```
RuntimeError: CUDA driver initialization failed, you might not have a CUDA gpu.
```

### Причины:

1. **Контейнер запущен без доступа к GPU**
   - В RunPod: Endpoint не настроен на использование GPU
   - Локально: Используется `docker run` без флага `--gpus all`

2. **NVIDIA драйверы не установлены или несовместимы**
   - Хост-система не имеет NVIDIA драйверов
   - Версия драйверов несовместима с CUDA 12.8

3. **CUDA runtime не установлен**
   - Базовый образ не включает CUDA runtime
   - Неправильный базовый образ (не CUDA devel variant)

### Решения:

#### Для RunPod:

1. **Проверьте конфигурацию Endpoint:**
   - Убедитесь, что выбран GPU (например, RTX 4090, L40, L40S, RTX 6000 Ada)
   - Проверьте, что CUDA версия совместима (12.8+ рекомендуется)

2. **Проверьте логи при старте:**
   - Должно быть сообщение: `GPU detected: NVIDIA L40 (48GB)` или аналогичное
   - Если видите `WARNING - nvidia-smi not found`, GPU недоступен

#### Для локального запуска:

1. **Используйте флаг `--gpus all`:**
   ```bash
   docker run --gpus all -it your-image-name
   ```

2. **Проверьте доступность GPU на хосте:**
   ```bash
   nvidia-smi
   ```

3. **Убедитесь, что драйверы установлены:**
   ```bash
   nvidia-smi --query-gpu=driver_version --format=csv
   ```

### Проверка в контейнере:

После запуска контейнера проверьте:

```bash
# Внутри контейнера
nvidia-smi
python3 -c "import torch; print('CUDA available:', torch.cuda.is_available())"
python3 -c "import torch; print('CUDA device:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'N/A')"
```

### Что было исправлено:

1. ✅ Обновлена переменная окружения: `PYTORCH_CUDA_ALLOC_CONF` → `PYTORCH_ALLOC_CONF` (исправляет предупреждение)
2. ✅ Добавлена проверка доступности GPU в `start.sh`
3. ✅ Добавлены информативные сообщения об ошибках при отсутствии GPU

### Дополнительная информация:

- **Базовый образ:** `nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04`
- **Требования:** NVIDIA драйверы версии 550+ для CUDA 12.8
- **Поддерживаемые GPU:** L40, L40S, RTX 6000 Ada, RTX 5090, RTX 4090

