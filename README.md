# Cliff Messenger

**Cliff Messenger** is an end-to-end encrypted, privacy-focused instant messaging application designed exclusively for group communication. Built with Flutter, it runs as a single app that can act as both a **self-hosted messaging server** and a **client**, communicating in real time over WebSocket with automatic LAN discovery via mDNS — no central infrastructure, no internet dependency.

_“Reborn in blood beneath the radiance of divinity, it awaken to a world transformed, its soul rekindled by sacred light and carried forward by the echoes of destiny.” — Sean Hank_

<img width="1080" height="1920" alt="771_1x_shots_so" src="https://github.com/user-attachments/assets/0002ea4e-1d02-4f58-a9c8-ebe96725f176" />

## Contents

- [Getting Started](#getting-started)
- [Highlights](#highlights)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Security Design](#security-design)
- [Features](#features)
- [Protocol](#protocol)
- [Contributing](#contributing)
- [License](#license)

---

## Getting Started

### Run a Pre-built Release

Simply download the latest release for your platform and enjoy.

### Build from Source

Prerequisites:

- Flutter SDK `^3.10.9`
- Dart SDK `^3.10.9`
- For macOS / iOS: CocoaPods and Xcode
- For Android: Android Studio / Gradle
- For desktop (Windows/Linux): respective Flutter desktop toolchains

```bash
# Install dependencies
flutter pub get

# Run on a connected device or emulator
flutter run

# Build a release artifact
flutter build <platform>   # apk | ios | macos | windows | linux | web
```

The first launch shows a mode selection screen — pick **Server Mode** to host a messaging server on this device, or **Client Mode** to discover and connect to a server on your local network.

### Supported Platforms

Android, iOS, macOS, Windows, Linux, and Web. The device-bound database key derivation adapts to each platform (ANDROID_ID, identifierForVendor, systemGUID, computerName, machineId, etc.).

## Highlights

### Security First

- **End-to-End Encryption**: All messages are encrypted using AES-256-GCM with group-specific keys
- **RSA-2048 Key Exchange**: Secure key distribution using RSA-OAEP padding with PKCS#8 PEM-encoded keys
- **Password-Protected Private Keys**: User private keys are encrypted locally with AES-256-GCM, using a key derived from the user's password via 10,000 rounds of SHA-256
- **Encrypted Local Database**: SQLCipher-encrypted client storage; the database key is bound to the device hardware identifier
- **Double File Encryption**: Files are encrypted with a file-specific AES key, which is then encrypted again with the group key
- **Per-Member Group Keys**: Each member receives the group key encrypted with their own RSA public key, so compromise of one member's key does not expose the group key in transit

### Decentralized Architecture

- **Self-Hosted Servers**: Run your own messaging server with zero configuration — the server is embedded in the same app
- **LAN Discovery**: Automatic server discovery over mDNS (`_cliff._tcp`) — no manual IP configuration needed
- **No Central Infrastructure**: Communicate directly over your local network without internet dependency

### Privacy by Design

- **Server Never Sees Plaintext**: The server operates as a blind relay, storing and forwarding only encrypted data. Once a message is delivered, it is removed from the server's memory and database
- **Per-User Key Management**: Each user maintains their own cryptographic keypair, stored only on their device
- **Group Key Re-Encryption**: When members join or leave, keys are securely re-encrypted for the new membership set

## Architecture

Cliff Messenger is a dual-mode Flutter application. A single binary can act as a server, a client, or both — the user chooses the mode at startup.

```
┌─────────────────────────────────────────────────────────────┐
│                        Cliff Messenger App                   │
│                                                              │
│   ┌──────────────────┐         ┌──────────────────────────┐ │
│   │   Server Mode    │         │      Client Mode         │ │
│   │                  │         │                          │ │
│   │  shelf HTTP/WS   │◄───────►│  WebSocket Client        │ │
│   │  ServerManager   │  WS     │  ServerConnection        │ │
│   │  Sembast DB      │         │  SQLCipher DB (per-user) │ │
│   │  File Storage    │         │  File Storage (per-user) │ │
│   │  mDNS Register   │         │  mDNS Discovery          │ │
│   └──────────────────┘         └──────────────────────────┘ │
│                                                              │
│   Shared core: crypto (AES/RSA/BCrypt), protocol, models    │
└─────────────────────────────────────────────────────────────┘
```

### State Management

Built on the `provider` package with three change-notifier providers wired up at app startup:

| Provider | Responsibility |
|----------|----------------|
| `ServerProvider` | Mode selection, server start/stop, server discovery, client connection management |
| `AuthProvider` | Registration, login, RSA key lifecycle, group key decryption & caching, join-request approval |
| `ChatProvider` | Message loading/pagination, send text/image/file, file download & decryption, group key lookup |

### Communication Flow

1. **Server Mode** starts a `shelf` HTTP server, upgrades `/ws` to WebSocket, and advertises itself via mDNS.
2. **Client Mode** listens for mDNS services (polls every 5s), or accepts manual host/port entry.
3. The client opens a WebSocket, registers/logs in, and exchanges JSON `WSMessage` frames.
4. Messages are encrypted on the client with the group's AES key; the server only stores and forwards ciphertext.

## Project Structure

```
lib/
├── main.dart                      # App entry; initializes DB, registers providers
├── core/
│   ├── constants/
│   │   ├── theme.dart             # Material 3 dark theme (purple palette)
│   │   └── app_strings.dart       # Localized UI strings
│   ├── crypto/
│   │   ├── aes_crypto.dart        # AES-256-GCM text/file/key encryption
│   │   ├── rsa_crypto.dart        # RSA-2048 OAEP, PKCS#8 PEM encode/decode
│   │   ├── key_manager.dart       # Per-user keypair storage & password-based encryption
│   │   ├── db_key_manager.dart    # Device-bound SQLCipher key derivation
│   │   └── bcrypt_helper.dart     # Password hashing helper
│   ├── network/
│   │   ├── protocol.dart          # WSMessage types & factory constructors
│   │   └── mdns_discovery.dart    # mDNS service register & query
│   └── utils/
│       ├── logger.dart            # Logging wrapper
│       └── utils.dart             # UUID & file utilities
├── models/
│   ├── user.dart                  # UserModel
│   ├── group.dart                 # GroupModel (with per-member encrypted keys)
│   ├── message.dart               # MessageModel, FileAttachment, MessageType
│   ├── server_config.dart         # Server connection config
│   └── discovered_server.dart     # mDNS-discovered server info
├── providers/
│   ├── server_provider.dart       # Server/client mode & discovery state
│   ├── auth_provider.dart         # Auth state & group key management
│   └── chat_provider.dart         # Chat state & message crypto
├── client/
│   ├── client_manager.dart        # Multi-server connection registry
│   ├── websocket_client.dart      # ServerConnection: WS transport & message handling
│   ├── db/
│   │   ├── client_db.dart         # SQLCipher global & per-user message DB
│   │   ├── message_store.dart     # Message CRUD & pagination
│   │   └── server_store.dart      # Saved server configs (sembast)
│   └── storage/
│       └── file_storage.dart      # Per-user decrypted file cache
├── server/
│   ├── server_manager.dart        # shelf HTTP/WS server & message routing
│   ├── db/
│   │   ├── server_db.dart         # Sembast database handle
│   │   ├── user_store.dart        # User records
│   │   ├── group_store.dart       # Group records
│   │   ├── offline_store.dart     # Offline message queue
│   │   ├── group_join_request_store.dart  # Pending join requests
│   │   └── group_dissolve_store.dart      # Dissolve notifications
│   └── storage/
│       └── file_storage.dart      # Encrypted file storage
├── screens/
│   ├── splash_screen.dart
│   ├── mode_selection_screen.dart
│   ├── server_setup_screen.dart
│   ├── server_running_screen.dart
│   ├── server_select_screen.dart
│   ├── discovery_screen.dart
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── home_screen.dart
│   ├── chat_screen.dart
│   ├── create_group_screen.dart
│   └── join_group_screen.dart
└── widgets/
    ├── message_bubble.dart
    └── group_card.dart
```

## Security Design

### Cryptographic Primitives

| Purpose | Algorithm | Details |
|---------|-----------|---------|
| Message encryption | AES-256-GCM | 16-byte random IV per message; auth tag included |
| File encryption | AES-256-GCM | 16-byte random IV; IV prepended to ciphertext |
| Key exchange | RSA-2048 | OAEP padding, PKCS#8 PEM format |
| Password hashing | BCrypt | Server-side, with random salt |
| Private key protection | AES-256-GCM | Key derived from password via 10,000 rounds of SHA-256 (PBKDF2-style), with random 16-byte salt & 12-byte IV |
| Local DB encryption | SQLCipher | Key derived from device hardware ID + static salt via SHA-256 |
| Group key wrapping | RSA-2048 | Each member's group key is encrypted with their own RSA public key |
| File key wrapping | AES-256-GCM | File-specific key encrypted with the group key |

### Key Hierarchy

```
User Password ──(PBKDF2-style)──► Private Key Encryption Key
                                          │
                                          ▼
                              RSA-2048 Private Key (encrypted at rest)
                                          │
                          (decrypts per-member encrypted group keys)
                                          │
                                          ▼
                                    Group AES-256 Key
                                          │
                          (decrypts message content & file keys)
                                          │
                                          ▼
                                    File AES-256 Key
                                          │
                                          ▼
                                    File Plaintext
```

### Group Key Lifecycle

- **Create group**: Server generates an AES-256 group key, encrypts it with the creator's RSA public key.
- **Join request**: Applicant submits a join request; the group owner approves or rejects.
- **Approve**: Owner decrypts the group key, fetches the applicant's public key from the server, re-encrypts the group key for the new member, and stores a per-member `encryptedGroupKeys` map. Each member only ever receives their own encrypted copy.
- **Leave / dissolve**: Members are removed from the group; if the owner leaves, the group is dissolved and all members are notified.
- **Offline delivery**: Join requests and dissolve notifications are persisted server-side and pushed when the recipient reconnects.

## Features

### Core Messaging

| Feature | Description |
|---------|-------------|
| Text Messages | Send and receive encrypted text messages in group chats |
| Image Sharing | Share images with automatic encryption and compression |
| File Transfer | Send any file type with double-layer encryption; chunked upload (64 KB chunks) |
| Offline Support | Messages queued server-side and delivered upon reconnection, with pagination |
| Message Pagination | Load history in 50-message pages, scrolling back from the oldest loaded message |

### Group Management

| Feature | Description |
|---------|-------------|
| Create Groups | Establish new groups with automatically generated AES-256 keys |
| Invite Codes | UUID-based invite codes for secure group joining |
| Join Requests | Admin-approved membership with secure per-member key distribution |
| Member Management | Add or remove members with per-member key re-encryption |
| Group Dissolution | Owner-initiated complete group cleanup; offline members notified on reconnect |
| Leave Group | Non-owner members can leave; owner departure dissolves the group |

### Server Mode

| Feature | Description |
|---------|-------------|
| One-Click Hosting | Launch a messaging server with minimal configuration |
| WebSocket Protocol | Efficient real-time communication over WebSocket (`shelf_web_socket`) |
| mDNS Discovery | Automatic LAN server advertisement and discovery (`_cliff._tcp`) |
| Encrypted Storage | Server-side encrypted file and message relay storage |
| Offline Queue | Persists undelivered messages and pushes them on recipient reconnection |

### Client Mode

| Feature | Description |
|---------|-------------|
| Auto Discovery | Scans the LAN for advertised servers every 5 seconds |
| Manual Connect | Direct host/port entry for non-discoverable servers |
| Multi-Server | Save and switch between multiple server connections |
| Per-User Storage | Each logged-in user gets an isolated SQLCipher database and file cache |
| Ping Keepalive | 30-second heartbeat to detect dropped connections |

## Protocol

All communication uses JSON `WSMessage` frames over WebSocket:

```json
{
  "type": "<message-type>",
  "id": "<uuid-v4>",
  "payload": {}
}
```

### Message Types

| Category | Types |
|----------|-------|
| Server info | `server_info`, `server_info_response` |
| Auth | `register`, `register_success`, `register_failed`, `login`, `login_success`, `login_failed` |
| Messaging | `msg`, `msg_ack` |
| Groups | `group_create`, `group_join`, `group_list`, `group_update`, `leave_group` |
| Join approval | `group_join_request`, `group_join_approve`, `group_join_reject`, `group_join_result` |
| Key exchange | `group_key_transfer`, `group_key_request`, `user_public_key`, `get_user_public_key` |
| Files | `file_upload`, `file_download`, `file_data`, `file_complete` |
| Offline | `offline_fetch`, `offline_page` |
| Heartbeat | `ping`, `pong` |
| Errors | `error` |

The server is a stateful relay: it authenticates users, tracks connected clients, routes group messages to online members, queues messages for offline members, and mediates group join/key-exchange flows. Message payloads remain opaque ciphertext to the server.

## Contributing

Contributions are welcomed! This project follows a standard fork-and-PR workflow.

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/SeanHank/CliffMessenger.git`
3. **Create a branch**: `git checkout -b feature/my-feature`
4. **Make changes**
5. **Commit** with clear messages
6. **Open a Pull Request**

## License

This project is licensed under the **GNU Affero General Public License v3.0** (AGPLv3).  

Copyright © 2026 Sean Hank.
