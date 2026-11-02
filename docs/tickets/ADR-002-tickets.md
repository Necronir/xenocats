# Epic: ADR-002 — Bremen-4 Progression, Fusion System & Multi-Phase Boss Overhaul

> **Source Specification:** [ADR-002: Progression, Boss Phases, Tiered Fusions & Meta-Narrative](../ADRs/ADR-002-Progression-Fusions-and-Boss-Phases.md)  
> **Engine:** Godot 4.7.2 (Stable) | GDScript Static Typing  
> **Target Release:** Milestone 2.0  
> **GitHub Tracker:** [Necronir/xenocats Issues](https://github.com/Necronir/xenocats/issues)

---

## Ticket Overview Matrix

| # | GitHub Issue | Ticket Title | Priority | Components | Estimated Effort |
|---|---|---|---|---|---|
| **T-01** | [#28](https://github.com/Necronir/xenocats/issues/28) | `feat(progression): Dynamic 4-run story loop and sequential biome unlock topology` | High | `core`, `models`, `map` | 5 SP |
| **T-02** | [#29](https://github.com/Necronir/xenocats/issues/29) | `feat(combat): Tiered robo-fusions with selectable cost tiers in all encounters` | High | `combat`, `models`, `ui` | 5 SP |
| **T-03** | [#30](https://github.com/Necronir/xenocats/issues/30) | `feat(boss): 4-phase final boss with color vulnerability matrix and ensemble finisher` | High | `combat`, `boss`, `qte` | 8 SP |
| **T-04** | [#31](https://github.com/Necronir/xenocats/issues/31) | `feat(story): Biome boss defeat triggers and companion rescue pipeline (MULE & COCK)` | Medium | `combat`, `event`, `save` | 3 SP |
| **T-05** | [#32](https://github.com/Necronir/xenocats/issues/32) | `feat(narrative): Dialogic 2 timelines with 4th-wall break choice and "pisikot" gag` | Medium | `dialogic`, `event`, `combat` | 3 SP |
| **T-06** | [#33](https://github.com/Necronir/xenocats/issues/33) | `feat(boss): "Honored Artists of Pop" comedic fake boss gatekeeper encounter` | Medium | `combat`, `enemy`, `audio` | 3 SP |
| **T-07** | [#34](https://github.com/Necronir/xenocats/issues/34) | `feat(epilogue): Robbers' cabin fairy-tale cutscene and grand victory rock concert` | Medium | `cutscene`, `audio`, `meta` | 5 SP |

---

### Ticket T-01: Dynamic 4-Run Story Loop & Sequential Biome Unlock Topology
* **GitHub Issue:** [#28](https://github.com/Necronir/xenocats/issues/28)
* **Labels:** `feature`, `progression`, `architecture`, `save-system`

#### Summary
Refactor the run progression system from a static 3-sector run to a narrative-driven 4-cycle loop with expanding biome topology:
* **Run 0 (Prologue):** Solo Felix (Cat), shortened **Blue Biome**.
* **Run 1 (Duo):** Felix + Hound, **Red Biome $\rightarrow$ Blue Biome**.
* **Run 2 (Trio):** Felix + Hound + Mule, **Yellow Biome $\rightarrow$ Red Biome $\rightarrow$ Blue Biome**.
* **Run 3 (Quartet):** Full band, **Green Biome $\rightarrow$ Yellow Biome $\rightarrow$ Red Biome $\rightarrow$ Blue Biome**.

---

### Ticket T-02: Tiered Robo-Fusions with Selectable Cost Tiers in All Battles
* **GitHub Issue:** [#29](https://github.com/Necronir/xenocats/issues/29)
* **Labels:** `feature`, `combat`, `fusion`, `ui`

#### Summary
Replace the binary "Pyramid" mechanic with a modular multi-tier Robo-Fusion system available in any combat encounter (normal, elite, boss). Players can choose which unlocked tier to activate based on available Sync Gauge:
* **Tier 1 (50% Sync):** Robo-CatDog (`ROBO_CATDOG`)
* **Tier 2 (75% Sync):** Robo-CatDogDonkey (`ROBO_CATDOG_DONKEY`)
* **Tier 3 (100% Sync):** Robo-RoosterCatDogDonkey (`ROBO_MEGA_PYRAMID`)

---

### Ticket T-03: 4-Phase Final Boss with Color Vulnerability Matrix & Finisher
* **GitHub Issue:** [#30](https://github.com/Necronir/xenocats/issues/30)
* **Labels:** `feature`, `boss`, `combat`, `qte`

#### Summary
Implement the multi-stage Final Boss ("The Chief Broadcast Censor / Audition Board") at the Bremen-4 Spire with Blue/Red/Yellow/Green affinity sectors, fusion breakthrough gates, and synchronized 4-note rhythmic QTE finisher.

---

### Ticket T-04: Biome Boss Defeat Triggers & Companion Rescue Pipeline
* **GitHub Issue:** [#31](https://github.com/Necronir/xenocats/issues/31)
* **Labels:** `feature`, `story`, `event`, `save-system`

#### Summary
Integrate companion rescue logic into biome boss victories:
* Defeating Yellow Biome Boss rescues **M.U.L.E.** (Donkey / Bassist).
* Defeating Green Biome Boss rescues **C.O.C.K.** (Rooster / Synth & Electronic Warfare).

---

### Ticket T-05: Dialogic 2 Timelines with 4th-Wall Break & "Pisikot" Humor Gag
* **GitHub Issue:** [#32](https://github.com/Necronir/xenocats/issues/32)
* **Labels:** `feature`, `narrative`, `dialogic`, `humor`

#### Summary
Implement Dialogic 2 timelines with meta-humor, 4th-wall break, and player choice branching (CatDog boomer joke choice, Mule trader robot concern, Cock callsign response).

---

### Ticket T-06: "Honored Artists of Pop" Comedic Fake Boss Gatekeeper
* **GitHub Issue:** [#33](https://github.com/Necronir/xenocats/issues/33)
* **Labels:** `feature`, `boss`, `combat`, `humor`, `audio`

#### Summary
Implement the comedic fake boss (*"Cyber-Primadonna / Golden Autotune Ensemble"*) at the entrance of the Bremen-4 Concert Hall that flees upon hearing live music.

---

### Ticket T-07: Robbers' Cabin Fairy-Tale Homage & Grand Victory Concert
* **GitHub Issue:** [#34](https://github.com/Necronir/xenocats/issues/34)
* **Labels:** `feature`, `epilogue`, `cutscene`, `audio`

#### Summary
Build the two-part epilogue sequence following the final boss defeat:
1. Act 1: The Robbers' Cabin (accidental Mega-Pyramid transform -> classic animal pyramid -> terrified robbers).
2. Act 2: Victory Rock Concert in the liberated Concert Hall + credits + NG+ unlock.
