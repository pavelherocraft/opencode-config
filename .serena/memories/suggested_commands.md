# Команды для проекта «Рефакторинг» (Windows, конфиги/доки, без сборки)

- **Поиск/якоря:** `rg -n "<pattern>" <file>`, `rg -c` (счёт), `rg -l` (файлы). Проверять уникальность якоря (`rg -c` → 1) ПЕРЕД string-replace правкой.
- **Валидация JSON после правок opencode.json:**
  `powershell -NoProfile -Command "Get-Content 'C:\Users\Admin\.config\opencode\opencode.json' -Raw | ConvertFrom-Json | Out-Null; 'JSON OK'"`
- **Синхронизация live ↔ repo (канонический путь, НЕ ручной Copy-Item):**
  ```powershell
  & "P:\Programming\Рефакторинг\.opencode\skills\config-sync\scripts\sync.ps1" -Plan    # drift-report
  & "P:\Programming\Рефакторинг\.opencode\skills\config-sync\scripts\sync.ps1" -Save    # live -> repo
  ```
  Ожидаемый результат `-Plan`: `STATUS:IN_SYNC` (5 пар). При расхождении — `STATUS:DRIFT_DETECTED`, лечится `-Save`.
- **Аудит реестра моделей** (read-only, severity nit/concern/blocker):
  `& "P:\Programming\Рефакторинг\.opencode\skills\provider-config-audit\scripts\audit.ps1"` (есть `.py`-зеркало с идентичным выводом).
- **Проверка целостности репо:** скилл `.opencode\skills\integrity-check` (drift-report + производные счётчики).
- **Тестирование конфигов:** только в НОВОЙ сессии opencode (конфиг читается на старте). Пилоты: `opencode --agent plankestrator` / `--agent orchestrator`.
- **Откат:** проектные файлы — `git restore <files>`; live-конфиги — копирование из `backup\<дата>_<тема>\` либо `config-sync -Restore`.
- **Git-коммиты:** ТОЛЬКО через агента `git-commit` (Task tool) — прямые `git commit`/`git push` запрещены глобальными правилами.
  ```powershell
  # коммит (gates: секреты, чувствительные имена, conflict-маркеры)
  & "...\commit.ps1" -Message "<subject>" -Files "a.md","b.md"
  # push уже закоммиченного (без нового коммита)
  & "...\commit.ps1" -PushOnly -RepoDir "P:\Programming\Рефакторинг"
  ```
- Линтеров/тестов кода нет; `utility`-агент — синтаксическая проверка .md/конфигов по pipeline. Скиллы `.ps1`+`.py` — держать в паритете (вывод должен быть идентичным).
