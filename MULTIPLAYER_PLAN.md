# Multiplayer Implementation Plan (Godot 4 High-Level Multiplayer)

## Phase 1: Architecture & Setup

### 1.1 Networking Model
*   **Architecture**: Authoritative Server (Host) with Clients.
    *   One player acts as **Host** (Server + Client).
    *   Other players join as **Clients**.
*   **Protocol**: ENet (Godot's default high-level multiplayer).
*   **Port**: Default 8910 (configurable).

### 1.2 Global Network Manager (`NetworkManager.gd`)
*   Create an Autoload `NetworkManager` to handle:
    *   `CreateGame()`: `enet_peer.create_server()`
    *   `JoinGame(ip)`: `enet_peer.create_client()`
    *   Player connections/disconnections signals (`peer_connected`, `peer_disconnected`).
    *   Syncing player info (Name, ID) across clients.

## Phase 2: Lobby & UI

### 2.1 Main Menu Update
*   Add "MULTIPLAYER" button to `MainMenu.tscn`.
*   Create a simple "Lobby" UI panel:
    *   **Host**: Input Port, "Start Server" button.
    *   **Join**: Input IP, Port, "Join" button.
    *   **Lobby Status**: List of connected players (Names).
    *   **Start Game**: Only visible to Host, transitions to `main.tscn`.

### 2.2 Player Registration
*   When a peer connects, they send their "Name" via RPC.
*   Server maintains a dictionary `players_network_data = { peer_id: { "name": "...", "chips": 5000 } }`.
*   Server broadcasts updated player list to all clients.

## Phase 3: Game Logic Adaptation (`GameManager.gd`)

### 3.1 Server Authority
*   `GameManager` logic only runs on the **Server** (Host).
*   Clients only receive state updates and visualize them.
*   **Rule**: `if not multiplayer.is_server(): return` for all game logic functions (`start_game`, `_start_new_round`, `_next_player_turn`, etc.).

### 3.2 RPC Implementation
*   **Server -> Clients (Broadcasts)**:
    *   `sync_game_state(state)`: Tell clients the current game phase.
    *   `sync_community_cards(cards)`: Send community cards.
    *   `sync_player_hand(peer_id, cards)`: **Targeted RPC**. Send hole cards ONLY to the specific player.
    *   `sync_pot_update(total_pot)`: Update pot UI.
    *   `notify_turn(player_id)`: Tell UI whose turn it is.
    *   `broadcast_action(player_id, action, amount)`: Show action log/animation to everyone.
    *   `game_over_state(winners)`: Show results.

*   **Client -> Server (Actions)**:
    *   `request_player_action(action, amount)`: Client sends their move.
    *   Server validates: Is it this player's turn? Is the move legal?
    *   If valid, Server executes `process_player_action` and broadcasts result.

### 3.3 Dynamic Spawning
*   `TableBuilder.gd` needs to spawn `HumanPlayer` nodes for *every* connected peer.
*   The "Local Player" (You) is identified by matching `multiplayer.get_unique_id()` with the player object's ID (or a generic `network_id` property).

## Phase 4: Implementation Steps

1.  **Create `NetworkManager.gd`**: Autoload setup.
2.  **UI**: Add Multiplayer menu.
3.  **Refactor `GameManager`**:
    *   Add `multiplayer_mode` flag.
    *   Wrap logic in `is_server()` checks.
    *   Add RPC functions for client sync.
4.  **Refactor `HumanPlayer`**:
    *   Instead of emitting local signals, call `NetworkManager.send_action()`.
5.  **Testing**: Test with 2 instances (Host + Client).

## Issues to Watch For
*   **Bot Handling**: In Multiplayer, the Host runs the Bots. Bots are just local logic on the Server.
*   **ID Mapping**: Godot uses integer Peer IDs. Our game uses String IDs ("You", "Bot_1").
    *   *Solution*: Switch to using Integer Network IDs for logic, or map Network ID -> String Name.
    *   *Decision*: Use `str(peer_id)` as the unique ID for network players. Host is `1`.

