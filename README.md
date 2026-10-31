# 🐾 Xenocats: Emergency Frequency Bremen-4

**A 2D party-based roguelike JRPG featuring modular mecha-cat assembly (Front Mission), timed attack QTEs (Paper Mario), real-time bullet-hell dodging (Undertale), and narrative events (Dialogic 2).**

* **Engine:** Godot 4.7.2 (Stable)
* **Language:** GDScript (strict static typing via `typed_gdscript`)
* **Base Resolution:** `640 × 360` (Pixel-Perfect 16:9, `Nearest` texture filtering, 2D Pixel Snapping)
* **Architecture:** Data-Driven (`Resource` / `.tres`), see [ADR-001](docs/ADR-001-Architecture-Design-Record.md)

---

## 📖 Story & Setting

In orbit above the untamed planet **Xenos-Prime**, the heavy cargo transport `Bremen-04` explodes. Its wreckage rains down into a toxic industrial scrapyard sector.
The protagonist — **FELIX** (a lightweight service android cat who narrowly escaped a magnetic crusher) — awakens amid the ruins. The ship's systems are dead, but atop a cyclopean relay tower on the horizon, an emergency transmitter — **Bremen-4** — blinks into the smog.

To fight through three sectors of feral scavenger drones ("The Brigands") led by a rogue factory logistics AI ("Atamansha") and broadcast an SOS signal into deep space, FELIX unites a gang of decommissioned robo-cats — defective prototypes inspired by the *Town Musicians of Bremen*.

---

## ⚙️ Core Gameplay Mechanics

### 1. The Decommissioned Cat Squad (4vX Party Combat)
| Character | Base Chassis | Archetype | Combat Role & Signature Abilities |
| :--- | :--- | :--- | :--- |
| **FELIX** | Domestic Service Android | Agile Striker / Combo Leader | High initiative, laser claws (applies **Mark** to trigger ally combo damage), battery grenades, party speed overdrive. |
| **M.U.L.E.** | Heavy Cargo Loader | Tank / Shield Support | Caterpillar tracks and a bulldozer scoop shield. Provokes enemy attacks (**Taunt**) and deploys group overheat shields (**Shield**). |
| **H.O.U.N.D.** | Security Patrol Droid | Bruiser / Armor Piercer | Sawblade jaws. Inflicts **Oil Leak (Bleed)** on enemy modules and delivers devastating armor-ignoring strikes. |
| **C.O.C.K.** | Electronic Warfare Unit | Mage / Crowd Control / Healer | Parabolic ear antennas and a tail-mounted megaphone. Stuns enemies (**Stun**) with acoustic waves, cleanses debuffs, and repairs ally cores. |

### 2. Modular Mecha System (Front Mission 3-Part Model)
Each of the 4 cats (as well as **Elite** and **Boss** enemies) consists of **3 independent destructible parts**, each with its own HP pool, armor rating, and attached skills:
* **Body (`Core`):** central reactor. If its HP drops to `0`, the unit is knocked out (`KO`).
* **Arms (`Weapons`):** combat manipulators. At `HP == 0`, weapon skills are disabled and the cat falls back to a weak *Emergency Poke* (while bosses lose access to their heavy weapon attacks).
* **Legs (`Chassis`):** locomotion unit. At `HP == 0`, the unit's initiative drops by **70%**, and avatar movement speed inside the defensive Dodge Box is reduced by **40%**.

### 3. Hybrid Real-Time Turn-Based Combat
* **Offense (Paper Mario QTE):** executing an attack triggers a timing bar. Hitting the cyan sweet-spot grants a `×1.5` critical multiplier and bonus Harmony (`Sync Gauge`) charge.
* **Defense (Undertale Dodge Box):** during enemy turns, a real-time bullet-hell arena opens. The defending cat's core avatar features **3 independent segmented `Area2D` colliders**:
  * **Top Segment** → projectile hits deal damage to `Arms`
  * **Center Segment** → projectile hits deal damage to `Body`
  * **Bottom Segment** → projectile hits deal damage to `Legs`

### 4. Signature Mechanic: "The Bremen Pyramid" (Docking)
Successful QTE crits, Mark combos, and flawless dodges fill the **Harmony Bar (`Sync Gauge`)**. At 100% charge, all surviving cats leap onto each other's shoulders, locking magnetic connectors to form a single towering mecha-totem for 1 round:
* Cleanses all negative status effects and grants a party-wide energy shield.
* Unlocks 2 ultimate abilities:
  * **Acoustic Storm** — massive AoE sonic bombardment across all enemies with a high stun chance.
  * **Cascade Overload** — a concentrated full-arsenal burst against a single target/part that pierces all armor and shields.

