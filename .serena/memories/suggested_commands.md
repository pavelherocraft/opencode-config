# Команды для проекта «Рефакторинг» (Windows, конфиги/доки, без сборки)

- **Поиск/якоря:** `rg -n "<pattern>" <file>`, `rg -c` (счёт), `rg -l` (файлы). Проверять уникальность якоря (`rg -c` → 1) ПЕРЕД string-replace правкой.
- **Валидация JSON после правок opencode.json:**
  `powershell -NoProfile -Command "Get-Content 'C:\Users\Admin\.config\opencode\opencode.json' -Raw | ConvertFrom-Json | Out-Null; 'JSON OK'"`
- **Сравнение файлов (live vs deploy snapshot):** `fc /b <file1> <file2>` → «FC: no differences encountered».
- **Проверка развёртывания:** `powershell deploy-package\scripts\verify.ps1` (считает agents\*.md, сейчас ожидает ≥35; после Phase 5 — 36).
- **Тестирование конфигов:** только в НОВОЙ сессии opencode (конфиг читается на старте). Пилоты: `opencode --agent plankestrator` / `--agent orchestrator`.
- **Откат:** проектные файлы — `git restore <files>`; live-конфиги — копирование из `backup\<дата>_<тема>\`.
- **Git-коммиты:** ТОЛЬКО через агента `git-commit` (Task tool) — прямые `git commit`/`git push` запрещены глобальными правилами.
- Линтеров/тестов кода нет; `utility`-агент — синтаксическая проверка .md/конфигов по pipeline.
