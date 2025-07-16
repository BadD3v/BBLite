**BBLite**  
*A modular, slot-based, schema-aware data framework for Roblox.*

---

**Description**  
BBLite is a structured database system for Roblox, built around schema correction, slot saving, and encrypted state management. Built with efficiency and developer extensibility in mind, BBLite avoids unnecessary abstractions while offering high flexibility for structured persistence and state validation. It is licensed under the **BBLite License**, with runtime enforcement of its licensing protections.

---

**Purpose**  
BBLite was designed to support complex save architectures in multiplayer games, such as MMO frameworks, inventory systems, or modular progression trees. It enables version-patched saves, dynamic schema correction, secure per-slot data auditing, and UUID-based player tracking — all while keeping a low overhead per operation.

---

**Key Features**  
- Schema-based fallback + recursive field patching  
- Per-user, per-slot UUID assignment and resolution  
- XOR-encrypted payloads with checksum validation  
- Auto-saving, stale detection, and tamper checks  
- Runtime license enforcement via script and property checks  
- Save log, session pruning, and key auditing  
- Public API for custom item patching, tagging, and deep field access  
- Slot comparison and data cloning utilities

---

**Limitations**  
- Not compatible with non-primitive types (userdata, functions, etc.)  
- Data compression is not supported  
- Runtime dependency on script names and licensing structures  
- Does not handle networking or replication (backend-only)
-# Please remember this is BBLite; Not BBFull. BBFull is expected to come out soon with all these capabilities plus 100 functions!

---

**Setup**  
Place BBLitePack in ServerScriptService, foldered or not. Opening BBConfig brings you to a simplistic Schema to use. All values/data added into the Schema as of installation are **MANDATORY** for BBLite to work.

all you need to customize is the BBConfig script, and the system does the rest. Despite the automatically made database system, there are over 50 functions as of **Version 1.4.3**!
---

**Licensing**  
BBLite and BBFull are licensed under the **BBLite License**.  
The license permits use, modification, and distribution with attribution.
