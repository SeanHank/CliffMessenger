# Cliff Messenger

**Cliff Messenger** is an end-to-end encrypted, privacy-focused instant messaging application designed exclusively for group communication. Built with Flutter, it provides robust security through encrypted message exchange, and a decentralized architecture that puts you in complete control of your data.

_“Reborn in blood beneath the radiance of divinity, it awaken to a world transformed, its soul rekindled by sacred light and carried forward by the echoes of destiny.”_

## Contents

- [Getting Started](#getting-started)
- [Highlights](#highlights)
- [Features](#features)
- [License](#license)
- [Credits](#credits)
- [Contributing](#contributing)

## Getting Started

### Installation

Simply download the latest release and enjoy! 

## Highlights

### Security First

- **End-to-End Encryption**: All messages are encrypted using AES with group-specific keys.
- **RSA-2048 Key Exchange**: Secure key distribution using RSA padding.
- **Password-Protected Private Keys**: User private keys are encrypted with AES. 
- **Encrypted Local Database**: SQLCipher-encrypted local storage protects cached messages.
- **Double File Encryption**: Files are encrypted with both file-specific keys and group keys.

### Decentralized Architecture

- **Self-Hosted Servers**: Run your own messaging server with zero configuration.
- **LAN Discovery**: Automatic server discovery - no manual IP configuration needed.
- **No Central Infrastructure**: Communicate directly over your local network without internet dependency.

### Privacy by Design

- **Server Never Sees Plaintext**: The server operates as a blind relay, storing and forwarding only encrypted data. Once data was sent, the server removes the data from its memory and database.
- **Per-User Key Management**: Each user maintains their own cryptographic keypair.
- **Group Key Re-Encryption**: When members join or leave, keys are securely re-encrypted.

## Features

### Core Messaging

| Feature | Description |
|---------|-------------|
| Text Messages | Send and receive encrypted text messages in group chats |
| Image Sharing | Share images with automatic encryption and compression |
| File Transfer | Send any file type with double-layer encryption |
| Offline Support | Messages queued and delivered upon reconnection |

### Group Management

| Feature | Description |
|---------|-------------|
| Create Groups | Establish new groups with automatically generated encryption keys |
| Invite Codes | UUID-based invite codes for secure group joining |
| Join Requests | Admin-approved membership with secure key distribution |
| Member Management | Add or remove members with real-time key re-encryption |
| Group Dissolution | Complete group cleanup by administrators |

### Server Mode

| Feature | Description |
|---------|-------------|
| One-Click Hosting | Launch a messaging server with minimal configuration |
| WebSocket Protocol | Efficient real-time communication over WebSocket |
| mDNS Discovery | Automatic LAN server advertisement and discovery |
| Encrypted Storage | Server-side encrypted file and message storage |

### Security Features

| Feature | Description |
|---------|-------------|
| AES-256-GCM | Military-grade symmetric encryption for all messages |
| RSA-2048 | Asymmetric encryption for secure key exchange |
| BCrypt | Password hashing with salt for authentication |
| SQLCipher | Encrypted local database for message caching |
| PBKDF2 | Key derivation with multiple SHA-256 iterations |

## License

**All rights reserved.**  
Copyright © Sean Hank.

See: `LICENSE`

## Credits

See: `CREDITS.md`

## Contributing

This repository is currently NOT accepting public contributions.

Forks and private modifications are not supported through official channels. Users who wish to create derivative works may do so under the constraints of the copyright license, though no assistance or guidance for such modifications is provided.

Questions, bug reports, and feature requests will not receive responses through public channels. The project maintains its current scope and direction without external input.
