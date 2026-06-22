# Last Colony — Flutter RTS

A real-time strategy game built with **Flutter + Flame**, a remake/homage of
Aditya Ravishankar's HTML5 *Last Colony* (from *Pro HTML5 Games*).

▶️ **Play in the browser:** https://applepang-cloud.github.io/last-colony/

## Features

- Tile-based map with **A\*** pathfinding
- Units: **Scout Tank, Heavy Tank, Harvester, Chopper, Wraith** (aircraft fly over terrain)
- Buildings: **Command Base, Turret, Power Plant** — with in-game **construction** (ghost placement)
- **Resource economy** — harvesters mine ore and deposit credits
- **Fog of war** (explored / visible), enemies hidden until scouted
- **Combat** with rotating turrets, muzzle flashes and explosions
- **Sound** (procedurally generated WAV effects)
- **3-mission story campaign** with scripted triggers, waves and reinforcements
- **Local 2-player hotseat** — share one device, swap sides with `TAB` / the SWAP button
- **Mouse + keyboard** and **touch** controls

## Controls

| Action | Desktop | Touch |
|---|---|---|
| Select | drag a box / click a unit | tap a unit |
| Order (move / attack / harvest) | right-click | tap destination |
| Pan camera | `WASD` / arrow keys | drag |
| Build units | `1`–`5` | sidebar |
| Build structures | `T` turret · `P` power plant | sidebar |
| Switch side (hotseat) | `TAB` | SWAP button |

## Run locally

```bash
flutter pub get
flutter run -d chrome      # web
flutter run                # device/emulator
flutter test               # unit + simulation tests
```

## Project layout

```
lib/
  main.dart            # app, HUD overlays, input, menu
  game/
    game.dart          # game loop, camera, fog, economy, AI, input
    entities.dart      # units, buildings, bullets, effects
    grid.dart          # tile grid + A* pathfinding
    missions.dart      # trigger system + campaign + skirmish
    sound.dart         # SoundFx wrapper
tool/gen_audio.dart    # regenerates assets/audio/*.wav
```

## Credits

Game design inspired by [adityaravishankar/last-colony](https://github.com/adityaravishankar/last-colony).
This is an independent reimplementation in Dart/Flutter (graphics are original vector art).