### 5. Roguelike Map (StS DAG) & Vagabond Camp (Hub)
* The climb toward the relay spire spans **3 biome sectors** of **15 floors** each (procedurally generated Directed Acyclic Graph seeded by `run_seed`):
  1. *Scrap Valley* — Sector Boss: **Three-Headed Press**
  2. *Outlaw Hub* — Sector Boss: **Atamansha (Crane-Walker)**
  3. *Bremen Spire* — Final Boss: **Sleeping Satellite Bremen-4**
* Node types: `COMBAT`, `ELITE`, `WORKSHOP (Garage)`, `EVENT (Dialogic 2 Transmission)`, `BOSS`.
* In the **Vagabond Camp (Hub)**, players spend `Titanium Scrap` to upgrade shuttle modules, `AI Cores` to unlock passive neural perks for each cat, and insert **Emergency Music Tapes** into the deck to change combat music and grant passive team auras.

---

## 🗂 Repository Structure

```text
res://
├── assets/
│   ├── sprites/          # Pixel-art sprites for cat parts, enemies, bosses, portraits, and UI
│   ├── audio/            # Music tapes (tapes/) and synthesized retro sound effects (sfx/)
│   └── fonts/            # UI fonts
├── addons/
│   └── dialogic/         # Official Dialogic 2 plugin
├── data/
│   ├── dialogues/        # Narrative event timelines (.dtl)
│   └── resources/        # Data-Driven resources (.tres): parts/, skills/, enemies/, music_tapes/
├── docs/
│   └── ADR-001-Architecture-Design-Record.md
├── src/
│   ├── core/             # EventBus, SaveManager, AudioManager, SceneManager (GameRoot)
│   ├── models/           # Strictly-typed models & resources (PartData, CatMechInstance, EnemyInstance...)
│   ├── combat/           # CombatArena, CombatFSM, QTEController, and dodge_box/DodgeArena
│   ├── map/              # 15-floor deterministic DAG generator (MapGenerator) and MapScene
│   ├── garage/           # Part repair and modular assembly screen (GarageScene)
│   ├── event/            # Narrative events powered by Dialogic 2 + EventBus (EventScene)
│   └── hub/              # Vagabond Camp meta-progression screen (HubScene)
└── tools/
    ├── generate_assets.py    # Procedural pixel-art & WAV audio generator
    ├── export_resources.gd   # Exports catalog definitions to .tres files
    └── verify_all_systems.gd # Automated headless test suite for all subsystems & scenes
```

---

## 🎮 Controls

* **Mouse (`LMB`):** select map nodes, skills, target specific enemy parts, and interact with Garage/Hub menus.
* **`Space` / `Enter` / `Z` (or `STRIKE!` button):** lock in timing on the attack QTE bar.
* **`WASD` / `Arrow Keys`:** move the 3-segmented cat core inside the `DodgeArena` during enemy attacks.

---

## 🚀 Running & Testing

### Launch the Game
```powershell
& "E:\godot\Godot_v4.7.2-stable_win64.exe" --path "E:\xenocats\xenocats"
```

### Open in Godot 4.7.2 Editor
```powershell
& "E:\godot\Godot_v4.7.2-stable_win64.exe" -e --path "E:\xenocats\xenocats"
```

### Run Automated Verification Suite (Headless CI)
```powershell
& "E:\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "E:\xenocats\xenocats" "res://tools/verify_scene.tscn"
```

---

## 🛠️ CI/CD & GitHub Releases

The project includes an automated GitHub Actions CI/CD pipeline:

### 1. Continuous Integration (CI) — `.github/workflows/ci.yml`
* Triggered automatically on every `push` and `pull_request` targeting `main`.
* Caches the headless Godot 4.7.2 binary for fast execution.
* Imports assets and runs the automated test verification suite (`res://tools/verify_scene.tscn`).

### 2. Multi-Platform Build & Release — `.github/workflows/release.yml`
* **Automated Release via Git Tag:**
  ```bash
  git tag v0.1.0
  git push origin v0.1.0
  ```
* **Manual Trigger via GitHub Actions UI (`workflow_dispatch`):**
  Enables one-click release builds directly from the GitHub Actions tab with customizable tag name, draft, or pre-release flags.
* **Target Export Platforms:**
  * **Windows Desktop (`x86_64`):** `Xenocats-Windows-x86_64.zip` (standalone executable with embedded `.pck`)
  * **Linux (`x86_64`):** `Xenocats-Linux-x86_64.zip` (standalone executable with execute permissions)
  * **Web (`HTML5/Wasm`):** `Xenocats-Web.zip` + automatic deployment to **GitHub Pages**
* **Automated Release Notes:** GitHub automatically generates release changelogs from commits and pull requests.

