# План оптимизаций проекта (код/окружение)

## 📋 Обзор

Этот документ описывает **только изменения в коде и окружении**. Советы по настройке workflow вынесены в отдельный файл `WORKFLOW-OPTIMIZATION-TIPS.md`.

## 🎯 Цель оптимизаций

1. **Убрать base64 для больших видео** → использовать S3 или чтение с диска
2. **Ускорить I/O операции** → чтение файлов напрямую с диска вместо HTTP /view
3. **Улучшить память** → добавить tcmalloc для оптимизации CPU/IO
4. **Проверить NVENC поддержку** → для ускорения кодирования видео

## ✅ Что будем реализовывать

### 1. **Добавить tcmalloc в Dockerfile**
- ✅ Установить `google-perftools libtcmalloc-minimal4`
- ✅ Уже есть код в `start.sh` для использования (нужно только добавить пакет)

### 2. **Оптимизировать handler.py - чтение с диска**
- ✅ Добавить функцию `_read_from_disk()` для чтения файлов напрямую
- ✅ Использовать её как приоритетный путь, fallback на `get_image_data()` (HTTP /view)

### 3. **Оптимизировать handler.py - форсировать S3 для видео**
- ✅ Добавить переменную окружения `FORCE_S3_VIDEO=true`
- ✅ Автоматически загружать видео в S3, даже если S3 обычно выключен
- ✅ Убрать base64 для больших видео файлов

### 4. **Проверить ffmpeg NVENC поддержку**
- ✅ Добавить проверку в `start.sh` при старте
- ✅ Логировать статус NVENC поддержки

### 5. **Документация**
- ✅ Создать файл с советами по workflow (для пользователя)
- ✅ Обновить README с новыми переменными окружения

## ❌ Что НЕ делаем (это настройки workflow)

- ❌ Lightning LoRA установка (пользователь сам скачивает модели)
- ❌ GGUF модели (пользователь сам выбирает в workflow)
- ❌ TeaCache установка (пользователь сам добавляет узлы)
- ❌ Изменение параметров workflow (разрешение, FPS, шаги)
- ❌ Attention mode настройки (пользователь настраивает в workflow)

**Всё это описано в `WORKFLOW-OPTIMIZATION-TIPS.md` для пользователя.**

## 📝 Детальный план изменений

### Файл: `Dockerfile`

**Изменения:**
1. Добавить `google-perftools libtcmalloc-minimal4` в `apt-get install`

**Место:**
```dockerfile
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    build-essential \
    google-perftools \
    libtcmalloc-minimal4 \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip
```

**Результат:** `start.sh` сможет использовать `libtcmalloc.so.4` для оптимизации памяти

---

### Файл: `handler.py`

**Изменения:**
1. Добавить функцию `_read_from_disk()` в начало файла (после импортов)
2. Изменить логику чтения файлов - сначала с диска, потом HTTP /view
3. Добавить поддержку `FORCE_S3_VIDEO` для видео файлов

**Добавить функцию:**
```python
def _read_from_disk(filename, subfolder, image_type):
    """
    Read file directly from disk instead of HTTP /view.
    This is much faster for large video files.
    
    Args:
        filename: Name of the file
        subfolder: Subfolder path (can be empty)
        image_type: Type of file ("output", "temp", etc.)
    
    Returns:
        bytes: File content, or None if file not found
    """
    root = "/comfyui"
    if image_type in ("output", "temp"):
        base = os.path.join(root, image_type)
    else:
        base = os.path.join(root, "output")
    
    path = os.path.join(base, subfolder, filename) if subfolder else os.path.join(base, filename)
    
    if os.path.isfile(path):
        try:
            with open(path, "rb") as f:
                return f.read()
        except Exception as e:
            print(f"worker-comfyui - Error reading {path} from disk: {e}")
            return None
    return None
```

**Изменить логику чтения файлов (около строки 720):**
```python
# Было:
image_bytes = get_image_data(filename, subfolder, img_type)

# Станет:
# Try reading from disk first (much faster for large videos)
image_bytes = _read_from_disk(filename, subfolder, img_type)
if image_bytes is None:
    # Fallback to HTTP /view if file not found on disk
    image_bytes = get_image_data(filename, subfolder, img_type)
```

