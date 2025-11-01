# Советы по оптимизации Workflow

Этот документ содержит рекомендации по настройке **workflow** для улучшения производительности. Все эти советы пользователь может применить в своем workflow независимо.

## 🚀 Быстрые выигрыши

### 1. Lightning LoRA для Wan 2.2

**Проблема:** Wan 2.2 FP8/FP16 требует 8-16 шагов на кадр, что медленно.

**Решение:** Используйте Lightning LoRA для сокращения шагов до 4-6.

**Как применить:**
1. Скачайте модели LoRA:
   - `Wan2.2-Lightning_I2V-A14B-4steps-lora_HIGH_fp16.safetensors`
   - `Wan2.2-Lightning_I2V-A14B-4steps-lora_LOW_fp16.safetensors`
   - Положите их в `models/loras/`

2. Подготовьте две ветки `KSamplerAdvanced`:
   - **High Noise**: `total_steps=4`, `Add noise ✅`, `Start at Step 0`, `End at Step 2`
   - **Low Noise**: `total_steps=4`, `Add noise ❌`, `Start at Step 2`, `End at Step 10000`

3. Добавьте два узла `LoRALoaderModelOnly` после загрузки UNet:
   - Загрузите HIGH/LOW LoRA
   - Установите `strength=1.0`

**Результат:** На RTX 4090 56-кадровый ролик 480p генерируется за ~60 секунд.

---

### 2. GGUF кванты вместо safetensors

**Проблема:** Большие safetensors модели требуют много VRAM.

**Решение:** Используйте GGUF кванты Q3/Q5, которые легче и быстрее.

**Как применить:**
1. Скачайте GGUF модели:
   - `Wan2.2-I2V-A14B-HighNoise-Q3_K_S.gguf` или `Q5_K_S.gguf`
   - `Wan2.2-I2V-A14B-LowNoise-Q3_K_S.gguf` или `Q5_K_S.gguf`
   - Положите их в `models/diffusion_models/` или `models/unet_gguf/`

2. В workflow:
   - Замените `UnetLoader` на `UnetLoaderGGUF`
   - Выберите GGUF файлы
   - **ВАЖНО:** Для GPU с 20GB+ VRAM (RTX 4090, L40, L40S):
     - Добавьте `"load_device": "main_device"` в inputs ноды
     - Это отключит LowVRAM режим и ускорит работу в 5-10 раз

**Результат:** Уменьшение размера модели и ускорение инференса.

---

### 3. TeaCache для кэширования

**Проблема:** Модели вычисляют одни и те же блоки повторно.

**Решение:** Используйте TeaCache для кэширования внутренних блоков.

**Как применить:**
1. Установите ComfyUI-TeaCache:
   ```bash
   cd /comfyui/custom_nodes
   git clone https://github.com/Gourieff/ComfyUI-TeaCache.git
   pip install -r ComfyUI-TeaCache/requirements.txt
   ```

2. В workflow:
   - После узлов `Load Diffusion Model` и `LoRALoaderModelOnly`
   - Добавьте узел `TeaCache`
   - Установите `rel_l1_thresh=0.2`, `max_skip_steps=3`

3. (Опционально) Добавьте `Compile Model`:
   - Первые 2-3 генерации будут дольше
   - Последующие ускорятся в 2.5-3 раза

**Результат:** До 3x ускорение для Flux и Wan 2.x.

---

### 4. Уменьшить разрешение и длину ролика

**Проблема:** Большое разрешение и длинные ролики = долгая обработка.

**Решение:** Оптимизируйте параметры генерации.

**Рекомендации:**
- **Разрешение:** 720p (1280x720) или 480p (848x480) вместо 1080p
- **FPS:** 12-16 вместо 24-30
- **Длительность:** 30-40 кадров вместо 65-80
- **Steps:** Используйте быстрые расписания (LCM) и меньше шагов, если качество приемлемо

**Для RIFE интерполяции:**
- Генерируйте с меньшим FPS (например, 12)
- Затем используйте узел `RIFE` для удвоения кадров в пост-обработке
- Это быстрее, чем генерировать сразу 24 FPS

**Результат:** Существенное сокращение времени обработки.

---

### 5. Attention mode: SDPA вместо SageAttention

**Проблема:** SageAttention требует компиляции CUDA ядер и может быть нестабилен.

**Решение:** Для WAN моделей используйте SDPA (Scaled Dot-Product Attention).

**Как применить:**
- В узлах WAN (`WanImageToVideo`, `UnetLoaderGGUF`, etc.):
  - Установите `attention_mode="sdpa"` вместо `"sageattn"` или `"auto"`
  - SDPA быстрее и стабильнее для WAN моделей
  - Не требует компиляции CUDA ядер

**Результат:** Минус 10-30% времени генерации и больше стабильности.

---

