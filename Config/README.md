# Config Layout

## iOS app

- `Debug.xcconfig` and `Release.xcconfig` define non-secret app configuration.
- `Secrets.xcconfig` is for local client-side secrets that are safe to inject into the app bundle.
- `Secrets.xcconfig` is ignored by git.

## Server

- `Server.example.env` lists the server-only environment variables for the backend.
- Copy it to `Server.env` locally when you have a backend project to run.
- `Server.env` is ignored by git.

## Security note

Do not place database passwords, JWT secrets, COS keys, or other backend credentials into `.xcconfig` files used by the iOS target, because they become part of the shipped client.
