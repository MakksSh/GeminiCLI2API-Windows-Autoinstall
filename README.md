# GeminiCLI2API Windows Autoinstall 🧩💻

Авто-установщик `geminicli2api` под Windows (PowerShell):

* Сам установит `uv` и `git` (если нет)
* Скачает репозиторий, настроит `.env`, установит зависимости
* Запоминает, на каком шаге остановился
* Логирует всё в консоль и в файл

## Что нужно заранее

1. **Windows 10/11**
2. Прочитай гайд от Фрэнки https://t.me/AIandDrama/129 В нём нас интересуют разделы со вступлением, "Подготовка аккаунта" и "Как подключить". Раздел установки на Windows пропускаем, скрипт сделает всё за вас.
3. У тебя должен быть **Google Cloud Project** (нужен его АЙДИ!)
4. БОНУС! Как получить доступ к Gemini 3 описано здесь: https://t.me/AIandDrama/151

> Найти айди проекта можно в Cloud Console: https://console.cloud.google.com/home/dashboard Убедись, что сверху слева выбран нужный проект. Плашка Project info -> Project ID

## Установка

1. Создай папку в любом удобном тебе месте - в ней будет сама cli и установщик.
2. Открой PowerShell в этой папке (Shift + ПКМ -> "Открыть окно PowerShell здесь", или ткни в адрес в проводнике в открытой папке напиши там `powershell` и нажми Enter).
3. Запусти скрипт:

```powershell
irm https://raw.githubusercontent.com/MakksSh/GeminiCLI2API-Windows-Autoinstall/refs/heads/main/cli2api.ps1 -OutFile cli2api.ps1; if ($?) { powershell -ExecutionPolicy Bypass -File .\cli2api.ps1}
```

Скрипт спросит `GOOGLE_CLOUD_PROJECT` (айди проекта).

Можно сразу передать айди аргументом:

```powershell
irm https://raw.githubusercontent.com/MakksSh/GeminiCLI2API-Windows-Autoinstall/refs/heads/main/cli2api.ps1 -OutFile cli2api.ps1; if ($?) { powershell -ExecutionPolicy Bypass -File .\cli2api.ps1 gen-lang-client-1234567890}
```

Айди в конце замени на свой айди проекта

## Как запускать в следующий раз

Запусти созданный установщиком файл `StartCLI.bat` внутри папки `geminicli2api`.

Он сразу запустит CLI без лишних операций.

## Что делает скрипт

Скрипт по шагам:

1. Проверяет и устанавливает `uv` (менеджер пакетов Python) и `git`.
2. Клонирует/обновляет репозиторий `geminicli2api`.
3. Чинит `requirements.txt` (гарантирует `pydantic<2.0`).
4. Создаёт/обновляет `.env` и прописывает туда `GOOGLE_CLOUD_PROJECT`.
5. Создаёт виртуальное окружение (`uv venv`) и ставит зависимости (`uv pip install`).
6. Запускает `run.py`.

## ВАЖНО: как правильно запускать Таверну рядом

* Окно PowerShell, где запустился `geminicli2api`, не закрывай.
* Открой SillyTavern (или другой клиент) отдельно.
* Остановить скрипт можно нажав `Ctrl+C` в окне PowerShell.

## Если скрипт видит папку `geminicli2api`

При запуске, если папка уже существует, он может спросить:

**“Perform a FULL REINSTALL (delete folder and start fresh)?”**

* `y` → удалит папку, всё обновит и поставит заново.
* `n` → попробует продолжить с существующими файлами.

## Где логи и “память прогресса”

Скрипт хранит состояние в папке `.geminicli2api-installer` (рядом со скриптом):
* Логи: `install.log`
* Состояние: `state.env`

## Как “сбросить всё и начать с нуля”

Открой PowerShell в папке СКРИПТА (Shift + ПКМ -> "Открыть окно PowerShell здесь", или ткни в адрес в проводнике в открытой папке напиши там `powershell` и нажми Enter), не в папке geminicli2api!

Выполни команду:
```powershell
irm https://raw.githubusercontent.com/MakksSh/GeminiCLI2API-Windows-Autoinstall/refs/heads/main/cli2api.ps1 -OutFile cli2api.ps1; if ($?) { powershell -ExecutionPolicy Bypass -File .\cli2api.ps1 --reset}
```
Скрипт запросит подверждение и выполнит переустановку

## Контакты

* Автор скрипта: https://t.me/Maks_Sh
* Мой ТГК с полезными гайдами: https://t.me/btwiusesillytavern
* Канал Фрэнки: https://t.me/AIandDrama
* Репо geminicli2api: https://github.com/gzzhongqi/geminicli2api
