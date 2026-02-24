# SimpleVNC (KRVN)

SimpleVNC is a single Windows application that can run in four roles:
- `Client` (controls a remote machine)
- `Server` (public relay/broker)
- `Provider` (machine being controlled)
- `Combo` (`Server + Provider` in one process)

The app uses a custom relay protocol (KRVN) over TCP and is designed for scenarios where the Provider is behind NAT/CGNAT.

## Requirements

- Windows
- Delphi / RAD Studio environment (project is VCL, Win32)
- Open TCP port for server (default: `5590`) if you host relay for external access

## Project Files

- `SimpleVNC.dproj` / `SimpleVNC.dpr` - main project
- `krvn.config.json` - runtime config (auto-created near EXE)
- `provider.id` - persistent provider identity (auto-created near EXE)
- `logs\` - runtime logs

## Default Accounts (first run)

If `krvn.config.json` does not exist, defaults are created:
- `admin / admin123` (roles: server-admin, client, provider)
- `client1 / client123` (role: client)
- `provider1 / provider123` (role: provider)

Change default passwords before production use.

## Quick Start

### 1) Start Relay Server
1. Open tab `Mode`, choose `Server` (or `Combo`), click `Apply Mode`.
2. Open tab `Server`.
3. Set:
   - `Bind IP` (for all interfaces use `0.0.0.0`)
   - `Port` (default `5590`)
4. Click `Start Server`.
5. Verify `Server state: started`.

### 2) Start Provider
1. Run another app instance (or use `Combo` on same app instance).
2. Choose mode `Provider` and click `Apply Mode`.
3. Open tab `Provider`:
   - In `Relay Server Credentials` set Server IP/Port and provider server account.
   - In `Provider Identity and Access` set display name, visibility, and optional provider auth.
4. Click `Start Provider`.
5. Wait for status `Registered and online`.

### 3) Connect Client
1. Run client instance, choose mode `Client`, click `Apply Mode`.
2. Open tab `Client`:
   - In `Server Connection` enter server IP/port and **server** login/password.
3. Click `Connect`.
4. Wait for provider list auto-update (every 1 second).
5. Select provider and click `Connect Selected` (or double-click row).

## UI Guide

### Mode Tab

- Select one of:
  - `Client`
  - `Server`
  - `Provider`
  - `Combo (Server + Provider)`
- `Apply Mode` starts/stops roles according to selection.
- `Save Config` writes current UI values to `krvn.config.json`.

### Server Tab

### Server Runtime
- `Bind IP`: local interface address for server socket binding.
  - `0.0.0.0` = listen on all interfaces.
  - `127.0.0.1` = local-only.
- `Port`: relay port.
- `Hidden Resolve Policy`:
  - `restricted` - fail if multiple hidden providers match same machine name
  - `first` - pick earliest registered match
  - `last` - pick latest registered match

### Server Users
- Manage accounts used by Client/Provider to authenticate to relay server.
- Fields:
  - `Login`
  - `Password`
  - `Role` (`client`, `provider`, `server-admin`)
- Buttons:
  - `Save User`
  - `Delete User`

### Server Lists
- Providers and sessions update automatically every second.
- Selection index is preserved during refresh.

### Provider Tab

### 1) Relay Server Credentials
- Credentials here are for Provider -> Server authentication.
- Not the same as provider session auth used by Client.

### 2) Provider Identity and Access
- `Display Name`
- `Visibility` (`public` or `hidden`)
- `Provider Auth`:
  - `none`
  - `login_password` (client must provide provider login/password)
- `Provider Login` / `Provider Password`
- Permissions:
  - `Auto accept session`
  - `Allow input`
  - `Allow clipboard`
  - `Allow files`

### 3) Active Session Control
- `End Active Session`
- Provider status label reflects connection/session state.

### Client Tab

### 1) Server Connection
- Server endpoint + **server** account used for Client -> Server authentication.

### 2) Provider Access
- Optional `Provider Login` / `Provider Password` sent when connecting to provider.
- `Hidden machineName` used for hidden-provider connect.
- `Connect Hidden` for hidden route.
- `Session Window` opens remote session form.

### Available Providers
- Auto-refresh each second.
- Double-click item = same as `Connect Selected`.

### Session Window (separate resizable form)
- Controls:
  - `Quality`
  - `FPS` (`5, 10, 15, 30, 45, 60, 100`)
  - `Input capture`
  - `Disconnect`
  - `Clipboard`
  - `Send File`
  - `Ctrl+Alt+Del`
- Remote view scales with window size.
- Multi-buffer rendering is used to reduce visible flicker.

## Typical Scenarios

### Public Provider
1. Provider visibility = `public`.
2. Client chooses provider from list and connects.

### Hidden Provider
1. Provider visibility = `hidden`.
2. Client enters exact `machineName` in `Hidden machineName`.
3. Client clicks `Connect Hidden`.
4. Server resolves provider using hidden policy.

### Combo Mode
- In `Combo`, server and provider run in one process.
- Provider server endpoint is forced to local (`127.0.0.1`) and visibility to `public`.

## Adaptive Streaming

On session start, client performs a short throughput precheck (~1.5s) and auto-adjusts quality/FPS profile.  
You can still override settings manually in session window.

## Security Notes

- Passwords are stored as PBKDF2 hashes for server users.
- Client/provider secrets in config are DPAPI-protected on Windows.
- Change default credentials.
- Open relay port only where needed and restrict firewall rules.

## Troubleshooting

- Provider is not visible:
  - Check provider status (`Registered and online`).
  - Verify Provider visibility (`public` for list mode).
  - Check server IP/port and credentials.
  - Check firewall/NAT path to relay.
- Authenticated but cannot connect:
  - Verify account role (`client` / `provider`) on Server tab.
  - For provider auth mode `login_password`, verify provider login/password entered on Client tab.
- Session drops:
  - Check logs in `Logs` tab and files in `logs\`.
  - Reduce FPS/quality for unstable network.
- No input on remote:
  - Ensure `Input capture` is enabled.
  - Provider must allow input.

## License

See `LICENSE`.