**Добавить FORCE_S3_VIDEO логику (около строки 726):**
```python
# Check if this is a video file
file_extension = os.path.splitext(filename)[1].lower() if filename else ".png"
video_exts = [".mp4", ".webm", ".avi", ".mov", ".mkv", ".gif", ".webp"]
is_video = file_extension in video_exts

# Force S3 for videos (to avoid large base64 responses)
force_s3_video = os.environ.get("FORCE_S3_VIDEO", "true").lower() == "true"
use_s3 = (is_video and force_s3_video) or os.environ.get("BUCKET_ENDPOINT_URL")

if use_s3:
    # Upload to S3 (existing code)
    ...
else:
    # Base64 only for images/small files
    ...
```

---

### Файл: `src/start.sh`

**Изменения:**
1. Добавить проверку NVENC поддержки в ffmpeg

**Добавить после проверки GPU:**
```bash
# Check ffmpeg NVENC support
log "worker-comfyui: Checking ffmpeg NVENC support"
if command -v ffmpeg >/dev/null 2>&1; then
    if ffmpeg -encoders 2>/dev/null | grep -q nvenc; then
        log "worker-comfyui: ✓ ffmpeg supports NVENC (hardware video encoding available)"
    else
        log "worker-comfyui: ⚠ ffmpeg does not support NVENC (software encoding will be used)"
    fi
else
    log "worker-comfyui: WARNING - ffmpeg not found"
fi
```

**Результат:** При старте будет видно, поддерживает ли ffmpeg NVENC

---

### Файл: `WORKFLOW-OPTIMIZATION-TIPS.md` (новый)

**Содержание:**
- Советы по настройке workflow (Lightning LoRA, GGUF, TeaCache)
- Рекомендации по параметрам (разрешение, FPS, шаги)
- Настройка attention_mode для WAN моделей

**Это для пользователя** - он сам решает, применять ли эти советы.

---

### Файл: `README.md`

**Обновить раздел с переменными окружения:**
```markdown
## Environment Variables

### S3 Configuration
- `BUCKET_ENDPOINT_URL`: S3 endpoint URL (optional)
- `BUCKET_ACCESS_KEY_ID`: S3 access key (optional)
- `BUCKET_SECRET_ACCESS_KEY`: S3 secret key (optional)
- `FORCE_S3_VIDEO`: Force S3 upload for video files (default: `true`)
  - When enabled, all video files (`.mp4`, `.webm`, etc.) are uploaded to S3
  - This avoids large base64 responses and significantly improves performance
```

---

## 🔄 Порядок реализации

1. ✅ **Обновить Dockerfile** - добавить tcmalloc
2. ✅ **Обновить handler.py** - добавить `_read_from_disk()` и `FORCE_S3_VIDEO`
3. ✅ **Обновить start.sh** - добавить проверку NVENC
4. ✅ **Создать WORKFLOW-OPTIMIZATION-TIPS.md** - советы для пользователя
5. ✅ **Обновить README.md** - документация новых переменных

## 📊 Ожидаемые результаты

### Производительность:
- **Чтение с диска**: Быстрее на 2-5x для больших видео (нет HTTP overhead)
- **S3 вместо base64**: Уменьшение размера ответа на 90%+ для видео
- **tcmalloc**: Ускорение CPU-bound операций на 10-20%
- **NVENC**: Ускорение кодирования видео на 2-5x (если поддерживается)

### Время обработки:
- **Чтение файлов**: -5-10 секунд на каждый запрос
- **Возврат результата**: -30-90 секунд для больших видео (S3 vs base64)
- **Кодирование видео**: -30-60 секунд (NVENC, если доступен)

## ⚠️ Важные замечания

1. **FORCE_S3_VIDEO**: По умолчанию `true`. Если S3 не настроен, будут ошибки. Можно отключить через `FORCE_S3_VIDEO=false`.

2. **Чтение с диска**: Работает только для файлов в `/comfyui/output` и `/comfyui/temp`. Для других путей используется fallback на HTTP /view.

3. **NVENC**: Зависит от версии ffmpeg. Может потребоваться пересборка ffmpeg с NVENC поддержкой, если не работает.

4. **tcmalloc**: Работает автоматически после установки пакета (код в `start.sh` уже есть).

