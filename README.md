# dualsense-battery

Заряд всех подключённых DualSense (и других геймпадов) в строке меню macOS.

- иконка геймпада + проценты по каждому: `🎮 80%  40%⚡︎`; ≤20% без зарядки — красным
- в меню: имя, заряд, состояние (заряжается / заряжен / от батареи), кружок цвета световой полосы — чтобы различать два одинаковых
- обновление: при подключении/отключении, при открытии меню и раз в 30 с
- «Запускать при входе» в меню — кладёт/убирает `~/Library/LaunchAgents/com.geforester.dualsense-battery.plist`

Источник — GameController.framework (`GCController.battery`), работает по Bluetooth и USB,
не конфликтует с chiaki/SDL. DualSense отдаёт заряд шагами ~10%.

## Сборка

```bash
./build.sh                    # → ~/Applications/DualSense Battery.app + ~/.local/bin/dualsense-battery
open ~/Applications/DualSense\ Battery.app
dualsense-battery --once      # разово в терминал (exit 1, если геймпадов нет)
```

## Статус

- 2026-11-25: собрано, запускается; без геймпада проверено «не подключены».
  С живым DualSense ещё не проверено.