### 6. Отключить Frame Interpolation

**Проблема:** Frame Interpolation добавляет 2-4 минуты обработки.

**Решение:** Отключите или уменьшите кратность интерполяции, если это возможно.

**Как применить:**
- Если в workflow есть узел `Frame-Interpolation`:
  - Отключите его или уменьшите параметр кратности
  - Используйте только если действительно нужно больше кадров

**Результат:** Экономия 2-4 минуты на каждом запросе.

---

## ⚙️ Дополнительные рекомендации

### Выбор модели

- **Flux1-schnell** вместо flux1-dev — оптимизирован под скорость
- **Tuned модели Wan2.2** для низкого количества шагов

### Настройка VRAM

- **Для GPU с 24-48GB VRAM** (RTX 4090, L40, L40S, RTX 6000 Ada):
  - Отключайте LowVRAM в workflow
  - Указывайте `load_device="main_device"` для всех узлов загрузки моделей

- **Для слабых GPU** (<16GB):
  - Оставляйте LowVRAM включенным
  - Уменьшите batch size до 1

### PyTorch и драйверы

- Убедитесь, что версия PyTorch соответствует CUDA на хосте
- Обновите драйверы NVIDIA до последней версии
- Для RTX 5090 (Blackwell) требуется PyTorch 2.5+ и CUDA 12.8+

---

## 📊 Ожидаемые результаты

После применения всех оптимизаций:

| Оптимизация | Экономия времени |
|-------------|------------------|
| Lightning LoRA | -50-70% времени генерации |
| GGUF + main_device | -80-90% (отключение LowVRAM) |
| TeaCache | -33-66% (2-3x ускорение) |
| SDPA вместо SageAttention | -10-30% |
| Отключение Frame Interpolation | -2-4 минуты |
| Уменьшение разрешения/FPS | -30-50% |
| **ИТОГО** | **С 7+ минут до 1-2 минут** |

---

## 🔧 Пример оптимизированного workflow

### Для Wan 2.2 на RTX 4090:

1. **UnetLoaderGGUF**:
   - `unet_name`: `Wan2.2-I2V-A14B-HighNoise-Q5_K_S.gguf`
   - `load_device`: `"main_device"` ⚠️ **КРИТИЧНО для отключения LowVRAM**

2. **LoRALoaderModelOnly** (после UNet):
   - HIGH: `Wan2.2-Lightning_I2V-A14B-4steps-lora_HIGH_fp16.safetensors`
   - LOW: `Wan2.2-Lightning_I2V-A14B-4steps-lora_LOW_fp16.safetensors`
   - `strength`: `1.0`

3. **KSamplerAdvanced**:
   - High Noise: `steps=4`, `Add noise ✅`, `Start=0`, `End=2`
   - Low Noise: `steps=4`, `Add noise ❌`, `Start=2`, `End=10000`

4. **WanImageToVideo**:
   - `width`: `848` (480p) или `1280` (720p)
   - `height`: `480` или `720`
   - `length`: `30-40` вместо 65+
   - `attention_mode`: `"sdpa"` ⚠️ **ВАЖНО**

5. **TeaCache** (после LoRA):
   - `rel_l1_thresh`: `0.2`
   - `max_skip_steps`: `3`

6. **Video Combine**:
   - `frame_rate`: `12-16` вместо 24-30
   - **Если поддерживается:** Включите NVENC (`h264_nvenc`)

---

## ⚠️ Важные замечания

1. **LowVRAM отключение:** Самое важное для RTX 4090 — обязательно добавьте `"load_device": "main_device"` в ноды `UnetLoaderGGUF`. Без этого LowVRAM будет активен и работа будет в 5-10 раз медленнее.

2. **SDPA vs SageAttention:** Для WAN моделей SDPA быстрее и стабильнее. Используйте его вместо SageAttention.

3. **S3 для видео:** Код автоматически загружает видео в S3 (если настроено), избегая base64. Это значительно улучшает производительность.

4. **NVENC:** Проверьте логи при старте — если ffmpeg поддерживает NVENC, включите его в видеонодах для 2-5x ускорения кодирования.

---

## 📝 Чеклист оптимизации

- [ ] Добавлен `"load_device": "main_device"` в `UnetLoaderGGUF` ноды
- [ ] Используется Lightning LoRA (HIGH + LOW)
- [ ] Установлены параметры `KSamplerAdvanced`: `steps=4`
- [ ] Разрешение снижено до 480p или 720p
- [ ] FPS снижен до 12-16
- [ ] Длина ролика уменьшена до 30-40 кадров
- [ ] `attention_mode="sdpa"` в WAN нодах
- [ ] Frame Interpolation отключен или уменьшен
- [ ] (Опционально) TeaCache добавлен в workflow
- [ ] (Опционально) NVENC включен в видеоноде

