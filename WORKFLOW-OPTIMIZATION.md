# Оптимизация Workflow для RTX 4090

## Проблема

Ноды `UnetLoaderGGUF` по умолчанию используют `load_device="offload_device"` (CPU), что включает LowVRAM режим и замедляет работу в 5-10 раз.

## Решение: Добавить `load_device` в workflow

### Было (медленно):

```json
"41": {
    "inputs": {
        "unet_name": "Wan2.2-I2V-A14B-HighNoise-Q5_K_S.gguf"
    },
    "class_type": "UnetLoaderGGUF",
    "_meta": {
        "title": "Unet Loader (GGUF)"
    }
}
```

### Стало (быстро):

```json
"41": {
    "inputs": {
        "unet_name": "Wan2.2-I2V-A14B-HighNoise-Q5_K_S.gguf",
        "load_device": "main_device"
    },
    "class_type": "UnetLoaderGGUF",
    "_meta": {
        "title": "Unet Loader (GGUF)"
    }
}
```

## Для обеих нод (41 и 42)

```json
"41": {
    "inputs": {
        "unet_name": "Wan2.2-I2V-A14B-HighNoise-Q5_K_S.gguf",
        "load_device": "main_device"
    },
    "class_type": "UnetLoaderGGUF",
    "_meta": {
        "title": "Unet Loader (GGUF)"
    }
},
"42": {
    "inputs": {
        "unet_name": "Wan2.2-I2V-A14B-LowNoise-Q5_K_S.gguf",
        "load_device": "main_device"
    },
    "class_type": "UnetLoaderGGUF",
    "_meta": {
        "title": "Unet Loader (GGUF)"
    }
}
```

## Что это делает

- **`"load_device": "main_device"`** - загружает модель напрямую в VRAM (GPU)
- **`"load_device": "offload_device"`** (по умолчанию) - загружает модель на CPU, что включает LowVRAM режим

## Результат

| Настройка | Устройство | LowVRAM | Время |
|----------|-----------|---------|-------|
| `offload_device` (по умолчанию) | CPU | ✅ Включен | **10:50 минут** |
| `main_device` | GPU | ❌ Отключен | **2-3 минуты** |

## Автоматическое исправление

**Хорошая новость:** После пересборки Docker образа код автоматически определит RTX 4090 и переключит `load_device` на `main_device`, даже если вы не добавите это в workflow.

Но если хотите быть уверены, добавьте `"load_device": "main_device"` явно в workflow.

## Дополнительные параметры (опционально)

Для еще большей производительности можно также настроить:

```json
"41": {
    "inputs": {
        "unet_name": "Wan2.2-I2V-A14B-HighNoise-Q5_K_S.gguf",
        "load_device": "main_device",
        "base_precision": "fp16",
        "patch_on_device": true
    },
    "class_type": "UnetLoaderGGUF"
}
```

Но самое важное - это `"load_device": "main_device"`.

